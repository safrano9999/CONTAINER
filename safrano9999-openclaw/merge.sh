#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

# Mirrors fedora43-ai/merge.sh, but reads merge inputs directly from the
# staged plugin ZIPs instead of unpacking whole repos on the host.
merge_dedup_from_zips() {
  local filename="$1"
  local output="$2"
  local mode="$3"

  local tmp_dir
  local -a files=()
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/safrano9999-openclaw-merge.XXXXXX")"

  shopt -s nullglob
  for zip_path in "$SAFRANO_DIR"/*-latest.zip; do
    if ! unzip -Z1 "$zip_path" | grep -qx "$filename"; then
      continue
    fi
    local base extracted
    base="$(basename "$zip_path" -latest.zip)"
    extracted="$tmp_dir/${base}.${filename}"
    unzip -p "$zip_path" "$filename" > "$extracted"
    files+=("$extracted")
  done
  shopt -u nullglob

  if [ "${#files[@]}" -eq 0 ]; then
    echo "  ! Keine $filename in safrano9999/*-latest.zip gefunden"
    : > "$output"
    rm -rf "$tmp_dir"
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

  rm -rf "$tmp_dir"
  echo "  Merged $filename (${#files[@]} Quellen) -> ${output#"$SCRIPT_DIR"/}"
}

merge_dedup_from_zips "env.example" "$SCRIPT_DIR/env.example" "env"
merge_dedup_from_zips "requirements.txt" "$SCRIPT_DIR/requirements.txt" "requirements"
cat "$SCRIPT_DIR/env.safrano9999-openclaw.example" >> "$SCRIPT_DIR/env.example"
