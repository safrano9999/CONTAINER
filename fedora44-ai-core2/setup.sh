#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
SHARED_DIR="$DEV_SCRIPTS_DIR/safrano9999"
REGISTRY_IMAGE=ghcr.io/safrano9999/fedora44-ai-core2:latest
INSTANCE="${CONFIG_CONTAINER_NAME:-fedora44-ai-core2}"
NO_BUILD=false

show_help() {
    printf '%s\n' \
      'Usage: ./setup.sh [--no-build] [INSTANCE]' \
      '' \
      'Merges the distilled examples, configures one instance and keeps all' \
      'generated files below CONTAINER/INSTANCE. --no-build performs no image' \
      'pull or local build.'
}

for argument in "$@"; do
    case "$argument" in
        --help|-h) show_help; exit 0 ;;
        --no-build|--config-only) NO_BUILD=true ;;
        --*) echo "Unknown option: $argument" >&2; exit 2 ;;
        *) INSTANCE="$argument" ;;
    esac
done

[[ "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo "Invalid instance name: $INSTANCE" >&2
    exit 2
}

for helper in config.sh merge.sh quadlet_finish.py optional_persistence.sh; do
    source="$SHARED_DIR/$helper"
    target="$SCRIPT_DIR/$helper"
    [ -f "$source" ] || continue
    [ -e "$target" ] && [ "$source" -ef "$target" ] || ln -f "$source" "$target"
done

INSTANCE_DIR="$SCRIPT_DIR/CONTAINER/$INSTANCE"
mkdir -p "$INSTANCE_DIR"
files=(
  "$INSTANCE.env"
  "${INSTANCE}_config.conf"
  "${INSTANCE}_container.conf"
  "${INSTANCE}_build.conf"
  "$INSTANCE-compose.yml"
  "$INSTANCE.container"
)

for file in "${files[@]}"; do
    [ ! -f "$INSTANCE_DIR/$file" ] || cp -f "$INSTANCE_DIR/$file" "$SCRIPT_DIR/$file"
done

fix_instance_paths() {
    local file generated compose="$SCRIPT_DIR/$INSTANCE-compose.yml"

    for file in "$compose" "$SCRIPT_DIR/$INSTANCE.container"; do
        [ -f "$file" ] || continue
        for generated in "${files[@]}"; do
            sed -i \
                "s#${SCRIPT_DIR}/${generated}#${INSTANCE_DIR}/${generated}#g" \
                "$file"
        done
    done

    # This wrapper deploys the published private image. A local build stanza
    # would become invalid after the generated Compose file is moved and could
    # also rebuild the image unintentionally.
    [ ! -f "$compose" ] || sed -i \
        '/^[[:space:]]*# Local build context detected by config[.]sh$/,+3d' \
        "$compose"
}

persist() {
    local file
    mkdir -p "$INSTANCE_DIR"
    fix_instance_paths
    [ ! -f "$SCRIPT_DIR/$INSTANCE.env" ] || chmod 0600 "$SCRIPT_DIR/$INSTANCE.env"
    for file in "${files[@]}"; do
        [ ! -f "$SCRIPT_DIR/$file" ] || mv -f "$SCRIPT_DIR/$file" "$INSTANCE_DIR/$file"
    done
}
trap persist EXIT

finish() {
    persist
    trap - EXIT
    python3 "$SCRIPT_DIR/quadlet_finish.py" \
        "$INSTANCE_DIR/$INSTANCE-compose.yml" \
        "$INSTANCE_DIR/$INSTANCE.container" \
        "$INSTANCE"
}

(cd "$SCRIPT_DIR" && bash "$SCRIPT_DIR/merge.sh")
CONFIG_CONTAINER_NAME="$INSTANCE" \
CONFIG_CONTAINER_IMAGE="$REGISTRY_IMAGE" \
  bash "$SCRIPT_DIR/config.sh"

if $NO_BUILD; then
    finish
    echo "Configuration complete; no image action was requested."
    exit 0
fi

echo "Pulling $REGISTRY_IMAGE ..."
podman pull "$REGISTRY_IMAGE"
echo "Image ready: $REGISTRY_IMAGE"
finish
