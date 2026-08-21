#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SHARED_CONFIG="$SCRIPT_DIR/../../SCRIPTS/safrano9999/config/config.sh"
REGISTRY_IMAGE="ghcr.io/safrano9999/thunderbird-mcp-alpine@sha256:299b2f8cede36029b071fc388fbabbdfcd9e8aa6143caf444e63336805c6167e"
NO_CONFIG=false
NO_PULL=false

usage() {
    printf '%s\n' \
        'Usage: ./setup.sh [--no-pull] [--no-config]' \
        '' \
        '  --no-pull    Configure without pulling the private GHCR image' \
        '  --no-config  Keep existing generated configuration files'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-pull) NO_PULL=true ;;
        --no-config) NO_CONFIG=true ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

relink_config() {
    [ -f "$SHARED_CONFIG" ] || {
        echo "Missing SOT config.sh: $SHARED_CONFIG" >&2
        return 1
    }
    ln -f -- "$SHARED_CONFIG" "$SCRIPT_DIR/config.sh"
}

ensure_ghcr_login() {
    local username

    podman login --get-login ghcr.io >/dev/null 2>&1 && return 0
    command -v gh >/dev/null 2>&1 || {
        echo 'gh is required to authenticate to private GHCR.' >&2
        return 1
    }
    username="$(gh api user --jq .login)"
    gh auth token | podman login ghcr.io --username "$username" --password-stdin
}

relink_config
cd "$SCRIPT_DIR"

if ! $NO_CONFIG; then
    ./config.sh
fi

if ! $NO_PULL; then
    ensure_ghcr_login
    podman pull "$REGISTRY_IMAGE"
fi

CONFIG_CONTAINER_IMAGE="$REGISTRY_IMAGE" ./config.sh --render-container
mkdir -p "$HOME/thunderbird-exchange"

quadlet="$SCRIPT_DIR/thunderbird-mcp.container"
unit_directory="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

printf '\nSetup complete. Image: %s\n' "$REGISTRY_IMAGE"
printf '\nLink the Thunderbird MCP Quadlet:\n'
printf '  mkdir -p %q && ln -sfn %q %q\n' \
    "$unit_directory" "$quadlet" "$unit_directory/thunderbird-mcp.container"
printf '\nThen reload and start it:\n'
printf '  systemctl --user daemon-reload && systemctl --user restart thunderbird-mcp\n'
