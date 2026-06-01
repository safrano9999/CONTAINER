#!/usr/bin/env bash
# OpenClaw plugins container entrypoint.
# Replaces the systemd services fedora43-ai uses (tailscaled / tailscale-up /
# openclaw-config / openclaw) with a single PID-1-friendly boot sequence:
#   1) join the tailnet (if TS_AUTHKEY is injected)
#   2) configure OpenClaw (gateway token + plugin loading; no LLM)
#   3) exec the gateway
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

# OpenClaw CLI: the image may expose `openclaw` on PATH or only openclaw.mjs.
if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN=(openclaw)
elif [ -f /app/openclaw.mjs ]; then
  OPENCLAW_BIN=(node /app/openclaw.mjs)
else
  log "FATAL: cannot find the openclaw CLI"; exit 1
fi
export OPENCLAW_BIN="${OPENCLAW_BIN[*]}"   # consumed by openclaw-configure

# --- 1) Tailscale ------------------------------------------------------------
# Ephemeral auth keys are recommended: the node re-registers cleanly on every
# restart. Needs NET_ADMIN + /dev/net/tun (set via *_CAPABILITIES/*_DEVICES).
if [ -n "${TS_AUTHKEY:-}" ]; then
  log "starting tailscaled (state: ${TS_STATE_DIR:=/var/lib/tailscale})"
  mkdir -p "${TS_STATE_DIR}" /run/tailscale
  tailscaled --state="${TS_STATE_DIR}/tailscaled.state" \
             --socket=/run/tailscale/tailscaled.sock >/var/log/tailscaled.log 2>&1 &
  for _ in $(seq 1 30); do
    tailscale status >/dev/null 2>&1 && break
    sleep 0.5
  done
  up_args=(up --authkey="${TS_AUTHKEY}" --accept-routes --accept-dns)
  [ -n "${TS_HOSTNAME:-}" ] && up_args+=(--hostname="${TS_HOSTNAME}")
  if tailscale "${up_args[@]}"; then
    log "tailscale up: $(tailscale ip -4 2>/dev/null | head -1 || echo '?')"
    if tailscale set --ssh; then
      log "tailscale ssh enabled"
    else
      log "WARN: 'tailscale set --ssh' failed - continuing without Tailscale SSH"
    fi
  else
    log "WARN: 'tailscale up' failed - continuing without tailnet"
  fi
else
  log "TS_AUTHKEY not set - skipping Tailscale"
fi

# --- 2) Configure OpenClaw ---------------------------------------------------
log "configuring OpenClaw (plugins only; no LLM provider)"
/usr/local/bin/openclaw-configure

# --- 2b) ZEROINBOX folder/label init -----------------------------------------
zdir="${OPENCLAW_PLUGINS_DIR:-/opt/safrano9999-openclaw}/ZEROINBOX"
if [ -x "${zdir}/.venv/bin/python" ] && [ -f "${zdir}/scripts/gmail-init-labels" ]; then
  log "running ZEROINBOX label init"
  if ( cd "${zdir}" && "${zdir}/.venv/bin/python" scripts/gmail-init-labels --account all ); then
    log "ZEROINBOX label init done"
  else
    log "WARN: ZEROINBOX label init failed - continuing"
  fi
fi

# --- 2c) KACHELMANN WebUI ----------------------------------------------------
# fedora43 runs each web app as its own systemd service; without systemd we run
# the KACHELMANN FastAPI WebUI as a background process (reachable on its port /
# over the tailnet). Gated on KACHELMANN_PORT.
if [ -n "${KACHELMANN_PORT:-}" ]; then
  kdir="${OPENCLAW_PLUGINS_DIR:-/opt/safrano9999-openclaw}/KACHELMANN"
  if [ -x "${kdir}/.venv/bin/uvicorn" ]; then
    log "starting KACHELMANN WebUI on 0.0.0.0:${KACHELMANN_PORT}"
    ( cd "${kdir}" && exec ./.venv/bin/uvicorn webui:app --host 0.0.0.0 --port "${KACHELMANN_PORT}" ) \
      >/var/log/kachelmann-webui.log 2>&1 &
  else
    log "WARN: KACHELMANN venv/uvicorn missing - WebUI not started"
  fi
fi

# --- 3) Run the gateway ------------------------------------------------------
gw_args=(gateway run --bind lan --port "${OPENCLAW_GATEWAY_PORT:-18789}")
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  gw_args+=(--auth token)
fi
log "starting gateway: ${OPENCLAW_BIN} ${gw_args[*]}"
exec ${OPENCLAW_BIN} "${gw_args[@]}"
