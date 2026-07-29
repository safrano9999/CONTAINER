#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "$root/runtime/fedora44-ai-init.sh" \
  "$root/runtime/fedora44-runtime-environment-generator.sh" \
  "$root/runtime/named_volume_links.sh" \
  "$root/runtime/named_volume_links_openclaw.sh" \
  "$root/runtime/named_volume_links_hermes.sh" \
  "$root/runtime/optional_persistence.sh" \
  "$root/runtime/tailscale-state-up.sh" \
  "$0"

python3 - "$root/runtime/hermes-ephemeral.py" <<'PY'
import ast
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
PY

grep -Fq 'FROM ${AI_CORE_IMAGE} AS ai-core2' "$root/Containerfile"
grep -Fq 'openclaw-ephemeral-source' "$root/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' "$root/systemd/openclaw-config.service"
grep -Eq '^Requires=.*openclaw-config[.]service' "$root/systemd/openclaw.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' "$root/systemd/hermes.service"
grep -Fq 'VDITOR_NOTES_PATH:-/data' "$root/systemd/vditor-notes.service"

if rg -n 'apt-get|dnf .*install|npm install -g|pip install|/app/node_modules' \
  "$root/Containerfile"; then
  echo "core2 must not reinstall the heavy parent toolchain" >&2
  exit 1
fi

echo "fedora44-ai-core2 runtime checks passed"
