#!/usr/bin/env bash
set -euo pipefail

# This image runs OpenClaw inside a fully trusted container. Keep the configured
# agent workspace intact while removing OpenClaw's sandbox, filesystem and exec
# approval restrictions.
openclaw config set agents.defaults.sandbox.mode '"off"' --strict-json
openclaw config set tools.profile '"full"' --strict-json
openclaw config set tools.fs.workspaceOnly false --strict-json
openclaw config set tools.exec.host '"gateway"' --strict-json
openclaw config set tools.exec.mode '"full"' --strict-json
openclaw config set tools.exec.applyPatch.workspaceOnly false --strict-json
openclaw exec-policy preset yolo
