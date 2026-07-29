#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

zdir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}/extensions/zeroinbox"
if [ -f "${zdir}/scripts/gmail-init-labels" ]; then
  log "running ZEROINBOX label init"
  if ( cd "${zdir}" && python3 scripts/gmail-init-labels --account all ); then
    log "ZEROINBOX label init done"
  else
    log "WARN: ZEROINBOX label init failed - continuing"
  fi
fi
