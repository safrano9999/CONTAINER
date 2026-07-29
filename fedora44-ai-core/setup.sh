#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
SHARED_SCRIPTS_DIR="$DEV_SCRIPTS_DIR/safrano9999"
REGISTRY_IMAGE="ghcr.io/safrano9999/fedora44-ai-core:latest"
LOCAL_IMAGE="${FEDORA44_AI_CORE_LOCAL_IMAGE:-localhost/fedora44-ai-core:latest}"
DEFAULT_INSTANCE="fedora44-ai-core"

CONFIG_ONLY=false
NO_CACHE=false
IMAGE_CHOICE=""
INSTANCE="${CONFIG_CONTAINER_NAME:-}"

show_help() {
    cat <<'EOF'
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --config-only  Merge and configure the instance without pulling or building
  --pull         Pull the configured FEDORA44_AI_CORE_IMAGE
  --build        Build the unchanged local fedora44-ai-core image context
  --no-cache     Pass --no-cache to a selected local build
  --help         Show this help and exit

INSTANCE defaults to fedora44-ai-core. Generated runtime files are kept below
CONTAINER/INSTANCE. Image selection is interactive unless an option preselects it.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)     show_help; exit 0 ;;
        --config-only) CONFIG_ONLY=true ;;
        --pull)        IMAGE_CHOICE=pull ;;
        --build)       IMAGE_CHOICE=build ;;
        --no-cache)    NO_CACHE=true ;;
        --*)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
        *)
            [ -z "$INSTANCE" ] || {
                echo "Only one INSTANCE may be selected" >&2
                exit 2
            }
            INSTANCE="$arg"
            ;;
    esac
done

INSTANCE="${INSTANCE:-$DEFAULT_INSTANCE}"
[[ "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo "Invalid instance name: $INSTANCE" >&2
    exit 2
}

INSTANCE_DIR="$SCRIPT_DIR/CONTAINER/$INSTANCE"
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

relink_shared_helpers() {
    local helper source target

    for helper in config.sh merge.sh quadlet_finish.py; do
        source="$SHARED_SCRIPTS_DIR/$helper"
        target="$SCRIPT_DIR/$helper"
        [ -f "$source" ] || continue
        ln -f -- "$source" "$target"
    done
}

fix_instance_paths() {
    local output generated

    for output in "$SCRIPT_DIR/$COMPOSE_FILE" "$SCRIPT_DIR/$QUADLET_FILE"; do
        [ -f "$output" ] || continue
        for generated in "${INSTANCE_FILES[@]}"; do
            sed -i \
                "s#${SCRIPT_DIR}/${generated}#${INSTANCE_DIR}/${generated}#g" \
                "$output"
        done
    done
}

persist_instance_files() {
    local generated

    mkdir -p "$INSTANCE_DIR"
    fix_instance_paths
    for generated in "${INSTANCE_FILES[@]}"; do
        [ ! -f "$SCRIPT_DIR/$generated" ] ||
            mv -f -- "$SCRIPT_DIR/$generated" "$INSTANCE_DIR/$generated"
    done
}

restore_instance_files() {
    local generated

    mkdir -p "$INSTANCE_DIR"
    for generated in "${INSTANCE_FILES[@]}"; do
        [ ! -f "$INSTANCE_DIR/$generated" ] ||
            cp -f -- "$INSTANCE_DIR/$generated" "$SCRIPT_DIR/$generated"
    done
}

finish_instance() {
    persist_instance_files
    trap - EXIT
    echo ""
    echo "  Instance: $INSTANCE_DIR"
    echo "  Compose:  $INSTANCE_DIR/$COMPOSE_FILE"
    echo "  Quadlet:  $INSTANCE_DIR/$QUADLET_FILE"
    if [ -f "$SCRIPT_DIR/quadlet_finish.py" ]; then
        python3 "$SCRIPT_DIR/quadlet_finish.py" \
            "$INSTANCE_DIR/$COMPOSE_FILE" \
            "$INSTANCE_DIR/$QUADLET_FILE" \
            "$INSTANCE"
    fi
}

build_output_image() {
    local configured=""

    if [ -f "$SCRIPT_DIR/$BUILD_FILE" ]; then
        configured="$(
            awk -F= '
                $1 == "FEDORA44_AI_CORE_IMAGE" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$SCRIPT_DIR/$BUILD_FILE"
        )"
    fi
    configured="${configured:-$REGISTRY_IMAGE}"
    [[ "$configured" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]] || {
        echo "Invalid FEDORA44_AI_CORE_IMAGE: $configured" >&2
        return 2
    }
    printf '%s\n' "$configured"
}

ensure_ghcr_login() {
    local username

    podman login --get-login ghcr.io >/dev/null 2>&1 && return 0
    command -v gh >/dev/null 2>&1 || {
        echo "gh is required to authenticate to GHCR" >&2
        return 1
    }
    username="$(gh api user --jq .login)"
    gh auth token |
        podman login ghcr.io --username "$username" --password-stdin
}

render_portless_core() {
    local image="$1"
    local additional
    local -a additional_lines=()

    while IFS= read -r additional; do
        [ -n "$additional" ] || continue
        additional_lines+=("$additional")
    done < <(
        awk -F= '
            $1 ~ /^ADDITIONAL_LINE(_[0-9]+)?$/ {
                print substr($0, index($0, "=") + 1)
            }
        ' "$SCRIPT_DIR/$CONTAINER_FILE"
    )

    {
        printf '# Generated by setup.sh for %s\n\n' "$INSTANCE"
        printf 'services:\n'
        printf '  %s:\n' "$INSTANCE"
        printf '    image: %s\n' "$image"
        printf '    container_name: %s\n' "$INSTANCE"
        printf '    hostname: %s\n' "$INSTANCE"
        printf '    env_file:\n'
        printf '      - %s\n' "$SCRIPT_DIR/$CONFIG_FILE"
        printf '      - %s\n' "$SCRIPT_DIR/$CONTAINER_FILE"
        printf '      - %s\n' "$SCRIPT_DIR/$ENV_FILE"
        printf '    restart: always\n'
    } > "$SCRIPT_DIR/$COMPOSE_FILE"

    {
        printf '# Generated by setup.sh for %s\n\n' "$INSTANCE"
        printf '[Container]\n'
        printf 'ContainerName=%s\n' "$INSTANCE"
        printf 'Image=%s\n' "$image"
        printf 'Exec=/sbin/init\n'
        printf 'AutoUpdate=registry\n'
        printf 'EnvironmentFile=%s\n' "$SCRIPT_DIR/$CONFIG_FILE"
        printf 'EnvironmentFile=%s\n' "$SCRIPT_DIR/$CONTAINER_FILE"
        printf 'EnvironmentFile=%s\n' "$SCRIPT_DIR/$ENV_FILE"
        for additional in "${additional_lines[@]}"; do
            printf '%s\n' "$additional"
        done
        printf '\n[Service]\n'
        printf 'Restart=always\n'
        printf 'TimeoutStartSec=60\n'
        printf '\n[Install]\n'
        printf 'WantedBy=default.target\n'
    } > "$SCRIPT_DIR/$QUADLET_FILE"
}

render_for_image() {
    local image="$1"
    render_portless_core "$image"
}

relink_shared_helpers
restore_instance_files
trap persist_instance_files EXIT

echo "  Merging core examples..."
(cd "$SCRIPT_DIR" && bash "$SCRIPT_DIR/merge.sh")

echo "  Configuring instance $INSTANCE..."
CONFIG_CONTAINER_NAME="$INSTANCE" \
CONFIG_CONTAINER_IMAGE="$REGISTRY_IMAGE" \
    bash "$SCRIPT_DIR/config.sh"
CONFIGURED_IMAGE="$(build_output_image)"
render_for_image "$CONFIGURED_IMAGE"

if $CONFIG_ONLY; then
    finish_instance
    echo "  Configuration complete; no image action was requested."
    exit 0
fi

if [ -z "$IMAGE_CHOICE" ]; then
    echo ""
    echo "  Image source:"
    echo "    (1) Pull $CONFIGURED_IMAGE"
    echo "    (2) Build the local core context [$LOCAL_IMAGE]"
    read -rp "  Choose [1/2] (default: 1): " IMAGE_CHOICE
    case "${IMAGE_CHOICE:-1}" in
        1) IMAGE_CHOICE=pull ;;
        2) IMAGE_CHOICE=build ;;
        *)
            echo "Invalid image choice: $IMAGE_CHOICE" >&2
            exit 2
            ;;
    esac
fi

case "$IMAGE_CHOICE" in
    pull)
        command -v podman >/dev/null 2>&1 || {
            echo "podman is required to pull the image" >&2
            exit 1
        }
        case "$CONFIGURED_IMAGE" in
            ghcr.io/*) ensure_ghcr_login ;;
        esac
        echo "  Pulling $CONFIGURED_IMAGE..."
        podman pull "$CONFIGURED_IMAGE"
        render_for_image "$CONFIGURED_IMAGE"
        ;;
    build)
        build_args=()
        $NO_CACHE && build_args+=(--no-cache)
        echo "  Building $LOCAL_IMAGE from the local core context..."
        FEDORA44_AI_CORE_IMAGE="$LOCAL_IMAGE" \
            "$SCRIPT_DIR/build-local.sh" "${build_args[@]}"
        render_for_image "$LOCAL_IMAGE"
        ;;
    *)
        echo "Invalid image choice: $IMAGE_CHOICE" >&2
        exit 2
        ;;
esac

finish_instance
