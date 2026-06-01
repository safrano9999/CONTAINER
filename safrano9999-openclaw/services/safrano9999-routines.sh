#!/usr/bin/env bash
set -euo pipefail

port="${OPENCLAW_GATEWAY_PORT:-18789}"
url="${OPENCLAW_GATEWAY_HTTP_URL:-http://127.0.0.1:${port}}/tools/invoke"
auth=()
[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}")

run_tool() {
  local command="$1" tool="$2"
  printf '[safrano9999-routines] /%s\n' "$command"
  curl -fsS -X POST "$url" \
    "${auth[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"tool\":\"${tool}\",\"args\":{},\"sessionKey\":\"main\"}" \
    | jq -r '.result.content[]?.text // empty' \
    | sed -n '1,12p'
}

lock=/tmp/safrano9999-routines.lock
(
  flock -n 9 || { echo '[safrano9999-routines] already running, skip'; exit 0; }
  run_tool kachelmann kachelmann_run
  run_tool calendar calendar_run
  run_tool zeroinbox zeroinbox_run
  run_tool dailynews dailynews_run
) 9>"$lock"
