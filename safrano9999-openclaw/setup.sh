#!/usr/bin/env bash
# setup.sh - orchestrate the safrano9999-openclaw container.
#
#   1) stage plugin release archives into ./safrano9999
#   2) merge env.example / requirements.txt / config.conf_example
#   3) run shared config.sh, delete generated compose/quadlet, render them here
#   4) choose Docker Hub pull or local build
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
SCRIPTS_DIR="$SCRIPT_DIR/SCRIPTS"
SAFRANO_SCRIPTS_DIR="$SCRIPTS_DIR/safrano9999"
SQLITE_PERSISTENCE="$SAFRANO_SCRIPTS_DIR/sqlite_persistence.sh"
OPTIONAL_PERSISTENCE="$SAFRANO_SCRIPTS_DIR/optional_persistence.sh"
IMAGE_SCRIPTS_DIR="$SAFRANO_SCRIPTS_DIR/image"
CONTAINER_SCRIPTS_DIR="$SAFRANO_SCRIPTS_DIR/container"
INSTALL_DIR="$IMAGE_SCRIPTS_DIR/install"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
CONTAINER_NAME=""
DOCKER_IO_IMAGE_DEFAULT="docker.io/safrano9999/safrano9999-openclaw:latest"
PLUGINS=(DAILYNEWS CALENDAR ZEROINBOX KACHELMANN CITADEL NOTE)
CONFIG_PLUGINS=(DAILYNEWS CALENDAR ZEROINBOX KACHELMANN NOTE)

NO_CONFIG=false
NO_CACHE=false
NO_BUILD=false
IMG_CHOICE=""

show_help() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS]

Options:
  --no-cache          Build locally with --pull=always --no-cache when selected
  --no-config         Skip config.sh
  --no-build          Stop after staging, merge, config and compose/quadlet rendering
  --help              Show this help and exit

Without options, setup runs config, then opens the interactive image menu.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help) show_help; exit 0 ;;
    --no-config) NO_CONFIG=true ;;
    --no-cache) NO_CACHE=true ;;
    --no-build) NO_BUILD=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

DEFAULT_CONTAINER_NAME="$(awk '
  $0 == "#CONTAINER-NAME" { active = 1; next }
  active && $0 ~ /^CONTAINER_NAME=/ { sub(/^[^=]*=/, ""); print; exit }
' "$SCRIPT_DIR/config.safrano9999-openclaw.conf_example")"
DEFAULT_CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-safrano9999-openclaw}"
CONTAINER_NAME="${CONFIG_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
if [ -t 0 ]; then
  read -rp "  Container name [$CONTAINER_NAME]: " selected_container_name
  CONTAINER_NAME="${selected_container_name:-$CONTAINER_NAME}"
fi
[[ "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
  echo "Invalid container name: $CONTAINER_NAME" >&2
  exit 2
}
export CONFIG_CONTAINER_NAME="$CONTAINER_NAME"
ENV_FILE="$SCRIPT_DIR/$CONTAINER_NAME.env"
CONFIG_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_config.conf"
CONTAINER_CONFIG_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_container.conf"
BUILD_FILE="$SCRIPT_DIR/${CONTAINER_NAME}_build.conf"
COMPOSE_FILE="$SCRIPT_DIR/$CONTAINER_NAME-compose.yml"
QUADLET_FILE="$SCRIPT_DIR/$CONTAINER_NAME.container"
LOCAL_IMAGE="localhost/${CONTAINER_NAME}:latest"

relink_dev_scripts() {
  local path source target

  [ -d "$DEV_SCRIPTS_DIR/.git" ] || return 0
  while IFS= read -r -d '' source; do
    path="${source#"$DEV_SCRIPTS_DIR/"}"
    target="$SCRIPTS_DIR/$path"
    mkdir -p "$(dirname "$target")"
    [ -e "$target" ] && [ "$source" -ef "$target" ] || ln -f "$source" "$target"
  done < <(
    find "$DEV_SCRIPTS_DIR/safrano9999" -type f \
      ! -path '*/__pycache__/*' \
      ! -name '*.pyc' \
      -print0
  )
  ln -f "$SAFRANO_SCRIPTS_DIR/merge.sh" "$SCRIPT_DIR/merge.sh"
  ln -f "$SAFRANO_SCRIPTS_DIR/quadlet_finish.py" "$SCRIPT_DIR/quadlet_finish.py"
}

relink_dev_scripts
"$INSTALL_DIR/github_auth.sh" safrano9999

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_kv_file() {
  local file="$1"
  local wanted="$2"
  local line stripped entry key value

  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    stripped="$(trim "$line")"
    [[ -z "$stripped" || "$stripped" == \#* ]] && continue
    entry="${line%%#*}"
    entry="$(trim "$entry")"
    [[ "$entry" == *=* ]] || continue
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
    "$CONTAINER_CONFIG_FILE" \
    "$CONFIG_FILE" \
    "$ENV_FILE" \
    "$SCRIPT_DIR/safrano9999-openclaw.build.conf_example" \
    "$SCRIPT_DIR/container.example" \
    "$SCRIPT_DIR/config.conf_example" \
    "$SCRIPT_DIR/env.example"; do
    read_kv_file "$file" "$key" && return 0
  done
  return 1
}

docker_io_image() {
  local configured
  configured="$(config_value SAFRANO9999_OPENCLAW_IMAGE || true)"
  printf '%s\n' "${configured:-$DOCKER_IO_IMAGE_DEFAULT}"
}

ensure_docker_io_login() {
  local engine="$1"
  if "$engine" login --get-login docker.io >/dev/null 2>&1; then
    return 0
  fi
  echo "  docker.io login required for private image pull."
  "$engine" login docker.io -u safrano9999
}

choose_pull_engine() {
  local engine
  echo "" >&2
  read -rp "  Pull engine [podman/docker] (default: podman): " engine
  engine="${engine:-podman}"
  case "$engine" in
    podman|docker) command -v "$engine" >/dev/null || { echo "$engine not found" >&2; exit 2; } ;;
    *) echo "Invalid pull engine: $engine" >&2; exit 2 ;;
  esac
  printf '%s\n' "$engine"
}

plugin_tag() {
  local name="$1"
  local key="${name}_PLUGIN_RELEASE_TAG"
  local value="${!key:-}"

  [ -n "$value" ] || value="$(config_value "$key" || true)"
  [ -n "$value" ] || value="${OPENCLAW_PLUGIN_RELEASE_TAG:-}"
  [ -n "$value" ] || value="$(config_value OPENCLAW_PLUGIN_RELEASE_TAG || true)"
  printf '%s\n' "${value:-latest}"
}

download_plugin_zip() {
  local name="$1"
  local lower tag zip zip_path sha_path url
  local downloaded=false
  local -a curl_auth=()

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  tag="$(plugin_tag "$name")"
  zip="${lower}-latest.zip"
  zip_path="$SAFRANO_DIR/$zip"
  sha_path="$SAFRANO_DIR/$zip.sha256"
  url="https://github.com/safrano9999/$name/releases/download/$tag"

  mkdir -p "$SAFRANO_DIR"
  rm -rf "$SAFRANO_DIR/$name" "$SAFRANO_DIR/.tmp-$name"
  rm -f "$zip_path" "$sha_path"
  echo "  downloading $name ($tag) -> $zip"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh release download "$tag" \
      -R "safrano9999/$name" \
      --pattern "$zip" \
      --pattern "$zip.sha256" \
      --dir "$SAFRANO_DIR" \
      --clobber >/dev/null; then
      downloaded=true
    else
      echo "  gh download failed for $name; falling back to curl"
    fi
  fi
  if [ "$downloaded" != "true" ]; then
    [ -n "${GH_TOKEN:-}" ] && curl_auth=(-H "Authorization: Bearer ${GH_TOKEN}")
    curl -fsSL --retry 3 --retry-delay 2 "${curl_auth[@]}" "$url/$zip" -o "$zip_path"
    curl -fsSL --retry 3 --retry-delay 2 "${curl_auth[@]}" "$url/$zip.sha256" -o "$sha_path"
  fi
  (cd "$SAFRANO_DIR" && sha256sum -c "$zip.sha256" >/dev/null)

  echo "  staged $name release archive"
}

stage_provider_conf() {
  local name="$1"
  local lower zip_path target

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  zip_path="$SAFRANO_DIR/${lower}-latest.zip"
  target="$SAFRANO_DIR/${lower}-provider.conf"
  rm -f "$target"
  if unzip -Z1 "$zip_path" | grep -qx 'provider.conf'; then
    unzip -p "$zip_path" provider.conf > "$target"
  fi
}

add_unique() {
  local value="$1"
  local array_name="$2"
  local -n array_ref="$array_name"
  local existing

  value="$(trim "$value")"
  [ -n "$value" ] || return 0
  for existing in "${array_ref[@]}"; do
    [ "$existing" = "$value" ] && return 0
  done
  array_ref+=("$value")
}

yaml_dq() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

add_volume_item() {
  local item="$1"
  local target_name="$2"
  local named_target_name="$3"
  local source

  item="$(trim "$item")"
  [ -n "$item" ] || return 0
  add_unique "$item" "$target_name"
  source="${item%%:*}"
  if [[ "$source" != /* && "$source" != .* && "$source" != "~"* && "$source" != '$'* && "$source" != *"/"* ]]; then
    add_unique "$source" "$named_target_name"
  fi
}

split_csv_into() {
  local value="$1"
  local -n target="$2"
  local item
  local -a items=()

  IFS=',' read -ra items <<< "$value"
  for item in "${items[@]}"; do add_unique "$item" "$2"; done
}

split_volumes_into() {
  local value="$1"
  local -n target="$2"
  local -n named_target="$3"
  local item
  local -a items=()

  IFS=',' read -ra items <<< "$value"
  for item in "${items[@]}"; do add_volume_item "$item" "$2" "$3"; done
}

source_file_for_render() {
  if [ -f "$CONFIG_FILE" ]; then
    printf '%s\n' "$CONFIG_FILE"
  elif [ -f "$SCRIPT_DIR/config.conf_example" ]; then
    printf '%s\n' "$SCRIPT_DIR/config.conf_example"
  else
    return 1
  fi
}

render_compose_and_quadlet() {
  local image="$1"
  local include_build="$2"
  local source_file host compose_file quadlet_file line stripped entry key value disabled
  local network
  local publish_ports=true
  local prefix internal_key internal_port publish_port publish_host map source
  local first_port=""
  local -a ports=()
  local -a volumes=()
  local -a disabled_volumes=()
  local -a caps=()
  local -a devices=()
  local -a named_volumes=()
  local -a disabled_named_volumes=()
  local -a persistent_envs=()

  local -a source_files=()
  [ -f "$SCRIPT_DIR/config.conf_example" ] && source_files+=("$SCRIPT_DIR/config.conf_example")
  [ -f "$SCRIPT_DIR/container.example" ] && source_files+=("$SCRIPT_DIR/container.example")
  [ -f "$CONFIG_FILE" ] && source_files+=("$CONFIG_FILE")
  [ -f "$CONTAINER_CONFIG_FILE" ] && source_files+=("$CONTAINER_CONFIG_FILE")
  if [ "${#source_files[@]}" -eq 0 ]; then
    source_files+=("$(source_file_for_render)")
  fi
  host="$(config_value FASTAPI_HOST || true)"
  [ -n "$host" ] || host="127.0.0.1"
  network="$(config_value SAFRANO9999_OPENCLAW_NETWORK || true)"
  network="$(trim "$network")"
  [ "$network" = "default" ] && network=""
  [[ "$network" == "host" || "$network" == "none" ]] && publish_ports=false
  compose_file="$COMPOSE_FILE"
  quadlet_file="$QUADLET_FILE"

  for source_file in "${source_files[@]}"; do
  while IFS= read -r line || [ -n "$line" ]; do
    stripped="$(trim "$line")"
    [[ -z "$stripped" ]] && continue

    disabled=false
    if [[ "$stripped" == \#* ]]; then
      disabled=true
      entry="$(trim "${stripped#\#}")"
    else
      entry="${line%%#*}"
      entry="$(trim "$entry")"
    fi
    [[ "$entry" == *=* ]] || continue

    key="$(trim "${entry%%=*}")"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    if $disabled; then
      value="$(trim "${entry#*=}")"
      if [[ "$key" == *_VOLUMES ]]; then
        split_volumes_into "$value" disabled_volumes disabled_named_volumes
      fi
      continue
    fi

    value="$(config_value "$key" || true)"
    [ -n "$value" ] || continue

    if [[ "$key" == *_PUBLISH_PORT ]]; then
      prefix="${key%_PUBLISH_PORT}"
      internal_key="${prefix}_PORT"
      internal_port="$(config_value "$internal_key" || true)"
      [ -n "$internal_port" ] || internal_port="$value"
      publish_port="$value"
      publish_host="$(config_value "${prefix}_PUBLISH_HOST" || true)"
      [ -n "$publish_host" ] || publish_host="$host"
      map="${publish_host}:${publish_port}:${internal_port}"
      add_unique "$map" ports
      [ -n "$first_port" ] || first_port="$internal_port"
      continue
    fi

    if [[ "$key" == "PORT" || ( "$key" == *_PORT && "$key" != *_PUBLISH_PORT ) ]]; then
      [ -n "$first_port" ] || first_port="$value"
      continue
    fi

    if [[ "$key" == *_CAPABILITIES ]]; then
      split_csv_into "$value" caps
    elif [[ "$key" == *_DEVICES ]]; then
      split_csv_into "$value" devices
    elif [[ "$key" == *_VOLUMES ]]; then
      split_volumes_into "$value" volumes named_volumes
    fi
  done < "$source_file"
  done

  while IFS= read -r item || [ -n "$item" ]; do
    [ -n "$item" ] || continue
    add_volume_item "$item" volumes named_volumes
  done < <("$SQLITE_PERSISTENCE" mounts \
    --zip-root "$SAFRANO_DIR" \
    --config-dir "$SCRIPT_DIR" \
    --container "$CONTAINER_NAME" \
    --target-root "$OPENCLAW_BUILD_CONFIG_DIR/extensions")

  while IFS= read -r item || [ -n "$item" ]; do
    [ -n "$item" ] || continue
    add_volume_item "$item" volumes named_volumes
  done < <("$OPTIONAL_PERSISTENCE" mounts --config-dir "$SCRIPT_DIR" --container "$CONTAINER_NAME")
  while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    persistent_envs+=("$key=$value")
  done < <("$OPTIONAL_PERSISTENCE" entries --config-dir "$SCRIPT_DIR")

  if [ "${#ports[@]}" -eq 0 ] && [ -n "$first_port" ]; then
    add_unique "${host}:${first_port}:${first_port}" ports
  fi

  {
    printf '# Generated by setup.sh for %s\n' "$CONTAINER_NAME"
    printf '# Edit %s, then run ./setup.sh again.\n' "$(basename "$CONFIG_FILE")"
    printf '# Usage: docker compose -f %s up -d\n\n' "$(basename "$COMPOSE_FILE")"
    printf 'services:\n'
    printf '  %s:\n' "$CONTAINER_NAME"
    if [ "$include_build" = "true" ]; then
      printf '    build:\n'
      printf '      context: .\n'
      printf '      dockerfile: Containerfile\n'
      printf '      args:\n'
      printf '        OPENCLAW_IMAGE: %s\n' "$(yaml_dq "$OPENCLAW_BUILD_IMAGE")"
      printf '        OPENCLAW_CONFIG_DIR: %s\n' "$(yaml_dq "$OPENCLAW_BUILD_CONFIG_DIR")"
    fi
    printf '    image: %s\n' "$image"
    printf '    labels:\n'
    printf '      - "io.containers.autoupdate=registry"\n'
    printf '    container_name: %s\n' "$CONTAINER_NAME"
    printf '    hostname: %s\n' "$CONTAINER_NAME"
    [ -n "$network" ] && printf '    network_mode: %s\n' "$(yaml_dq "$network")"
    if $publish_ports && [ "${#ports[@]}" -gt 0 ]; then
      printf '    ports:\n'
      for item in "${ports[@]}"; do printf '      - %s\n' "$(yaml_dq "$item")"; done
    fi
    if [ -f "$CONFIG_FILE" ] || [ -f "$CONTAINER_CONFIG_FILE" ] || [ -f "$BUILD_FILE" ] || [ -f "$ENV_FILE" ]; then
      printf '    env_file:\n'
      [ -f "$CONFIG_FILE" ] && printf '      - %s\n' "$CONFIG_FILE"
      [ -f "$CONTAINER_CONFIG_FILE" ] && printf '      - %s\n' "$CONTAINER_CONFIG_FILE"
      [ -f "$BUILD_FILE" ] && printf '      - %s\n' "$BUILD_FILE"
      [ -f "$ENV_FILE" ] && printf '      - %s\n' "$ENV_FILE"
    fi
    if [ "${#persistent_envs[@]}" -gt 0 ]; then
      printf '    environment:\n'
      for item in "${persistent_envs[@]}"; do printf '      - %s\n' "$(yaml_dq "$item")"; done
    fi
    if [ "${#volumes[@]}" -gt 0 ] || [ "${#disabled_volumes[@]}" -gt 0 ]; then
      printf '    volumes:\n'
      for item in "${disabled_volumes[@]}"; do printf '      # - %s\n' "$item"; done
      for item in "${volumes[@]}"; do printf '      - %s\n' "$item"; done
    fi
    if [ "${#caps[@]}" -gt 0 ]; then
      printf '    cap_add:\n'
      for item in "${caps[@]}"; do printf '      - %s\n' "$item"; done
    fi
    if [ "${#devices[@]}" -gt 0 ]; then
      printf '    devices:\n'
      for item in "${devices[@]}"; do printf '      - %s\n' "$item"; done
    fi
    printf '    restart: always\n'
    if [ "${#named_volumes[@]}" -gt 0 ] || [ "${#disabled_named_volumes[@]}" -gt 0 ]; then
      printf '\nvolumes:\n'
      for item in "${disabled_named_volumes[@]}"; do printf '  # %s: {}\n' "$item"; done
      for item in "${named_volumes[@]}"; do printf '  %s: {}\n' "$item"; done
    fi
  } > "$compose_file"
  echo "  Written: $compose_file"

  {
    printf '# Generated by setup.sh for %s\n' "$CONTAINER_NAME"
    printf '# Edit %s, then run ./setup.sh again.\n\n' "$(basename "$CONFIG_FILE")"
    printf '[Container]\n'
    printf 'ContainerName=%s\n' "$CONTAINER_NAME"
    printf 'Image=%s\n' "$image"
    [ -n "$network" ] && printf 'Network=%s\n' "$network"
    [ -f "$CONFIG_FILE" ] && printf 'EnvironmentFile=%s\n' "$CONFIG_FILE"
    [ -f "$CONTAINER_CONFIG_FILE" ] && printf 'EnvironmentFile=%s\n' "$CONTAINER_CONFIG_FILE"
    [ -f "$BUILD_FILE" ] && printf 'EnvironmentFile=%s\n' "$BUILD_FILE"
    [ -f "$ENV_FILE" ] && printf 'EnvironmentFile=%s\n' "$ENV_FILE"
    for item in "${persistent_envs[@]}"; do printf 'Environment=%s\n' "$(yaml_dq "$item")"; done
    if $publish_ports; then
      for item in "${ports[@]}"; do printf 'PublishPort=%s\n' "$item"; done
    fi
    for item in "${disabled_volumes[@]}"; do printf '# Volume=%s\n' "$item"; done
    for item in "${volumes[@]}"; do printf 'Volume=%s\n' "$item"; done
    for item in "${caps[@]}"; do printf 'AddCapability=%s\n' "$item"; done
    for item in "${devices[@]}"; do printf 'AddDevice=%s\n' "$item"; done
    printf 'AutoUpdate=registry\n\n'
    printf '[Service]\n'
    printf 'Restart=always\n'
    printf 'TimeoutStartSec=30\n\n'
    printf '[Install]\n'
    printf 'WantedBy=default.target\n'
  } > "$quadlet_file"
  echo "  Written: $quadlet_file"
}

echo "  Staging plugin release archives -> safrano9999/"
for p in "${PLUGINS[@]}"; do
  download_plugin_zip "$p"
  stage_provider_conf "$p"
done
rm -f "$SCRIPT_DIR"/*_init*

echo "  Merging examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh" "${CONFIG_PLUGINS[@]}"

if ! $NO_CONFIG; then
  config_sh="$SAFRANO_SCRIPTS_DIR/config.sh"
  [ -f "$config_sh" ] || { echo "Missing bundled config.sh at $config_sh" >&2; exit 1; }
  ( cd "$SCRIPT_DIR" && bash "$config_sh" )
  rm -f "$QUADLET_FILE" "$COMPOSE_FILE" "$SCRIPT_DIR/docker-compose.yml"
  ( cd "$SCRIPT_DIR" && bash "$SAFRANO_SCRIPTS_DIR/legacy.sh" "$SCRIPT_DIR" )
fi

DOCKER_IO_IMAGE="$(docker_io_image)"
OPENCLAW_BUILD_IMAGE="$(config_value OPENCLAW_IMAGE || true)"
[ -n "$OPENCLAW_BUILD_IMAGE" ] || { echo "Missing OPENCLAW_IMAGE in $(basename "$BUILD_FILE")" >&2; exit 1; }
OPENCLAW_BUILD_CONFIG_DIR="$(config_value OPENCLAW_CONFIG_DIR || true)"
[ -n "$OPENCLAW_BUILD_CONFIG_DIR" ] || { echo "Missing OPENCLAW_CONFIG_DIR in $(basename "$BUILD_FILE")" >&2; exit 1; }

EXISTING_IMAGE="$(read_kv_file "$QUADLET_FILE" Image || true)"
RENDER_IMAGE="${EXISTING_IMAGE:-$DOCKER_IO_IMAGE}"
RENDER_BUILD=false
[ "$RENDER_IMAGE" = "$LOCAL_IMAGE" ] && RENDER_BUILD=true
render_compose_and_quadlet "$RENDER_IMAGE" "$RENDER_BUILD"

$NO_BUILD && { echo "  Staging done."; exit 0; }

if [ -z "$IMG_CHOICE" ]; then
  echo ""
  echo "  Image source:"
  echo "    (1) Pull from docker.io  [$DOCKER_IO_IMAGE]"
  echo "    (2) Build locally"
  echo ""
  read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
  IMG_CHOICE="${IMG_CHOICE:-2}"
fi

case "$IMG_CHOICE" in
  1)
    echo ""
    PULL_ENGINE="$(choose_pull_engine)"
    ensure_docker_io_login "$PULL_ENGINE"
    echo "  Pulling $DOCKER_IO_IMAGE ..."
    "$PULL_ENGINE" pull "$DOCKER_IO_IMAGE"
    render_compose_and_quadlet "$DOCKER_IO_IMAGE" false
    echo "  Done. Image ready: $DOCKER_IO_IMAGE"
    ;;
  2)
    echo ""
    if $NO_CACHE; then
      echo "  Building $LOCAL_IMAGE with --no-cache ..."
      podman build --pull=always --no-cache \
        --build-arg "OPENCLAW_IMAGE=$OPENCLAW_BUILD_IMAGE" \
        --build-arg "OPENCLAW_CONFIG_DIR=$OPENCLAW_BUILD_CONFIG_DIR" \
        -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    else
      echo "  Building $LOCAL_IMAGE ..."
      podman build \
        --build-arg "OPENCLAW_IMAGE=$OPENCLAW_BUILD_IMAGE" \
        --build-arg "OPENCLAW_CONFIG_DIR=$OPENCLAW_BUILD_CONFIG_DIR" \
        -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    fi
    render_compose_and_quadlet "$LOCAL_IMAGE" true
    echo "  Done. Image ready: $LOCAL_IMAGE"
    ;;
  *)
    echo "Invalid image choice: $IMG_CHOICE" >&2
    exit 2
    ;;
esac

echo ""
python3 "$SCRIPT_DIR/quadlet_finish.py" "$COMPOSE_FILE" "$QUADLET_FILE" "$CONTAINER_NAME"
