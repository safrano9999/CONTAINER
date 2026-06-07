#!/usr/bin/env bash
# Install managed OpenClaw cronjobs and trigger the generated webhook script.
set -euo pipefail

log() { printf '[safrano9999-routines] %s\n' "$*"; }

timezone="${SAFRANO9999_ROUTINES_TZ:-Europe/Vienna}"
crontab_file="${OPENCLAW_PLUGINS_DIR:-/opt/safrano9999-openclaw}/.openclaw-crontab"
crontab_spec="${OPENCLAW_CRONTAB:-${SAFRANO9999_ROUTINES_CRONTAB:-}}"
[ -n "$crontab_spec" ] || [ ! -f "$crontab_file" ] || crontab_spec="$(cat "$crontab_file")"
crontab_spec="${crontab_spec:-CET 07:00,CET 12:00,CET 15:30,CET 19:00}"
openclaw_config_dir="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}"
webhook_script="${SAFRANO9999_WEBHOOK_SCRIPT:-/usr/local/bin/safrano9999-webhooks}"

run_all() {
  [ -x "$webhook_script" ] || { log "missing webhook script: $webhook_script"; return 1; }
  "$webhook_script"
}

install_crons() {
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
    --crontab "${spec}" \
    --message "__safrano9999_webhooks__"
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
