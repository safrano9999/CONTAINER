#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
    "$ROOT/build-local.sh" \
    "$ROOT/prepare-build-context.sh" \
    "$ROOT/build/resolve-build-inputs.sh" \
    "$0"

(
    set -a
    # shellcheck source=/dev/null
    . "$ROOT/build.conf"
    set +a
    [ "$OPENCLAW_VERSION" = 2026.7.1 ]
    [ "$HERMES_COMMIT" = 3ef6bbd201263d354fd83ec55b3c306ded2eb72a ]
    [ "$HERMES_VERSION" = 0.19.0 ]
    [ "$VDITOR_VERSION" = 3.11.2 ]
    [ "$ELECTRUM_VERSION" = 4.7.2 ]
    [ "$LND_VERSION" = v0.20.1-beta ]
    [ "$GETH_VERSION" = 1.17.2 ]
    [ "$GETH_COMMIT" = be4dc0c4 ]
    [ "$WEBHOOK_VERSION" = 2.8.3 ]
)

[ "$(sed -n '1p' "$ROOT/Containerfile")" = "FROM quay.io/fedora/fedora:44 AS ai-core" ]
grep -Eq '^CMD \["/sbin/init"\]$' "$ROOT/Containerfile"
grep -Eq '^STOPSIGNAL SIGRTMIN\+3$' "$ROOT/Containerfile"
grep -Eq 'openclaw@\$\{OPENCLAW_VERSION\}' "$ROOT/Containerfile"

for forbidden in \
    openclaw-ephemeral \
    openclaw-deterministic \
    patch.tar.gz \
    note-latest.zip \
    /opt/safrano9999 \
    SAFRANO9999_STAGE_DIR \
    WELCOME \
    CODEANALYST \
    CITADEL \
    DIESDAS- \
    NEXTCLOUD \
    JUGO \
    VikAI \
    KIWIX_BRIDGE \
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES \
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW \
    ZEROINBOX \
    DAILYNEWS \
    SPANKER \
    KACHELMANN \
    PV_D-A-CH \
    NaturalGrounding; do
    if grep -rn -F "$forbidden" \
        "$ROOT/Containerfile" \
        "$ROOT/build.conf" \
        "$ROOT/requirements.base.txt" \
        "$ROOT/build" \
        "$ROOT/prepare-build-context.sh" \
        "$ROOT/build-local.sh"; then
        echo "Forbidden Base-layer content found in core: $forbidden" >&2
        exit 1
    fi
done

workflow="$ROOT/../.github/workflows/fedora44-core-image.yml"
if [ -f "$workflow" ]; then
    grep -Fq 'no-cache: true' "$workflow"
    if grep -En 'cache-(from|to):' "$workflow"; then
        echo "Persistent build cache configuration is forbidden" >&2
        exit 1
    fi
fi

echo "fedora44-core static checks passed"
