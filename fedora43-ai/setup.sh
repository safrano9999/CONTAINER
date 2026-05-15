#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
ENV_FILE="$SCRIPT_DIR/.env"

CONFIG_ONLY=false
INSTANCE="fedora43-ai"

for arg in "$@"; do
    case "$arg" in
        --config) CONFIG_ONLY=true ;;
        *) INSTANCE="$arg" ;;
    esac
done

# ── Repos klonen ──────────────────────────────────────────────────────
mkdir -p "$SAFRANO_DIR"
[ ! -d "$SAFRANO_DIR/CODEANALYST" ] && git clone --depth 1 https://github.com/safrano9999/CODEANALYST "$SAFRANO_DIR/CODEANALYST"
[ ! -d "$SAFRANO_DIR/JUGO" ]        && git clone --depth 1 https://github.com/safrano9999/JUGO "$SAFRANO_DIR/JUGO"

# ── env.examples dedupliziert zusammenführen ──────────────────────────
echo "  Merging env.examples..."
bash "$SCRIPT_DIR/merge.sh"

# ── config.sh direkt im fedora43-ai-Verzeichnis ausführen ────────────
CONFIG_SH="$(find "$SAFRANO_DIR" -maxdepth 2 -name "config.sh" | head -1)"
echo ""
(cd "$SCRIPT_DIR" && bash "$CONFIG_SH")

$CONFIG_ONLY && echo "" && echo "  Config done." && exit 0

# ── Build ─────────────────────────────────────────────────────────────
echo ""
echo "  Starte Build..."
INSTANCE="$INSTANCE" \
HOST_SRV_DIR="/srv/$INSTANCE" \
podman-compose \
    -p "$INSTANCE" \
    -f "$SCRIPT_DIR/compose.yml" \
    up -d --build --force-recreate --no-cache
