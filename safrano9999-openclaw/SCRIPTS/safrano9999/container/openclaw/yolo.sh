#!/usr/bin/env bash
set -euo pipefail

# This image runs OpenClaw inside a fully trusted container. Keep the configured
# agent workspace intact while removing OpenClaw's sandbox, filesystem and exec
# approval restrictions.
#
# The yolo preset synchronizes the host approval file, but OpenClaw 2026.7.1
# still writes the legacy tools.exec.security/tools.exec.ask keys. Convert those
# keys to the canonical tools.exec.mode form afterwards; both forms must never
# coexist in one config.
openclaw config unset tools.exec.mode >/dev/null 2>&1 || true
openclaw exec-policy preset yolo
openclaw config unset tools.exec.security
openclaw config unset tools.exec.ask
openclaw config set agents.defaults.sandbox.mode '"off"' --strict-json
openclaw config set tools.profile '"full"' --strict-json
openclaw config set tools.fs.workspaceOnly false --strict-json
openclaw config set tools.exec.host '"gateway"' --strict-json
openclaw config set tools.exec.mode '"full"' --strict-json
openclaw config set tools.exec.applyPatch.workspaceOnly false --strict-json
