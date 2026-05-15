#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

CONFIG_ONLY=false
NO_CONFIG=false
INSTANCE="fedora43-ai"

for arg in "$@"; do
    case "$arg" in
        --config)    CONFIG_ONLY=true ;;
        --no-config) NO_CONFIG=true ;;
        *) INSTANCE="$arg" ;;
    esac
done

# ── Repos klonen ──────────────────────────────────────────────────────
mkdir -p "$SAFRANO_DIR"
[ ! -d "$SAFRANO_DIR/CODEANALYST" ] && git clone --depth 1 https://github.com/safrano9999/CODEANALYST "$SAFRANO_DIR/CODEANALYST"
[ ! -d "$SAFRANO_DIR/JUGO" ]        && git clone --depth 1 https://github.com/safrano9999/JUGO "$SAFRANO_DIR/JUGO"
[ ! -d "$SAFRANO_DIR/CITADEL" ]     && git clone --depth 1 https://github.com/safrano9999/CITADEL "$SAFRANO_DIR/CITADEL"

# ── env.examples + requirements.txt dedupliziert zusammenführen ──────
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

# ── config.sh direkt im fedora43-ai-Verzeichnis ausführen ────────────
if ! $NO_CONFIG; then
    CONFIG_SH="$(find "$SAFRANO_DIR" -maxdepth 2 -name "config.sh" | head -1)"
    ln -sf "$CONFIG_SH" "$SCRIPT_DIR/config.sh"
    echo ""
    (cd "$SCRIPT_DIR" && bash config.sh)
    CONTAINER_NAME="$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')"
    rm -f "$SCRIPT_DIR/$CONTAINER_NAME.container" "$SCRIPT_DIR/docker-compose.yml"
fi

# ── Werte aus .env, BIP39_PORT aus Containerfile ─────────────────────
env_val() { grep "^${1}=" "$SCRIPT_DIR/.env" | head -1 | cut -d= -f2-; }
HOST="$(env_val HOST)"
CODEANALYST_PORT="$(env_val CODEANALYST_PORT)"
JUGO_PORT="$(env_val JUGO_PORT)"
CITADEL_WEBUI_PORT="$(env_val CITADEL_WEBUI_PORT)"
BIP39_PORT="$(grep "^ARG BIP39_PORT=" "$SCRIPT_DIR/Containerfile" | head -1 | cut -d= -f2-)"

# ── compose.yml generieren ───────────────────────────────────────────
echo "  Generating compose.yml..."
cat > "$SCRIPT_DIR/compose.yml" <<EOF
services:
  fedora43-ai:
    build:
      context: .
      dockerfile: Containerfile
    image: localhost/fedora43-ai:latest
    container_name: \${INSTANCE:-fedora43-ai}

    cap_add:
      - NET_ADMIN
      - NET_RAW

    devices:
      - /dev/net/tun

    security_opt:
      - label=disable

    tmpfs:
      - /tmp
      - /run
      - /run/lock

    ports:
      - "$HOST:$CODEANALYST_PORT:$CODEANALYST_PORT"
      - "$HOST:$JUGO_PORT:$JUGO_PORT"
      - "$HOST:$CITADEL_WEBUI_PORT:$CITADEL_WEBUI_PORT"
      - "$HOST:$BIP39_PORT:$BIP39_PORT"

    env_file:
      - path: .env
        required: false

    environment:
      - PATH=/usr/local/bin:/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - DISPLAY=\${DISPLAY:-:0}
      - NO_AT_BRIDGE=1
      - XDG_RUNTIME_DIR=/tmp/runtime-root
      - HERMES_HOME=/root/hermes-home
      - HERMES_INSTALL_DIR=/usr/local/lib/hermes-agent

    volumes:
      - \${HOST_HOME_DIR:-home}:/home
      - \${HOST_SRV_DIR}:/srv
      - \${HOST_ROOT_DIR:-root}:/root
      - \${HOST_OPT_DIR:-/opt/fedora43-ai}:/opt
      - \${HOST_TAILSCALE_DIR:-tailscale}:/var/lib/tailscale
      - /tmp/.X11-unix:/tmp/.X11-unix
      - $SCRIPT_DIR/.env:/safrano/.env:ro

volumes:
  home:
  root:
  tailscale:
EOF

$CONFIG_ONLY && echo "" && echo "  Config done." && exit 0

# ── Build ─────────────────────────────────────────────────────────────
echo ""
echo "  Starte Build..."
HOST_SRV_DIR="/srv/$INSTANCE"
export INSTANCE HOST_SRV_DIR
podman-compose \
    -f "$SCRIPT_DIR/compose.yml" \
    build
