#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

CONTEXT="$(cd "${1:-.}" && pwd)"
BUILD="$CONTEXT/build"

set -a
# shellcheck source=/dev/null
. "$CONTEXT/build.conf"
set +a

for command in curl git jq openssl python3 sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing build preparation dependency: $command" >&2
        exit 1
    }
done

stage_certificates() {
    local source="$1" target cert fingerprint count=0
    [[ "$source" == /* ]] || {
        echo "CERTS must be an absolute path: $source" >&2
        exit 1
    }
    target="$CONTEXT/${source#/}"
    case "$target" in
        "$CONTEXT"/*) ;;
        *) echo "Unsafe certificate staging target: $target" >&2; exit 1 ;;
    esac

    rm -rf -- "$target"
    mkdir -p "$target"
    if [ ! -d "$source" ]; then
        echo "  No custom certificates at $source"
        return
    fi

    while IFS= read -r -d '' cert; do
        openssl x509 -in "$cert" -noout >/dev/null 2>&1 || continue
        fingerprint="$(openssl x509 -in "$cert" -noout -fingerprint -sha256 \
            | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
        install -m 0644 "$cert" "$target/fedora44-ai-${fingerprint}.crt"
        count=$((count + 1))
    done < <(find "$source" -type f \( -name '*.crt' -o -name '*.pem' \) -print0)
    printf '  Staged %d certificate(s)\n' "$count"
}

stage_certificates "$CERTS"
"$BUILD/resolve-build-inputs.sh" \
    "$CONTEXT/.resolved-build.env" \
    "$NODE_VERSION" \
    "$OPENCLAW_VERSION"

set -a
# shellcheck source=/dev/null
. "$CONTEXT/.resolved-build.env"
set +a

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
    printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum -c -
}

stage_release_asset \
    "$OPENCLAW_DETERMINISTIC_REPOSITORY" \
    "$OPENCLAW_DETERMINISTIC_TAG" \
    "$OPENCLAW_DETERMINISTIC_ASSET" \
    "$OPENCLAW_DETERMINISTIC_SHA256" \
    "$vendor_stage/openclaw-deterministic/$OPENCLAW_DETERMINISTIC_ASSET"

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
git -C "$ephemeral_checkout" fetch -q --depth=1 origin "$OPENCLAW_EPHEMERAL_COMMIT"
git -C "$ephemeral_checkout" checkout -q --detach FETCH_HEAD
[ "$(git -C "$ephemeral_checkout" rev-parse HEAD)" = "$OPENCLAW_EPHEMERAL_COMMIT" ] || {
    echo "Ephemeral source commit mismatch" >&2
    exit 1
}

ephemeral_files=(
    openclaw-ephemeral.py
    runtime/yolo.sh
    openclaw_ephemeral/__init__.py
    openclaw_ephemeral/cli.py
    openclaw_ephemeral/configuration.py
    openclaw_ephemeral/environment.py
    openclaw_ephemeral/filesystem.py
    openclaw_ephemeral/providers.py
)
for relative in "${ephemeral_files[@]}"; do
    [ -f "$ephemeral_checkout/$relative" ] || {
        echo "Missing Ephemeral runtime file at $OPENCLAW_EPHEMERAL_COMMIT: $relative" >&2
        exit 1
    }
    install -D -m 0644 \
        "$ephemeral_checkout/$relative" \
        "$vendor_stage/openclaw-ephemeral/$relative"
done
printf '%s\n' "$OPENCLAW_EPHEMERAL_COMMIT" \
    > "$vendor_stage/openclaw-ephemeral.commit"
rm -rf -- "$ephemeral_checkout"

[ "$(find "$vendor_stage/openclaw-ephemeral" -type f | wc -l)" -eq 8 ] || {
    echo "Ephemeral vendor payload must contain exactly eight runtime files" >&2
    exit 1
}

rm -rf -- "$BUILD/vendor"
mv -- "$vendor_stage" "$BUILD/vendor"
trap - EXIT
printf 'Build context ready: %s\n' "$CONTEXT"
