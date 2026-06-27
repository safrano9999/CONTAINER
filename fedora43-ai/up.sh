#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="$(awk -F= '$1 == "CONTAINER_NAME" { print substr($0, index($0, "=") + 1); exit }' "$SCRIPT_DIR/config.conf")"
[ -n "$CONTAINER_NAME" ] || CONTAINER_NAME="fedora43-ai"
COMPOSE_FILE="$SCRIPT_DIR/$CONTAINER_NAME-compose.yml"

HOST_SRV_DIR="/srv/$CONTAINER_NAME"

mkdir -p "$HOST_SRV_DIR"

INSTANCE="$CONTAINER_NAME" \
HOST_SRV_DIR="$HOST_SRV_DIR" \
podman-compose \
  -p "$CONTAINER_NAME" \
  -f "$COMPOSE_FILE" \
  up -d
