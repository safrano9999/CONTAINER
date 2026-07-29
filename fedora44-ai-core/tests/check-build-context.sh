#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
    "$ROOT/build-local.sh" \
    "$ROOT/prepare-build-context.sh" \
    "$ROOT/build/resolve-build-inputs.sh" \
    "$ROOT/setup.sh" \
    "$ROOT/optional_persistence.sh" \
    "$ROOT"/image/runtime.d/*.sh \
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

grep -Fq 'FROM ${OPENCLAW_EPHEMERAL_IMAGE} AS openclaw-ephemeral-source' \
    "$ROOT/Containerfile"
grep -Fq 'FROM quay.io/fedora/fedora:44 AS ai-core' "$ROOT/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' \
    "$ROOT/image/systemd/openclaw-config.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' \
    "$ROOT/image/systemd/hermes.service"
grep -Eq '^CMD \["/sbin/init"\]$' "$ROOT/Containerfile"
grep -Eq '^STOPSIGNAL SIGRTMIN\+3$' "$ROOT/Containerfile"
grep -Eq '^USER root$' "$ROOT/Containerfile"

for forbidden in \
    /opt/safrano9999 \
    SAFRANO9999_STAGE_DIR \
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
        "$ROOT/image" \
        "$ROOT/prepare-build-context.sh" \
        "$ROOT/build-local.sh"; then
        echo "Project-layer content found in Core: $forbidden" >&2
        exit 1
    fi
done

workflow="$ROOT/../.github/workflows/fedora44-ai-core-image.yml"
if [ -f "$workflow" ]; then
    grep -Fq 'no-cache: true' "$workflow"
    if grep -En 'cache-(from|to):' "$workflow"; then
        echo "Persistent build cache configuration is forbidden" >&2
        exit 1
    fi
fi

"$ROOT/tests/check-fedora-chain.sh"
echo "fedora44-ai-core static checks passed"
