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

CONFIG_ONLY=false
NO_CACHE=false
OFFLINE=false
IMG_CHOICE=""
INSTANCE="${CONFIG_CONTAINER_NAME:-}"

show_help() {
    cat <<EOF
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --config-only  Stage sources and render config without an image operation
  --offline      Use already staged repositories without network access
  --pull         Pull $REGISTRY_IMAGE
  --build        Build this repository's Containerfile
  --no-cache     Reclone sources and disable the local image build cache
  --help         Show this help and exit

Generated files are kept below CONTAINER/INSTANCE.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --help|-h) show_help; exit 0 ;;
        --config-only) CONFIG_ONLY=true ;;
        --offline) OFFLINE=true ;;
        --pull) IMG_CHOICE=1 ;;
        --build) IMG_CHOICE=2 ;;
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

INSTANCE="${INSTANCE:-$DEFAULT_INSTANCE}"
[[ "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo "Invalid instance name: $INSTANCE" >&2
    exit 2
}

INSTANCE_DIR="$ROOT/CONTAINER/$INSTANCE"
ENV_FILE="$INSTANCE.env"
CONFIG_FILE="${INSTANCE}_config.conf"
CONTAINER_FILE="${INSTANCE}_container.conf"
BUILD_FILE="${INSTANCE}_build.conf"
COMPOSE_FILE="${INSTANCE}-compose.yml"
QUADLET_FILE="${INSTANCE}.container"
INSTANCE_FILES=(
    "$ENV_FILE"
    "$CONFIG_FILE"
    "$CONTAINER_FILE"
    "$BUILD_FILE"
    "$COMPOSE_FILE"
    "$QUADLET_FILE"
)

fix_instance_paths() {
    local output generated
    for output in "$ROOT/$COMPOSE_FILE" "$ROOT/$QUADLET_FILE"; do
        [ -f "$output" ] || continue
        for generated in "${INSTANCE_FILES[@]}"; do
            sed -i \
                "s#${ROOT}/${generated}#${INSTANCE_DIR}/${generated}#g" \
                "$output"
        done
    done
}

persist_instance() {
    local generated
    mkdir -p "$INSTANCE_DIR"
    fix_instance_paths
    [ ! -f "$ROOT/$ENV_FILE" ] || chmod 0600 "$ROOT/$ENV_FILE"
    for generated in "${INSTANCE_FILES[@]}"; do
        [ ! -f "$ROOT/$generated" ] ||
            mv -f -- "$ROOT/$generated" "$INSTANCE_DIR/$generated"
    done
}

restore_instance() {
    local generated
    mkdir -p "$INSTANCE_DIR"
    for generated in "${INSTANCE_FILES[@]}"; do
        [ ! -f "$INSTANCE_DIR/$generated" ] ||
            cp -f -- "$INSTANCE_DIR/$generated" "$ROOT/$generated"
    done
}

finish() {
    persist_instance
    trap - EXIT
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
    local compose="$ROOT/$COMPOSE_FILE"
    local quadlet="$ROOT/$QUADLET_FILE"
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

sync_arguments=()
$OFFLINE && sync_arguments+=(--offline)
$NO_CACHE && sync_arguments+=(--no-cache)
bash "$ROOT/image/setup.d/sync-sources.sh" \
    "${sync_arguments[@]}" sync "${REPOS[@]}"

restore_instance
trap persist_instance EXIT

echo "  Merging the Fedora image example cascade..."
(
    cd "$ROOT"
    FEDORA44_AI_EXAMPLE_DIRS="$EXAMPLE_DIRS" \
        bash "$ROOT/merge.sh" "${REPOS[@]}"
)

echo "  Configuring instance $INSTANCE..."
CONFIG_CONTAINER_NAME="$INSTANCE" \
CONFIG_CONTAINER_IMAGE="$REGISTRY_IMAGE" \
    bash "$ROOT/config.sh"
render_image "$REGISTRY_IMAGE"

if $CONFIG_ONLY; then
    finish
    echo "  Configuration complete; no image operation was requested."
    exit 0
fi

if [ -z "$IMG_CHOICE" ]; then
    printf '\n  Image source:\n    (1) Pull %s\n    (2) Build %s\n' \
        "$REGISTRY_IMAGE" "$LOCAL_IMAGE"
    echo "  Build locally from this repository's context."
    read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
    IMG_CHOICE="${IMG_CHOICE:-2}"
fi

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
