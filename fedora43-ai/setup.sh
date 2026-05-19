#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"

CONFIG_ONLY=false
NO_CONFIG=false
INSTANCE="fedora43-ai"

for arg in "$@"; do
    case "$arg" in
        --config)    CONFIG_ONLY=true ;;
        --no-config) NO_CONFIG=true ;;
        *) INSTANCE="$arg" ;;
    esac
done

sync_repo() {
    local repo="$1"
    if [ -d "$SAFRANO_DIR/$repo" ]; then
        git -C "$SAFRANO_DIR/$repo" pull --ff-only
    else
        git clone --depth 1 "https://github.com/safrano9999/$repo" "$SAFRANO_DIR/$repo"
    fi
}

# ── Repos klonen oder aktualisieren ──────────────────────────────────
REPOS=(CODEANALYST JUGO CITADEL VikAI)

mkdir -p "$SAFRANO_DIR"
for repo in "${REPOS[@]}"; do sync_repo "$repo"; done

# ── env.examples + requirements.txt dedupliziert zusammenführen ──────
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

COMPOSE_MERGE_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/merge_compose.sh"
COMPOSE_CONFIG_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/config_compose.sh"
ln -f "$COMPOSE_MERGE_SH" "$SCRIPT_DIR/merge_compose.sh"
ln -f "$COMPOSE_CONFIG_SH" "$SCRIPT_DIR/config_compose.sh"
bash "$SCRIPT_DIR/merge_compose.sh"

# ── config.sh aus SCRIPTS/INSTALL als Hardlink bereitstellen ─────────
if ! $NO_CONFIG; then
    CONFIG_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS/INSTALL/config_template.sh"
    ln -f "$CONFIG_SH" "$SCRIPT_DIR/config.sh"
    echo ""
    (cd "$SCRIPT_DIR" && bash config.sh)
    (cd "$SCRIPT_DIR" && bash config_compose.sh)
    CONTAINER_NAME="$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')"
    rm -f "$SCRIPT_DIR/$CONTAINER_NAME.container" "$SCRIPT_DIR/docker-compose.yml"
elif [ ! -f "$SCRIPT_DIR/compose.conf" ]; then
    (cd "$SCRIPT_DIR" && bash config_compose.sh --defaults)
fi

# ── Werte aus .env und compose.conf ──────────────────────────────────
env_val() { grep "^${1}=" "$SCRIPT_DIR/.env" | head -1 | cut -d= -f2-; }
HOST="$(env_val HOST)"

declare -a PUBLISH_PORTS=()
declare -a ADD_CAPABILITIES=()
declare -a ADD_DEVICES=()
declare -a EXTRA_VOLUMES=()
declare -a NAMED_VOLUMES=()

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

add_unique() {
    local array_name="$1"
    local value="$2"
    local item
    local -n array_ref="$array_name"
    [ -n "$value" ] || return 0
    for item in "${array_ref[@]}"; do
        [ "$item" = "$value" ] && return 0
    done
    array_ref+=("$value")
}

normalize_publish_port() {
    local raw
    raw="$(trim "$1")"
    raw="${raw%\"}"
    raw="${raw#\"}"
    raw="${raw%\'}"
    raw="${raw#\'}"

    local -a parts=()
    local published target count
    IFS=':' read -r -a parts <<< "$raw"
    count="${#parts[@]}"
    if [ "$count" -eq 1 ]; then
        published="${parts[0]}"
        target="${parts[0]}"
    elif [ "$count" -eq 2 ]; then
        published="${parts[0]}"
        target="${parts[1]}"
    else
        published="${parts[$((count - 2))]}"
        target="${parts[$((count - 1))]}"
    fi
    printf '%s:%s:%s' "$HOST" "$published" "$target"
}

volume_target() {
    local raw="$1"
    if [[ "$raw" == *:* ]]; then
        printf '%s' "${raw#*:}"
    else
        printf '%s' "$raw"
    fi
}

maybe_add_named_volume() {
    local raw="$1"
    [[ "$raw" == *:* ]] || return 0
    local source="${raw%%:*}"
    case "$source" in
        ""|/*|.*|\$*|~*|*/*) return 0 ;;
    esac
    add_unique NAMED_VOLUMES "$source"
}

load_compose_conf() {
    local conf="$SCRIPT_DIR/compose.conf"
    [ -f "$conf" ] || { echo "No compose.conf" >&2; exit 1; }

    local line stripped key value cap existing_target target
    while IFS= read -r line || [ -n "$line" ]; do
        stripped="$(trim "$line")"
        [[ -z "$stripped" || "$stripped" == \#* || "$stripped" != *=* ]] && continue
        key="$(trim "${stripped%%=*}")"
        value="$(trim "${stripped#*=}")"
        [ -n "$value" ] || continue

        case "$key" in
            PublishPort)
                add_unique PUBLISH_PORTS "$(normalize_publish_port "$value")"
                ;;
            AddCapability)
                for cap in $value; do add_unique ADD_CAPABILITIES "$cap"; done
                ;;
            AddDevice)
                add_unique ADD_DEVICES "$value"
                ;;
            Volume)
                target="$(volume_target "$value")"
                for existing_target in "${EXTRA_VOLUMES[@]}"; do
                    [ "$(volume_target "$existing_target")" = "$target" ] && continue 2
                done
                EXTRA_VOLUMES+=("$value")
                maybe_add_named_volume "$value"
                ;;
        esac
    done < "$conf"
}

load_compose_conf

# ── compose.yml generieren ───────────────────────────────────────────
echo "  Generating compose.yml..."
cat > "$SCRIPT_DIR/compose.yml" <<EOF
services:
  fedora43-ai:
    build:
      context: .
      dockerfile: Containerfile
    image: localhost/fedora43-ai:latest
    container_name: \${INSTANCE:-fedora43-ai}

    ports:
EOF
for port in "${PUBLISH_PORTS[@]}"; do
    printf '      - "%s"\n' "$port" >> "$SCRIPT_DIR/compose.yml"
done

cat >> "$SCRIPT_DIR/compose.yml" <<EOF
    env_file:
      - .env

    environment:
      - PATH=/usr/local/bin:/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - DISPLAY=\${DISPLAY:-:0}
      - NO_AT_BRIDGE=1
      - XDG_RUNTIME_DIR=/tmp/runtime-root
      - HERMES_HOME=/root/hermes-home
      - HERMES_INSTALL_DIR=/usr/local/lib/hermes-agent
      - OPENCLAW_START=1
      - HERMES_START=1

    volumes:
      - \${HOST_HOME_DIR:-home}:/home
      - \${HOST_SRV_DIR}:/srv
      - \${HOST_ROOT_DIR:-root}:/root
      - /tmp/.X11-unix:/tmp/.X11-unix
EOF
for volume in "${EXTRA_VOLUMES[@]}"; do
    printf '      - %s\n' "$volume" >> "$SCRIPT_DIR/compose.yml"
done

if [ "${#ADD_CAPABILITIES[@]}" -gt 0 ]; then
    printf '    cap_add:\n' >> "$SCRIPT_DIR/compose.yml"
    for cap in "${ADD_CAPABILITIES[@]}"; do
        printf '      - %s\n' "$cap" >> "$SCRIPT_DIR/compose.yml"
    done
fi

if [ "${#ADD_DEVICES[@]}" -gt 0 ]; then
    printf '    devices:\n' >> "$SCRIPT_DIR/compose.yml"
    for device in "${ADD_DEVICES[@]}"; do
        printf '      - %s\n' "$device" >> "$SCRIPT_DIR/compose.yml"
    done
fi

cat >> "$SCRIPT_DIR/compose.yml" <<EOF
volumes:
  home: {}
  root: {}
EOF
for volume_name in "${NAMED_VOLUMES[@]}"; do
    printf '  %s: {}\n' "$volume_name" >> "$SCRIPT_DIR/compose.yml"
done

# ── Quadlet .container generieren ────────────────────────────────────
echo "  Generating fedora43-ai.container..."
cat > "$SCRIPT_DIR/fedora43-ai.container" <<EOF
[Container]
ContainerName=fedora43-ai
Image=localhost/fedora43-ai:latest
EnvironmentFile=$SCRIPT_DIR/.env
Environment=OPENCLAW_START=1
Environment=HERMES_START=1
EOF
for port in "${PUBLISH_PORTS[@]}"; do
    printf 'PublishPort=%s\n' "$port" >> "$SCRIPT_DIR/fedora43-ai.container"
done

cat >> "$SCRIPT_DIR/fedora43-ai.container" <<EOF
Volume=$HOME/fedora43-ai/srv:/srv
EOF
for volume in "${EXTRA_VOLUMES[@]}"; do
    printf 'Volume=%s\n' "$volume" >> "$SCRIPT_DIR/fedora43-ai.container"
done
for cap in "${ADD_CAPABILITIES[@]}"; do
    printf 'AddCapability=%s\n' "$cap" >> "$SCRIPT_DIR/fedora43-ai.container"
done
for device in "${ADD_DEVICES[@]}"; do
    printf 'AddDevice=%s\n' "$device" >> "$SCRIPT_DIR/fedora43-ai.container"
done

printf '\n' >> "$SCRIPT_DIR/fedora43-ai.container"
cat >> "$SCRIPT_DIR/fedora43-ai.container" <<EOF
[Service]
Restart=always
TimeoutStartSec=60

[Install]
WantedBy=default.target
EOF

$CONFIG_ONLY && echo "" && echo "  Config done." && exit 0

# ── Image-Quelle wählen ──────────────────────────────────────────────
DOCKER_IO_IMAGE="docker.io/safrano9999/fedora43-ai:latest"
LOCAL_IMAGE="localhost/fedora43-ai:latest"

echo ""
echo "  Image source:"
echo "    (1) Pull from docker.io  [$DOCKER_IO_IMAGE]"
echo "    (2) Build locally"
echo ""
read -rp "  Choose [1/2] (default: 1): " IMG_CHOICE
IMG_CHOICE="${IMG_CHOICE:-1}"

case "$IMG_CHOICE" in
    1)
        echo ""
        echo "  Pulling $DOCKER_IO_IMAGE ..."
        podman pull "$DOCKER_IO_IMAGE"
        IMAGE_REF="$DOCKER_IO_IMAGE"
        # Update compose.yml to use pulled image (no build)
        sed -i '/^\s*build:/,/^\s*dockerfile:/d' "$SCRIPT_DIR/compose.yml"
        sed -i "s|image: .*|image: $DOCKER_IO_IMAGE|" "$SCRIPT_DIR/compose.yml"
        # Update quadlet .container
        sed -i "s|^Image=.*|Image=$DOCKER_IO_IMAGE|" "$SCRIPT_DIR/fedora43-ai.container"
        echo "  Done. Image ready: $DOCKER_IO_IMAGE"
        ;;
    2)
        echo ""
        echo "  Starte Build..."
        HOST_SRV_DIR="/srv/$INSTANCE"
        export INSTANCE HOST_SRV_DIR
        podman-compose \
            -f "$SCRIPT_DIR/compose.yml" \
            build
        ;;
esac
