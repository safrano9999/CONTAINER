#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=false
NO_CACHE=false
REPOS=(
    JUGO
    VikAI
    PV_D-A-CH
    KIWIX_BRIDGE
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual
    DAILYNEWS
    ZEROINBOX
    SPANKER
    KACHELMANN
)

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
    "$ROOT/.safrano9999-source-tags.tsv" "${REPOS[@]}"

if ! $OFFLINE; then
    bash "$ROOT/image/build.d/stage-release-plugin.sh" \
        safrano9999/KACHELMANN \
        kachelmann-latest.zip \
        "$ROOT/safrano9999/KACHELMANN"
fi

requirement_files=()
for specification in "${REPOS[@]}"; do
    repository="${specification%@*}"
    source="$ROOT/safrano9999/$repository/requirements.txt"
    [ ! -f "$source" ] || requirement_files+=("$source")
done
if [ "${#requirement_files[@]}" -eq 0 ]; then
    : > "$ROOT/requirements.safrano9999.txt"
else
    awk '
    {
        stripped = $0
        sub(/^[[:space:]]+/, "", stripped)
        if (stripped == "" || substr(stripped, 1, 1) == "#") { print; next }
        match(stripped, /^[A-Za-z0-9._-]+/)
        if (RSTART == 0) { print; next }
        key = tolower(substr(stripped, RSTART, RLENGTH))
        if (!(key in seen)) { seen[key] = 1; print }
    }
    ' "${requirement_files[@]}" > "$ROOT/requirements.safrano9999.txt"
fi
python3 "$ROOT/image/build.d/welcome-ref.py" "$ROOT" "$ROOT/ref.safrano9999.conf"
bash "$ROOT/image/build.d/resolve-build-inputs.sh" \
    "$ROOT/.resolved-build.env" \
    "$ROOT/.safrano9999-source-tags.tsv"

printf 'Safrano build context ready: %s\n' "$ROOT"
