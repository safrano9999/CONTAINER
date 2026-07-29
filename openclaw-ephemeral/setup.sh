#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
SHARED_SCRIPTS_DIR="$DEV_SCRIPTS_DIR/safrano9999"
PUBLIC_IMAGE_DEFAULT="docker.io/safrano9999/openclaw-ephemeral:latest"

NO_CONFIG=false
NO_CACHE=false
NO_BUILD=false
IMAGE_ACTION=""
ENGINE="${CONTAINER_ENGINE:-}"
INSTANCE_NAME="${CONFIG_CONTAINER_NAME:-}"

relink_shared_helpers() {
  local helper source target

  for helper in config.sh merge.sh quadlet_finish.py; do
    source="$SHARED_SCRIPTS_DIR/$helper"
    target="$SCRIPT_DIR/$helper"
    [ -f "$source" ] || continue
    ln -f -- "$source" "$target"
  done
}

show_help() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Configure one openclaw-ephemeral instance and optionally pull or build its image.

Options:
  --pull              Pull the public Docker Hub image
  --build             Build the exact local Containerfile context
  --engine ENGINE     Use podman or docker
  --no-cache          Add --pull and --no-cache to a local build
  --no-config         Keep existing instance values and only re-render
  --no-build          Configure and render without pulling or building
  --help              Show this help

Without --pull, --build, or --no-build, setup asks which image source to use.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --pull)
      [ -z "$IMAGE_ACTION" ] || {
        echo "--pull and --build are mutually exclusive" >&2
        exit 2
      }
      IMAGE_ACTION=pull
      ;;
    --build)
      [ -z "$IMAGE_ACTION" ] || {
        echo "--pull and --build are mutually exclusive" >&2
        exit 2
      }
      IMAGE_ACTION=build
      ;;
    --engine)
      shift
      [ "$#" -gt 0 ] || {
        echo "--engine requires podman or docker" >&2
        exit 2
      }
      ENGINE="$1"
      ;;
    --no-cache)
      NO_CACHE=true
      ;;
    --no-config)
      NO_CONFIG=true
      ;;
    --no-build)
      NO_BUILD=true
      ;;
    --*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      [ -z "$INSTANCE_NAME" ] || {
        echo "Only one INSTANCE may be supplied" >&2
        exit 2
      }
      INSTANCE_NAME="$1"
      ;;
  esac
  shift
done

if $NO_BUILD && [ -n "$IMAGE_ACTION" ]; then
  echo "--no-build cannot be combined with --pull or --build" >&2
  exit 2
fi

relink_shared_helpers
select_args=("$SCRIPT_DIR")
[ -z "$INSTANCE_NAME" ] || select_args+=(--name "$INSTANCE_NAME")
CONTAINER_NAME="$(python3 "$SCRIPT_DIR/container_instance.py" "${select_args[@]}")"
export CONFIG_CONTAINER_NAME="$CONTAINER_NAME"

INSTANCE_DIR="$SCRIPT_DIR/CONTAINER/$CONTAINER_NAME"
ENV_FILE="$SCRIPT_DIR/$CONTAINER_NAME.env"
CONFIG_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_config.conf"
CONTAINER_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_container.conf"
BUILD_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_build.conf"
COMPOSE_FILE="$SCRIPT_DIR/$CONTAINER_NAME-compose.yml"
QUADLET_FILE="$SCRIPT_DIR/$CONTAINER_NAME.container"
INSTANCE_FILES=(
  "$CONTAINER_NAME.env"
  "${CONTAINER_NAME}_config.conf"
  "${CONTAINER_NAME}_container.conf"
  "${CONTAINER_NAME}_build.conf"
  "$CONTAINER_NAME-compose.yml"
  "$CONTAINER_NAME.container"
)
LOCAL_IMAGE="localhost/$CONTAINER_NAME:latest"

mkdir -p "$INSTANCE_DIR"
for file in "${INSTANCE_FILES[@]}"; do
  [ ! -f "$INSTANCE_DIR/$file" ] || cp -f "$INSTANCE_DIR/$file" "$SCRIPT_DIR/$file"
done

fix_instance_paths() {
  local generated
  for generated in "$COMPOSE_FILE" "$QUADLET_FILE"; do
    [ -f "$generated" ] || continue
    python3 - "$generated" "$SCRIPT_DIR" "$INSTANCE_DIR" "${INSTANCE_FILES[@]}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = Path(sys.argv[2])
destination = Path(sys.argv[3])
names = sys.argv[4:]
text = path.read_text(encoding="utf-8")
for name in names:
    text = text.replace(str(source / name), str(destination / name))
path.write_text(text, encoding="utf-8")
PY
  done
}

persist_instance_files() {
  local file
  fix_instance_paths
  [ ! -f "$ENV_FILE" ] || chmod 0600 "$ENV_FILE"
  for file in "${INSTANCE_FILES[@]}"; do
    [ ! -f "$SCRIPT_DIR/$file" ] || mv -f "$SCRIPT_DIR/$file" "$INSTANCE_DIR/$file"
  done
}
trap persist_instance_files EXIT

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_kv_file() {
  local file="$1"
  local wanted="$2"
  local line entry key value
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    entry="$(trim "${line%%#*}")"
    key="$(trim "${entry%%=*}")"
    value="$(trim "${entry#*=}")"
    if [ "$key" = "$wanted" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done < "$file"
  return 1
}

config_value() {
  local key="$1"
  local file
  for file in \
    "$BUILD_FILE" \
    "$CONTAINER_FILE" \
    "$CONFIG_FILE" \
    "$ENV_FILE" \
    "$SCRIPT_DIR/openclaw-ephemeral.build.conf_example" \
    "$SCRIPT_DIR/container.example" \
    "$SCRIPT_DIR/config.conf_example" \
    "$SCRIPT_DIR/env.example"; do
    read_kv_file "$file" "$key" && return 0
  done
  return 1
}

yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

public_image() {
  local configured
  configured="$(config_value OPENCLAW_EPHEMERAL_IMAGE || true)"
  printf '%s\n' "${configured:-$PUBLIC_IMAGE_DEFAULT}"
}

existing_image() {
  local value
  value="$(read_kv_file "$QUADLET_FILE" Image || true)"
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

render_container_files() {
  local image="$1"
  local include_build="$2"
  local host internal_port publish_port network container_nr publish_ports=true

  host="$(config_value FASTAPI_HOST || true)"
  internal_port="$(config_value OPENCLAW_GATEWAY_PORT || true)"
  publish_port="$(config_value OPENCLAW_GATEWAY_PUBLISH_PORT || true)"
  network="$(config_value OPENCLAW_EPHEMERAL_NETWORK || true)"
  container_nr="$(config_value CONTAINER_NR || true)"

  host="${host:-127.0.0.1}"
  internal_port="${internal_port:-18789}"
  publish_port="${publish_port:-18789}"
  network="${network:-default}"

  [ "${container_nr^^}" != "TUN" ] || {
    echo "CONTAINER_NR=TUN is unsupported by openclaw-ephemeral; use 2-5 or blank" >&2
    return 2
  }
  [[ "$network" != "host" && "$network" != "none" ]] || publish_ports=false

  {
    printf '# Generated by setup.sh for %s\n' "$CONTAINER_NAME"
    printf '# Edit files below CONTAINER/%s, then run setup.sh again.\n\n' "$CONTAINER_NAME"
    printf 'services:\n'
    printf '  %s:\n' "$CONTAINER_NAME"
    if [ "$include_build" = true ]; then
      printf '    build:\n'
      printf '      context: %s\n' "$(yaml_quote "$SCRIPT_DIR")"
      printf '      dockerfile: Containerfile\n'
    fi
    printf '    image: %s\n' "$(yaml_quote "$image")"
    printf '    labels:\n'
    printf '      - "io.containers.autoupdate=registry"\n'
    printf '    container_name: %s\n' "$(yaml_quote "$CONTAINER_NAME")"
    printf '    hostname: %s\n' "$(yaml_quote "$CONTAINER_NAME")"
    [ "$network" = default ] || printf '    network_mode: %s\n' "$(yaml_quote "$network")"
    if $publish_ports; then
      printf '    ports:\n'
      printf '      - %s\n' "$(yaml_quote "$host:$publish_port:$internal_port")"
    fi
    if [ -f "$CONFIG_FILE" ] || [ -f "$CONTAINER_FILE" ] || [ -f "$ENV_FILE" ]; then
      printf '    env_file:\n'
      [ -f "$CONFIG_FILE" ] && printf '      - %s\n' "$(yaml_quote "$CONFIG_FILE")"
      [ -f "$CONTAINER_FILE" ] && printf '      - %s\n' "$(yaml_quote "$CONTAINER_FILE")"
      [ -f "$ENV_FILE" ] && printf '      - %s\n' "$(yaml_quote "$ENV_FILE")"
    fi
    printf '    restart: always\n'
  } > "$COMPOSE_FILE"

  {
    printf '# Generated by setup.sh for %s\n\n' "$CONTAINER_NAME"
    printf '[Container]\n'
    printf 'ContainerName=%s\n' "$CONTAINER_NAME"
    printf 'Image=%s\n' "$image"
    [ "$network" = default ] || printf 'Network=%s\n' "$network"
    [ -f "$CONFIG_FILE" ] && printf 'EnvironmentFile=%s\n' "$CONFIG_FILE"
    [ -f "$CONTAINER_FILE" ] && printf 'EnvironmentFile=%s\n' "$CONTAINER_FILE"
    [ -f "$ENV_FILE" ] && printf 'EnvironmentFile=%s\n' "$ENV_FILE"
    $publish_ports && printf 'PublishPort=%s\n' "$host:$publish_port:$internal_port"
    printf 'AutoUpdate=registry\n\n'
    printf '[Service]\n'
    printf 'Restart=always\n'
    printf 'TimeoutStartSec=60\n\n'
    printf '[Install]\n'
    printf 'WantedBy=default.target\n'
  } > "$QUADLET_FILE"

  echo "  Written: $(basename "$COMPOSE_FILE")"
  echo "  Written: $(basename "$QUADLET_FILE")"
}

resolve_engine() {
  if [ -z "$ENGINE" ]; then
    if command -v podman >/dev/null 2>&1; then
      ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then
      ENGINE=docker
    else
      echo "Neither podman nor docker is installed" >&2
      return 2
    fi
  fi
  case "$ENGINE" in
    podman|docker)
      command -v "$ENGINE" >/dev/null 2>&1 || {
        echo "$ENGINE is not installed" >&2
        return 2
      }
      ;;
    *)
      echo "Invalid engine: $ENGINE (use podman or docker)" >&2
      return 2
      ;;
  esac
}

finish() {
  persist_instance_files
  trap - EXIT
  echo ""
  python3 "$SCRIPT_DIR/quadlet_finish.py" \
    "$INSTANCE_DIR/$(basename "$COMPOSE_FILE")" \
    "$INSTANCE_DIR/$(basename "$QUADLET_FILE")" \
    "$CONTAINER_NAME"
}

echo "  Merging local examples..."
PREVIOUS_IMAGE="$(existing_image || true)"
(cd "$SCRIPT_DIR" && bash "$SCRIPT_DIR/merge.sh")
[ ! -f "$SCRIPT_DIR/requirements.txt" ] || [ -s "$SCRIPT_DIR/requirements.txt" ] || rm -f "$SCRIPT_DIR/requirements.txt"

if ! $NO_CONFIG; then
  (cd "$SCRIPT_DIR" && bash "$SCRIPT_DIR/config.sh")
fi

PUBLIC_IMAGE="$(public_image)"
RENDER_IMAGE="${PREVIOUS_IMAGE:-$PUBLIC_IMAGE}"
RENDER_BUILD=false
[ "$RENDER_IMAGE" = "$LOCAL_IMAGE" ] && RENDER_BUILD=true
render_container_files "$RENDER_IMAGE" "$RENDER_BUILD"

if $NO_BUILD; then
  echo "  Configuration and rendering complete; no image action requested."
  finish
  exit 0
fi

if [ -z "$IMAGE_ACTION" ]; then
  echo ""
  echo "  Image source:"
  echo "    (1) Pull public image [$PUBLIC_IMAGE]"
  echo "    (2) Build exact local context [$LOCAL_IMAGE]"
  read -r -p "  Choose [1/2] (default: 1): " choice
  case "${choice:-1}" in
    1) IMAGE_ACTION=pull ;;
    2) IMAGE_ACTION=build ;;
    *) echo "Invalid image choice: $choice" >&2; exit 2 ;;
  esac
fi

resolve_engine
case "$IMAGE_ACTION" in
  pull)
    echo "  Pulling public image with $ENGINE: $PUBLIC_IMAGE"
    "$ENGINE" pull "$PUBLIC_IMAGE"
    render_container_files "$PUBLIC_IMAGE" false
    ;;
  build)
    build_options=()
    $NO_CACHE && build_options+=(--pull --no-cache)
    echo "  Building exact local context with $ENGINE: $LOCAL_IMAGE"
    "$ENGINE" build \
      "${build_options[@]}" \
      -t "$LOCAL_IMAGE" \
      -f "$SCRIPT_DIR/Containerfile" \
      "$SCRIPT_DIR"
    render_container_files "$LOCAL_IMAGE" true
    ;;
  *)
    echo "Invalid image action: $IMAGE_ACTION" >&2
    exit 2
    ;;
esac

finish
