#!/usr/bin/env bash
set -u

echo "=== FORCE CLEAN: containers ==="
for id in $(podman ps -aq); do
  echo "rm -f container $id"
  podman rm -f "$id" || true
done

echo "=== FORCE CLEAN: pods ==="
for id in $(podman pod ps -aq); do
  echo "pod rm -f $id"
  podman pod rm -f "$id" || true
done

echo "=== FORCE CLEAN: networks ==="
for net in $(podman network ls --format '{{.Name}}' | grep -vE '^(podman|host|none)$'); do
  echo "network rm -f $net"
  podman network rm -f "$net" || true
done

echo "=== LEFTOVER CHECK ==="
podman ps -a
podman pod ps
podman network ls
