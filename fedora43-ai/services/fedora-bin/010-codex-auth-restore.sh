#!/usr/bin/env bash
set -euo pipefail

mkdir -p /root/.codex
[ ! -f /fedora/codex-auth/auth.json ] || install -m 600 /fedora/codex-auth/auth.json /root/.codex/auth.json
