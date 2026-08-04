#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="${FEDORA_LAYER_ROOT:?missing FEDORA_LAYER_ROOT}"
REGISTRY_IMAGE="${FEDORA_LAYER_REGISTRY_IMAGE:?missing registry image}"
LOCAL_IMAGE="${FEDORA_LAYER_LOCAL_IMAGE:?missing local image}"
OUTPUT_IMAGE_KEY="${FEDORA_LAYER_OUTPUT_IMAGE_KEY:?missing output image key}"
DEFAULT_INSTANCE="${FEDORA_LAYER_DEFAULT_INSTANCE:?missing default instance}"
EXAMPLE_DIRS="${FEDORA_LAYER_EXAMPLE_DIRS:-}"
readarray -t REPOS <<< "${FEDORA_LAYER_REPOS:?missing repository list}"

NO_CONFIG=false
NO_BUILD=false
NO_CACHE=false
INSTANCE="${CONFIG_CONTAINER_NAME:-}"

show_help() {
    cat <<EOF
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --no-config    Skip config.sh
  --no-build     Stop after staging, merge, config and rendering
  --no-cache     Disable the local image build cache
  --help         Show this help and exit

Generated files are kept below CONTAINER/INSTANCE.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --help|-h) show_help; exit 0 ;;
        --no-config) NO_CONFIG=true ;;
        --no-build) NO_BUILD=true ;;
        --no-cache) NO_CACHE=true ;;
        --*) echo "Unknown option: $argument" >&2; exit 2 ;;
        *)
            [ -z "$INSTANCE" ] || {
                echo "Only one INSTANCE may be selected" >&2
                exit 2
            }
            INSTANCE="$argument"
            ;;
    esac
done

[ -z "$INSTANCE" ] || [[ "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo "Invalid instance name: $INSTANCE" >&2
    exit 2
}

finish() {
    python3 "$ROOT/quadlet_finish.py" \
        "$INSTANCE_DIR/$COMPOSE_FILE" \
        "$INSTANCE_DIR/$QUADLET_FILE" \
        "$INSTANCE"
    printf '\n  Instance: %s\n  Compose:  %s\n  Quadlet:  %s\n' \
        "$INSTANCE_DIR" \
        "$INSTANCE_DIR/$COMPOSE_FILE" \
        "$INSTANCE_DIR/$QUADLET_FILE"
}

render_image() {
    local image="$1"
    local compose="$INSTANCE_DIR/$COMPOSE_FILE"
    local quadlet="$INSTANCE_DIR/$QUADLET_FILE"
    local temporary="${compose}.tmp"

    [ -f "$compose" ] && [ -f "$quadlet" ] || {
        echo "config.sh did not render Compose and Quadlet files" >&2
        return 1
    }
    awk '
        /^    build:[[:space:]]*$/ { skipping = 1; next }
        skipping && /^    [^[:space:]]/ { skipping = 0 }
        !skipping { print }
    ' "$compose" > "$temporary"
    mv -f -- "$temporary" "$compose"
    sed -i "s#^    image: .*#    image: $image#" "$compose"
    sed -i "s#^Image=.*#Image=$image#" "$quadlet"
}

ensure_ghcr_login() {
    local username
    podman login --get-login ghcr.io >/dev/null 2>&1 && return 0
    command -v gh >/dev/null 2>&1 || {
        echo "gh is required to authenticate to private GHCR images" >&2
        return 1
    }
    username="$(gh api user --jq .login)"
    gh auth token |
        podman login ghcr.io --username "$username" --password-stdin
}

instance_arguments=(
    "$ROOT"
    --config "$ROOT/config.sh"
    --default-name "$DEFAULT_INSTANCE"
)
[ -z "$INSTANCE" ] || instance_arguments+=(--name "$INSTANCE")
IFS=: read -ra example_directories <<< "$EXAMPLE_DIRS"
for example_directory in "${example_directories[@]}"; do
    [ -n "$example_directory" ] && instance_arguments+=(--example-dir "$example_directory")
done
for repository in "${REPOS[@]}"; do
    instance_arguments+=(--repository "$repository")
done
INSTANCE_DIR="$(python3 "$ROOT/container-instance-setup.py" "${instance_arguments[@]}")"
INSTANCE="${INSTANCE_DIR##*/}"
ENV_FILE="$INSTANCE.env"
CONFIG_FILE="${INSTANCE}_config.conf"
CONTAINER_FILE="${INSTANCE}_container.conf"
BUILD_FILE="${INSTANCE}_build.conf"
COMPOSE_FILE="${INSTANCE}-compose.yml"
QUADLET_FILE="${INSTANCE}.container"

if ! $NO_CONFIG; then
    echo "  Configuring instance $INSTANCE..."
    (
        cd "$INSTANCE_DIR"
        CONFIG_CONTAINER_NAME="$INSTANCE" \
        CONFIG_CONTAINER_IMAGE="$REGISTRY_IMAGE" \
            bash ./config.sh
    )
    [ ! -f "$INSTANCE_DIR/$ENV_FILE" ] || chmod 0600 "$INSTANCE_DIR/$ENV_FILE"
    render_image "$REGISTRY_IMAGE"
fi

if $NO_BUILD; then
    finish
    echo "  Staging, merge, configuration and rendering complete; no image operation was requested."
    exit 0
fi

printf '\n  Image source:\n    (1) Pull %s\n    (2) Build %s\n' \
    "$REGISTRY_IMAGE" "$LOCAL_IMAGE"
echo "  Build locally from this repository's context."
read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
IMG_CHOICE="${IMG_CHOICE:-2}"

case "$IMG_CHOICE" in
    1)
        command -v podman >/dev/null 2>&1 || {
            echo "podman is required to pull the image" >&2
            exit 1
        }
        case "$REGISTRY_IMAGE" in ghcr.io/*) ensure_ghcr_login ;; esac
        podman pull --retry 10 --retry-delay 5s "$REGISTRY_IMAGE"
        render_image "$REGISTRY_IMAGE"
        ;;
    2)
        arguments=()
        $NO_CACHE && arguments+=(--no-cache)
        env "$OUTPUT_IMAGE_KEY=$LOCAL_IMAGE" \
            "$ROOT/build-local.sh" "${arguments[@]}"
        render_image "$LOCAL_IMAGE"
        ;;
    *)
        echo "Invalid image choice: $IMG_CHOICE" >&2
        exit 2
        ;;
esac

finish
