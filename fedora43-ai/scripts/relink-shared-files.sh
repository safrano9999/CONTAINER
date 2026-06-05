#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="${1:-$SCRIPT_DIR/../safrano9999}"
SAFCONTAINER_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SHARED_DIR="$SAFCONTAINER_DIR/SCRIPTS"

link_if_present() {
    local shared="$1"
    local target="$2"

    [ -f "$shared" ] || return 0
    [ -e "$target" ] || return 0
    ln -f "$shared" "$target"
    echo "  hardlinked $(realpath --relative-to="$SAFRANO_DIR" "$target")"
}

[ -d "$SAFRANO_DIR" ] || exit 0

while IFS= read -r repo; do
    link_if_present "$SHARED_DIR/python_header.py" "$repo/python_header.py"
    link_if_present "$SHARED_DIR/python_header.py" "$repo/functions/python_header.py"
    link_if_present "$SHARED_DIR/send_message.sh" "$repo/send_message.sh"
    link_if_present "$SHARED_DIR/send_message.sh" "$repo/scripts/send_message.sh"
    link_if_present "$SHARED_DIR/note.sh" "$repo/note.sh"
    link_if_present "$SHARED_DIR/note.sh" "$repo/scripts/note.sh"
done < <(find "$SAFRANO_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
