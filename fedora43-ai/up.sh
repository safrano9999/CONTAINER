#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?usage: ./up.sh INSTANCE}"

HOST_BASE_DIR="$HOME/fedora43-ai/$INSTANCE"
HOST_HOME_DIR="$HOST_BASE_DIR/home"
HOST_ROOT_DIR="$HOST_BASE_DIR/root"
HOST_SRV_DIR="$HOST_BASE_DIR/srv"
HOST_OPT_DIR="$HOST_BASE_DIR/opt"
HOST_TAILSCALE_DIR="$HOST_BASE_DIR/tailscale"

mkdir -p \
  "$HOST_HOME_DIR" \
  "$HOST_ROOT_DIR" \
  "$HOST_SRV_DIR" \
  "$HOST_OPT_DIR" \
  "$HOST_TAILSCALE_DIR"

export INSTANCE HOST_HOME_DIR HOST_ROOT_DIR HOST_SRV_DIR HOST_OPT_DIR HOST_TAILSCALE_DIR
podman-compose \
  -p "$INSTANCE" \
  -f compose.yml \
  up -d
