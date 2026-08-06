#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_ROOT="$ROOT/.."

for script in \
    "$ROOT"/*.sh \
    "$ROOT"/image/build.d/*.sh \
    "$ROOT"/image/setup.d/*.sh; do
    bash -n "$script"
done

grep -Fq 'FROM ${AI_BASE_IMAGE} AS ai-kachelmann' "$ROOT/Containerfile"
grep -Fq 'io.safrano9999.parent="fedora44-ai-base"' "$ROOT/Containerfile"
grep -Fq 'openclaw-layer-build --repos KACHELMANN' "$ROOT/Containerfile"
grep -Fq 'FEDORA_LAYER_REPOS=KACHELMANN' "$ROOT/setup.sh"
grep -Fqx $'KACHELMANN\tstandalone\tyes\tyes' "$ROOT/image/contributions.tsv"
grep -Fq 'kachelmann-latest.zip' "$ROOT/prepare-build-context.sh"
grep -Fq 'asset_name = f"{repository}-examplefiles.zip"' \
    "$ROOT/container-instance-setup.py"
grep -Fq 'hardlink(source, instance / source.name)' "$ROOT/container-instance-setup.py"
grep -Fq 'symlink(cache, instance / "safrano9999")' "$ROOT/container-instance-setup.py"

for forbidden in \
    JUGO VikAI PV_D-A-CH KIWIX_BRIDGE \
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES \
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW \
    NaturalGrounding-Tiktok-Ying-Video-Manager \
    DAILYNEWS ZEROINBOX SPANKER; do
    if grep -Fq "$forbidden" \
        "$ROOT/Containerfile" \
        "$ROOT/setup.sh" \
        "$ROOT/prepare-build-context.sh" \
        "$ROOT/image/contributions.tsv"; then
        echo "Non-KACHELMANN project found in reduced layer: $forbidden" >&2
        exit 1
    fi
done

workflow="$CONTAINER_ROOT/.github/workflows/fedora44-ai-kachelmann-image.yml"
[ -f "$workflow" ]
grep -Fq 'no-cache: true' "$workflow"
if grep -En 'cache-(from|to):' "$workflow"; then
    echo "Persistent build cache configuration is forbidden" >&2
    exit 1
fi

"$CONTAINER_ROOT/fedora44-ai-core/tests/check-build-context.sh"
echo "fedora44-ai-kachelmann static checks passed"
