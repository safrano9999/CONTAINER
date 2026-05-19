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
REPOS=(CODEANALYST JUGO CITADEL VikAI)

mkdir -p "$SAFRANO_DIR"
for repo in "${REPOS[@]}"; do sync_repo "$repo"; done

# ── env.examples + requirements.txt dedupliziert zusammenführen ──────
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

CONFIG_YAML_PY="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/config_yaml.py"
ln -f "$CONFIG_YAML_PY" "$SCRIPT_DIR/config_yaml.py"
python3 "$SCRIPT_DIR/config_yaml.py" merge "$SCRIPT_DIR"

# ── config.sh aus SCRIPTS/INSTALL als Hardlink bereitstellen ─────────
if ! $NO_CONFIG; then
    CONFIG_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/config_template.sh"
    ln -f "$CONFIG_SH" "$SCRIPT_DIR/config.sh"
    echo ""
    (cd "$SCRIPT_DIR" && bash config.sh)
    python3 "$SCRIPT_DIR/config_yaml.py" configure "$SCRIPT_DIR"
    CONTAINER_NAME="$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')"
    rm -f "$SCRIPT_DIR/$CONTAINER_NAME.container" "$SCRIPT_DIR/docker-compose.yml"
elif [ ! -f "$SCRIPT_DIR/config.local.yaml" ]; then
    python3 "$SCRIPT_DIR/config_yaml.py" configure "$SCRIPT_DIR" --defaults
fi

# ── compose.yml + Quadlet aus YAML-Config generieren ─────────────────
echo "  Generating compose.yml..."
echo "  Generating fedora43-ai.container..."
python3 "$SCRIPT_DIR/config_yaml.py" render "$SCRIPT_DIR"

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
