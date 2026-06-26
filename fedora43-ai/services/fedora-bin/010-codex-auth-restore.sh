#!/usr/bin/env bash
set -euo pipefail

mkdir -p /root/.codex
[ ! -f /persistent/codex-auth/auth.json ] || install -m 600 /persistent/codex-auth/auth.json /root/.codex/auth.json
