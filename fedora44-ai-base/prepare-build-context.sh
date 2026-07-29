#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=false
NO_CACHE=false
REPOS=(WELCOME CODEANALYST CITADEL DIESDAS- NEXTCLOUD)

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

for command in curl git python3 sha256sum; do
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
    "$ROOT/.fedora44-ai-base-source-tags.tsv" "${REPOS[@]}"

(
    cd "$ROOT"
    FEDORA44_AI_EXAMPLE_DIRS="$ROOT/examples.d/core" \
        bash "$ROOT/merge.sh" "${REPOS[@]}"
)
mv -f -- "$ROOT/requirements.txt" "$ROOT/requirements.base.txt"
python3 "$ROOT/image/build.d/welcome-ref.py" "$ROOT" "$ROOT/ref.base.conf"
bash "$ROOT/image/build.d/resolve-build-inputs.sh" \
    "$ROOT/.resolved-build.env" \
    "$ROOT/.fedora44-ai-base-source-tags.tsv"

printf 'Base build context ready: %s\n' "$ROOT"
