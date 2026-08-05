#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
    "$ROOT/build-local.sh" \
    "$ROOT/prepare-build-context.sh" \
    "$ROOT/build/resolve-build-inputs.sh" \
    "$0"

grep -Fq -- '--retry-all-errors' "$ROOT/build/resolve-build-inputs.sh"
grep -Fq 'git_remote_commit()' "$ROOT/build/resolve-build-inputs.sh"

grep -Fq 'FROM quay.io/fedora/fedora:44 AS ai-core-pre' "$ROOT/Containerfile"
grep -Fq 'openclaw@${OPENCLAW_VERSION}' "$ROOT/Containerfile"
grep -Fq '/usr/local/lib/hermes-agent' "$ROOT/Containerfile"
grep -Fq '@openai/codex@${CODEX_VERSION}' "$ROOT/Containerfile"
grep -Fq '@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}' "$ROOT/Containerfile"
grep -Eq '^CMD \["/sbin/init"\]$' "$ROOT/Containerfile"
grep -Eq '^STOPSIGNAL SIGRTMIN\+3$' "$ROOT/Containerfile"

for forbidden in \
    '/opt/safrano9999' \
    'build/vendor' \
    'openclaw-ephemeral.py' \
    'hermes-ephemeral.py' \
    'note-latest.zip' \
    'image/systemd'; do
    ! grep -rn -F "$forbidden" \
        "$ROOT/Containerfile" \
        "$ROOT/build.conf" \
        "$ROOT/build" \
        "$ROOT/requirements.base.txt"
done

echo "fedora44-ai-core-pre static checks passed"
