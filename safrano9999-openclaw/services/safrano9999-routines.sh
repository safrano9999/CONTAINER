#!/usr/bin/env bash
# Trigger the four bundled safcontainer routines without involving an LLM.
set -euo pipefail

log() { printf '[safrano9999-routines] %s\n' "$*"; }

gateway_port="${OPENCLAW_GATEWAY_PORT:-18789}"
gateway_url="${OPENCLAW_GATEWAY_URL:-http://127.0.0.1:${gateway_port}}"
timezone="${SAFRANO9999_ROUTINES_TZ:-Europe/Vienna}"
crontab_spec="${OPENCLAW_CRONTAB:-${SAFRANO9999_ROUTINES_CRONTAB:-CET 07:00,CET 12:00,CET 15:30,CET 19:00}}"
telegram_target="${OPENCLAW_TELEGRAM_TARGET:-}"
telegram_token="${TELEGRAMTOKEN_OPENCLAW:-}"
openclaw_config_dir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}"

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
  local spec="${crontab_spec}"
  if [ "${1:-}" = "--crontab" ]; then
    shift
    spec="$*"
  elif [ "$#" -gt 0 ]; then
    spec="$*"
  fi
  python3 /usr/local/bin/safrano9999_plugins.py crontab \
    --config-dir "${openclaw_config_dir}" \
    --tz "${timezone}" \
    --crontab "${spec}"
}

init() {
  install_crons "$@" || true
  if [ "${SAFRANO9999_ROUTINES_RUN_ON_START:-1}" = "1" ]; then
    run_all || true
  fi
}

case "${1:-run}" in
  init)
    shift || true
    init "$@"
    ;;
  install-crons)
    shift || true
    install_crons "$@"
    ;;
  run)
    run_all
    ;;
  --crontab)
    install_crons "$@"
    ;;
  *)
    printf 'Usage: %s [init|install-crons|run] [--crontab "CET 23:49,CET 12:00"]\n' "$0" >&2
    exit 2
    ;;
esac
