#!/usr/bin/env bash
# setup.sh - orchestrate the safrano9999-openclaw container.
#
# Mirrors CONTAINER/fedora43-ai/setup.sh:
#   1) stage plugin release archives into ./safrano9999
#   2) merge env.example / requirements.txt / config.conf_example
#   3) run shared config.sh, delete generated compose/quadlet, render them here
#   4) choose Docker Hub pull or local build
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
SCRIPTS_DIR="$SCRIPT_DIR/SCRIPTS"
SAFRANO_SCRIPTS_DIR="$SCRIPTS_DIR/safrano9999"
IMAGE_SCRIPTS_DIR="$SAFRANO_SCRIPTS_DIR/image"
CONTAINER_SCRIPTS_DIR="$SAFRANO_SCRIPTS_DIR/container"
INSTALL_DIR="$IMAGE_SCRIPTS_DIR/install"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
CONTAINER_NAME="safrano9999-openclaw"
LOCAL_IMAGE="localhost/${CONTAINER_NAME}:latest"
DOCKER_IO_IMAGE_DEFAULT="docker.io/safrano9999/${CONTAINER_NAME}:latest"
PLUGINS=(DAILYNEWS CALENDAR ZEROINBOX KACHELMANN)

NO_CONFIG=false
NO_CACHE=false
NO_BUILD=false
IMG_CHOICE=""

show_help() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS]

Options:
  --no-cache          Build locally with --pull=always --no-cache when selected
  --no-config         Skip init scripts and config.sh
  --no-build          Stop after staging, merge, config and compose/quadlet rendering
  --help              Show this help and exit

Without options, setup runs config, then asks interactively for pull/build.
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

relink_dev_scripts() {
  local path source target
  local -a paths=(
    safrano9999/config.sh
    safrano9999/container/openclaw/openclaw_allow_all.mjs
    safrano9999/container/openclaw/openclaw_crontabs.conf
    safrano9999/container/openclaw/openclaw_crontabs.sh
    safrano9999/container/safrano9999-openclaw/entrypoint.sh
    safrano9999/container/safrano9999-openclaw/openclaw-configure.py
    safrano9999/container/safrano9999-openclaw/safrano9999-routines.sh
    safrano9999/image/install/github_auth.sh
    safrano9999/image/install/merge_conf.sh
    safrano9999/image/safrano9999_container.sh
    safrano9999/image/services/openclaw/openclaw-patch-deterministic.sh
    safrano9999/image/services/openclaw/openclaw_common.py
    safrano9999/image/services/openclaw/safrano9999_plugins.py
  )

  [ -d "$DEV_SCRIPTS_DIR/.git" ] || return 0
  for path in "${paths[@]}"; do
    source="$DEV_SCRIPTS_DIR/$path"
    target="$SCRIPTS_DIR/$path"
    [ -f "$source" ] || { echo "Missing SOT file: $source" >&2; exit 1; }
    mkdir -p "$(dirname "$target")"
    [ -e "$target" ] && [ "$source" -ef "$target" ] || ln -f "$source" "$target"
  done
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

  for file in "$SCRIPT_DIR/config.conf" "$SCRIPT_DIR/config.conf_example" "$SCRIPT_DIR/.env" "$SCRIPT_DIR/env.example"; do
    read_kv_file "$file" "$key" && return 0
  done
  return 1
}

docker_io_image() {
  local configured
  configured="$(config_value SAFRANO9999_OPENCLAW_DOCKER_IMAGE || true)"
  printf '%s\n' "${configured:-$DOCKER_IO_IMAGE_DEFAULT}"
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

stage_init_scripts() {
  local name="$1"
  local lower zip_path member target

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  zip_path="$SAFRANO_DIR/${lower}-latest.zip"
  rm -f "$SCRIPT_DIR/${name}_init"*

  while IFS= read -r member || [ -n "$member" ]; do
    [ -n "$member" ] || continue
    target="$SCRIPT_DIR/$(basename "$member")"
    unzip -p "$zip_path" "$member" > "$target"
    chmod +x "$target"
    echo "  staged init script: $(basename "$target")"
  done < <(unzip -Z1 "$zip_path" | grep -E "^${name}_init[^/]*$" || true)
}

run_init_scripts() {
  local script
  shopt -s nullglob
  for script in "$SCRIPT_DIR"/*_init*; do
    [ -f "$script" ] || continue
    [ -x "$script" ] || chmod +x "$script"
    echo "  Running init script: $(basename "$script")"
    (cd "$SCRIPT_DIR" && "$script")
  done
  shopt -u nullglob
}

merge_config_examples() {
  local merge_conf="$INSTALL_DIR/merge_conf.sh"
  local output="$SCRIPT_DIR/config.conf_example"
  local container_example="$SCRIPT_DIR/config.safrano9999-openclaw.conf_example"
  local tmp_sources

  tmp_sources="$(mktemp -d "${TMPDIR:-/tmp}/safrano9999-openclaw-config.XXXXXX")"

  shopt -s nullglob
  for zip_path in "$SAFRANO_DIR"/*-latest.zip; do
    local base dst
    if ! unzip -Z1 "$zip_path" | grep -qx 'config.conf_example'; then
      continue
    fi
    base="$(basename "$zip_path" -latest.zip)"
    dst="$tmp_sources/${base^^}"
    mkdir -p "$dst"
    unzip -p "$zip_path" config.conf_example > "$dst/config.conf_example"
  done
  shopt -u nullglob

  if [ -f "$merge_conf" ]; then
    bash "$merge_conf" \
      "$SCRIPT_DIR" \
      "$output" \
      "$container_example" \
      "$tmp_sources" \
      "config.conf_example"
    rm -rf "$tmp_sources"
    return 0
  fi

  echo "  merge_conf.sh not found; using setup.sh fallback merger"
  shopt -s nullglob
  local -a config_files=("$tmp_sources"/*/config.conf_example)
  shopt -u nullglob
  if [ "${#config_files[@]}" -eq 0 ]; then
    cp "$container_example" "$output"
    rm -rf "$tmp_sources"
    return 0
  fi
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function parse_key(line,    entry, key) {
      entry = line
      sub(/#.*/, "", entry)
      entry = trim(entry)
      if (entry !~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) return ""
      key = entry
      sub(/[[:space:]]*=.*/, "", key)
      return trim(key)
    }
    FNR == 1 {
      pending = ""
      label = FILENAME
      sub(/^.*\//, "", label)
      pending = pending "\n# --- " label " ---\n"
    }
    {
      raw = $0
      stripped = trim(raw)
      if (stripped == "" || substr(stripped, 1, 1) == "#") {
        pending = pending raw "\n"
        next
      }
      key = parse_key(raw)
      if (key == "") {
        pending = ""
        next
      }
      if (!(key in seen)) {
        printf "%s%s\n", pending, raw
        seen[key] = 1
      }
      pending = ""
    }
  ' "$container_example" "${config_files[@]}" > "$output"
  rm -rf "$tmp_sources"
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
  if [ -f "$SCRIPT_DIR/config.conf" ]; then
    printf '%s\n' "$SCRIPT_DIR/config.conf"
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
  local prefix internal_key internal_port publish_port publish_host map source
  local first_port=""
  local -a ports=()
  local -a volumes=()
  local -a disabled_volumes=()
  local -a caps=()
  local -a devices=()
  local -a named_volumes=()
  local -a disabled_named_volumes=()

  local -a source_files=()
  [ -f "$SCRIPT_DIR/config.conf_example" ] && source_files+=("$SCRIPT_DIR/config.conf_example")
  [ -f "$SCRIPT_DIR/config.conf" ] && source_files+=("$SCRIPT_DIR/config.conf")
  if [ "${#source_files[@]}" -eq 0 ]; then
    source_files+=("$(source_file_for_render)")
  fi
  host="$(config_value HOST || true)"
  [ -n "$host" ] || host="127.0.0.1"
  compose_file="$SCRIPT_DIR/compose.yml"
  quadlet_file="$SCRIPT_DIR/${CONTAINER_NAME}.container"

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

  if [ "${#ports[@]}" -eq 0 ] && [ -n "$first_port" ]; then
    add_unique "${host}:${first_port}:${first_port}" ports
  fi

  {
    printf '# Generated by setup.sh for %s\n' "$CONTAINER_NAME"
    printf '# Edit config.conf, then run ./setup.sh again.\n'
    printf '# Usage: docker compose -f compose.yml up -d\n\n'
    printf 'services:\n'
    printf '  %s:\n' "$CONTAINER_NAME"
    if [ "$include_build" = "true" ]; then
      printf '    build:\n'
      printf '      context: .\n'
      printf '      dockerfile: Containerfile\n'
    fi
    printf '    image: %s\n' "$image"
    printf '    container_name: %s\n' "$CONTAINER_NAME"
    printf '    hostname: %s\n' "$CONTAINER_NAME"
    if [ "${#ports[@]}" -gt 0 ]; then
      printf '    ports:\n'
      for item in "${ports[@]}"; do printf '      - %s\n' "$(yaml_dq "$item")"; done
    fi
    if [ -f "$SCRIPT_DIR/config.conf" ] || [ -f "$SCRIPT_DIR/.env" ]; then
      printf '    env_file:\n'
      [ -f "$SCRIPT_DIR/config.conf" ] && printf '      - %s\n' "$SCRIPT_DIR/config.conf"
      [ -f "$SCRIPT_DIR/.env" ] && printf '      - %s\n' "$SCRIPT_DIR/.env"
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
    printf '# Edit config.conf, then run ./setup.sh again.\n\n'
    printf '[Container]\n'
    printf 'ContainerName=%s\n' "$CONTAINER_NAME"
    printf 'Image=%s\n' "$image"
    [ -f "$SCRIPT_DIR/config.conf" ] && printf 'EnvironmentFile=%s\n' "$SCRIPT_DIR/config.conf"
    [ -f "$SCRIPT_DIR/.env" ] && printf 'EnvironmentFile=%s\n' "$SCRIPT_DIR/.env"
    for item in "${ports[@]}"; do printf 'PublishPort=%s\n' "$item"; done
    for item in "${disabled_volumes[@]}"; do printf '# Volume=%s\n' "$item"; done
    for item in "${volumes[@]}"; do printf 'Volume=%s\n' "$item"; done
    for item in "${caps[@]}"; do printf 'AddCapability=%s\n' "$item"; done
    for item in "${devices[@]}"; do printf 'AddDevice=%s\n' "$item"; done
    printf '#AutoUpdate=registry\n\n'
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
  stage_init_scripts "$p"
done

echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

echo "  Merging config.conf_example ..."
merge_config_examples

if ! $NO_CONFIG; then
  run_init_scripts
  config_sh="$SAFRANO_SCRIPTS_DIR/config.sh"
  [ -f "$config_sh" ] || { echo "Missing bundled config.sh at $config_sh" >&2; exit 1; }
  ( cd "$SCRIPT_DIR" && bash "$config_sh" )
  rm -f "$SCRIPT_DIR/${CONTAINER_NAME}.container" "$SCRIPT_DIR/compose.yml" "$SCRIPT_DIR/docker-compose.yml"
fi

render_compose_and_quadlet "$LOCAL_IMAGE" true

$NO_BUILD && { echo "  Staging done."; exit 0; }

DOCKER_IO_IMAGE="$(docker_io_image)"

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
    echo "  Pulling $DOCKER_IO_IMAGE ..."
    podman pull "$DOCKER_IO_IMAGE"
    render_compose_and_quadlet "$DOCKER_IO_IMAGE" false
    echo "  Done. Image ready: $DOCKER_IO_IMAGE"
    ;;
  2)
    echo ""
    if $NO_CACHE; then
      echo "  Building $LOCAL_IMAGE with --no-cache ..."
      podman build --pull=always --no-cache -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    else
      echo "  Building $LOCAL_IMAGE ..."
      podman build -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
    fi
    echo "  Done. Image ready: $LOCAL_IMAGE"
    ;;
  *)
    echo "Invalid image choice: $IMG_CHOICE" >&2
    exit 2
    ;;
esac

echo ""
echo "  Start:   podman-compose -f $SCRIPT_DIR/compose.yml up -d"
echo "  Quadlet: ln -sf $SCRIPT_DIR/${CONTAINER_NAME}.container ~/.config/containers/systemd/${CONTAINER_NAME}.container"
echo "           systemctl --user daemon-reload && systemctl --user restart ${CONTAINER_NAME}.service"
