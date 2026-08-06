#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=false
NO_CACHE=false
REPOS=(KACHELMANN)

for argument in "$@"; do
    case "$argument" in
        --offline) OFFLINE=true ;;
        --no-cache) NO_CACHE=true ;;
        --help|-h)
            echo "Usage: ./prepare-build-context.sh [--offline] [--no-cache]"
            exit 0
            ;;
        *) echo "Unknown option: $argument" >&2; exit 2 ;;
    esac
done

for command in git python3 sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing build preparation dependency: $command" >&2
        exit 1
    }
done

sync_arguments=()
$OFFLINE && sync_arguments+=(--offline)
$NO_CACHE && sync_arguments+=(--no-cache)
bash "$ROOT/image/setup.d/sync-sources.sh" \
    "${sync_arguments[@]}" sync "${REPOS[@]}"
bash "$ROOT/image/setup.d/sync-sources.sh" \
    "${sync_arguments[@]}" manifest \
    "$ROOT/.kachelmann-source-tags.tsv" "${REPOS[@]}"

if ! $OFFLINE; then
    bash "$ROOT/image/build.d/stage-release-plugin.sh" \
        safrano9999/KACHELMANN-MCP-ONLY \
        kachelmann-mcp-only-latest.zip \
        "$ROOT/safrano9999/KACHELMANN"
fi

(
    cd "$ROOT"
    FEDORA44_AI_EXAMPLE_DIRS="$ROOT/examples.d/core:$ROOT/examples.d/base" \
        bash "$ROOT/merge.sh" "${REPOS[@]}"
)
mv -f -- "$ROOT/requirements.txt" "$ROOT/requirements.kachelmann.txt"
bash "$ROOT/image/build.d/resolve-build-inputs.sh" \
    "$ROOT/.resolved-build.env" \
    "$ROOT/.kachelmann-source-tags.tsv"

printf 'KACHELMANN build context ready: %s\n' "$ROOT"
