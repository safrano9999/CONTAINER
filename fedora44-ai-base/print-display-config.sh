#!/usr/bin/env bash
set -euo pipefail

display="${DISPLAY:-:0}"
xdg_runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"

printf 'DISPLAY=%s\n' "$display"
printf 'NO_AT_BRIDGE=1\n'
printf 'XDG_RUNTIME_DIR=%s\n' "$xdg_runtime_dir"
