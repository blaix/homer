"""Tag music files, comparing existing tags / folder names / MusicBrainz.

Walks a music root assumed to look like:

    root/Artist Name/Album Name/[NN - ]Track Title.ext

For each audio file that's missing any of artist/album/title/tracknumber,
shows the three candidate values side-by-side for each field:

  - current     : what's in the file's tag right now
  - folder/file : derived from the path or filename
  - musicbrainz : looked up from MB based on the folder-derived values

You pick which source to write per field (or accept all recommendations).
Existing tags CAN be overwritten — useful when an old rip has wrong
metadata. Files where all four fields are already populated are skipped.
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
FOLDER_LABEL = {
    "artist": "folder",
    "album": "folder",
    "title": "filename",
    "tracknumber": "filename",
}
MB_API = "https://musicbrainz.org/ws/2/recording/"
USER_AGENT = "homer-tag-music/1.0 ( https://github.com/blaix/homer )"
MB_RATE_LIMIT_S = 1.1
MB_MIN_SCORE = 80
SIMILAR_THRESHOLD = 0.85

DISC_TRACK_RE = re.compile(r"^(\d+)[-_.](\d+)[-_.\s]+(.+?)$")
TRACK_PREFIX_RE = re.compile(r"^(\d+)[-_.\s]+(.+?)$")
NORM_RE = re.compile(r"[^\w]+")

ANSI_BOLD = "\033[1m"
ANSI_DIM = "\033[2m"
ANSI_GREEN = "\033[1;32m"
ANSI_YELLOW = "\033[33m"
ANSI_RESET = "\033[0m"

USE_COLOR = True


def main():
    global USE_COLOR
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("path", nargs="?",
                        help="music folder (prompts if omitted)")
    parser.add_argument("--dry-run", action="store_true",
                        help="show proposed changes without writing")
    parser.add_argument("--no-mb", action="store_true",
                        help="skip MusicBrainz lookups entirely")
    parser.add_argument("--no-color", action="store_true",
                        help="disable color output")
    args = parser.parse_args()

    USE_COLOR = not args.no_color and sys.stdout.isatty()

    raw = args.path or input("Music folder: ").strip()
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    try:
        run(root, dry_run=args.dry_run, use_mb=not args.no_mb)
    except KeyboardInterrupt:
        print("\ninterrupted.")


def run(root, dry_run, use_mb):
    apply_all = False
    last_mb_at = 0.0
    counts = {"written": 0, "complete": 0, "skipped": 0}

    for path in iter_audio(root):
        try:
            current = read_tags(path)
        except Exception as e:
            print(f"[!] {path}: {e}", file=sys.stderr)
            continue

        folder = derive_tags(path, root)

        if all(current.get(f) for f in TAG_FIELDS):
            counts["complete"] += 1
            continue

        canonical = None
        have_seed = all(folder.get(k) for k in ("artist", "album", "title"))
        if use_mb and have_seed:
            wait = MB_RATE_LIMIT_S - (time.monotonic() - last_mb_at)
            if wait > 0:
                time.sleep(wait)
            print(f"[querying MusicBrainz] {path}", file=sys.stderr)
            canonical = mb_canonicalize(folder["artist"],
                                        folder["album"],
                                        folder["title"])
            last_mb_at = time.monotonic()

        recs = {f: pick_recommendation(f, current, folder, canonical)
                for f in TAG_FIELDS}
        show_diff(path, current, folder, canonical, recs)

        if apply_all:
            print(colored("  [auto-applying recommendations]", ANSI_DIM))
            choice = "y"
        else:
            prompt = ("\n  Apply? [y]es=recommended / [c]ustomize / "
                      "[a]ll remaining / [s]kip / [q]uit: ")
            choice = (input(prompt).strip().lower() or "y")[:1]

        if choice == "q":
            break
        if choice == "s":
            counts["skipped"] += 1
            continue
        if choice == "a":
            apply_all = True
            choice = "y"

        if choice == "y":
            changes = {f: v for f, (src, v) in recs.items()
                       if src != "k" and v}
        elif choice == "c":
            changes = customize(current, folder, canonical, recs)
        else:
            print(f"  unrecognized input: {choice!r}, skipping file")
            counts["skipped"] += 1
            continue

        if not changes:
            print("  (nothing to write)")
            counts["skipped"] += 1
            continue

        print("  writing:")
        for k, v in changes.items():
            print(f"    {k:12} {v}")

        if dry_run:
            print("  (dry-run: not written)")
            counts["written"] += 1
            continue

        try:
            write_tags(path, changes)
            counts["written"] += 1
            print(f"  {colored('written.', ANSI_GREEN)}")
        except Exception as e:
            print(f"  [!] write failed: {e}", file=sys.stderr)

    print()
    print(f"done. written={counts['written']} "
          f"complete={counts['complete']} skipped={counts['skipped']}")


def colored(s, code):
    if not USE_COLOR:
        return s
    return f"{code}{s}{ANSI_RESET}"


def pick_recommendation(field, current, folder, canonical):
    """Return (source_key, value).

    source_key ∈ {"m", "f", "k"} for musicbrainz / folder / keep.
    Prefer MB if it differs from current at all (case-sensitive), so
    canonicalization happens. Fall back to folder only when current is
    empty. Otherwise keep current.
    """
    cur = current.get(field)
    fld = folder.get(field)
    mb = (canonical or {}).get(field)

    if mb and cur != mb:
        return ("m", mb)
    if not cur and fld:
        return ("f", fld)
    return ("k", cur)


def show_diff(path, current, folder, canonical, recs):
    print()
    print(f"{colored('File:', ANSI_BOLD)} {path}")
    for field in TAG_FIELDS:
        print_field_rows(field, current, folder, canonical, recs)


def print_field_rows(field, current, folder, canonical, recs):
    """Render a field's three sources with color + recommendation marker."""
    rec_src, rec_val = recs[field]
    rows = [
        ("current", current.get(field), "c"),
        (FOLDER_LABEL[field], folder.get(field), "f"),
        ("musicbrainz", (canonical or {}).get(field), "m"),
    ]
    print(f"\n  {colored(field, ANSI_BOLD)}:")
    for label, val, src_key in rows:
        display = format_cell(val, rec_val, src_key == rec_src)
        star = (colored("  ★ recommended", ANSI_GREEN)
                if src_key == rec_src and rec_src != "k" else "")
        print(f"    {label:12} {display}{star}")


def format_cell(val, rec_val, is_recommended):
    if val is None or val == "":
        return colored("(empty)", ANSI_DIM)
    if is_recommended:
        return colored(val, ANSI_GREEN)
    if rec_val and not similar(val, rec_val):
        return colored(val, ANSI_YELLOW)
    return val


def customize(current, folder, canonical, recs):
    """Walk each field; prompt for which source to write (or type custom)."""
    changes = {}
    print()
    print(f"  {colored('Customize:', ANSI_BOLD)}")
    for field in TAG_FIELDS:
        rec_src, _ = recs[field]
        fld = folder.get(field)
        mb = (canonical or {}).get(field)
        f_label = FOLDER_LABEL[field]

        # Reprint the three sources so the choice has the colored context
        # right above the prompt without scrolling.
        print_field_rows(field, current, folder, canonical, recs)

        options = ["[c]urrent"]
        if fld:
            options.append(f"[f]{f_label[1:]}")
        if mb:
            options.append("[m]b")
        options.append("[t]ype")

        default = rec_src if rec_src in ("m", "f") else "c"
        prompt = f"    {' / '.join(options)} [default: {default}]: "
        choice = (input(prompt).strip().lower() or default)[:1]

        if choice == "m" and mb:
            changes[field] = mb
        elif choice == "f" and fld:
            changes[field] = fld
        elif choice == "t":
            val = input(f"    enter value for {field}: ").strip()
            if val:
                changes[field] = val
        # 'c' or unknown: no write (current stays as-is)

    return changes


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


def derive_tags(path, root):
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    parts = rel.parts

    out = {}
    if len(parts) >= 3:
        out["artist"] = parts[-3]
        out["album"] = parts[-2]
    elif len(parts) == 2:
        out["artist"] = parts[-2]

    track_num, title = parse_stem(path.stem)
    if title:
        out["title"] = title
    if track_num:
        out["tracknumber"] = track_num
    return out


def parse_stem(stem):
    stem = stem.strip()
    m = DISC_TRACK_RE.match(stem)
    if m:
        return str(int(m.group(2))), m.group(3).strip()
    m = TRACK_PREFIX_RE.match(stem)
    if m:
        return str(int(m.group(1))), m.group(2).strip()
    return None, stem


def mb_canonicalize(artist, album, title):
    """Query MB for the canonical artist/album/title/tracknumber.

    Quote only the recording title in the query (most reliable in folder
    layouts). Artist and album go in as unquoted terms so MB's relevance
    scoring tolerates typos / case / missing punctuation. The client-side
    similar() filter handles the false positives.
    """
    q = (f'recording:"{escape(title)}" '
         f'AND artist:({lucene_terms(artist)}) '
         f'AND release:({lucene_terms(album)})')
    params = {"query": q, "fmt": "json", "limit": "25"}
    headers = {"User-Agent": USER_AGENT}
    try:
        r = requests.get(MB_API, params=params, headers=headers, timeout=10)
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        print(f"  (MB lookup failed: {e})", file=sys.stderr)
        return None

    recordings = data.get("recordings", []) or []
    for rec in recordings:
        if rec.get("score", 0) < MB_MIN_SCORE:
            continue
        rec_title = rec.get("title", "")
        if not similar(rec_title, title):
            continue
        ac = rec.get("artist-credit", []) or []
        if not ac:
            continue
        if not similar(ac[0].get("name", ""), artist):
            continue
        canonical_artist = join_artist_credit(ac)
        for rel in rec.get("releases", []) or []:
            rel_title = rel.get("title", "")
            if not similar(rel_title, album):
                continue
            for medium in rel.get("media", []) or []:
                for track in medium.get("track", []) or []:
                    if similar(track.get("title", ""), title):
                        n = track.get("number")
                        return {
                            "artist": canonical_artist,
                            "album": rel_title,
                            "title": rec_title,
                            "tracknumber": str(n) if n else None,
                        }
            return {
                "artist": canonical_artist,
                "album": rel_title,
                "title": rec_title,
                "tracknumber": None,
            }
    if recordings:
        print(f"  (MB returned {len(recordings)} candidate(s) but none "
              f"matched artist+album closely enough)", file=sys.stderr)
    return None


def lucene_terms(s):
    """Escape Lucene specials in a multi-word value used as unquoted terms."""
    # Strip Lucene operator characters; the value becomes a bag of terms.
    return re.sub(r'[+\-&|!(){}\[\]^"~*?:\\]', " ", s).strip()


def join_artist_credit(ac):
    parts = []
    for entry in ac:
        parts.append(entry.get("name", ""))
        joinphrase = entry.get("joinphrase", "")
        if joinphrase:
            parts.append(joinphrase)
    return "".join(parts)


def similar(a, b):
    """Loose equality with fuzzy matching.

    Catches case + punctuation differences exactly, plus short edit-distance
    differences (folder typos, missing characters that aren't legal in
    paths, etc.) via difflib's similarity ratio.
    """
    if not a or not b:
        return False
    na = NORM_RE.sub("", a.lower())
    nb = NORM_RE.sub("", b.lower())
    if na == nb:
        return True
    # Avoid false positives on very short strings (e.g. "Hum" vs "Humbucker"
    # would score 0.5; we still want to reject it).
    if min(len(na), len(nb)) < 4:
        return False
    return SequenceMatcher(None, na, nb).ratio() >= SIMILAR_THRESHOLD


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


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


if __name__ == "__main__":
    main()
