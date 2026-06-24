{ pkgs }:

# sort-media: rename and move movie, TV, and music files into tidy,
# server-friendly layouts using FileBot (video matched against TheMovieDB /
# TheTVDB; music identified by AcoustID audio fingerprint). Point it at a
# directory and it reorganizes the files inside it *in place*. The common use
# is sorting a download/inbox folder into lowercase movies/, tv/, and music/
# subfolders (mirroring /mnt/media), then running tag-music over the music and
# rsyncing each into the real library. Also works pointed straight at a library
# folder (/mnt/media/movies, /mnt/media/tv, /mnt/media/music).
#
# This only renames/moves — it never writes tags (FileBot doesn't). tag-music
# remains the music tagger; sort-media just gets files into the Artist/Album/
# Track layout it expects.
#
# FileBot is unfree and its CLI requires a *purchased* license (a .psm file)
# to run -rename. Activate it once per machine/user with:
#     filebot --license /path/to/FileBot_License_Pxxxx.psm
# or pass --license <path> to this script the first time. See
# https://www.filebot.net/purchase.html
let
  # FileBot 5.2.0 calls `fpcalc -json` for AcoustID matching, but chromaprint
  # 1.6.0 prints a fractional "duration" (e.g. 153.933) that FileBot parses as
  # an integer -> java.lang.NumberFormatException "Bad duration value", which
  # aborts every music match. Shim fpcalc to floor the duration to an integer
  # in both the JSON and legacy text output forms. The real fpcalc is called by
  # absolute path, so it works regardless of PATH order, and pipefail keeps its
  # exit status. See https://www.filebot.net/forums/viewtopic.php?t=3317
  fpcalc-int = pkgs.writeShellScriptBin "fpcalc" ''
    set -o pipefail
    ${pkgs.chromaprint}/bin/fpcalc "$@" | ${pkgs.gnused}/bin/sed -E \
      -e 's/("duration": [0-9]+)\.[0-9]+/\1/' \
      -e 's/^(DURATION=[0-9]+)\.[0-9]+$/\1/'
  '';
in
pkgs.writeShellApplication {
  name = "sort-media";
  # fpcalc-int = chromaprint's fpcalc wrapped to fix its fractional-duration
  # output (see above); FileBot shells out to fpcalc by bare name for AcoustID
  # fingerprinting, and it isn't in filebot's own closure.
  runtimeInputs = with pkgs; [ filebot findutils coreutils fpcalc-int ];
  text = ''
    usage() {
      cat <<'EOF'
    Usage: sort-media [options] <path>

    Renames and moves movie, TV, and music files under <path> into tidy
    layouts using FileBot. Operates in place: matched files are relocated
    within <path>. Unmatched files are left untouched.

    Mode (pick one; default is --auto):
      -a, --auto     Sort a mixed download/inbox folder into lowercase movies/,
                     tv/, and music/ subfolders of <path> (mirroring /mnt/media),
                     so each can be rsynced into the matching library:
                       movies/Name (Year)/Name (Year).ext
                       tv/Name/Season NN/Name - SxxExx - Title.ext
                       music/Artist/Album/NN - Title.ext
      -m, --movies   Treat everything as movies. Lays them out directly under
                     <path> as "Name (Year)/Name (Year).ext".
      -t, --tv       Treat everything as episodes. Lays them out directly under
                     <path> as "Name/Season NN/Name - SxxExx - Title.ext".
          --music    Treat everything as music. Reads each file's existing
                     tags (--db ID3) and lays tracks out directly under <path>
                     as "Artist/Album/NN - Title.ext" — the layout tag-music
                     expects. Renames only; run tag-music afterward (Navidrome
                     groups by tags, so the tagging is what matters).

    Options:
      -n, --dry-run     Show proposed renames without moving anything
                        (FileBot --action test). Also lists clutter that would
                        be removed, without deleting it.
          --copy        Copy instead of move (leave the originals in place).
          --fingerprint Music: identify by AcoustID audio fingerprint instead
                        of reading tags. For untagged/mislabeled files. Slower
                        (network + fpcalc) and matches per-track, which can
                        split one album across releases — prefer the tag-based
                        default for already-tagged rips.
          --license F   Activate a FileBot .psm license, then continue.
      -h, --help        Show this help.

    Examples:
      sort-media /mnt/media/inbox                 # sort a mixed inbox
      sort-media --dry-run /mnt/media/inbox       # preview first
      sort-media --movies /mnt/media/movies       # tidy the movie library
      sort-media --music /mnt/media/music         # identify/sort, then tag-music
    EOF
    }

    mode="auto"
    action="move"
    music_db="ID3"
    license=""
    path=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -a|--auto) mode="auto" ;;
        -m|--movies) mode="movies" ;;
        -t|--tv) mode="tv" ;;
        --music) mode="music" ;;
        --fingerprint) music_db="AcoustID" ;;
        -n|--dry-run) action="test" ;;
        --copy) action="copy" ;;
        --license) shift; license="''${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        --) shift; path="''${1:-}"; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) path="$1" ;;
      esac
      shift
    done

    # Activate a license if one was passed, before the preflight check.
    if [ -n "$license" ]; then
      if [ ! -f "$license" ]; then
        echo "License file not found: $license" >&2
        exit 1
      fi
      echo "==> Activating FileBot license: $license"
      filebot --license "$license"
    fi

    if [ -z "$path" ]; then
      usage >&2
      exit 2
    fi
    if [ ! -d "$path" ]; then
      echo "Not a directory: $path" >&2
      exit 1
    fi

    # FileBot's CLI silently does nothing useful without a valid license, so
    # fail fast with a clear message instead. Only block on the unambiguous
    # UNREGISTERED signal so a string-format change can't lock out a licensed
    # install.
    if filebot -script fn:sysinfo 2>/dev/null | grep -qi "UNREGISTERED"; then
      echo "FileBot has no valid license installed." >&2
      echo "Activate it once with:" >&2
      echo "    filebot --license /path/to/FileBot_License_Pxxxx.psm" >&2
      echo "or pass --license <file> to this command." >&2
      echo "Purchase: https://www.filebot.net/purchase.html" >&2
      exit 1
    fi

    # Run one FileBot rename pass. All passes share these flags: -non-strict
    # enables opportunistic name/fingerprint matching when an exact match
    # isn't found; --apply prune clears the empty source folders FileBot moved
    # files out of during this run.
    #
    # FileBot exits non-zero whenever it can't match some files (a normal,
    # expected outcome) or hits an error mid-pass. The whole script runs under
    # `set -e`, so a bare call would abort here and SKIP the clutter cleanup and
    # empty-folder sweep below — which is exactly why leftovers lingered. Guard
    # the call so a non-zero exit is reported but never fatal; cleanup always
    # runs afterward.
    run_filebot() {
      local desc="$1"; shift
      local fbcmd=(filebot -rename "$path" -r -non-strict \
                   --output "$path" --action "$action" --apply prune "$@")
      echo "==> [$desc] ''${fbcmd[*]}"
      if ! "''${fbcmd[@]}"; then
        echo "    [$desc] filebot exited non-zero (some files unmatched or an" \
             "error occurred) — continuing to cleanup." >&2
      fi
    }

    # Music layout tag-music expects: Artist/Album/NN - Title. The album-artist
    # folder (falling back to track artist) keeps a compilation's tracks
    # together, and the per-track artist is added to the filename only when it
    # differs from the album artist — i.e. the "NN - Artist - Title" form
    # tag-music parses for Various-Artists albums, and plain "NN - Title"
    # otherwise.
    music_fmt="{any{albumArtist}{artist}}/{album}/{pi.pad(2)} - {any{albumArtist != artist ? artist+' - '+t : t}{t}}"

    # --auto unified video format: episodes take the first branch; movies fall
    # through to the second (the episode-only bindings throw for a movie, so
    # any{} picks the movie branch). Both get a lowercase tv/ or movies/ prefix
    # to mirror /mnt/media. Specials go to a "Season 00" folder (see --tv).
    video_auto_fmt="{any{'tv/'+n+'/'+(episode.special ? 'Season 00' : 'Season '+s.pad(2))+'/'+n+' - '+s00e00+' - '+t}{'movies/'+n+' ('+y+')/'+n+' ('+y+')'}}"

    echo "==> mode=$mode action=$action path=$path"
    case "$mode" in
      auto)
        # Two passes over the mixed folder, split by media type (f.video /
        # f.audio) so the video pass never tries to match a song as a movie,
        # and AcoustID never fingerprints a video.
        run_filebot "video" --file-filter "f.video" --format "$video_auto_fmt"
        run_filebot "music" --db "$music_db" --file-filter "f.audio" --format "music/$music_fmt"
        ;;
      movies)
        run_filebot "movies" --db TheMovieDB --format "{n} ({y})/{n} ({y})"
        ;;
      tv)
        # Specials have a null season, so a bare {s.pad(2)} would yield an empty
        # "Season " folder. The ternary short-circuits before s.pad(2) for
        # specials and maps them to "Season 00" — consistent with the numbered
        # "Season NN" folders, and read by Jellyfin as season 0.
        run_filebot "tv" --db "TheMovieDB::TV" --format "{n}/{episode.special ? 'Season 00' : 'Season '+s.pad(2)}/{n} - {s00e00} - {t}"
        ;;
      music)
        # Default --db ID3 reads each file's existing tags, so an album's
        # tracks stay together under one folder (the download's own album tag
        # is uniform). --fingerprint switches to AcoustID, which matches each
        # track independently and can scatter one album across several
        # MusicBrainz releases (e.g. live/bonus tracks landing in a "(Deluxe)"
        # folder). Renames only — run tag-music afterward; Navidrome groups by
        # tags, so the tagging is what actually matters.
        run_filebot "music" --db "$music_db" --format "$music_fmt"
        ;;
    esac

    # After moving the real files out, a source folder is often left holding
    # only cruft, which would stop the empty-folder sweep below from removing
    # it. Two kinds: macOS sidecar junk (._* AppleDouble forks, .DS_Store,
    # Spotlight/Trashes dirs) and download clutter beside the video FileBot
    # moved out — scene release info/notes (.nfo, .txt, .url, .sfv) and Windows
    # turds (Thumbs.db, desktop.ini). None of it has value on the servers
    # (Jellyfin fetches video metadata online; Navidrome + tag-music handle
    # music tags). Subtitles, artwork, and the media files themselves are
    # never matched here.
    clutter=(
      -name '._*' -o -name '.DS_Store' -o -name '.AppleDouble'
      -o -name '.Spotlight-V100' -o -name '.Trashes' -o -name '.fseventsd'
      -o -name '.TemporaryItems' -o -name '.apdisk'
      -o -iname '*.nfo' -o -iname '*.txt' -o -iname '*.url' -o -iname '*.sfv'
      -o -iname 'thumbs.db' -o -iname 'desktop.ini'
    )
    # -depth so a junk dir's contents are visited before the dir; rm -rf to
    # clear non-empty junk dirs (Spotlight etc.). On --dry-run nothing is
    # deleted — the matches are just listed.
    if [ "$action" = "test" ]; then
      echo "==> (dry-run) clutter that would be removed under $path:"
      find "$path" -depth \( "''${clutter[@]}" \) -print \
        | while IFS= read -r f; do echo "    would remove: $f"; done || true
    else
      echo "==> removing macOS junk and download clutter under $path"
      find "$path" -depth \( "''${clutter[@]}" \) -print -exec rm -rf {} + \
        | while IFS= read -r f; do echo "    removed: $f"; done || true
    fi

    # FileBot's --apply prune only tidies folders that held files it moved in
    # this run, so empty folders left over from earlier runs (or the old
    # "Season" layout) linger. Sweep them all here. -delete implies -depth, so
    # nested empty trees collapse in one pass. <path> itself is never removed
    # (-mindepth 1). Skipped on --dry-run so a preview deletes nothing.
    if [ "$action" != "test" ]; then
      echo "==> pruning empty folders under $path"
      find "$path" -mindepth 1 -type d -empty -print -delete \
        | while IFS= read -r d; do echo "    removed: $d"; done || true
    fi
  '';
}
