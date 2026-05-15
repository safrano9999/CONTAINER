#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CA_DIR="$SCRIPT_DIR/safrano9999/CODEANALYST"
JUGO_DIR="$SCRIPT_DIR/safrano9999/JUGO"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
ENV_FILE="$SCRIPT_DIR/.env"
CONFIG_SH="$JUGO_DIR/config.sh"

CONFIG_ONLY=false
INSTANCE="fedora43-ai"

for arg in "$@"; do
    case "$arg" in
        --config) CONFIG_ONLY=true ;;
        *) INSTANCE="$arg" ;;
    esac
done

# ── Repos prüfen ─────────────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/safrano9999"
[ ! -d "$CA_DIR" ]   && git clone --depth 1 https://github.com/safrano9999/CODEANALYST "$CA_DIR"
[ ! -d "$JUGO_DIR" ] && git clone --depth 1 https://github.com/safrano9999/JUGO "$JUGO_DIR"

# ── env.example zusammenführen ────────────────────────────────────────
echo "  Merging env.example..."
cat "$CA_DIR/env.example" "$JUGO_DIR/env.example" > "$ENV_EXAMPLE"

# ── config.sh interaktiv ausführen → .env erzeugen ───────────────────
echo ""
ENV="$ENV_FILE" bash "$CONFIG_SH"

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
