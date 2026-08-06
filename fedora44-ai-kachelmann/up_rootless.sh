#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="${1:-fedora44-ai}"
CONFIG_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_config.conf"
[ -f "$CONFIG_FILE" ] && CONTAINER_NAME="$(awk -F= '$1 == "CONTAINER_NAME" { print substr($0, index($0, "=") + 1); exit }' "$CONFIG_FILE")"
COMPOSE_FILE="$SCRIPT_DIR/$CONTAINER_NAME-compose.yml"
HOST_SRV_DIR="$HOME/$CONTAINER_NAME/srv"

mkdir -p "$HOST_SRV_DIR"

INSTANCE="$CONTAINER_NAME"
export INSTANCE HOST_SRV_DIR
podman-compose \
  -p "$CONTAINER_NAME" \
  -f "$COMPOSE_FILE" \
  up -d
