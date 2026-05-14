"""Tag music: fill in missing artist/album/title/tracknumber tags.

Walks a music root assumed to look like:

    root/Artist Name/Album Name/[NN - ]Track Title.ext

Only missing tags get written; existing tags are left alone. The first
time an artist or album folder is encountered, MusicBrainz is queried
and you're prompted to choose between the folder name, the canonical MB
name, or a custom value. That choice is reused for the rest of the
folder. Missing titles get a per-file MB lookup (prompting only when MB
differs significantly from the filename). Missing track numbers are
filled in silently from MB or the filename — but only when we're
already fixing artist or album on that file.
"""
import argparse
import re
import sys
import time
from difflib import SequenceMatcher
from pathlib import Path

import mutagen
import requests


AUDIO_EXTENSIONS = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".aac"}
TAG_FIELDS = ("artist", "album", "title", "tracknumber")
MB_BASE = "https://musicbrainz.org/ws/2"
USER_AGENT = "homer-tag-music/2.0 ( https://github.com/blaix/homer )"
MB_RATE_LIMIT_S = 1.1
MB_MIN_SCORE = 80
SIMILAR_THRESHOLD = 0.85

DISC_TRACK_RE = re.compile(r"^(\d+)[-_.](\d+)[-_.\s]+(.+?)$")
TRACK_PREFIX_RE = re.compile(r"^(\d+)[-_.\s]+(.+?)$")
NORM_RE = re.compile(r"[^\w]+")

BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

_last_mb_at = 0.0


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("path", nargs="?",
                        help="music folder (prompts if omitted)")
    parser.add_argument("--dry-run", action="store_true",
                        help="show proposed changes without writing")
    args = parser.parse_args()

    raw = args.path or input("Music folder: ").strip()
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    try:
        run(root, dry_run=args.dry_run)
    except KeyboardInterrupt:
        print("\ninterrupted.")


def run(root, dry_run):
    artist_cache = {}  # artist_dir Path -> chosen artist string
    album_cache = {}   # album_dir Path -> chosen album string
    counts = {"written": 0, "complete": 0, "skipped": 0}

    for path in iter_audio(root):
        try:
            process_file(path, root, artist_cache, album_cache,
                         dry_run, counts)
        except Exception as e:
            print(f"[!] {path}: {e}", file=sys.stderr)
            counts["skipped"] += 1

    print()
    print(f"done. written={counts['written']} "
          f"complete={counts['complete']} skipped={counts['skipped']}")


def process_file(path, root, artist_cache, album_cache, dry_run, counts):
    current = read_tags(path)
    missing = {f for f in TAG_FIELDS if not current.get(f)}

    # Only artist, album, or title trigger processing. Track number alone
    # never does — by the user's spec.
    if not (missing & {"artist", "album", "title"}):
        counts["complete"] += 1
        return

    artist_dir, album_dir = get_artist_album_dirs(path, root)

    print()
    print(f"{BOLD}{path}{RESET}")

    changes = {}
    effective_artist = current.get("artist")
    effective_album = current.get("album")

    if "artist" in missing:
        if artist_dir is None:
            print(f"  {DIM}skip: cannot derive artist from path{RESET}")
            counts["skipped"] += 1
            return
        if artist_dir not in artist_cache:
            artist_cache[artist_dir] = resolve_artist(artist_dir.name)
        effective_artist = artist_cache[artist_dir]
        changes["artist"] = effective_artist

    if "album" in missing:
        if album_dir is None:
            print(f"  {DIM}skip: cannot derive album from path{RESET}")
            counts["skipped"] += 1
            return
        if album_dir not in album_cache:
            album_cache[album_dir] = resolve_album(album_dir.name,
                                                   effective_artist)
        effective_album = album_cache[album_dir]
        changes["album"] = effective_album

    fixing_artist_or_album = "artist" in missing or "album" in missing
    need_title = "title" in missing
    need_tracknum = "tracknumber" in missing and fixing_artist_or_album

    if need_title or need_tracknum:
        track_from_file, title_from_file = parse_stem(path.stem)
        mb_rec = None
        if effective_artist and effective_album and title_from_file:
            mb_rec = mb_search_recording(effective_artist,
                                         effective_album,
                                         title_from_file)

        if need_title:
            chosen = resolve_title(title_from_file,
                                   (mb_rec or {}).get("title"))
            if chosen:
                changes["title"] = chosen

        if need_tracknum:
            mb_tn = (mb_rec or {}).get("tracknumber")
            if mb_tn:
                changes["tracknumber"] = mb_tn
            elif track_from_file:
                changes["tracknumber"] = track_from_file

    if not changes:
        print(f"  {DIM}(nothing to write){RESET}")
        counts["skipped"] += 1
        return

    print("  writing:")
    for k, v in changes.items():
        print(f"    {k:12} {v}")

    if dry_run:
        print(f"  {DIM}(dry-run, not written){RESET}")
        counts["written"] += 1
        return

    write_tags(path, changes)
    counts["written"] += 1


def resolve_artist(folder_name):
    mb_name = mb_search_artist(folder_name)
    return prompt_choose("artist", folder_name, mb_name)


def resolve_album(folder_name, artist):
    mb_name = mb_search_album(folder_name, artist) if artist else None
    return prompt_choose("album", folder_name, mb_name)


def prompt_choose(label, folder_name, mb_name):
    print(f"  {BOLD}{label}{RESET}")
    print(f"    [f] folder      : {folder_name}")
    has_distinct_mb = bool(mb_name and mb_name != folder_name)
    if has_distinct_mb:
        print(f"    [m] musicbrainz : {mb_name}")
        default = "m"
    else:
        if mb_name:
            print(f"    {DIM}(musicbrainz returned same as folder){RESET}")
        else:
            print(f"    {DIM}(musicbrainz: no match){RESET}")
        default = "f"
    print("    [t] type custom")
    while True:
        choice = (input(f"    choose [default: {default}]: ")
                  .strip().lower() or default)[:1]
        if choice == "f":
            return folder_name
        if choice == "m" and has_distinct_mb:
            return mb_name
        if choice == "t":
            val = input(f"    enter {label}: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        print(f"    unrecognized: {choice!r}")


def resolve_title(filename_title, mb_title):
    if not filename_title and not mb_title:
        return None
    if not mb_title:
        return filename_title
    if not filename_title:
        return mb_title

    na = NORM_RE.sub("", filename_title.lower())
    nb = NORM_RE.sub("", mb_title.lower())
    if na == nb:
        return filename_title

    short = min(len(na), len(nb)) < 4
    ratio = 0 if short else SequenceMatcher(None, na, nb).ratio()
    if ratio >= SIMILAR_THRESHOLD:
        return mb_title

    print(f"  {BOLD}title differs from filename{RESET}")
    print(f"    [f] filename    : {filename_title}")
    print(f"    [m] musicbrainz : {mb_title}")
    print("    [t] type custom")
    while True:
        choice = (input("    choose [default: m]: ")
                  .strip().lower() or "m")[:1]
        if choice == "f":
            return filename_title
        if choice == "m":
            return mb_title
        if choice == "t":
            val = input("    enter title: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        print(f"    unrecognized: {choice!r}")


def mb_get(endpoint, params):
    global _last_mb_at
    wait = MB_RATE_LIMIT_S - (time.monotonic() - _last_mb_at)
    if wait > 0:
        time.sleep(wait)
    headers = {"User-Agent": USER_AGENT}
    url = f"{MB_BASE}/{endpoint}/"
    try:
        r = requests.get(url, params=params, headers=headers, timeout=10)
        r.raise_for_status()
        _last_mb_at = time.monotonic()
        return r.json()
    except Exception as e:
        print(f"    (MB {endpoint} lookup failed: {e})", file=sys.stderr)
        _last_mb_at = time.monotonic()
        return None


def mb_search_artist(name):
    data = mb_get("artist", {
        "query": f'artist:"{escape(name)}"',
        "fmt": "json",
        "limit": "5",
    })
    if not data:
        return None
    for item in data.get("artists", []) or []:
        if item.get("score", 0) < MB_MIN_SCORE:
            continue
        cand = item.get("name")
        if cand and similar(cand, name):
            return cand
    return None


def mb_search_album(name, artist):
    q = f'release:"{escape(name)}" AND artist:({lucene_terms(artist)})'
    data = mb_get("release", {"query": q, "fmt": "json", "limit": "5"})
    if not data:
        return None
    for item in data.get("releases", []) or []:
        if item.get("score", 0) < MB_MIN_SCORE:
            continue
        cand = item.get("title")
        if cand and similar(cand, name):
            return cand
    return None


def mb_search_recording(artist, album, title):
    q = (f'recording:"{escape(title)}" '
         f'AND artist:({lucene_terms(artist)}) '
         f'AND release:({lucene_terms(album)})')
    data = mb_get("recording", {"query": q, "fmt": "json", "limit": "25"})
    if not data:
        return None
    for rec in data.get("recordings", []) or []:
        if rec.get("score", 0) < MB_MIN_SCORE:
            continue
        rec_title = rec.get("title", "")
        if not similar(rec_title, title):
            continue
        ac = rec.get("artist-credit", []) or []
        if not ac or not similar(ac[0].get("name", ""), artist):
            continue
        for rel in rec.get("releases", []) or []:
            if not similar(rel.get("title", ""), album):
                continue
            for medium in rel.get("media", []) or []:
                for track in medium.get("track", []) or []:
                    if similar(track.get("title", ""), title):
                        n = track.get("number")
                        return {
                            "title": rec_title,
                            "tracknumber": str(n) if n else None,
                        }
            return {"title": rec_title, "tracknumber": None}
    return None


def iter_audio(root):
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        if p.name.startswith("._"):
            continue
        if p.suffix.lower() not in AUDIO_EXTENSIONS:
            continue
        yield p


def read_tags(path):
    f = mutagen.File(path, easy=True)
    if f is None or f.tags is None:
        return {}
    out = {}
    for k in TAG_FIELDS:
        val = f.tags.get(k)
        if val:
            out[k] = val[0] if isinstance(val, list) else str(val)
    return out


def write_tags(path, changes):
    f = mutagen.File(path, easy=True)
    if f is None:
        raise RuntimeError("unsupported audio format")
    if f.tags is None:
        f.add_tags()
    for k, v in changes.items():
        if v is None:
            continue
        f[k] = v
    f.save()


def get_artist_album_dirs(path, root):
    """Return (artist_dir, album_dir) relative to the music root.

    Expects root/Artist/Album/track.ext layout, so the file's parent is
    the album folder and the grandparent is the artist folder. Returns
    None for either piece if the path isn't deep enough below root.
    """
    try:
        rel = path.relative_to(root)
    except ValueError:
        return (None, None)
    parts = rel.parts
    if len(parts) >= 3:
        return (path.parent.parent, path.parent)
    if len(parts) == 2:
        return (path.parent, None)
    return (None, None)


def parse_stem(stem):
    stem = stem.strip()
    m = DISC_TRACK_RE.match(stem)
    if m:
        return str(int(m.group(2))), m.group(3).strip()
    m = TRACK_PREFIX_RE.match(stem)
    if m:
        return str(int(m.group(1))), m.group(2).strip()
    return None, stem


def lucene_terms(s):
    return re.sub(r'[+\-&|!(){}\[\]^"~*?:\\]', " ", s).strip()


def similar(a, b):
    if not a or not b:
        return False
    na = NORM_RE.sub("", a.lower())
    nb = NORM_RE.sub("", b.lower())
    if na == nb:
        return True
    if min(len(na), len(nb)) < 4:
        return False
    return SequenceMatcher(None, na, nb).ratio() >= SIMILAR_THRESHOLD


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


if __name__ == "__main__":
    main()
