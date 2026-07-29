#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

cdir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}/extensions/citadel"
if [ -x "${cdir}/scan.sh" ]; then
  log "scanning services for CITADEL"
  if (cd "$cdir" && ./scan.sh) >/var/log/citadel-scan.log 2>&1; then
    log "CITADEL scan done"
  else
    log "WARN: CITADEL localhost scan failed - continuing"
  fi
fi
