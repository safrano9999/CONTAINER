#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
if [ -n "${TS_AUTHKEY:-}" ] || [ -s "${TS_STATE_DIR}/tailscaled.state" ]; then
  log "starting tailscaled (state: ${TS_STATE_DIR})"
  mkdir -p "${TS_STATE_DIR}" /run/tailscale
  tailscaled --state="${TS_STATE_DIR}/tailscaled.state" \
             --socket=/run/tailscale/tailscaled.sock >/var/log/tailscaled.log 2>&1 &
  if /usr/local/bin/tailscale-state-up.sh; then
    log "tailscale up: $(tailscale ip -4 2>/dev/null | head -1 || echo '?')"
  else
    log "WARN: 'tailscale up' failed - continuing without tailnet"
  fi
else
  log "Tailscale state and TS_AUTHKEY not set - skipping Tailscale"
fi
