#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

OUTPUT="${1:-.resolved-build.env}"
SOURCE_TAG_MANIFEST="${2:-.safrano9999-source-tags.tsv}"

[ -s "$SOURCE_TAG_MANIFEST" ] || {
    echo "Missing Safrano source manifest: $SOURCE_TAG_MANIFEST" >&2
    exit 1
}

SAFRANO9999_SOURCE_KEY="$(sha256sum "$SOURCE_TAG_MANIFEST" | cut -d' ' -f1)"
[[ "$SAFRANO9999_SOURCE_KEY" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid Safrano source key" >&2
    exit 1
}

temporary="${OUTPUT}.tmp"
printf 'SAFRANO9999_SOURCE_KEY=%s\n' "$SAFRANO9999_SOURCE_KEY" > "$temporary"
mv -f -- "$temporary" "$OUTPUT"
printf 'Resolved Safrano build inputs -> %s\n' "$OUTPUT"
