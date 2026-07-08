"""Tag music: fill in missing tags, or fix inconsistencies across the library.

Three modes:

Default — fill in missing artist/albumartist/album/title/tracknumber:
    Walks a music root assumed to look like:
        root/Artist Name/Album Name/[NN - ]Track Title.ext
    Only missing tags get written; existing tags are left alone.
    Albumartist is resolved first (folder name vs. MusicBrainz prompt,
    cached per folder). For normal albums, missing artist defaults to
    albumartist without a separate prompt. For compilations
    (albumartist contains "various", "compilation", "soundtrack", or
    equals "VA"), per-track artist is parsed from "NN - Artist - Title"
    filenames when present and otherwise left blank rather than being
    mass-tagged with the folder name. Album folders prompt the same
    way as artist folders. Missing titles get a per-file MB lookup
    (prompting only when MB differs significantly from the filename).
    Missing track numbers are filled in silently from MB or filename —
    but only when we're already fixing artist or album on that file.
    MusicBrainz IDs (recording, release, and artist) are filled in
    silently from the same recording lookup on a confident match, and a
    track missing any of them is enough on its own to trigger that
    lookup — so an already-tagged library can be back-filled with the IDs
    Navidrome and the ListenBrainz playlist plugin match tracks on.
    Existing IDs are never overwritten.

--fix — find and resolve inconsistencies in tags that already exist:
    Scans the whole library and surfaces (a) cross-file variant
    clusters: values that normalize to the same name but disagree in
    spelling (e.g. "Capn Jazz" vs "Cap'n Jazz" across files), (b)
    release-date clusters: tracks of one album that carry disagreeing
    date tags (which makes players like Navidrome split a single album
    into several; the prompt offers the album's MusicBrainz release date
    and the latest of the listed dates alongside the variants), (c)
    musicbrainz album-id clusters: tracks of one album that carry
    disagreeing MusicBrainz Album Ids — or where some tracks carry an id
    and others none — the same kind of split as a date cluster but on the
    id Navidrome's album grouping keys on first, so a folder tagged
    per-recording against several releases (or with a few tracks the
    default pass couldn't back-fill) shows up as multiple album copies
    (the prompt defaults to MusicBrainz's release match when there is one,
    else the id on the most tracks, and writes the chosen id to every
    track in the album, untagged ones included),
    (d) within-file mismatches where artist and
    albumartist disagree but are similar (single combined prompt sets
    both), and (e) per-album genre gaps and outliers: albums where some
    tracks have no genre, or where the tracks' genres disagree. Each such
    album is resolved against its MusicBrainz genres (the default, when a
    confident release match is found) or the album's own majority genre
    (the fallback), written as a single comma-joined value that
    Navidrome's default separators split back into multiple genres.
    Uniform, fully-tagged albums are left alone, and compilations only
    have missing genres filled (their existing per-track genres, which
    legitimately vary, are not overwritten). Clusters are handled per
    field — artist, albumartist
    (global), album (scoped per artist), and date and musicbrainz_albumid
    (each scoped per album).
    Finishes with a list of filesystem warnings (folder names that
    disagree with chosen tags, sibling folders that normalize to the
    same name) for you to fix by hand.

--art — fill in missing album cover art:
    Walks each album folder and, for any that has no cover image yet
    (cover/folder/front.*), reads the album+artist tags off its tracks,
    looks the release up across several sources — the MusicBrainz Cover
    Art Archive first, then iTunes and Deezer as fallbacks — and saves
    the first front cover found into the folder as cover.jpg. Every
    source is gated by the same artist+album similarity check so a loose
    text match can't drop the wrong cover in. Navidrome picks up cover.*
    automatically, so the art is added without rewriting any track.
    Non-interactive: it takes the best match or reports no match. Artist
    images aren't handled here — Navidrome fetches those itself via its
    external agents.

--gain — normalize every track to a target loudness (ReplayGain):
    Writes a ReplayGain *track* gain to every file so tracks play at a
    uniform loudness (default target -14 LUFS). Loud tracks get a negative
    gain (turned down), quiet tracks a positive one, capped by
    positive-only clip protection. Set the target with --target. Existing
    tags are preserved and already-tagged files skipped, so re-runs are
    cheap; pass --wipe to delete all tags first and re-derive (needed once
    when changing the target). Album folders run in parallel (--jobs).
    --dry-run lists the per-track gains without writing (add --wipe to
    preview every file, since --dry-run alone skips already-tagged ones).

--missing — flag albums that look incomplete:
    Read-only pass. For each album folder, combines two signals:
    interior gaps in the local track-number sequence (1,2,4,5 → 3
    missing) and a MusicBrainz canonical-count check that catches
    missing trailing tracks (have 1–8, MB says 12 → 9–12 missing).
    The canonical count is the **shortest** matching MB release, so
    Japanese / deluxe / bonus-track editions can't make a complete
    standard album look short. Multi-disc folders (detected via
    duplicate tracknumbers) skip interior-gap detection and only
    compare file count against the canonical total. Albums with no
    album/artist tags or no tracknumbers are skipped — the default
    pass exists to fill those in.
"""
import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import time
from difflib import SequenceMatcher
from functools import lru_cache
from pathlib import Path

import mutagen
import requests

# mutagen's EasyMP4 doesn't map the MusicBrainz freeform atoms by default,
# so register the three IDs we write. EasyID3 (mp3) and VorbisComment
# (flac/ogg/opus) already handle these keys, so this is only needed so
# m4a/aac files don't error on write.
try:
    from mutagen.easymp4 import EasyMP4Tags
    for _key, _atom in (
        ("musicbrainz_trackid", "MusicBrainz Track Id"),
        ("musicbrainz_albumid", "MusicBrainz Album Id"),
        ("musicbrainz_artistid", "MusicBrainz Artist Id"),
    ):
        EasyMP4Tags.RegisterFreeformKey(_key, _atom)
except Exception:
    pass


AUDIO_EXTENSIONS = {".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav", ".aac"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
# Filename stems (case-insensitive) that count as an existing cover, so
# --art leaves those folders alone. Matches Navidrome's default lookup.
COVER_STEMS = {"cover", "folder", "front", "album", "albumart"}
# Extensions --cleanup deletes outright: download-bundle clutter Navidrome
# doesn't need — .nfo info files and .m3u/.m3u8 playlists.
CLEANUP_EXTENSIONS = {".nfo", ".m3u", ".m3u8"}
TAG_FIELDS = ("artist", "albumartist", "album", "title", "tracknumber")
# MusicBrainz IDs the default pass back-fills. musicbrainz_trackid is the
# *recording* ID (the historical tag name) — the one ListenBrainz
# playlists reference and Navidrome matches on; the other two are the
# release and (track) artist IDs. A track missing any of these triggers a
# recording lookup.
MBID_FIELDS = ("musicbrainz_trackid", "musicbrainz_albumid",
               "musicbrainz_artistid")
# Fields read off every file. The default missing-tag pass fills
# TAG_FIELDS and MBID_FIELDS, but --fix also needs the release date to
# spot albums that have been split across inconsistent date tags, and the
# genre to fill gaps and unify outliers per album.
READ_FIELDS = TAG_FIELDS + ("date", "genre") + MBID_FIELDS
MB_BASE = "https://musicbrainz.org/ws/2"
CAA_BASE = "https://coverartarchive.org"
USER_AGENT = "homer-tag-music/2.0 ( https://github.com/blaix/homer )"
MB_RATE_LIMIT_S = 1.1
CAA_RATE_LIMIT_S = 0.5
MB_MIN_SCORE = 80
SIMILAR_THRESHOLD = 0.85

DISC_TRACK_RE = re.compile(r"^(\d+)[-_.](\d+)[-_.\s]+(.+?)$")
TRACK_PREFIX_RE = re.compile(r"^(\d+)[-_.\s]+(.+?)$")
VA_ARTIST_TITLE_RE = re.compile(r"^(.+?)\s+[-–—]\s+(.+)$")
NORM_RE = re.compile(r"[^\w]+")
COSMETIC_RE = re.compile(r"[^\w\s]+")  # strip punctuation, keep letters/whitespace
COMPILATION_KEYWORDS = ("various", "compilation", "soundtrack")

BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
RESET = "\033[0m"

_last_mb_at = 0.0
_last_caa_at = 0.0


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
    parser.add_argument("--art", action="store_true",
                        help="download missing album cover art from the "
                             "Cover Art Archive into each album folder")
    parser.add_argument("--cleanup", action="store_true",
                        help="delete library clutter: AppleDouble sidecars "
                             "(._* beside a real file), .nfo info files, and "
                             ".m3u/.m3u8 playlists (prompts before deleting)")
    parser.add_argument("--gain", action="store_true",
                        help="normalize every track to a target loudness "
                             "(turns loud tracks down and quiet tracks up)")
    parser.add_argument("--target", type=float, default=-14.0,
                        help="target loudness in LUFS for --gain; every "
                             "track is normalized to it (default: -14)")
    parser.add_argument("--wipe", action="store_true",
                        help="with --gain, delete all existing ReplayGain "
                             "tags first and re-derive from scratch (default "
                             "preserves tags a file already has)")
    parser.add_argument("--jobs", type=int, default=None,
                        help="parallel album-folder workers for --gain "
                             "(default: CPU count)")
    parser.add_argument("--missing", action="store_true",
                        help="list albums that look like they have "
                             "missing tracks (read-only; uses MusicBrainz "
                             "to skip bonus-track editions)")
    args = parser.parse_args()

    maybe_disable_color()

    raw = args.path or input("Music folder: ").strip()
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    try:
        if args.cleanup:
            run_cleanup(root, dry_run=args.dry_run)
        elif args.gain:
            run_gain(root, dry_run=args.dry_run,
                     target=args.target, wipe=args.wipe, jobs=args.jobs)
        elif args.art:
            run_art(root, dry_run=args.dry_run)
        elif args.fix:
            run_fix(root, dry_run=args.dry_run)
        elif args.missing:
            run_missing(root)
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
    need_mbid = any(not current.get(f) for f in MBID_FIELDS)

    # Track number alone never triggers processing — by the user's spec —
    # but a missing MusicBrainz ID does, so an already-tagged library can
    # be back-filled with the IDs the ListenBrainz plugin matches on.
    triggers_text = bool(missing & {"artist", "albumartist", "album", "title"})
    if not triggers_text and not need_mbid:
        counts["complete"] += 1
        return

    artist_dir, album_dir = get_artist_album_dirs(path, root)

    print()
    print(f"{BOLD}{path}{RESET}")

    changes = {}
    effective_artist = current.get("artist")
    effective_albumartist = current.get("albumartist")
    effective_album = current.get("album")

    # Albumartist first — it tells us whether this is a compilation,
    # which changes how we resolve the per-track artist.
    if "albumartist" in missing:
        if artist_dir is None:
            print(f"  {DIM}skip: cannot derive albumartist from path{RESET}")
            counts["skipped"] += 1
            return
        if artist_dir not in albumartist_cache:
            albumartist_cache[artist_dir] = resolve_artist(
                artist_dir.name, label="albumartist")
        effective_albumartist = albumartist_cache[artist_dir]
        changes["albumartist"] = effective_albumartist

    is_va = is_compilation_albumartist(effective_albumartist)

    if "artist" in missing and not is_va:
        if effective_albumartist:
            # Single-artist album: artist == albumartist almost always.
            effective_artist = effective_albumartist
            changes["artist"] = effective_artist
        else:
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
            lookup_artist = effective_albumartist or effective_artist
            album_cache[album_dir] = resolve_album(album_dir.name,
                                                   lookup_artist)
        effective_album = album_cache[album_dir]
        changes["album"] = effective_album

    fixing_artist_or_album = "artist" in missing or "album" in missing
    need_va_artist = is_va and "artist" in missing
    need_title = "title" in missing
    need_tracknum = "tracknumber" in missing and fixing_artist_or_album

    if need_title or need_tracknum or need_va_artist or need_mbid:
        track_from_file, artist_from_file, title_from_file = parse_stem(
            path.stem, va=is_va)

        if need_va_artist:
            if artist_from_file:
                effective_artist = artist_from_file
                changes["artist"] = effective_artist
            else:
                print(f"  {DIM}compilation: no 'Artist - Title' in "
                      f"filename, leaving artist blank{RESET}")

        # Prefer the title already on the file (or just chosen above) over
        # the filename parse — it's the most reliable key for the search,
        # and back-filling MBIDs runs on files that are already titled.
        effective_title = (current.get("title")
                           or changes.get("title")
                           or title_from_file)

        mb_rec = None
        if effective_artist and effective_album and effective_title:
            mb_rec = mb_search_recording(effective_artist,
                                         effective_album,
                                         effective_title)

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

        if need_mbid and mb_rec:
            # Fill only the IDs that are absent; never overwrite an
            # existing one (it may be a more precise Picard tagging).
            #
            # The album id comes from a release search (mb_find_release),
            # NOT from whichever release happens to hang off the recording
            # match. A recording appears on many releases (US/UK/deluxe/
            # comp) returned in no particular order, so picking the first
            # similar one is arbitrary — and it disagrees with what --fix's
            # own mb_find_release lookup considers authoritative, so --fix
            # would re-flag the album and propose a different id. Routing
            # both passes through the same lookup makes them converge. The
            # recording match still supplies the recording and artist ids.
            release_mbid = None
            if not current.get("musicbrainz_albumid"):
                lookup_artist = effective_albumartist or effective_artist
                rel = mb_find_release(effective_album, lookup_artist)
                release_mbid = rel.get("release") if rel else None
            for field, value in (
                    ("musicbrainz_trackid", mb_rec.get("mbid")),
                    ("musicbrainz_albumid", release_mbid),
                    ("musicbrainz_artistid", mb_rec.get("artist_mbid"))):
                if not current.get(field) and value:
                    changes[field] = value

    if not changes:
        print(f"  {DIM}(nothing to write){RESET}")
        counts["skipped"] += 1
        return

    print("  writing:")
    for k, v in changes.items():
        print(f"    {k:20} {v}")

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
    date_clusters = find_date_clusters_per_album(library)
    albumid_clusters = find_albumid_clusters_per_album(library)

    print()
    print(f"  artist clusters     : {len(artist_clusters)}")
    print(f"  albumartist clusters: {len(albumartist_clusters)}")
    print(f"  album clusters      : {len(album_clusters)}")
    print(f"  date clusters       : {len(date_clusters)}")
    print(f"  album-id clusters   : {len(albumid_clusters)}")

    resolve_clusters("artist", artist_clusters, dry_run, counts)
    resolve_clusters("albumartist", albumartist_clusters, dry_run, counts)
    resolve_album_clusters(album_clusters, dry_run, counts)
    resolve_date_clusters(date_clusters, dry_run, counts)
    resolve_albumid_clusters(albumid_clusters, dry_run, counts)

    # After cluster cleanup; mismatches are computed off the updated state.
    mismatches = find_within_file_mismatches(library)
    print()
    print(f"{BOLD}within-file mismatches: {len(mismatches)}{RESET}")
    resolve_mismatches(mismatches, dry_run, counts)

    resolve_genres_per_album(library, root, dry_run, counts)

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


def find_date_clusters_per_album(library):
    """Release-date clusters scoped to one album at a time.

    Tracks of the same album (same albumartist, falling back to artist,
    plus album name — both normalized) should all carry the same release
    date. Files are bucketed by that pair, then the distinct date values
    within each bucket are surfaced. A bucket with two or more distinct
    dates is a cluster — the kind of split that makes Navidrome treat one
    album as several. Files with no date tag at all are ignored here;
    filling absent tags is the default pass's job, not --fix's.
    """
    by_album = {}
    for entry in library:
        a = entry["tags"].get("albumartist") or entry["tags"].get("artist")
        album = entry["tags"].get("album")
        if not a or not album:
            continue
        a_norm = NORM_RE.sub("", a.lower())
        al_norm = NORM_RE.sub("", album.lower())
        if not a_norm or not al_norm:
            continue
        by_album.setdefault((a_norm, al_norm), []).append(entry)

    clusters = []
    for entries in by_album.values():
        by_date = {}
        for e in entries:
            date = e["tags"].get("date")
            if not date:
                continue
            by_date.setdefault(date, []).append(e)
        if len(by_date) < 2:
            continue
        sorted_variants = sorted(by_date.items(), key=lambda x: -len(x[1]))
        sample = sorted_variants[0][1][0]
        clusters.append({
            "variants": sorted_variants,
            "context_artist": (sample["tags"].get("albumartist")
                               or sample["tags"].get("artist")),
            "context_album": sample["tags"].get("album"),
        })
    return clusters


def find_albumid_clusters_per_album(library):
    """MusicBrainz album-id clusters scoped to one album at a time.

    Tracks of the same album (same albumartist, falling back to artist,
    plus album name — both normalized) should all carry the same
    MusicBrainz Album Id. When they don't, Navidrome's default album
    grouping — whose persistent id keys on musicbrainz_albumid before
    falling back to albumartist/album — treats each distinct id as a
    separate release and splits one folder into several albums in the UI
    (the classic "why do I have four copies of Extraordinary Machine"
    case, where a per-recording tagger matched tracks to different
    releases of the same album). Files are bucketed by the (artist,
    album) pair, then the distinct musicbrainz_albumid values within each
    bucket are surfaced. A bucket with two or more distinct ids is a
    cluster — structurally the same split as a release-date cluster, just
    keyed on the id instead of the date. Files with no album-id tag at
    all are ignored here; back-filling absent ids is the default pass's
    job, not --fix's.
    """
    by_album = {}
    for entry in library:
        a = entry["tags"].get("albumartist") or entry["tags"].get("artist")
        album = entry["tags"].get("album")
        if not a or not album:
            continue
        a_norm = NORM_RE.sub("", a.lower())
        al_norm = NORM_RE.sub("", album.lower())
        if not a_norm or not al_norm:
            continue
        by_album.setdefault((a_norm, al_norm), []).append(entry)

    clusters = []
    for entries in by_album.values():
        by_id = {}
        blanks = []
        for e in entries:
            mbid = e["tags"].get("musicbrainz_albumid")
            if not mbid:
                blanks.append(e)
                continue
            by_id.setdefault(mbid, []).append(e)
        # Nothing to choose from when no track carries an id at all —
        # back-filling a wholly-untagged album is the default pass's job.
        if not by_id:
            continue
        # Flag the album when its ids disagree (two or more distinct ids)
        # or when some tracks carry an id and others are blank. Both split
        # the folder into separate albums in Navidrome — the blank case is
        # the common one the default pass leaves behind when a recording
        # lookup can't confidently match a track, so the chosen id is
        # applied to the untagged tracks too (see apply_cluster_choice).
        if len(by_id) < 2 and not blanks:
            continue
        sorted_variants = sorted(by_id.items(), key=lambda x: -len(x[1]))
        sample = sorted_variants[0][1][0]
        clusters.append({
            "variants": sorted_variants,
            "blanks": blanks,
            "context_artist": (sample["tags"].get("albumartist")
                               or sample["tags"].get("artist")),
            "context_album": sample["tags"].get("album"),
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


def resolve_date_clusters(clusters, dry_run, counts):
    if not clusters:
        return
    print()
    print(f"{BOLD}resolving release-date clusters ({len(clusters)}){RESET}")
    for cluster in clusters:
        ctx = cluster["context_artist"]
        if cluster.get("context_album"):
            ctx = f"{ctx} — {cluster['context_album']}"
        chosen = prompt_date_cluster(cluster, ctx)
        if chosen is None:
            continue
        apply_cluster_choice("date", cluster, chosen, dry_run, counts)


def prompt_date_cluster(cluster, context):
    """Resolve a release-date cluster.

    Beyond the disagreeing date variants found across the album's tracks,
    this offers two extra picks: the album's original release date looked
    up on MusicBrainz, and the latest of the listed dates. The MB date is
    the default when one is found (it's the authoritative answer), else we
    default to the latest.
    """
    variants = cluster["variants"]
    total = sum(len(entries) for _, entries in variants)

    print()
    title_ctx = f" [{context}]" if context else ""
    print(f"  {BOLD}date cluster{RESET}{title_ctx} "
          f"({len(variants)} variants, {total} files)")

    latest = latest_date([raw for raw, _ in variants])

    mb_date = None
    if cluster.get("context_artist") and cluster.get("context_album"):
        mb_date = mb_release_date(cluster["context_album"],
                                  cluster["context_artist"])

    for i, (raw, entries) in enumerate(variants, 1):
        marker = f" {DIM}(latest){RESET}" if raw == latest else ""
        print(f"    [{i}] {YELLOW}{raw}{RESET} ({len(entries)} files){marker}")

    # The MB date may coincide with a variant already on the list (same
    # string), in which case point at that variant instead of duplicating.
    mb_matches_idx = None
    if mb_date:
        for i, (raw, _) in enumerate(variants):
            if raw == mb_date:
                mb_matches_idx = i
                break
    if mb_date and mb_matches_idx is None:
        print(f"    [m] musicbrainz : {CYAN}{mb_date}{RESET}")
        default = "m"
    elif mb_date:
        print(f"    {DIM}(musicbrainz matches "
              f"variant [{mb_matches_idx + 1}]){RESET}")
        default = str(mb_matches_idx + 1)
    else:
        print(f"    {DIM}(musicbrainz: no date found){RESET}")
        default = "l"
    print(f"    [l] latest      : {latest}")
    print("    [t] type custom")
    print("    [s] skip")

    while True:
        choice = (input(f"    choose [default: {default}]: ")
                  .strip().lower() or default)
        if choice == "s":
            return None
        if choice == "l":
            return latest
        if choice == "m" and mb_date and mb_matches_idx is None:
            return mb_date
        if choice == "t":
            val = input("    enter date: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(variants):
                return variants[idx][0]
        print(f"    unrecognized: {choice!r}")


def resolve_albumid_clusters(clusters, dry_run, counts):
    if not clusters:
        return
    print()
    print(f"{BOLD}resolving musicbrainz album-id clusters "
          f"({len(clusters)}){RESET}")
    for cluster in clusters:
        ctx = cluster["context_artist"]
        if cluster.get("context_album"):
            ctx = f"{ctx} — {cluster['context_album']}"
        chosen = prompt_albumid_cluster(cluster, ctx)
        if chosen is None:
            continue
        apply_cluster_choice("musicbrainz_albumid", cluster, chosen,
                             dry_run, counts)


def prompt_albumid_cluster(cluster, context):
    """Resolve a MusicBrainz album-id cluster.

    The disagreeing ids found across the album's tracks are listed with
    their file counts, the dominant one ("majority") marked. We look the
    album up on MusicBrainz and, whenever it returns a release match, that
    id is the default — it's the authoritative answer, whether or not any
    track already carries it. If MB matches an id we already hold, that
    variant is marked and defaulted to; if MB points at an id present on
    no track, it's offered as [m] and is still the default. Only when MB
    has no match at all does the default fall back to the majority id
    already on the most tracks. The chosen id is written to every track in
    the album, including any with no album-id tag at all (those untagged
    tracks are what split the folder into a duplicate album in the first
    place).
    """
    variants = cluster["variants"]
    total = sum(len(entries) for _, entries in variants)
    n_blank = len(cluster.get("blanks", []))

    print()
    title_ctx = f" [{context}]" if context else ""
    blank_note = f", {n_blank} untagged" if n_blank else ""
    print(f"  {BOLD}musicbrainz album-id cluster{RESET}{title_ctx} "
          f"({len(variants)} variants, {total} files{blank_note})")

    majority = variants[0][0]

    mb_id = None
    if cluster.get("context_artist") and cluster.get("context_album"):
        rel = mb_find_release(cluster["context_album"],
                              cluster["context_artist"])
        if rel:
            mb_id = rel.get("release")

    mb_matches_idx = None
    if mb_id:
        for i, (raw, _) in enumerate(variants):
            if raw == mb_id:
                mb_matches_idx = i
                break

    for i, (raw, entries) in enumerate(variants, 1):
        marks = []
        if raw == majority:
            marks.append("majority")
        if mb_id and raw == mb_id:
            marks.append("musicbrainz")
        marker = f" {DIM}({', '.join(marks)}){RESET}" if marks else ""
        print(f"    [{i}] {YELLOW}{raw}{RESET} ({len(entries)} files){marker}")

    if mb_id and mb_matches_idx is None:
        print(f"    [m] musicbrainz : {CYAN}{mb_id}{RESET} "
              f"{DIM}(on no track){RESET}")
        default = "m"
    elif mb_id:
        default = str(mb_matches_idx + 1)
    else:
        print(f"    {DIM}(musicbrainz: no release match){RESET}")
        default = "1"
    print("    [t] type custom")
    print("    [s] skip")

    while True:
        choice = (input(f"    choose [default: {default}]: ")
                  .strip().lower() or default)
        if choice == "s":
            return None
        if choice == "m" and mb_id and mb_matches_idx is None:
            return mb_id
        if choice == "t":
            val = input("    enter musicbrainz album id: ").strip()
            if val:
                return val
            print("    (empty input)")
            continue
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(variants):
                return variants[idx][0]
        print(f"    unrecognized: {choice!r}")


def prompt_cluster(field, cluster, context_artist):
    variants = cluster["variants"]
    total = sum(len(entries) for _, entries in variants)

    print()
    title_ctx = f" [{context_artist}]" if context_artist else ""
    print(f"  {BOLD}{field} cluster{RESET}{title_ctx} "
          f"({len(variants)} variants, {total} files)")

    seed = variants[0][0]
    uses_mb = field in ("artist", "albumartist", "album")
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
        if uses_mb:
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
    # Tracks that carried no value at all (only album-id clusters record
    # these) get the chosen value written too, so an album split by a few
    # untagged tracks is fully unified rather than left half-fixed.
    for entry in cluster.get("blanks", []):
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


def resolve_genres_per_album(library, root, dry_run, counts):
    """Fill missing genres and unify outliers, one album folder at a time.

    Genre is near-uniform per album, so the album folder is the unit. An
    album is flagged when some of its tracks have no genre, or when the
    tracks carry disagreeing genre values. Uniform, fully-tagged albums
    are skipped so existing curation is left alone. For each flagged
    album the chosen genre defaults to the album's MusicBrainz genres
    (when a confident release match is found) and falls back to the
    album's own majority genre, written as one comma-joined value.

    Compilations (Various Artists / soundtracks) legitimately span
    genres, so they only get missing genres filled — existing per-track
    genres are never overwritten.
    """
    by_folder = {}
    for entry in library:
        artist_dir, album_dir = get_artist_album_dirs(entry["path"], root)
        folder = album_dir or artist_dir
        if folder is None:
            continue
        by_folder.setdefault(folder, []).append(entry)

    todo = []
    for folder, entries in sorted(by_folder.items()):
        present = {e["tags"].get("genre") for e in entries if e["tags"].get("genre")}
        n_missing = sum(1 for e in entries if not e["tags"].get("genre"))
        if n_missing == 0 and len(present) <= 1:
            continue
        todo.append((folder, entries))

    if not todo:
        return

    print()
    print(f"{BOLD}resolving album genres ({len(todo)}){RESET}")
    for folder, entries in todo:
        chosen = prompt_genre(folder, entries)
        if chosen is None:
            continue
        is_va = is_compilation_albumartist(
            album_artist_from_entries(entries)[1])
        for e in entries:
            cur = e["tags"].get("genre")
            if cur == chosen:
                continue
            # On compilations only fill blanks; never clobber an existing
            # per-track genre, since variety there is expected.
            if is_va and cur:
                continue
            write_one(e, {"genre": chosen}, dry_run, counts)


def album_artist_from_entries(entries):
    """Most common (album, albumartist-or-artist) across an album's entries."""
    albums = {}
    artists = {}
    for e in entries:
        al = e["tags"].get("album")
        if al:
            albums[al] = albums.get(al, 0) + 1
        ar = e["tags"].get("albumartist") or e["tags"].get("artist")
        if ar:
            artists[ar] = artists.get(ar, 0) + 1
    album = max(albums, key=albums.get) if albums else None
    artist = max(artists, key=artists.get) if artists else None
    return album, artist


def prompt_genre(folder, entries):
    """Resolve one album's genre. Returns the chosen string or None (skip)."""
    tally = {}
    for e in entries:
        g = e["tags"].get("genre")
        if g:
            tally[g] = tally.get(g, 0) + 1
    consensus = max(tally, key=tally.get) if tally else None
    n_missing = sum(1 for e in entries if not e["tags"].get("genre"))

    album, artist = album_artist_from_entries(entries)
    mb_list = mb_genres(album, artist) if (album and artist) else []
    mb = ", ".join(mb_list) if mb_list else None

    print()
    print(f"  {BOLD}{folder}{RESET}")
    print(f"  {DIM}{artist or '?'} — {album or '?'} "
          f"({len(entries)} tracks, {n_missing} missing genre){RESET}")
    for g, c in sorted(tally.items(), key=lambda x: -x[1]):
        print(f"    {YELLOW}{g}{RESET} ({c})")

    # MB is the default when present, else the album's own majority.
    if mb:
        print(f"    [m] musicbrainz : {CYAN}{mb}{RESET}")
    else:
        print(f"    {DIM}(musicbrainz: no genres found){RESET}")
    if consensus:
        print(f"    [c] consensus   : {consensus}")
    print("    [t] type custom")
    print("    [s] skip")

    if mb:
        default = "m"
    elif consensus:
        default = "c"
    else:
        default = "s"

    while True:
        choice = (input(f"    choose [default: {default}]: ")
                  .strip().lower() or default)[:1]
        if choice == "s":
            return None
        if choice == "m" and mb:
            return mb
        if choice == "c" and consensus:
            return consensus
        if choice == "t":
            val = input("    enter genre(s), comma-separated: ").strip()
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


# ----- --art mode -----

def run_art(root, dry_run):
    print(f"{BOLD}scanning album folders...{RESET}")
    albums = {}  # album folder Path -> [track paths]
    for path in iter_audio(root):
        artist_dir, album_dir = get_artist_album_dirs(path, root)
        folder = album_dir or artist_dir
        if folder is None:
            continue
        albums.setdefault(folder, []).append(path)
    print(f"  {len(albums)} album folders")

    counts = {"written": 0, "have": 0, "skipped": 0,
              "nomatch": 0, "errors": 0}

    for folder, paths in sorted(albums.items()):
        if folder_cover(folder):
            counts["have"] += 1
            continue

        album, artist = album_artist_for_folder(paths)
        print()
        print(f"{BOLD}{folder}{RESET}")
        if not album or not artist:
            print(f"  {DIM}skip: missing album/artist tags{RESET}")
            counts["skipped"] += 1
            continue
        print(f"  {DIM}{artist} — {album}{RESET}")

        img = find_cover_art(album, artist)
        if img is None:
            print(f"  {YELLOW}no cover art found "
                  f"(tried musicbrainz, itunes, deezer){RESET}")
            counts["nomatch"] += 1
            continue

        dest = folder / f"cover{ext_for_content_type(img['content_type'])}"
        size_kb = len(img["data"]) // 1024
        if dry_run:
            print(f"  {DIM}(dry-run){RESET} would write "
                  f"{dest.name} ({size_kb} KB, via {img['source']})")
            counts["written"] += 1
            continue
        try:
            dest.write_bytes(img["data"])
            print(f"  {GREEN}wrote {dest.name}{RESET} "
                  f"({size_kb} KB, via {img['source']})")
            counts["written"] += 1
            # Bump the tracks' mtimes so Navidrome's next scan treats the
            # album as changed and refreshes its cached cover art — a new
            # sibling cover.jpg alone wouldn't trigger that.
            bump_mtimes(folder, paths)
        except Exception as e:
            print(f"  {RED}[!] write failed: {e}{RESET}", file=sys.stderr)
            counts["errors"] += 1

    print()
    err = (f" {RED}errors={counts['errors']}{RESET}"
           if counts["errors"] else "")
    print(f"{BOLD}done.{RESET} "
          f"{GREEN}written={counts['written']}{RESET} "
          f"have-art={counts['have']} "
          f"no-match={counts['nomatch']} "
          f"skipped={counts['skipped']}{err}")


def find_cover_art(album, artist):
    """Walk art sources in order, returning the first front cover found.

    Each candidate is gated by similar() on both artist and album so a
    loose text search can't return a wrong cover. Result is the image
    dict {"data", "content_type", "source"} or None if every source
    came up empty.
    """
    rel = mb_find_release(album, artist)
    if rel is not None:
        img = None
        if rel.get("release"):
            img = caa_fetch_front("release", rel["release"])
        if img is None and rel.get("release_group"):
            img = caa_fetch_front("release-group", rel["release_group"])
        if img is not None:
            img["source"] = "musicbrainz"
            return img

    img = itunes_fetch_front(album, artist)
    if img is not None:
        img["source"] = "itunes"
        return img

    img = deezer_fetch_front(album, artist)
    if img is not None:
        img["source"] = "deezer"
        return img

    return None


def folder_cover(folder):
    """Return an existing cover image in folder, or None."""
    try:
        for p in folder.iterdir():
            if (p.is_file()
                    and p.suffix.lower() in IMAGE_EXTENSIONS
                    and p.stem.lower() in COVER_STEMS):
                return p
    except OSError:
        pass
    return None


def album_artist_for_folder(paths):
    """Most common (album, albumartist-or-artist) across a folder's tracks."""
    albums = {}
    artists = {}
    for path in paths:
        try:
            tags = read_tags(path)
        except Exception:
            continue
        album = tags.get("album")
        if album:
            albums[album] = albums.get(album, 0) + 1
        artist = tags.get("albumartist") or tags.get("artist")
        if artist:
            artists[artist] = artists.get(artist, 0) + 1
    album = max(albums, key=albums.get) if albums else None
    artist = max(artists, key=artists.get) if artists else None
    return album, artist


def bump_mtimes(folder, paths):
    """Touch the album's tracks (and its folder) to the current time.

    A folder cover.jpg added beside unchanged audio files won't trip
    Navidrome's quick scan, so the album's updated_at never moves and the
    cached grid thumbnail stays stale. Touching the tracks makes the next
    scan re-import them, which bumps the album's updated_at, changes its
    artwork id, and invalidates the old cached cover.
    """
    for p in paths:
        try:
            os.utime(p, None)
        except OSError:
            pass
    try:
        os.utime(folder, None)
    except OSError:
        pass


def ext_for_content_type(content_type):
    ct = (content_type or "").lower()
    if "png" in ct:
        return ".png"
    if "gif" in ct:
        return ".gif"
    if "webp" in ct:
        return ".webp"
    return ".jpg"


# ----- --cleanup mode -----

def run_cleanup(root, dry_run):
    """Delete clutter from the library: AppleDouble sidecars, plus .nfo
    info files and .m3u/.m3u8 playlists.

    macOS writes a ._<name> sidecar next to <name> on non-HFS volumes; we
    only delete a ._* file when its real counterpart exists in the same
    folder, so a (rare) legitimately-named ._ file with no sibling is left
    alone. .nfo and .m3u/.m3u8 files are download-bundle leftovers Navidrome
    doesn't need and are removed wherever they appear. The deletion is a
    single all-or-nothing prompt; when stdout isn't a terminal (piped to
    less, etc.) we can't safely prompt, so we just list and assume "no".
    """
    print(f"{BOLD}scanning for clutter...{RESET}")
    junk = set()
    # AppleDouble sidecars: only when the real file they shadow exists.
    for p in root.rglob("._*"):
        if p.is_file() and (p.parent / p.name[2:]).exists():
            junk.add(p)
    # Info files and playlists: download leftovers, removed anywhere.
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in CLEANUP_EXTENSIONS:
            junk.add(p)
    junk = sorted(junk)

    if not junk:
        print(f"  {GREEN}none found.{RESET}")
        return

    print(f"  {len(junk)} clutter file(s):")
    for p in junk:
        print(f"    {p}")

    if dry_run:
        print(f"  {DIM}(dry-run, nothing deleted){RESET}")
        return

    if not sys.stdout.isatty():
        print(f"  {DIM}(not a terminal, assuming no — nothing deleted){RESET}")
        return

    answer = input(f"  delete all {len(junk)}? [y/N]: ").strip().lower()
    if answer not in ("y", "yes"):
        print("  nothing deleted.")
        return

    deleted = 0
    for p in junk:
        try:
            p.unlink()
            deleted += 1
        except OSError as e:
            print(f"  {RED}[!] {p}: {e}{RESET}", file=sys.stderr)
    print(f"  {GREEN}deleted {deleted}.{RESET}")


# ----- --gain mode -----

# rsgain's `easy` recommended settings (share/rsgain/presets/default.ini):
# positive-only clip protection, 0 dB max sample peak, standard ReplayGain
# tags for Opus. We mirror them in custom mode so the normalize pass
# matches easy's per-format quality. Custom mode is single-threaded and its
# -O output is keyed by basename, so we drive it one folder at a time and
# parallelize across folders ourselves.
GAIN_BASE = ["rsgain", "custom", "-q", "-c", "p", "-m", "0"]


def run_gain(root, dry_run, target=-14.0, wipe=False, jobs=None):
    """Normalize every track to `target` LUFS with ReplayGain.

    rsgain measures and writes a track-gain tag in one pass per album
    folder: loud tracks get a negative gain, quiet ones a positive gain
    capped by positive-only clip protection. Per-folder invocation keeps
    rsgain's basename-only -O output unambiguous; folders run concurrently
    via a thread pool (each worker shells out to rsgain, so the GIL isn't
    a bottleneck). The -O table is parsed only to report how many tracks
    went up vs down.

    Existing tags are preserved by default (rsgain's -S skips them) so the
    pass is cheap to re-run as new tracks are added. `wipe=True` deletes
    all existing tags first and re-derives from scratch -- needed once
    when changing the target, since -S would otherwise skip stale tags.
    """
    if not shutil.which("rsgain"):
        sys.exit(f"{RED}rsgain not found on PATH.{RESET}")

    folders = {}
    for p in iter_audio(root):
        folders.setdefault(p.parent, []).append(p)
    if not folders:
        print(f"{DIM}no audio files found under {root}{RESET}")
        return

    target_s = str(target)
    # No -S when wiping: tags are gone (real run) or we want every file
    # classified for an accurate preview (dry-run --wipe).
    skip = [] if wipe else ["-S"]
    # Dry-run scans without writing tags; a real run writes them.
    tag_mode = "s" if dry_run else "i"
    workers = max(1, jobs or (os.cpu_count() or 4))

    state = []
    if wipe:
        state.append("wiping existing tags")
    if dry_run:
        state.append("dry-run")
    suffix = f" ({', '.join(state)})" if state else ""
    print(f"{BOLD}normalize ReplayGain{RESET} target {target_s} LUFS"
          f"{suffix}; {len(folders)} folders, {workers} workers")

    def process(folder):
        files = sorted(folders[folder])
        paths = [str(f) for f in files]
        if wipe and not dry_run:
            _run_rsgain(GAIN_BASE + ["-s", "d"] + paths)
        out = _run_rsgain(
            GAIN_BASE + skip + ["-s", tag_mode, "-l", target_s, "-O"] + paths,
            capture=True)
        return _parse_gains(out, folder)

    up = 0
    down = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for gains in ex.map(process, sorted(folders)):
            for path, gain in gains:
                if gain > 0:
                    up += 1
                    label = f"{GREEN}up  {gain:+.1f} dB{RESET}"
                else:
                    down += 1
                    label = f"{YELLOW}down{gain:+.1f} dB{RESET}"
                print(f"  {label}  {path.relative_to(root)}")

    verb = "would tag" if dry_run else "tagged"
    print(f"{BOLD}{verb} {up + down}{RESET} track(s); "
          f"{up} boosted, {down} turned down")


def _run_rsgain(cmd, capture=False):
    try:
        result = subprocess.run(
            cmd, check=False,
            stdout=subprocess.PIPE if capture else None,
            text=True)
    except OSError as e:
        sys.exit(f"{RED}failed to run rsgain: {e}{RESET}")
    if result.returncode != 0:
        sys.exit(f"{RED}rsgain exited with status "
                 f"{result.returncode}{RESET}")
    return result.stdout if capture else ""


def _parse_gains(output, folder):
    """(path, gain_dB) for each file in rsgain's -O table.

    The output is tab-delimited with a header row; column 0 is the
    basename and column 2 the clip-adjusted track gain (negative = turned
    down, positive = boosted). Rows that don't parse (header, error lines)
    are skipped.
    """
    gains = []
    for line in output.splitlines():
        cols = line.split("\t")
        if len(cols) < 3:
            continue
        try:
            gain = float(cols[2])
        except ValueError:
            continue  # header row or an error line
        gains.append((folder / cols[0], gain))
    return gains


# ----- --missing mode -----

def run_missing(root):
    """Flag albums whose track set looks incomplete.

    Interior gaps in local track-number sequences are reported on
    their own (high confidence — they're holes in your own files).
    For the trailing case (have 1–8 of a 12-track album) we lean on
    MusicBrainz: the smallest matching release wins as the canonical
    count so bonus-track editions on Japanese / deluxe pressings
    can't make a complete standard album look short.
    """
    print(f"{BOLD}scanning album folders...{RESET}")
    albums = {}
    for path in iter_audio(root):
        artist_dir, album_dir = get_artist_album_dirs(path, root)
        folder = album_dir or artist_dir
        if folder is None:
            continue
        albums.setdefault(folder, []).append(path)
    print(f"  {len(albums)} album folders")

    flagged = 0
    for folder, paths in sorted(albums.items()):
        finding = inspect_album(paths)
        if finding is None:
            continue
        flagged += 1
        report_missing(folder, finding)

    print()
    print(f"{BOLD}done.{RESET} "
          f"{YELLOW}flagged={flagged}{RESET} "
          f"checked={len(albums)}")


def inspect_album(paths):
    """Detect missing tracks across a folder's audio files.

    Returns a finding dict or None if nothing looks off (or there
    isn't enough tag info to judge).
    """
    entries = []
    album_name = None
    artist_name = None
    for path in paths:
        try:
            tags = read_tags(path)
        except Exception:
            continue
        entries.append(tags)
        if not album_name:
            album_name = tags.get("album")
        if not artist_name:
            artist_name = tags.get("albumartist") or tags.get("artist")

    if not entries or not album_name or not artist_name:
        return None

    track_nums = []
    for tags in entries:
        n = parse_tracknum(tags.get("tracknumber"))
        if n:
            track_nums.append(n)
    if not track_nums:
        return None

    # Duplicate tracknumbers mean per-disc numbering, so gap detection
    # on the raw numbers would be a false-positive minefield.
    multi_disc = len(track_nums) != len(set(track_nums))
    interior_gaps = []
    if not multi_disc:
        interior_gaps = find_gaps(sorted(set(track_nums)))

    canonical = mb_canonical_track_count(album_name, artist_name)

    trailing = []
    shortfall = None
    if canonical:
        if multi_disc:
            if len(entries) < canonical:
                shortfall = canonical - len(entries)
        else:
            max_existing = max(track_nums)
            if max_existing < canonical:
                trailing = list(range(max_existing + 1, canonical + 1))
        # Bonus-edition filter: drop interior gaps past the canonical
        # count — that's the bonus region of an extended pressing.
        interior_gaps = [g for g in interior_gaps if g <= canonical]

    if not interior_gaps and not trailing and not shortfall:
        return None

    return {
        "album": album_name,
        "artist": artist_name,
        "local_count": len(entries),
        "canonical": canonical,
        "interior_gaps": interior_gaps,
        "trailing": trailing,
        "shortfall": shortfall,
    }


def report_missing(folder, finding):
    print()
    print(f"{BOLD}{folder}{RESET}")
    print(f"  {DIM}{finding['artist']} — {finding['album']}{RESET}")
    if finding["canonical"]:
        count_str = f"{finding['local_count']}/{finding['canonical']}"
    else:
        count_str = f"{finding['local_count']}/?"
    parts = [f"have {count_str}"]
    if finding["interior_gaps"]:
        gaps = ", ".join(str(n) for n in finding["interior_gaps"])
        parts.append(f"gaps: {gaps}")
    if finding["trailing"]:
        t = finding["trailing"]
        rng = f"{t[0]}–{t[-1]}" if len(t) > 1 else str(t[0])
        parts.append(f"trailing: {rng}")
    if finding["shortfall"]:
        parts.append(f"short by {finding['shortfall']} (multi-disc)")
    print(f"  {YELLOW}{'  '.join(parts)}{RESET}")


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
        artist_mbid = (ac[0].get("artist") or {}).get("id")
        for rel in rec.get("releases", []) or []:
            if not similar(rel.get("title", ""), album):
                continue
            base = {
                "title": rec_title,
                "mbid": rec.get("id"),
                "artist_mbid": artist_mbid,
            }
            for medium in rel.get("media", []) or []:
                for track in medium.get("track", []) or []:
                    if similar(track.get("title", ""), title):
                        n = track.get("number")
                        return {**base,
                                "tracknumber": str(n) if n else None}
            return {**base, "tracknumber": None}
    return None


@lru_cache(maxsize=None)
def mb_find_release(album, artist):
    """Best-matching release MBID (plus its release-group MBID).

    Cached because both the default pass (back-filling musicbrainz_albumid)
    and --fix resolve the album id through here, often for the same album
    across many files — one release search per (album, artist) is enough.
    Callers only read the returned dict, so sharing it is safe."""
    q = f'release:"{escape(album)}" AND artist:({lucene_terms(artist)})'
    data = mb_get("release", {"query": q, "fmt": "json", "limit": "5"})
    if not data:
        return None
    for item in data.get("releases", []) or []:
        if item.get("score", 0) < MB_MIN_SCORE:
            continue
        if not similar(item.get("title", ""), album):
            continue
        rg = item.get("release-group") or {}
        return {
            "release": item.get("id"),
            "release_group": rg.get("id"),
            "title": item.get("title"),
        }
    return None


@lru_cache(maxsize=None)
def mb_genres(album, artist):
    """The album's top genres per MusicBrainz, Title-Cased, or [].

    Resolves the album's release-group (via the same gated search --art
    uses) and reads its folksonomy genres, which carry community vote
    counts. The genres are returned highest-vote-first, capped at three
    so the joined value stays useful for the umbrella `contains` rules
    rather than a sprawling tag list. MB genres are lowercase, so they're
    Title-Cased to match the rest of the library.
    """
    rel = mb_find_release(album, artist)
    if not rel or not rel.get("release_group"):
        return []
    data = mb_get(f"release-group/{rel['release_group']}",
                  {"inc": "genres", "fmt": "json"})
    if not data:
        return []
    genres = [g for g in (data.get("genres") or [])
              if g.get("name") and g.get("count", 0) > 0]
    genres.sort(key=lambda g: -g.get("count", 0))
    return [g["name"].title() for g in genres[:3]]


@lru_cache(maxsize=None)
def mb_canonical_track_count(album, artist):
    """Smallest matching MB release's track count, summed across discs.

    Used by --missing as the canonical album length. Picking the
    minimum across pressings is the bonus-track defense: deluxe /
    Japanese / anniversary editions add tracks, so the standard
    release is the shortest.
    """
    q = f'release:"{escape(album)}" AND artist:({lucene_terms(artist)})'
    data = mb_get("release", {"query": q, "fmt": "json", "limit": "10"})
    if not data:
        return None
    counts = []
    for item in data.get("releases", []) or []:
        if item.get("score", 0) < MB_MIN_SCORE:
            continue
        if not similar(item.get("title", ""), album):
            continue
        ac = item.get("artist-credit", []) or []
        if not ac or not similar(ac[0].get("name", ""), artist):
            continue
        media = item.get("media", []) or []
        total = sum((m.get("track-count") or 0) for m in media)
        if total > 0:
            counts.append(total)
    return min(counts) if counts else None


@lru_cache(maxsize=None)
def mb_release_date(album, artist):
    """The album's original release date per MusicBrainz, or None.

    Used by --fix to break release-date ties: among the matching
    releases we take the earliest date, which is the album's original
    release rather than a later reissue. The raw MB string (which may be
    a bare year, year-month, or full date) is returned as-is.
    """
    q = f'release:"{escape(album)}" AND artist:({lucene_terms(artist)})'
    data = mb_get("release", {"query": q, "fmt": "json", "limit": "10"})
    if not data:
        return None
    dates = []
    for item in data.get("releases", []) or []:
        if item.get("score", 0) < MB_MIN_SCORE:
            continue
        if not similar(item.get("title", ""), album):
            continue
        ac = item.get("artist-credit", []) or []
        if not ac or not similar(ac[0].get("name", ""), artist):
            continue
        d = item.get("date")
        if d:
            dates.append(d)
    return min(dates, key=date_sort_key) if dates else None


# ----- Cover Art Archive -----

def caa_fetch_front(kind, mbid):
    """Download the front cover for a release / release-group MBID.

    Returns {"data": bytes, "content_type": str} or None (404 / error).
    """
    global _last_caa_at
    wait = CAA_RATE_LIMIT_S - (time.monotonic() - _last_caa_at)
    if wait > 0:
        time.sleep(wait)
    url = f"{CAA_BASE}/{kind}/{mbid}/front"
    headers = {"User-Agent": USER_AGENT}
    try:
        r = requests.get(url, headers=headers, timeout=30)
        _last_caa_at = time.monotonic()
        if r.status_code == 404:
            return None
        r.raise_for_status()
        return {
            "data": r.content,
            "content_type": r.headers.get("Content-Type", ""),
        }
    except Exception as e:
        print(f"    {DIM}(CAA {kind} fetch failed: {e}){RESET}",
              file=sys.stderr)
        _last_caa_at = time.monotonic()
        return None


# ----- art fallbacks (iTunes, Deezer) -----

def itunes_fetch_front(album, artist):
    """Front cover via the keyless iTunes Search API, or None."""
    data = http_get_json("https://itunes.apple.com/search", {
        "term": f"{artist} {album}",
        "entity": "album",
        "limit": "10",
    })
    if not data:
        return None
    for item in data.get("results", []) or []:
        if not similar(item.get("collectionName", ""), album):
            continue
        if not similar(item.get("artistName", ""), artist):
            continue
        url = item.get("artworkUrl100")
        if not url:
            continue
        # The 100x100 thumbnail URL upscales by swapping the dimensions.
        url = url.replace("100x100bb", "600x600bb")
        return download_image(url)
    return None


def deezer_fetch_front(album, artist):
    """Front cover via the keyless Deezer API, or None."""
    data = http_get_json("https://api.deezer.com/search/album", {
        "q": f'artist:"{artist}" album:"{album}"',
    })
    if not data:
        return None
    for item in data.get("data", []) or []:
        if not similar(item.get("title", ""), album):
            continue
        art = item.get("artist") or {}
        if not similar(art.get("name", ""), artist):
            continue
        url = item.get("cover_xl") or item.get("cover_big")
        if not url:
            continue
        return download_image(url)
    return None


def http_get_json(url, params):
    headers = {"User-Agent": USER_AGENT}
    try:
        r = requests.get(url, params=params, headers=headers, timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"    {DIM}(art search failed: {e}){RESET}", file=sys.stderr)
        return None


def download_image(url):
    headers = {"User-Agent": USER_AGENT}
    try:
        r = requests.get(url, headers=headers, timeout=30)
        r.raise_for_status()
        return {
            "data": r.content,
            "content_type": r.headers.get("Content-Type", ""),
        }
    except Exception as e:
        print(f"    {DIM}(image download failed: {e}){RESET}",
              file=sys.stderr)
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
    for k in READ_FIELDS:
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


def parse_stem(stem, va=False):
    stem = stem.strip()
    track = None
    rest = stem
    m = DISC_TRACK_RE.match(stem)
    if m:
        track = str(int(m.group(2)))
        rest = m.group(3).strip()
    else:
        m = TRACK_PREFIX_RE.match(stem)
        if m:
            track = str(int(m.group(1)))
            rest = m.group(2).strip()

    artist = None
    title = rest
    if va:
        m = VA_ARTIST_TITLE_RE.match(rest)
        if m:
            artist = m.group(1).strip()
            title = m.group(2).strip()

    return track, artist, title


def parse_tracknum(s):
    """Leading integer of a track tag like '5', '05', '5/12', or None."""
    if not s:
        return None
    m = re.match(r"^(\d+)", str(s))
    return int(m.group(1)) if m else None


def date_sort_key(d):
    """Sortable (year, month, day) for a release date string.

    Handles bare years, year-month, and full dates by pulling out the
    leading numbers and padding the missing parts with zero, so a bare
    "1999" sorts just before "1999-09-21".
    """
    parts = [int(n) for n in re.findall(r"\d+", str(d))[:3]]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def latest_date(dates):
    """The latest of a set of release-date strings (chronologically)."""
    return max(dates, key=date_sort_key)


def find_gaps(sorted_nums):
    """Interior gaps in a sorted unique sequence ([1,2,4,5] -> [3])."""
    if not sorted_nums:
        return []
    full = set(range(sorted_nums[0], sorted_nums[-1] + 1))
    return sorted(full - set(sorted_nums))


def is_compilation_albumartist(s):
    """True if albumartist looks like a compilation marker.

    Matches "Various Artists", "VA", "V.A.", "V/A", "Compilation",
    "Original Soundtrack", etc. Uses normalized substring against the
    longer keywords, plus an exact match for "va" to avoid false
    positives like "Vacation".
    """
    if not s:
        return False
    norm = NORM_RE.sub("", s).lower()
    if norm == "va":
        return True
    return any(k in norm for k in COMPILATION_KEYWORDS)


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
