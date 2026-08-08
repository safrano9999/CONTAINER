#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KERNEL="$(cd -- "$ROOT/.." && pwd)/.github/scripts/fedora44-ai-example-chain.py"
MERGE_WILDCARDS=(
    'env|env.example|*env*example'
    'config|config.conf_example|*config.conf*example'
    'container|container.example|*container*example'
)
[ -f "$KERNEL" ] || {
    echo "Missing example-chain kernel: $KERNEL" >&2
    exit 1
}

show_help() {
    cat <<EOF
Usage: ./merge.sh OUTPUT_BASE

Offline fallback for a cumulative Fedora example triple. OUTPUT_BASE names all
three outputs, for example fedora44-ai-base. All matching example files found
directly in ./ are merged, including an already existing output triple.

No repository list is read and no network request is made.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi
[ "$#" -eq 1 ] || {
    show_help >&2
    exit 2
}
OUTPUT_BASE="$1"
[[ "$OUTPUT_BASE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "Invalid output base: $OUTPUT_BASE" >&2
    exit 2
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fedora-example-merge.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
source_arguments=()
stage_index=0

stage_file() {
    local kind="$1" target="$2" source="$3"
    local stage="$TMP_DIR/$(printf '%03d' "$stage_index")-${source##*/}"
    stage_index=$((stage_index + 1))
    mkdir -p "$stage"
    cp -- "$source" "$stage/$target"
    source_arguments+=(--source-dir "$stage")
}

declare -A seen_files=()
declare -A kind_counts=()
kind_order=()
collect_kind() {
    local kind="$1" target="$2"
    shift 2
    local source
    for source in "$@"; do
        [ -f "$source" ] && [ ! -L "$source" ] || continue
        [ -z "${seen_files["$kind:$source"]:-}" ] || continue
        seen_files["$kind:$source"]=1
        stage_file "$kind" "$target" "$source"
        kind_counts[$kind]=$((kind_counts[$kind] + 1))
    done
}

shopt -s nullglob
for rule in "${MERGE_WILDCARDS[@]}"; do
    IFS='|' read -r kind target pattern <<< "$rule"
    if [ -z "${kind_counts[$kind]+set}" ]; then
        kind_counts[$kind]=0
        kind_order+=("$kind")
    fi
    matches=("$ROOT"/$pattern)
    collect_kind "$kind" "$target" "${matches[@]}"
done
shopt -u nullglob

for kind in "${kind_order[@]}"; do
    [ "${kind_counts[$kind]}" -gt 0 ] || {
        echo "No $kind example files found in $ROOT" >&2
        exit 1
    }
done

python3 "$KERNEL" merge \
    --output-dir "$ROOT" \
    --output-prefix "$OUTPUT_BASE" \
    "${source_arguments[@]}"
