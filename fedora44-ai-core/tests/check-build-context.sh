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
    [ "$OPENCLAW_NPM_INTEGRITY" = 'sha512-ge/Xss99CHAjPL/ikmH/UFoiOrjcxDB4sW3y9mhyCD+dYW3wzV7TKbAVdkrXFgAG2d2BjpJofP97zUZ+umxo8g==' ]
    [ "$OPENCLAW_DETERMINISTIC_REPOSITORY" = safrano9999/openclaw ]
    [ "$OPENCLAW_DETERMINISTIC_TAG" = 2026.7.1-deterministic.1 ]
    [ "$OPENCLAW_DETERMINISTIC_ASSET" = openclaw-2026.7.1-deterministic-810bafba.tar.gz ]
    [ "$OPENCLAW_DETERMINISTIC_SHA256" = 8d13b120b2e8f7a4876ea4b3f4d38148466b025f56c511a9ea209a69ab87c2a9 ]
    [ "$OPENCLAW_EPHEMERAL_REPOSITORY" = safrano9999/openclaw-ephemeral ]
    [ "$OPENCLAW_EPHEMERAL_COMMIT" = 40d29af55bab4331eddfa40809c5f3eb25e7600b ]
    [ "$NOTE_REPOSITORY" = safrano9999/NOTE ]
    [ "$NOTE_RELEASE_TAG" = 2026.7.36 ]
    [ "$NOTE_RELEASE_ASSET" = note-latest.zip ]
    [ "$NOTE_RELEASE_SHA256" = 2d3a4bff771e9dd85b6d39c0a1bb63dd68f99f65d73c6d2caae29eb65a6ba26b ]
    [ "$HERMES_COMMIT" = 3ef6bbd201263d354fd83ec55b3c306ded2eb72a ]
    [ "$HERMES_VERSION" = 0.19.0 ]
    [ "$VDITOR_VERSION" = 3.11.2 ]
    [ "$ELECTRUM_VERSION" = 4.7.2 ]
    [ "$LND_VERSION" = v0.20.1-beta ]
    [ "$GETH_VERSION" = 1.17.2 ]
    [ "$GETH_COMMIT" = be4dc0c4 ]
    [ "$WEBHOOK_VERSION" = 2.8.3 ]
)

if rg -n 'OPENCLAW_EPHEMERAL_IMAGE|openclaw-ephemeral-source|COPY --from=.*openclaw-ephemeral' \
    "$ROOT/Containerfile" "$ROOT/build.conf" "$ROOT/build-local.sh"; then
    echo "Ephemeral container-image donor remains in Core" >&2
    exit 1
fi
grep -Fq 'FROM quay.io/fedora/fedora:44 AS ai-core' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-deterministic/' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-ephemeral/' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/note/note-latest.zip' "$ROOT/Containerfile"
grep -Fq 'local-roots-*.js' "$ROOT/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' \
    "$ROOT/image/systemd/openclaw-config.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' \
    "$ROOT/image/systemd/hermes.service"
grep -Eq '^CMD \["/sbin/init"\]$' "$ROOT/Containerfile"
grep -Eq '^STOPSIGNAL SIGRTMIN\+3$' "$ROOT/Containerfile"
grep -Eq '^USER root$' "$ROOT/Containerfile"
grep -Fq 'lsof strace tcpdump nmap nmap-ncat' "$ROOT/Containerfile"

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
