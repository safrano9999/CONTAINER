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
printf 'Build context ready: %s\n' "$CONTEXT"
