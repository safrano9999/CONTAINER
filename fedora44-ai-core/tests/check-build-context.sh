#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PRE="$ROOT/../fedora44-ai-core-pre"

bash -n \
    "$ROOT/build-local.sh" \
    "$ROOT/prepare-build-context.sh" \
    "$ROOT/setup.sh" \
    "$ROOT/config/optional_persistence.sh" \
    "$ROOT"/image/runtime.d/*.sh \
    "$0"

(
    set -a
    # shellcheck source=/dev/null
    . "$ROOT/build.conf"
    set +a
    for name in AI_CORE_PRE_IMAGE FEDORA44_AI_CORE_IMAGE OPENCLAW_VERSION \
        NOTE_REPOSITORY NOTE_RELEASE_TAG NOTE_RELEASE_ASSET NOTE_RELEASE_SHA256; do
        [ -n "${!name:-}" ]
    done
    [[ "$NOTE_RELEASE_SHA256" =~ ^[0-9a-f]{64}$ ]]
)

if rg -n 'OPENCLAW_EPHEMERAL_IMAGE|openclaw-ephemeral-source|COPY --from=.*openclaw-ephemeral' \
    "$ROOT/Containerfile" "$ROOT/build.conf" "$ROOT/build-local.sh"; then
    echo "Ephemeral container-image donor remains in Core" >&2
    exit 1
fi
grep -Fq 'FROM ${AI_CORE_PRE_IMAGE} AS ai-core' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-deterministic/openclaw-deterministic.tar.gz' \
    "$ROOT/Containerfile"
grep -Fq 'dist/extensions/codex/index.js' "$ROOT/Containerfile"
grep -Fq 'rm -rf /root/.openclaw/extensions/codex' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-ephemeral/' "$ROOT/Containerfile"
grep -Fq 'COPY build/vendor/note/note-latest.zip' "$ROOT/Containerfile"
if grep -Fq 'local-roots-*.js' "$ROOT/Containerfile"; then
    echo "Global OpenClaw local-media root patch remains in Core" >&2
    exit 1
fi
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
echo "fedora44-ai-core static checks passed"
