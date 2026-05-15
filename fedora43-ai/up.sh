#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:?usage: ./up.sh INSTANCE}"

HOST_SRV_DIR="/srv/$INSTANCE"

mkdir -p "$HOST_SRV_DIR"
mkdir -p "/opt/$INSTANCE"          # ← neu


INSTANCE="$INSTANCE" \
HOST_SRV_DIR="$HOST_SRV_DIR" \
podman-compose \
  -p "$INSTANCE" \
  -f compose.yml \
  up -d
