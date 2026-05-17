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

sync_repo() {
    local repo="$1"
    if [ -d "$SAFRANO_DIR/$repo" ]; then
        git -C "$SAFRANO_DIR/$repo" pull --ff-only
    else
        git clone --depth 1 "https://github.com/safrano9999/$repo" "$SAFRANO_DIR/$repo"
    fi
}

# ── Repos klonen oder aktualisieren ──────────────────────────────────
REPOS=(CODEANALYST JUGO CITADEL)

mkdir -p "$SAFRANO_DIR"
for repo in "${REPOS[@]}"; do sync_repo "$repo"; done

# ── env.examples + requirements.txt dedupliziert zusammenführen ──────
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

# ── config.sh aus SCRIPTS/INSTALL als Hardlink bereitstellen ─────────
if ! $NO_CONFIG; then
    CONFIG_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/config_template.sh"
    ln -f "$CONFIG_SH" "$SCRIPT_DIR/config.sh"
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
BIP39_PORT="$(env_val BIP39_PORT)"

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

    #security_opt:
    #  - label=disable

    #tmpfs:
    #  - /tmp
    #  - /run
    #  - /run/lock

    ports:
      - "$HOST:$CODEANALYST_PORT:$CODEANALYST_PORT"
      - "$HOST:$JUGO_PORT:$JUGO_PORT"
      - "$HOST:$CITADEL_WEBUI_PORT:$CITADEL_WEBUI_PORT"
      - "$HOST:$BIP39_PORT:$BIP39_PORT"

    env_file:
      - .env

    environment:
      - PATH=/usr/local/bin:/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - DISPLAY=\${DISPLAY:-:0}
      - NO_AT_BRIDGE=1
      - XDG_RUNTIME_DIR=/tmp/runtime-root
      - HERMES_HOME=/root/hermes-home
      - HERMES_INSTALL_DIR=/usr/local/lib/hermes-agent
      - OPENCLAW_START=1
      - HERMES_START=1

    volumes:
      - \${HOST_HOME_DIR:-home}:/home
      - \${HOST_SRV_DIR}:/srv
      - \${HOST_ROOT_DIR:-root}:/root
      - \${HOST_TAILSCALE_DIR:-tailscale}:/var/lib/tailscale
      - /tmp/.X11-unix:/tmp/.X11-unix

volumes:
  home:
  root:
  tailscale:
EOF

# ── Quadlet .container generieren ────────────────────────────────────
echo "  Generating fedora43-ai.container..."
cat > "$SCRIPT_DIR/fedora43-ai.container" <<EOF
[Container]
ContainerName=fedora43-ai
Image=localhost/fedora43-ai:latest
EnvironmentFile=$SCRIPT_DIR/.env
Environment=OPENCLAW_START=1
Environment=HERMES_START=1
PublishPort=$HOST:$CODEANALYST_PORT:$CODEANALYST_PORT
PublishPort=$HOST:$JUGO_PORT:$JUGO_PORT
PublishPort=$HOST:$CITADEL_WEBUI_PORT:$CITADEL_WEBUI_PORT
PublishPort=$HOST:$BIP39_PORT:$BIP39_PORT
AddCapability=NET_ADMIN NET_RAW
AddDevice=/dev/net/tun
Volume=$HOME/fedora43-ai/srv:/srv

[Service]
Restart=always
TimeoutStartSec=60

[Install]
WantedBy=default.target
EOF

$CONFIG_ONLY && echo "" && echo "  Config done." && exit 0

# ── Image-Quelle wählen ──────────────────────────────────────────────
DOCKER_IO_IMAGE="docker.io/safrano9999/fedora43-ai:latest"
LOCAL_IMAGE="localhost/fedora43-ai:latest"

echo ""
echo "  Image source:"
echo "    (1) Pull from docker.io  [$DOCKER_IO_IMAGE]"
echo "    (2) Build locally"
echo ""
read -rp "  Choose [1/2] (default: 1): " IMG_CHOICE
IMG_CHOICE="${IMG_CHOICE:-1}"

case "$IMG_CHOICE" in
    1)
        echo ""
        echo "  Pulling $DOCKER_IO_IMAGE ..."
        podman pull "$DOCKER_IO_IMAGE"
        IMAGE_REF="$DOCKER_IO_IMAGE"
        # Update compose.yml to use pulled image (no build)
        sed -i '/^\s*build:/,/^\s*dockerfile:/d' "$SCRIPT_DIR/compose.yml"
        sed -i "s|image: .*|image: $DOCKER_IO_IMAGE|" "$SCRIPT_DIR/compose.yml"
        # Update quadlet .container
        sed -i "s|^Image=.*|Image=$DOCKER_IO_IMAGE|" "$SCRIPT_DIR/fedora43-ai.container"
        echo "  Done. Image ready: $DOCKER_IO_IMAGE"
        ;;
    2)
        echo ""
        echo "  Starte Build..."
        HOST_SRV_DIR="/srv/$INSTANCE"
        export INSTANCE HOST_SRV_DIR
        podman-compose \
            -f "$SCRIPT_DIR/compose.yml" \
            build
        ;;
esac
