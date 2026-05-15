#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
OUTPUT="$SCRIPT_DIR/.env.example"

declare -A seen_keys=()
> "$OUTPUT"

for repo_dir in "$SAFRANO_DIR"/*/; do
    example="$repo_dir/env.example"
    [ -f "$example" ] || continue

    repo_name="$(basename "$repo_dir")"
    added=0

    while IFS= read -r line; do
        stripped="${line#"${line%%[![:space:]]*}"}"

        if [[ -z "$stripped" || "$stripped" == \#* ]]; then
            echo "$line" >> "$OUTPUT"
            continue
        fi

        [[ "$line" != *=* ]] && echo "$line" >> "$OUTPUT" && continue

        key="${line%%=*}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        if [[ -n "${seen_keys[$key]+x}" ]]; then
            continue
        fi

        seen_keys[$key]=1
        echo "$line" >> "$OUTPUT"
        added=$((added + 1))
    done < "$example"

    echo "  $repo_name: $added vars merged"
done

echo ""
echo "  → $OUTPUT"
