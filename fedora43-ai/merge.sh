#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

# Mergt eine Datei aus allen Repos in safrano9999/*/ ohne Doubletten ins SCRIPT_DIR.
# Leerzeilen und Kommentare (#) bleiben erhalten und werden nicht dedupliziert.
#
# Args:
#   $1 = Dateiname im Repo (z.B. env.example, requirements.txt)
#   $2 = Zielpfad
#   $3 = Dedup-Modus:
#          "env"          - Key vor "=" (KEY=value)
#          "requirements" - Paketname am Zeilenanfang
#          "line"         - komplette Zeile
merge_dedup_from_repos() {
    local filename="$1"
    local output="$2"
    local mode="$3"

    local -a files=()
    for repo_dir in "$SAFRANO_DIR"/*/; do
        [ -f "$repo_dir$filename" ] && files+=("$repo_dir$filename")
    done

    if [ ${#files[@]} -eq 0 ]; then
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

    echo "  Merged $filename (${#files[@]} Quellen) → ${output#$SCRIPT_DIR/}"
}

merge_dedup_from_repos "env.example"      "$SCRIPT_DIR/env.example"      "env"
merge_dedup_from_repos "requirements.txt" "$SCRIPT_DIR/requirements.txt" "requirements"
