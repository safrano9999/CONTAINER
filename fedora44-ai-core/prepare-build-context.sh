#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

CONTEXT="$(cd "${1:-.}" && pwd)"
BUILD="$CONTEXT/build"

set -a
# shellcheck source=/dev/null
. "$CONTEXT/build.conf"
set +a

OPENCLAW_DETERMINISTIC_REPOSITORY=safrano9999/openclaw-deterministic
OPENCLAW_DETERMINISTIC_TAG="${OPENCLAW_VERSION}-deterministic.1"
OPENCLAW_DETERMINISTIC_ASSET="openclaw-${OPENCLAW_VERSION}-deterministic.tar.gz"
OPENCLAW_EPHEMERAL_REPOSITORY=safrano9999/openclaw-ephemeral

for command in curl git sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing build preparation dependency: $command" >&2
        exit 1
    }
done

vendor_stage="$(mktemp -d "$BUILD/.vendor.XXXXXX")"
cleanup_vendor_stage() {
    rm -rf -- "$vendor_stage"
}
trap cleanup_vendor_stage EXIT

stage_release_asset() {
    local repository="$1" tag="$2" asset="$3" expected_sha256="$4" destination="$5"
    mkdir -p "$(dirname "$destination")"
    curl -fsSL --retry 3 --connect-timeout 15 \
        "https://github.com/${repository}/releases/download/${tag}/${asset}" \
        -o "$destination"
    if [ -n "$expected_sha256" ]; then
        printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum -c -
    fi
}

stage_release_asset \
    "$OPENCLAW_DETERMINISTIC_REPOSITORY" \
    "$OPENCLAW_DETERMINISTIC_TAG" \
    "$OPENCLAW_DETERMINISTIC_ASSET" \
    "" \
    "$vendor_stage/openclaw-deterministic/openclaw-deterministic.tar.gz"

stage_release_asset \
    "$NOTE_REPOSITORY" \
    "$NOTE_RELEASE_TAG" \
    "$NOTE_RELEASE_ASSET" \
    "$NOTE_RELEASE_SHA256" \
    "$vendor_stage/note/$NOTE_RELEASE_ASSET"

ephemeral_checkout="$vendor_stage/.openclaw-ephemeral-checkout"
git init -q "$ephemeral_checkout"
git -C "$ephemeral_checkout" remote add origin \
    "https://github.com/${OPENCLAW_EPHEMERAL_REPOSITORY}.git"
git -C "$ephemeral_checkout" fetch -q --depth=1 origin main
git -C "$ephemeral_checkout" checkout -q --detach FETCH_HEAD

ephemeral_files=(
    openclaw-ephemeral.py
    openclaw_ephemeral/__init__.py
    openclaw_ephemeral/cli.py
    openclaw_ephemeral/configuration.py
    openclaw_ephemeral/environment.py
    openclaw_ephemeral/filesystem.py
    openclaw_ephemeral/providers.py
)
for relative in "${ephemeral_files[@]}"; do
    [ -f "$ephemeral_checkout/$relative" ] || {
        echo "Missing Ephemeral runtime file on main: $relative" >&2
        exit 1
    }
    install -D -m 0644 \
        "$ephemeral_checkout/$relative" \
        "$vendor_stage/openclaw-ephemeral/$relative"
done
install -D -m 0644 \
    "$ephemeral_checkout/container/runtime/yolo.sh" \
    "$vendor_stage/openclaw-ephemeral/runtime/yolo.sh"
rm -rf -- "$ephemeral_checkout"

[ "$(find "$vendor_stage/openclaw-ephemeral" -type f | wc -l)" -eq 8 ] || {
    echo "Ephemeral vendor payload must contain exactly eight runtime files" >&2
    exit 1
}

rm -rf -- "$BUILD/vendor"
mv -- "$vendor_stage" "$BUILD/vendor"
trap - EXIT
printf 'Build context ready: %s\n' "$CONTEXT"
