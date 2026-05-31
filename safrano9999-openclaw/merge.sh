#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

# Mirrors fedora43-ai/merge.sh: merge one file from all staged
# ./safrano9999/* sources into the container root without duplicate keys.
merge_dedup_from_repos() {
  local filename="$1"
  local output="$2"
  local mode="$3"

  local -a files=()
  for repo_dir in "$SAFRANO_DIR"/*/; do
    [ -f "$repo_dir$filename" ] && files+=("$repo_dir$filename")
  done

  if [ "${#files[@]}" -eq 0 ]; then
    echo "  ! Keine $filename in safrano9999/*/ gefunden"
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

  echo "  Merged $filename (${#files[@]} Quellen) -> ${output#"$SCRIPT_DIR"/}"
}

merge_dedup_from_repos "env.example" "$SCRIPT_DIR/env.example" "env"
merge_dedup_from_repos "requirements.txt" "$SCRIPT_DIR/requirements.txt" "requirements"
cat "$SCRIPT_DIR/env.safrano9999-openclaw.example" >> "$SCRIPT_DIR/env.example"
