#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$(dirname "$DIR")"
SCRIPTS_DIR="$(dirname "$SAFRANO_DIR")"
ROOT="$(dirname "$SCRIPTS_DIR")"
PY_CORE_DIR="$SCRIPTS_DIR/safrano9999-lib/py-core"
declare -a EXTRA_ROOTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --extra-root)
            [ "$#" -ge 2 ] || { echo "--extra-root requires a path" >&2; exit 2; }
            EXTRA_ROOTS+=("$2")
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

shared_source() {
    local file="$1"

    case "$file" in
        python_header.py|openai_v1.py)
            if [ -f "$PY_CORE_DIR/$file" ]; then
                printf '%s\n' "$PY_CORE_DIR/$file"
            fi
            return 0
            ;;
        *)
            find "$SAFRANO_DIR" -type f -name "$file" -print -quit
            ;;
    esac
}

for file; do
    source="$(shared_source "$file")"
    [ -n "$source" ] || { echo "Missing shared file: $file" >&2; exit 1; }
    while IFS= read -r -d '' target; do
        [ "$source" -ef "$target" ] || ln -f "$source" "$target" || exit 1
    done < <(find "$ROOT" -path "$SCRIPTS_DIR" -prune -o -path '*/.git' -prune -o -type f -name "$file" -print0)
    for extra_root in "${EXTRA_ROOTS[@]}"; do
        [ -d "$extra_root" ] || continue
        while IFS= read -r -d '' target; do
            [ "$source" -ef "$target" ] || ln -f "$source" "$target" || exit 1
        done < <(find "$extra_root" -type f -name "$file" -print0)
    done
done
