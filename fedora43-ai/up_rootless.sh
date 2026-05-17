#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?usage: ./up_rootless.sh INSTANCE}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_SRV_DIR="$HOME/fedora43-ai/$INSTANCE/srv"

mkdir -p "$HOST_SRV_DIR"

export INSTANCE HOST_SRV_DIR
podman-compose \
  -p "$INSTANCE" \
  -f "$SCRIPT_DIR/compose.yml" \
  up -d
