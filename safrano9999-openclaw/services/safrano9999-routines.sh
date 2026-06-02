#!/usr/bin/env bash
# Trigger the four bundled safcontainer routines without involving an LLM.
set -euo pipefail

log() { printf '[safrano9999-routines] %s\n' "$*"; }

gateway_port="${OPENCLAW_GATEWAY_PORT:-18789}"
gateway_url="${OPENCLAW_GATEWAY_URL:-http://127.0.0.1:${gateway_port}}"
timezone="${SAFRANO9999_ROUTINES_TZ:-Europe/Vienna}"
telegram_target="${OPENCLAW_TELEGRAM_TARGET:-}"
telegram_token="${TELEGRAMTOKEN_OPENCLAW:-}"
cron_dir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}/cron"
cron_jobs="${cron_dir}/jobs.json"
cron_state="${cron_dir}/jobs-state.json"

auth_header=()
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  auth_header=(-H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}")
fi

wait_gateway() {
  for _ in $(seq 1 120); do
    if curl -fsS "${gateway_url}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  log "WARN: gateway not ready at ${gateway_url}"
  return 1
}

post_json() {
  local route="$1"
  curl -fsS -X POST "${auth_header[@]}" "${gateway_url}${route}"
}

send_text() {
  local text="$1"
  [ -n "${telegram_target}" ] || return 0
  [ -n "${telegram_token}" ] || return 0
  [ -n "${text}" ] || return 0
  curl -fsS -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" \
    -d "chat_id=${telegram_target}" \
    --data-urlencode "text=${text}" >/dev/null
}

send_media() {
  local media="$1"
  local caption="${2:-}"
  [ -n "${telegram_target}" ] || return 0
  [ -n "${telegram_token}" ] || return 0
  [ -n "${media}" ] || return 0
  [ -f "${media}" ] || return 0
  local args=(-X POST "https://api.telegram.org/bot${telegram_token}/sendDocument" -F "chat_id=${telegram_target}" -F "document=@${media}")
  [ -n "${caption}" ] && args+=(-F "caption=${caption}")
  curl -fsS "${args[@]}" >/dev/null
}

handle_payload() {
  local label="$1"
  local payload="$2"
  local delivered text media

  delivered="$(jq -r 'if .delivered == true then "true" else "false" end' <<<"${payload}" 2>/dev/null || printf 'false')"
  text="$(jq -r '.text // .message // empty' <<<"${payload}" 2>/dev/null || true)"
  media="$(jq -r '.media // .path // .reportPath // empty' <<<"${payload}" 2>/dev/null | sed 's/^MEDIA://')"

  if [ "${delivered}" != "true" ]; then
    if [ -n "${text}" ]; then
      send_text "${text}" || log "WARN: Telegram text delivery failed for ${label}"
    elif [ -n "${telegram_target}" ] && [ -z "${media}" ]; then
      send_text "${label}: erledigt." || log "WARN: Telegram text delivery failed for ${label}"
    fi
  fi

  if [ -n "${media}" ]; then
    send_media "${media}" "${label}" || log "WARN: Telegram media delivery failed for ${label}: ${media}"
  fi
}

run_webhook() {
  local label="$1"
  local route="$2"
  log "trigger ${label}"
  local payload
  if payload="$(post_json "${route}")"; then
    handle_payload "${label}" "${payload}"
  else
    log "WARN: ${label} trigger failed"
    [ -n "${telegram_target}" ] && send_text "${label}: Trigger fehlgeschlagen." || true
  fi
}

run_all() {
  wait_gateway || return 1
  run_webhook "DAILYNEWS" "/plugins/dailynews"
  run_webhook "CALENDAR" "/plugins/calendar/run"
  run_webhook "ZEROINBOX" "/plugins/zeroinbox/run"
  run_webhook "KACHELMANN" "/kachelmann/reminder"
}

install_crons() {
  wait_gateway || return 1
  mkdir -p "${cron_dir}"
  local now current tmp state_tmp message
  now="$(date +%s%3N)"
  message=$'/dailynews\n/calendar\n/zeroinbox\n/kachelmann status'

  current="$(mktemp /tmp/safrano9999-cron-current.XXXXXX)"
  tmp="$(mktemp /tmp/safrano9999-cron-jobs.XXXXXX)"
  if [ -s "${cron_jobs}" ] && jq -e 'type == "object" and (.jobs | type == "array")' "${cron_jobs}" >/dev/null 2>&1; then
    cp "${cron_jobs}" "${current}"
  else
    printf '{"version":1,"jobs":[]}\n' > "${current}"
  fi

  if ! jq -n \
    --argjson now "${now}" \
    --arg tz "${timezone}" \
    --arg text "${message}" \
    --slurpfile current "${current}" '
      def job($id; $name; $expr):
        {
          id: $id,
          name: $name,
          enabled: true,
          createdAtMs: $now,
          updatedAtMs: $now,
          schedule: {kind: "cron", expr: $expr, tz: $tz, staggerMs: 0},
          sessionTarget: "main",
          wakeMode: "now",
          payload: {kind: "systemEvent", text: $text},
          state: {}
        };
      {
        version: 1,
        jobs: (
          (($current[0].jobs // []) | map(select(((.id // "") | startswith("safrano9999-routines-")) | not)))
          + [
            job("safrano9999-routines-0000"; "safrano9999-routines-0000"; "0 0 * * *"),
            job("safrano9999-routines-0530"; "safrano9999-routines-0530"; "30 5 * * *"),
            job("safrano9999-routines-1200"; "safrano9999-routines-1200"; "0 12 * * *"),
            job("safrano9999-routines-1900"; "safrano9999-routines-1900"; "0 19 * * *")
          ]
        )
      }
    ' > "${tmp}"; then
    rm -f "${current}" "${tmp}"
    log "WARN: OpenClaw cronjobs render failed"
    return 1
  fi

  if ! jq -e '(.version == 1) and ((.jobs | map(select((.id // "") | startswith("safrano9999-routines-"))) | length) == 4)' "${tmp}" >/dev/null; then
    rm -f "${current}" "${tmp}"
    log "WARN: OpenClaw cronjobs validation failed"
    return 1
  fi

  mv "${tmp}" "${cron_jobs}"
  chmod 600 "${cron_jobs}"
  rm -f "${current}"
  if [ -f "${cron_state}" ]; then
    state_tmp="$(mktemp /tmp/safrano9999-cron-state.XXXXXX)"
    jq 'if .version == 1 and (.jobs | type == "object") then .jobs |= with_entries(select((.key | startswith("safrano9999-routines-")) | not)) else . end' \
      "${cron_state}" > "${state_tmp}" && mv "${state_tmp}" "${cron_state}" || rm -f "${state_tmp}"
  fi
  log "OpenClaw cronjobs written: 00:00, 05:30, 12:00, 19:00 ${timezone}"
}

init() {
  install_crons || true
  if [ "${SAFRANO9999_ROUTINES_RUN_ON_START:-1}" = "1" ]; then
    run_all || true
  fi
}

case "${1:-run}" in
  init)
    init
    ;;
  install-crons)
    install_crons
    ;;
  run)
    run_all
    ;;
  *)
    printf 'Usage: %s [init|install-crons|run]\n' "$0" >&2
    exit 2
    ;;
esac
