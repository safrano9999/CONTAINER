#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NO_CACHE=false

case "${1:-}" in
    "") ;;
    --no-cache) NO_CACHE=true ;;
    --help|-h)
        echo "Usage: ./build-local.sh [--no-cache]"
        exit 0
        ;;
    *) echo "Usage: ./build-local.sh [--no-cache]" >&2; exit 2 ;;
esac

command -v podman >/dev/null 2>&1 || {
    echo "Missing local build dependency: podman" >&2
    exit 1
}

ensure_ghcr_login() {
    local username
    podman login --get-login ghcr.io >/dev/null 2>&1 && return 0
    command -v gh >/dev/null 2>&1 || {
        echo "gh is required to authenticate to the private Base image" >&2
        return 1
    }
    username="$(gh api user --jq .login)"
    gh auth token |
        podman login ghcr.io --username "$username" --password-stdin
}

prepare_arguments=()
$NO_CACHE && prepare_arguments+=(--no-cache)
"$ROOT/prepare-build-context.sh" "${prepare_arguments[@]}"

set -a
# shellcheck source=/dev/null
. "$ROOT/build.conf"
set +a

for name in AI_BASE_IMAGE FEDORA44_AI_KACHELMANN_IMAGE; do
    [ -n "${!name:-}" ] || {
        echo "Missing $name in build.conf" >&2
        exit 1
    }
done
[ -s "$ROOT/.resolved-build.env" ] || {
    echo "Missing .resolved-build.env" >&2
    exit 1
}
PULL_POLICY=always
[[ "$AI_BASE_IMAGE" != localhost/* ]] || PULL_POLICY=missing
[[ "$AI_BASE_IMAGE" != ghcr.io/* ]] || ensure_ghcr_login

BUILD_ARGS=(--build-arg "AI_BASE_IMAGE=$AI_BASE_IMAGE")
while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
        echo "Invalid resolved build argument: $key" >&2
        exit 1
    }
    BUILD_ARGS+=(--build-arg "$key=$value")
done < "$ROOT/.resolved-build.env"
$NO_CACHE && BUILD_ARGS+=(--no-cache)

IMAGE="$FEDORA44_AI_KACHELMANN_IMAGE"
echo "  Building $IMAGE from $ROOT ..."
podman build --pull="$PULL_POLICY" "${BUILD_ARGS[@]}" \
    --target ai-kachelmann \
    -t "$IMAGE" \
    -f "$ROOT/Containerfile" \
    "$ROOT"
echo "  Done. Image ready: $IMAGE"
