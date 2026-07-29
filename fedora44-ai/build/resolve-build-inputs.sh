#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

OUTPUT="${1:-.resolved-build.env}"
SOURCE_TAG_MANIFEST="${2:-.safrano9999-source-tags.tsv}"
BASE_SOURCE_TAG_MANIFEST="${3:-.fedora44-ai-base-source-tags.tsv}"

for command in curl sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing build resolver dependency: $command" >&2
        exit 1
    }
done

[ -s "$SOURCE_TAG_MANIFEST" ] || {
    echo "Missing Safrano source manifest: $SOURCE_TAG_MANIFEST" >&2
    exit 1
}
[ -s "$BASE_SOURCE_TAG_MANIFEST" ] || {
    echo "Missing Base source manifest: $BASE_SOURCE_TAG_MANIFEST" >&2
    exit 1
}

SAFRANO9999_SOURCE_KEY="$(
    sha256sum "$SOURCE_TAG_MANIFEST" | cut -d' ' -f1
)"
FEDORA44_AI_BASE_SOURCE_KEY="$(
    sha256sum "$BASE_SOURCE_TAG_MANIFEST" | cut -d' ' -f1
)"
NEXTCLOUD_PLUGIN_SHA256="$(
    curl -fsSL --retry 3 --connect-timeout 15 \
      https://github.com/safrano9999/NEXTCLOUD/releases/download/latest/nextcloud-fedora64-plugin-latest.zip.sha256 \
      | awk 'NR == 1 {print $1}'
)"

for pair in \
    "SAFRANO9999_SOURCE_KEY=$SAFRANO9999_SOURCE_KEY" \
    "FEDORA44_AI_BASE_SOURCE_KEY=$FEDORA44_AI_BASE_SOURCE_KEY" \
    "NEXTCLOUD_PLUGIN_SHA256=$NEXTCLOUD_PLUGIN_SHA256"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] || {
        echo "Invalid resolved value for $name: $value" >&2
        exit 1
    }
done

temporary="${OUTPUT}.tmp"
{
    printf 'SAFRANO9999_SOURCE_KEY=%s\n' "$SAFRANO9999_SOURCE_KEY"
    printf 'FEDORA44_AI_BASE_SOURCE_KEY=%s\n' "$FEDORA44_AI_BASE_SOURCE_KEY"
    printf 'NEXTCLOUD_PLUGIN_SHA256=%s\n' "$NEXTCLOUD_PLUGIN_SHA256"
} > "$temporary"
mv -f "$temporary" "$OUTPUT"
printf 'Resolved layered build inputs -> %s\n' "$OUTPUT"
