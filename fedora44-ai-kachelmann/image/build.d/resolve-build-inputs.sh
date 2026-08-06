#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

OUTPUT="${1:-.resolved-build.env}"
SOURCE_TAG_MANIFEST="${2:-.kachelmann-source-tags.tsv}"

[ -s "$SOURCE_TAG_MANIFEST" ] || {
    echo "Missing KACHELMANN source manifest: $SOURCE_TAG_MANIFEST" >&2
    exit 1
}

KACHELMANN_SOURCE_KEY="$(sha256sum "$SOURCE_TAG_MANIFEST" | cut -d' ' -f1)"
[[ "$KACHELMANN_SOURCE_KEY" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid KACHELMANN source key" >&2
    exit 1
}

temporary="${OUTPUT}.tmp"
printf 'KACHELMANN_SOURCE_KEY=%s\n' "$KACHELMANN_SOURCE_KEY" > "$temporary"
mv -f -- "$temporary" "$OUTPUT"
printf 'Resolved KACHELMANN build inputs -> %s\n' "$OUTPUT"
