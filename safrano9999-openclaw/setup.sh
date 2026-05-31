#!/usr/bin/env bash
# setup.sh - orchestrate the safrano9999-openclaw container.
# Modelled on CONTAINER/fedora43-ai/setup.sh:
#   1) download the four plugin release archives into ./safrano9999/<NAME>
#   2) merge their SOT env.example + config.conf_example (+ the container's own)
#   3) run the shared config.sh (SOT, hardlinked) -> .env + config.conf + compose/quadlet
#   4) build the image
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
ZIP_DIR="$SCRIPT_DIR/plugin-zips"
SAFCONTAINER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_DIR="$SAFCONTAINER_DIR/SCRIPTS/INSTALL"
IMAGE="localhost/safrano9999-openclaw:latest"
PLUGINS=(DAILYNEWS CALENDAR ZEROINBOX KACHELMANN)

NO_CONFIG=false; CONFIG_ONLY=false; FRESH=false
for arg in "$@"; do
  case "$arg" in
    --no-config) NO_CONFIG=true ;;
    --config)    CONFIG_ONLY=true ;;
    --fresh)     FRESH=true ;;
  esac
done

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
  local lower tag zip zip_path sha_path url tmp dst token
  local -a curl_auth=()

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  tag="$(plugin_tag "$name")"
  zip="${lower}-latest.zip"
  zip_path="$ZIP_DIR/$zip"
  sha_path="$ZIP_DIR/$zip.sha256"
  url="https://github.com/safrano9999/$name/releases/download/$tag"
  tmp="$SAFRANO_DIR/.tmp-$name"
  dst="$SAFRANO_DIR/$name"

  mkdir -p "$ZIP_DIR" "$SAFRANO_DIR"
  rm -f "$zip_path" "$sha_path"
  echo "  downloading $name ($tag) -> $zip"
  if command -v gh >/dev/null 2>&1; then
    gh release download "$tag" \
      -R "safrano9999/$name" \
      --pattern "$zip" \
      --pattern "$zip.sha256" \
      --dir "$ZIP_DIR" \
      --clobber >/dev/null
  else
    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [ -n "$token" ] && curl_auth=(-H "Authorization: Bearer $token")
    curl -fsSL --retry 3 --retry-delay 2 "${curl_auth[@]}" "$url/$zip" -o "$zip_path"
    curl -fsSL --retry 3 --retry-delay 2 "${curl_auth[@]}" "$url/$zip.sha256" -o "$sha_path"
  fi
  (cd "$ZIP_DIR" && sha256sum -c "$zip.sha256" >/dev/null)

  rm -rf "$tmp" "$dst"
  mkdir -p "$tmp"
  unzip -q "$zip_path" -d "$tmp"
  mv "$tmp" "$dst"
  echo "  staged $name from release archive"
}

# 1) download release archives into ./safrano9999/<NAME>
echo "  Staging plugin release archives -> safrano9999/"
for p in "${PLUGINS[@]}"; do download_plugin_zip "$p"; done

# 2) merge SOT examples
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

echo "  Merging config.conf_example ..."
ln -f "$INSTALL_DIR/merge_conf.sh" "$SCRIPT_DIR/merge_conf.sh"
bash "$SCRIPT_DIR/merge_conf.sh" \
  "$SCRIPT_DIR" \
  "$SCRIPT_DIR/config.conf_example" \
  "$SCRIPT_DIR/config.safrano9999-openclaw.conf_example" \
  "$SCRIPT_DIR/safrano9999" \
  "config.conf_example"

# 3) interactive config + compose/quadlet render via the shared config.sh
if ! $NO_CONFIG; then
  ln -f "$INSTALL_DIR/config.sh" "$SCRIPT_DIR/config.sh"
  ( cd "$SCRIPT_DIR" && bash config.sh )
fi

$CONFIG_ONLY && { echo "  Config done."; exit 0; }

# 4) build the image
if $FRESH; then
  echo "  Fresh build ..."
  podman build --pull=always --no-cache -t "$IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
else
  echo "  Building $IMAGE ..."
  podman build -t "$IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
fi
echo ""
echo "  Done. Image: $IMAGE"
echo "  Start:   podman-compose -f $SCRIPT_DIR/compose.yml up -d"
echo "  Quadlet: cp $SCRIPT_DIR/safrano9999-openclaw.container ~/.config/containers/systemd/"
echo "           systemctl --user daemon-reload && systemctl --user start safrano9999-openclaw"
