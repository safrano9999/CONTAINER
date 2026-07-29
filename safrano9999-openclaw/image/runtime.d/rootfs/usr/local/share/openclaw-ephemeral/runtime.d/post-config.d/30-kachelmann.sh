#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

kdir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}/extensions/kachelmann"
if [ -n "${KACHELMANN_PORT:-}" ]; then
  if [ -f "${kdir}/webui.py" ]; then
    log "starting KACHELMANN WebUI on 0.0.0.0:${KACHELMANN_PORT}"
    ( cd "${kdir}" && exec python3 -m uvicorn webui:app --host 0.0.0.0 --port "${KACHELMANN_PORT}" ) \
      >/var/log/kachelmann-webui.log 2>&1 &
    for _ in {1..30}; do
      curl -sS -o /dev/null "http://127.0.0.1:${KACHELMANN_PORT}/" 2>/dev/null && break
      sleep 0.2
    done
  else
    log "WARN: KACHELMANN webui.py missing - WebUI not started"
  fi
fi

if [ -n "${KACHELMANN_MCP_PORT:-}" ]; then
  if [ -f "${kdir}/kachelmann/mcp_server.py" ]; then
    log "starting KACHELMANN MCP HTTP on 0.0.0.0:${KACHELMANN_MCP_PORT}/mcp"
    ( cd "${kdir}" && exec python3 -m kachelmann.mcp_server --transport streamable-http ) \
      >/var/log/kachelmann-mcp-http.log 2>&1 &
  else
    log "WARN: KACHELMANN MCP server missing - HTTP MCP not started"
  fi
fi
