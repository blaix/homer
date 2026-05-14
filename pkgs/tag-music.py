"""Tag music: fill in missing tags, or fix inconsistencies across the library.

Two modes:

Default — fill in missing artist/albumartist/album/title/tracknumber:
    Walks a music root assumed to look like:
        root/Artist Name/Album Name/[NN - ]Track Title.ext
    Only missing tags get written; existing tags are left alone. The
    first time an artist, albumartist, or album folder is encountered,
    MusicBrainz is queried and you're prompted to choose between folder
    name, canonical MB name, or custom value. That choice is reused for
    the rest of the folder. Missing titles get a per-file MB lookup
    (prompting only when MB differs significantly from the filename).
    Missing track numbers are filled in silently from MB or filename —
    but only when we're already fixing artist or album on that file.

--fix — find and resolve inconsistencies in tags that already exist:
    Scans the whole library and surfaces (a) cross-file variant
    clusters: values that normalize to the same name but disagree in
    spelling (e.g. "Capn Jazz" vs "Cap'n Jazz" across files), and (b)
    within-file mismatches where artist and albumartist disagree but
    are similar (single combined prompt sets both). Clusters are
    handled per field — artist, albumartist (global) and album
    (scoped per artist). Finishes with a list of filesystem warnings
    (folder names that disagree with chosen tags, sibling folders that
    normalize to the same name) for you to fix by hand.
"""
import argparse
import re
import sys
import time
from difflib import SequenceMatcher
from functools import lru_cache
from pathlib import Path

import mutagen
import requests


AUDIO_EXTENSIONS = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".aac"}
TAG_FIELDS = ("artist", "albumartist", "album", "title", "tracknumber")
MB_BASE = "https://musicbrainz.org/ws/2"
USER_AGENT = "homer-tag-music/2.0 ( https://github.com/blaix/homer )"
MB_RATE_LIMIT_S = 1.1
MB_MIN_SCORE = 80
SIMILAR_THRESHOLD = 0.85

DISC_TRACK_RE = re.compile(r"^(\d+)[-_.](\d+)[-_.\s]+(.+?)$")
TRACK_PREFIX_RE = re.compile(r"^(\d+)[-_.\s]+(.+?)$")
NORM_RE = re.compile(r"[^\w]+")
COSMETIC_RE = re.compile(r"[^\w\s]+")  # strip punctuation, keep letters/whitespace

BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
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
    parser.add_argument("--fix", action="store_true",
                        help="scan for inconsistent tags across the "
                             "library and resolve them (independent of "
                             "the default missing-tag pass)")
    args = parser.parse_args()

    maybe_disable_color()

    raw = args.path or input("Music folder: ").strip()
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    try:
        if args.fix:
            run_fix(root, dry_run=args.dry_run)
        else:
            run(root, dry_run=args.dry_run)
    except KeyboardInterrupt:
        print("\ninterrupted.")


def maybe_disable_color():
    if sys.stdout.isatty():
        return
    global BOLD, DIM, RED, GREEN, YELLOW, CYAN, RESET
    BOLD = DIM = RED = GREEN = YELLOW = CYAN = RESET = ""


# ----- default missing-tag mode -----

def run(root, dry_run):
    artist_cache = {}        # artist_dir Path -> chosen artist string
    albumartist_cache = {}   # artist_dir Path -> chosen albumartist string
    album_cache = {}         # album_dir Path -> chosen album string
    counts = {"written": 0, "complete": 0, "skipped": 0, "errors": 0}

    for path in iter_audio(root):
        try:
            process_file(path, root, artist_cache, albumartist_cache,
                         album_cache, dry_run, counts)
        except Exception as e:
            print(f"{RED}[!] {path}: {e}{RESET}", file=sys.stderr)
            counts["errors"] += 1

    print()
    err = (f" {RED}errors={counts['errors']}{RESET}"
           if counts["errors"] else "")
    print(f"{BOLD}done.{RESET} "
          f"{GREEN}written={counts['written']}{RESET} "
          f"complete={counts['complete']} "
          f"skipped={counts['skipped']}{err}")


def process_file(path, root, artist_cache, albumartist_cache, album_cache,
                 dry_run, counts):
    current = read_tags(path)
    missing = {f for f in TAG_FIELDS if not current.get(f)}

    # Track number alone never triggers processing — by the user's spec.
    if not (missing & {"artist", "albumartist", "album", "title"}):
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

    if "albumartist" in missing:
        if artist_dir is None:
            print(f"  {DIM}skip: cannot derive albumartist from path{RESET}")
            counts["skipped"] += 1
            return
        if artist_dir not in albumartist_cache:
            albumartist_cache[artist_dir] = resolve_artist(
                artist_dir.name, label="albumartist")
        changes["albumartist"] = albumartist_cache[artist_dir]

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

    try:
        write_tags(path, changes)
        print(f"  {GREEN}written.{RESET}")
        counts["written"] += 1
    except Exception as e:
        print(f"  {RED}[!] write failed: {e}{RESET}", file=sys.stderr)
        counts["errors"] += 1


def resolve_artist(folder_name, label="artist"):
    mb_name = mb_search_artist(folder_name)
    return prompt_choose(label, folder_name, mb_name)


def resolve_album(folder_name, artist):
    mb_name = mb_search_album(folder_name, artist) if artist else None
    return prompt_choose("album", folder_name, mb_name)


def prompt_choose(label, folder_name, mb_name):
    print(f"  {BOLD}{label}{RESET}")
    print(f"    [f] folder      : {folder_name}")
    has_distinct_mb = bool(mb_name and mb_name != folder_name)
    if has_distinct_mb:
        print(f"    [m] musicbrainz : {CYAN}{mb_name}{RESET}")
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
    print(f"    [m] musicbrainz : {CYAN}{mb_title}{RESET}")
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


# ----- --fix mode -----

def run_fix(root, dry_run):
    print(f"{BOLD}scanning library...{RESET}")
    library = scan_library(root)
    print(f"  {len(library)} audio files read")

    counts = {"written": 0, "errors": 0}

    artist_clusters = find_clusters(library, "artist")
    albumartist_clusters = find_clusters(library, "albumartist")
    album_clusters = find_album_clusters_per_artist(library)

    print()
    print(f"  artist clusters     : {len(artist_clusters)}")
    print(f"  albumartist clusters: {len(albumartist_clusters)}")
    print(f"  album clusters      : {len(album_clusters)}")

    resolve_clusters("artist", artist_clusters, dry_run, counts)
    resolve_clusters("albumartist", albumartist_clusters, dry_run, counts)
    resolve_album_clusters(album_clusters, dry_run, counts)

    # After cluster cleanup; mismatches are computed off the updated state.
    mismatches = find_within_file_mismatches(library)
    print()
    print(f"{BOLD}within-file mismatches: {len(mismatches)}{RESET}")
    resolve_mismatches(mismatches, dry_run, counts)

    warnings = collect_fs_warnings(root, library)
    if warnings:
        print()
        print(f"{BOLD}{YELLOW}filesystem warnings (fix by hand):{RESET}")
        for w in warnings:
            print(f"  {YELLOW}{w}{RESET}")

    print()
    err = (f" {RED}errors={counts['errors']}{RESET}"
           if counts["errors"] else "")
    print(f"{BOLD}done.{RESET} "
          f"{GREEN}written={counts['written']}{RESET}"
          f"{err}")


def scan_library(root):
    library = []
    for path in iter_audio(root):
        try:
            tags = read_tags(path)
        except Exception as e:
            print(f"{RED}[!] {path}: {e}{RESET}", file=sys.stderr)
            continue
        library.append({"path": path, "tags": tags})
    return library


def find_clusters(library, field):
    """Return list of clusters for the given field.

    A cluster is a normalized form with two or more raw spellings. Each
    cluster is {"variants": [(raw, [entries]), ...]}, variants sorted
    by file count descending.
    """
    by_norm = {}
    for entry in library:
        raw = entry["tags"].get(field)
        if not raw:
            continue
        norm = NORM_RE.sub("", raw.lower())
        if not norm:
            continue
        by_norm.setdefault(norm, {}).setdefault(raw, []).append(entry)

    clusters = []
    for variants in by_norm.values():
        if len(variants) < 2:
            continue
        sorted_variants = sorted(variants.items(), key=lambda x: -len(x[1]))
        clusters.append({"variants": sorted_variants})
    return clusters


def find_album_clusters_per_artist(library):
    """Album clusters scoped to one artist at a time.

    Files are bucketed by normalized albumartist (falling back to
    artist), then album clusters are computed within each bucket. This
    keeps self-titled albums by different artists from colliding.
    """
    by_artist = {}
    for entry in library:
        a = entry["tags"].get("albumartist") or entry["tags"].get("artist")
        if not a:
            continue
        a_norm = NORM_RE.sub("", a.lower())
        if not a_norm:
            continue
        by_artist.setdefault(a_norm, []).append(entry)

    clusters = []
    for entries in by_artist.values():
        by_album_norm = {}
        for e in entries:
            album = e["tags"].get("album")
            if not album:
                continue
            al_norm = NORM_RE.sub("", album.lower())
            if not al_norm:
                continue
            by_album_norm.setdefault(al_norm, {}).setdefault(album, []).append(e)
        for variants in by_album_norm.values():
            if len(variants) < 2:
                continue
            sorted_variants = sorted(variants.items(),
                                     key=lambda x: -len(x[1]))
            sample = sorted_variants[0][1][0]
            context_artist = (sample["tags"].get("albumartist")
                              or sample["tags"].get("artist"))
            clusters.append({
                "variants": sorted_variants,
                "context_artist": context_artist,
            })
    return clusters


def find_within_file_mismatches(library):
    out = []
    for entry in library:
        a = entry["tags"].get("artist")
        aa = entry["tags"].get("albumartist")
        if not a or not aa or a == aa:
            continue
        if similar(a, aa):
            out.append(entry)
    return out


def resolve_clusters(field, clusters, dry_run, counts):
    if not clusters:
        return
    print()
    print(f"{BOLD}resolving {field} clusters ({len(clusters)}){RESET}")
    for cluster in clusters:
        chosen = prompt_cluster(field, cluster, context_artist=None)
        if chosen is None:
            continue
        apply_cluster_choice(field, cluster, chosen, dry_run, counts)


def resolve_album_clusters(clusters, dry_run, counts):
    if not clusters:
        return
    print()
    print(f"{BOLD}resolving album clusters ({len(clusters)}){RESET}")
    for cluster in clusters:
        chosen = prompt_cluster("album", cluster, cluster["context_artist"])
        if chosen is None:
            continue
        apply_cluster_choice("album", cluster, chosen, dry_run, counts)


def prompt_cluster(field, cluster, context_artist):
    variants = cluster["variants"]
    total = sum(len(entries) for _, entries in variants)

    print()
    title_ctx = f" [{context_artist}]" if context_artist else ""
    print(f"  {BOLD}{field} cluster{RESET}{title_ctx} "
          f"({len(variants)} variants, {total} files)")

    seed = variants[0][0]
    if field in ("artist", "albumartist"):
        mb_name = mb_search_artist(seed)
    elif field == "album":
        mb_name = (mb_search_album(seed, context_artist)
                   if context_artist else None)
    else:
        mb_name = None

    matching_variant_idx = None
    if mb_name:
        for i, (raw, _) in enumerate(variants):
            if raw == mb_name:
                matching_variant_idx = i
                break

    for i, (raw, entries) in enumerate(variants, 1):
        print(f"    [{i}] {YELLOW}{raw}{RESET} ({len(entries)} files)")

    if mb_name and matching_variant_idx is None:
        print(f"    [m] musicbrainz : {CYAN}{mb_name}{RESET}")
        default = "m"
    elif mb_name:
        print(f"    {DIM}(musicbrainz matches "
              f"variant [{matching_variant_idx + 1}]){RESET}")
        default = str(matching_variant_idx + 1)
    else:
        print(f"    {DIM}(musicbrainz: no match){RESET}")
        default = "1"
    print("    [t] type custom")
    print("    [s] skip")

    while True:
        choice = (input(f"    choose [default: {default}]: ")
                  .strip().lower() or default)
        if choice == "s":
            return None
        if choice == "m" and mb_name and matching_variant_idx is None:
            return mb_name
        if choice == "t":
            val = input(f"    enter {field}: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(variants):
                return variants[idx][0]
        print(f"    unrecognized: {choice!r}")


def apply_cluster_choice(field, cluster, chosen, dry_run, counts):
    for raw, entries in cluster["variants"]:
        if raw == chosen:
            continue
        for entry in entries:
            write_one(entry, {field: chosen}, dry_run, counts)


def resolve_mismatches(mismatches, dry_run, counts):
    if not mismatches:
        return
    decisions = {}  # frozenset({a, aa}) -> chosen value (or None if skipped)
    for entry in mismatches:
        # Re-check in case cluster cleanup has already resolved this one.
        a = entry["tags"].get("artist")
        aa = entry["tags"].get("albumartist")
        if not a or not aa or a == aa or not similar(a, aa):
            continue
        key = frozenset((a, aa))
        if key in decisions:
            chosen = decisions[key]
        else:
            chosen = prompt_mismatch(entry)
            decisions[key] = chosen
        if chosen is None:
            continue
        updates = {}
        if entry["tags"].get("artist") != chosen:
            updates["artist"] = chosen
        if entry["tags"].get("albumartist") != chosen:
            updates["albumartist"] = chosen
        if updates:
            write_one(entry, updates, dry_run, counts)


def prompt_mismatch(entry):
    a = entry["tags"]["artist"]
    aa = entry["tags"]["albumartist"]
    print()
    print(f"  {BOLD}{entry['path']}{RESET}")
    print(f"    {YELLOW}artist     : {a}{RESET}")
    print(f"    {YELLOW}albumartist: {aa}{RESET}")

    mb_name = mb_search_artist(a)
    has_distinct_mb = bool(mb_name and mb_name not in (a, aa))

    print(f"    [1] {a}")
    print(f"    [2] {aa}")
    if has_distinct_mb:
        print(f"    [m] musicbrainz : {CYAN}{mb_name}{RESET}")
        default = "m"
    elif mb_name:
        if mb_name == a:
            default = "1"
        else:
            default = "2"
        print(f"    {DIM}(musicbrainz matches variant [{default}]){RESET}")
    else:
        print(f"    {DIM}(musicbrainz: no match){RESET}")
        default = "1"
    print("    [t] type custom")
    print("    [s] skip")

    while True:
        choice = (input(f"    set both fields to [default: {default}]: ")
                  .strip().lower() or default)
        if choice == "s":
            return None
        if choice == "1":
            return a
        if choice == "2":
            return aa
        if choice == "m" and has_distinct_mb:
            return mb_name
        if choice == "t":
            val = input("    enter value: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        print(f"    unrecognized: {choice!r}")


def write_one(entry, updates, dry_run, counts):
    path = entry["path"]
    summary = ", ".join(f"{k}={v}" for k, v in updates.items())
    if dry_run:
        print(f"    {DIM}(dry-run){RESET} {path} → {summary}")
        for k, v in updates.items():
            entry["tags"][k] = v
        counts["written"] += 1
        return
    try:
        write_tags(path, updates)
        for k, v in updates.items():
            entry["tags"][k] = v
        print(f"    {GREEN}written{RESET} {path} → {summary}")
        counts["written"] += 1
    except Exception as e:
        print(f"    {RED}[!] {path}: {e}{RESET}", file=sys.stderr)
        counts["errors"] += 1


def collect_fs_warnings(root, library):
    """Filesystem mistakes for the user to fix by hand."""
    warnings = []

    # Group entries by their artist/album folder paths.
    by_artist_folder = {}
    by_album_folder = {}
    for entry in library:
        path = entry["path"]
        try:
            rel = path.relative_to(root)
        except ValueError:
            continue
        if len(rel.parts) >= 3:
            by_artist_folder.setdefault(path.parent.parent, []).append(entry)
            by_album_folder.setdefault(path.parent, []).append(entry)
        elif len(rel.parts) == 2:
            by_artist_folder.setdefault(path.parent, []).append(entry)

    try:
        artist_folders = sorted([p for p in root.iterdir() if p.is_dir()])
    except OSError:
        artist_folders = []

    # Sibling artist folders that normalize to the same name.
    sib_norm = {}
    for af in artist_folders:
        norm = NORM_RE.sub("", af.name.lower())
        if norm:
            sib_norm.setdefault(norm, []).append(af)
    for folders in sib_norm.values():
        if len(folders) > 1:
            names = ", ".join(str(f) for f in folders)
            warnings.append(f"merge sibling artist folders: {names}")

    # Artist folder name disagrees with the (now-unified) tag value.
    for af, entries in by_artist_folder.items():
        values = set()
        for e in entries:
            v = e["tags"].get("albumartist") or e["tags"].get("artist")
            if v:
                values.add(v)
        if len(values) != 1:
            continue
        only = next(iter(values))
        if (NORM_RE.sub("", only.lower()) == NORM_RE.sub("", af.name.lower())
                and only != af.name
                and not cosmetic_only_diff(only, af.name)):
            new_path = af.parent / sanitize_folder_name(only)
            warnings.append(f"rename folder: {af} → {new_path}")

    # Sibling album folders that normalize to the same name (per artist).
    for af in artist_folders:
        try:
            album_folders = sorted([p for p in af.iterdir() if p.is_dir()])
        except OSError:
            continue
        sib_norm = {}
        for alf in album_folders:
            norm = NORM_RE.sub("", alf.name.lower())
            if norm:
                sib_norm.setdefault(norm, []).append(alf)
        for folders in sib_norm.values():
            if len(folders) > 1:
                names = ", ".join(str(f) for f in folders)
                warnings.append(f"merge sibling album folders: {names}")

    # Album folder name disagrees with the tag value.
    for alf, entries in by_album_folder.items():
        values = set()
        for e in entries:
            v = e["tags"].get("album")
            if v:
                values.add(v)
        if len(values) != 1:
            continue
        only = next(iter(values))
        if (NORM_RE.sub("", only.lower()) == NORM_RE.sub("", alf.name.lower())
                and only != alf.name
                and not cosmetic_only_diff(only, alf.name)):
            new_path = alf.parent / sanitize_folder_name(only)
            warnings.append(f"rename folder: {alf} → {new_path}")

    return warnings


def sanitize_folder_name(name):
    return name.replace("/", "-")


# ----- MusicBrainz -----

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
        print(f"    {DIM}(MB {endpoint} lookup failed: {e}){RESET}",
              file=sys.stderr)
        _last_mb_at = time.monotonic()
        return None


@lru_cache(maxsize=None)
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


# ----- I/O and string helpers -----

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


def cosmetic_only_diff(a, b):
    """True iff a and b are equal once case and punctuation are ignored.

    Used to suppress filesystem-rename warnings for folders that only
    differ from the tag value in case or in stripped punctuation
    (apostrophes, periods, etc.) — the kind of cosmetic mismatch that
    isn't worth renaming.
    """
    return (COSMETIC_RE.sub("", a.lower())
            == COSMETIC_RE.sub("", b.lower()))


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
