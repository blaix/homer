{ pkgs }:

# cbr2cbz: convert RAR-based comic archives (.cbr, including RAR5) into .cbz
# (a plain zip), which Komga reads natively. Komga's reader only supports RAR4,
# so most modern .cbr files come up "unsupported". This verifies the source is
# complete before converting, so a truncated/corrupt download never silently
# becomes a broken .cbz.
pkgs.writeShellApplication {
  name = "cbr2cbz";
  runtimeInputs = with pkgs; [ unrar zip unzip coreutils findutils gnused ];
  text = ''
    usage() {
      cat <<'EOF'
    Usage: cbr2cbz [options] <file.cbr | dir> ...

    Converts each .cbr to a .cbz alongside it (same name, .cbz extension).
    Directories are searched recursively for .cbr files.

    Options:
      -r, --rm       Delete the source .cbr after a verified conversion
      -f, --force    Overwrite an existing .cbz
      -h, --help     Show this help
    EOF
    }

    rm_source=0
    force=0
    args=()

    while [ $# -gt 0 ]; do
      case "$1" in
        -r|--rm) rm_source=1 ;;
        -f|--force) force=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) args+=("$1") ;;
      esac
      shift
    done

    if [ "''${#args[@]}" -eq 0 ]; then
      usage >&2
      exit 2
    fi

    # Collect target .cbr files from the given files/directories.
    cbrs=()
    for p in "''${args[@]}"; do
      if [ -d "$p" ]; then
        while IFS= read -r -d "" f; do
          cbrs+=("$f")
        done < <(find "$p" -type f -iname "*.cbr" -print0 | sort -z)
      elif [ -f "$p" ]; then
        cbrs+=("$p")
      else
        echo "skip: not found: $p" >&2
      fi
    done

    if [ "''${#cbrs[@]}" -eq 0 ]; then
      echo "No .cbr files found." >&2
      exit 1
    fi

    # Scratch state cleaned up on every exit path.
    tmp=""
    partial=""
    cleanup() {
      [ -n "$tmp" ] && rm -rf "$tmp"
      [ -n "$partial" ] && rm -f "$partial"
      tmp=""
      partial=""
    }
    trap cleanup EXIT

    ok=0
    failed=0
    skipped=0

    for src in "''${cbrs[@]}"; do
      out="''${src%.[cC][bB][rR]}.cbz"
      echo "==> $src"

      if [ -e "$out" ] && [ "$force" -ne 1 ]; then
        echo "    skip: $out already exists (use --force to overwrite)"
        skipped=$((skipped + 1))
        continue
      fi

      # 1. Verify the source archive is complete and not corrupt.
      if ! unrar t -inul "$src" >/dev/null 2>&1; then
        echo "    FAIL: corrupt or not a RAR archive (source left untouched)" >&2
        failed=$((failed + 1))
        continue
      fi

      # Keep scratch on the same filesystem as the source (avoids filling a
      # RAM-backed /tmp and lets the final move be a fast rename).
      dir="$(dirname "$src")"
      tmp="$(mktemp -d "$dir/.cbr2cbz.XXXXXX")"
      partial="$out.partial"

      # 2. Extract.
      if ! unrar x -inul -o+ "$src" "$tmp/" >/dev/null 2>&1; then
        echo "    FAIL: extraction error (source left untouched)" >&2
        cleanup
        failed=$((failed + 1))
        continue
      fi

      # 3. Repackage as zip. Pages are already-compressed images, so store them
      #    (-0) and add entries in sorted order for predictable page ordering.
      if ! ( cd "$tmp" && find . -type f | sed "s|^\./||" | LC_ALL=C sort | zip -0 -X -q "$partial" -@ ); then
        echo "    FAIL: could not build .cbz (source left untouched)" >&2
        cleanup
        failed=$((failed + 1))
        continue
      fi

      # 4. Verify the produced zip before putting it in place.
      if ! unzip -tqq "$partial" >/dev/null 2>&1; then
        echo "    FAIL: produced .cbz failed verification (source left untouched)" >&2
        cleanup
        failed=$((failed + 1))
        continue
      fi

      mv -f "$partial" "$out"
      partial=""
      chmod 644 "$out"
      cleanup
      echo "    OK: $out"

      if [ "$rm_source" -eq 1 ]; then
        rm -f "$src"
        echo "    removed source: $src"
      fi
      ok=$((ok + 1))
    done

    echo "Done. converted=$ok failed=$failed skipped=$skipped"
    [ "$failed" -eq 0 ]
  '';
}
