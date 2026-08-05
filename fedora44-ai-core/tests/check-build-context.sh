#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PRE="$ROOT/../fedora44-ai-core-pre"

bash -n \
    "$ROOT/build-local.sh" \
    "$ROOT/prepare-build-context.sh" \
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
    [ "$(grep -c '^OPENCLAW_' "$ROOT/build.conf")" -eq 1 ]
    [ "$NOTE_REPOSITORY" = safrano9999/NOTE ]
    [ "$NOTE_RELEASE_TAG" = 2026.7.36 ]
    [ "$NOTE_RELEASE_ASSET" = note-latest.zip ]
    [ "$NOTE_RELEASE_SHA256" = 2d3a4bff771e9dd85b6d39c0a1bb63dd68f99f65d73c6d2caae29eb65a6ba26b ]
    [ "$AI_CORE_PRE_IMAGE" = ghcr.io/safrano9999/fedora44-ai-core-pre:latest ]
)

if rg -n 'OPENCLAW_EPHEMERAL_IMAGE|openclaw-ephemeral-source|COPY --from=.*openclaw-ephemeral' \
    "$ROOT/Containerfile" "$ROOT/build.conf" "$ROOT/build-local.sh"; then
    echo "Ephemeral container-image donor remains in Core" >&2
    exit 1
fi
grep -Fq 'FROM ${AI_CORE_PRE_IMAGE} AS ai-core' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-deterministic/openclaw-deterministic.tar.gz' \
    "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-ephemeral/' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/note/note-latest.zip' "$ROOT/Containerfile"
grep -Fq 'local-roots-*.js' "$ROOT/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' \
    "$ROOT/image/systemd/openclaw-config.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' \
    "$ROOT/image/systemd/hermes.service"
grep -Fq 'mcp_servers_config' \
    "$ROOT/image/runtime.d/hermes-ephemeral.py"
grep -Eq '^CMD \["/sbin/init"\]$' "$ROOT/Containerfile"
grep -Eq '^STOPSIGNAL SIGRTMIN\+3$' "$ROOT/Containerfile"
grep -Eq '^USER root$' "$ROOT/Containerfile"
grep -Fq 'io.safrano9999.parent="fedora44-ai-core-pre"' "$ROOT/Containerfile"

python3 "$ROOT/tests/test-hermes-mcp-ephemeral.py"

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
        "$ROOT/build" \
        "$ROOT/image" \
        "$ROOT/prepare-build-context.sh" \
        "$ROOT/build-local.sh"; then
        echo "Project-layer content found in Core: $forbidden" >&2
        exit 1
    fi
done

for workflow in \
    "$ROOT/../.github/workflows/fedora44-ai-core-pre-image.yml" \
    "$ROOT/../.github/workflows/fedora44-ai-core-image.yml"; do
    if [ -f "$workflow" ]; then
        grep -Fq 'no-cache: true' "$workflow"
    fi
    if [ -f "$workflow" ] && grep -En 'cache-(from|to):' "$workflow"; then
        echo "Persistent build cache configuration is forbidden" >&2
        exit 1
    fi
done

"$PRE/tests/check-build-context.sh"
"$ROOT/tests/check-fedora-chain.sh"
echo "fedora44-ai-core static checks passed"
