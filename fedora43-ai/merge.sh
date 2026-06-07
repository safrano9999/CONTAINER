#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

# Merge one file from all repositories in safrano9999/*/ without duplicates.
# Blank lines and comments (#) are preserved and are not deduplicated.
#
# Args:
#   $1 = filename in the repository (for example env.example or requirements.txt)
#   $2 = destination path
#   $3 = deduplication mode:
#          "env"          - key before "=" (KEY=value)
#          "requirements" - package name at the start of the line
#          "line"         - complete line
merge_dedup_from_repos() {
    local filename="$1"
    local output="$2"
    local mode="$3"

    local -a files=()
    for repo_dir in "$SAFRANO_DIR"/*/; do
        [ -f "$repo_dir$filename" ] && files+=("$repo_dir$filename")
    done

    if [ ${#files[@]} -eq 0 ]; then
        echo "  ! No $filename found in safrano9999/*/"
        : > "$output"
        return
    fi

    awk -v mode="$mode" '
    {
      stripped = $0
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped == "" || substr(stripped, 1, 1) == "#") { print; next }

      key = ""
      if (mode == "env") {
        idx = index(stripped, "=")
        if (idx == 0) { print; next }
        key = substr(stripped, 1, idx - 1)
        sub(/[[:space:]]+$/, "", key)
      } else if (mode == "requirements") {
        match(stripped, /^[a-zA-Z0-9._-]+/)
        if (RSTART == 0) { print; next }
        key = substr(stripped, RSTART, RLENGTH)
      } else {
        key = $0
      }

      if (!(key in seen)) { seen[key] = 1; print }
    }' "${files[@]}" > "$output"

    echo "  Merged $filename (${#files[@]} sources) -> ${output#"$SCRIPT_DIR"/}"
}

merge_dedup_from_repos "env.example"      "$SCRIPT_DIR/env.example"      "env"
merge_dedup_from_repos "requirements.txt" "$SCRIPT_DIR/requirements.txt" "requirements"
cat "$SCRIPT_DIR/env.fedora43-ai.example" >> "$SCRIPT_DIR/env.example"
