#!/usr/bin/env bash
set -euo pipefail

CODEX_AUTH_DIR="${CODEX_AUTH_DIR:-/persistent/codex-auth}"
AUTH_FILE="/root/.codex/auth.json"

if [ ! -f "$AUTH_FILE" ]; then
    echo "No Codex auth file found at $AUTH_FILE" >&2
    exit 1
fi

mkdir -p "$CODEX_AUTH_DIR"
chmod 700 "$CODEX_AUTH_DIR" 2>/dev/null || true
install -m 600 "$AUTH_FILE" "$CODEX_AUTH_DIR/auth.json"
echo "Saved Codex auth to $CODEX_AUTH_DIR/auth.json"
