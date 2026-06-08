#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
SHARED_SCRIPTS_DIR="${SHARED_SCRIPTS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)/SCRIPTS}"
SHARED_SAFRANO_DIR="$SHARED_SCRIPTS_DIR/safrano9999"
SHARED_IMAGE_DIR="$SHARED_SAFRANO_DIR/image"

CONFIG_ONLY=false
NO_CONFIG=false
NO_CACHE=false
BUILD_ONLY=false
NO_BUILD=false
IMG_CHOICE=""
INSTANCE="fedora43-ai"

show_help() {
    cat <<'EOF'
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --build-only        Skip config.sh, then ask interactively for pull/build
  --no-cache          Use with --build-only to build with --pull=always --no-cache
  --config-only       Stop after staging, merging, config, compose and quadlet
  --help              Show this help and exit

INSTANCE defaults to fedora43-ai and is used by compose build metadata.
Without options, setup runs config + local build without --no-cache.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help)      show_help; exit 0 ;;
        --config|--config-only) CONFIG_ONLY=true ;;
        --build-only) BUILD_ONLY=true; NO_CONFIG=true ;;
        --no-cache)  NO_CACHE=true ;;
        --no-config) NO_CONFIG=true ;;
        --no-build|--stage-only) NO_BUILD=true; NO_CONFIG=true ;;
        --pull)      IMG_CHOICE=1 ;;
        --build)     IMG_CHOICE=2 ;;
        --*)         echo "Unknown argument: $arg" >&2; exit 2 ;;
        *) INSTANCE="$arg" ;;
    esac
done

github_repo_url() {
    local repo="$1"

    printf 'https://github.com/safrano9999/%s' "$repo"
}

sync_repo() {
    local spec="$1"
    local repo="$spec"
    local branch=""
    local before after

    if [[ "$spec" == *@* ]]; then
        repo="${spec%@*}"
        branch="${spec#*@}"
    fi

    if [ -d "$SAFRANO_DIR/$repo" ]; then
        before="$(git -C "$SAFRANO_DIR/$repo" rev-parse HEAD)"
        echo "  [$repo] Updating..."
        if [ -n "$branch" ]; then
            git -C "$SAFRANO_DIR/$repo" fetch --quiet --depth 1 origin "$branch"
            if git -C "$SAFRANO_DIR/$repo" rev-parse --verify "$branch" >/dev/null 2>&1; then
                git -C "$SAFRANO_DIR/$repo" checkout --quiet "$branch"
            else
                git -C "$SAFRANO_DIR/$repo" checkout --quiet -b "$branch" "origin/$branch"
            fi
            git -C "$SAFRANO_DIR/$repo" pull --quiet --ff-only origin "$branch"
        else
            git -C "$SAFRANO_DIR/$repo" pull --quiet --ff-only
        fi
        after="$(git -C "$SAFRANO_DIR/$repo" rev-parse HEAD)"
        [ "$before" = "$after" ] && echo "  [$repo] Up to date." || echo "  [$repo] Updated."
    else
        local url
        url="$(github_repo_url "$repo")"
        echo "  [$repo] Cloning..."
        if [ -n "$branch" ]; then
            git clone --quiet --depth 1 --branch "$branch" "$url" "$SAFRANO_DIR/$repo"
        else
            git clone --quiet --depth 1 "$url" "$SAFRANO_DIR/$repo"
        fi
        echo "  [$repo] Cloned."
    fi
}

# Clone or update repositories.
REPOS=(
    SCRIPTS
    CODEANALYST
    JUGO
    CITADEL
    VikAI
    PV_D-A-CH
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual
    DAILYNEWS
    CALENDAR
    ZEROINBOX
    KACHELMANN
)

mkdir -p "$SAFRANO_DIR"
for repo in "${REPOS[@]}"; do sync_repo "$repo"; done
mkdir -p "$SAFRANO_DIR/SCRIPTS/safrano9999/image" "$SAFRANO_DIR/SCRIPTS/safrano9999/container/openclaw"
ln -f "$SHARED_IMAGE_DIR/safrano9999_container.sh" "$SAFRANO_DIR/SCRIPTS/safrano9999/image/safrano9999_container.sh"
ln -f "$SHARED_SAFRANO_DIR/container/openclaw/openclaw_crontabs.sh" "$SAFRANO_DIR/SCRIPTS/safrano9999/container/openclaw/openclaw_crontabs.sh"
"$SHARED_IMAGE_DIR/relink_shared.sh" \
    config.sh merge_conf.sh python_header.py \
    openclaw-config.service openclaw.service openclaw_common.py \
    safrano9999_plugins.py tailscale-up.service tailscaled.service

# Merge and deduplicate env examples and requirements.
echo "  Merging env.examples + requirements.txt..."
bash "$SCRIPT_DIR/merge.sh"

bash "$SHARED_IMAGE_DIR/install/merge_conf.sh" \
    "$SCRIPT_DIR" \
    "$SCRIPT_DIR/config.conf_example" \
    "$SCRIPT_DIR/config.fedora43-ai.conf_example" \
    "$SCRIPT_DIR/safrano9999" \
    "config.conf_example"

if ! $NO_CONFIG; then
    echo ""
    (cd "$SCRIPT_DIR" && bash "$SHARED_SAFRANO_DIR/config.sh")
    CONTAINER_NAME="$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')"
    rm -f "$SCRIPT_DIR/$CONTAINER_NAME.container" "$SCRIPT_DIR/docker-compose.yml"
fi

render_compose_from_conf() {
    local input="$SCRIPT_DIR/config.conf"
    if [ ! -f "$input" ]; then
        input="$SCRIPT_DIR/config.conf_example"
    fi
    [ -f "$input" ] || { echo "No config.conf or config.conf_example" >&2; exit 1; }

    awk -v cwd="$SCRIPT_DIR" -v home="$HOME" '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    function val(line) {
        sub(/^[^:]+:[[:space:]]*/, "", line)
        return trim(line)
    }
    function clean_value(s) {
        s = trim(s)
        if ((s ~ /^".*"$/) || (s ~ /^\047.*\047$/)) s = substr(s, 2, length(s) - 2)
        return s
    }
    function yaml_dq(s,    t) {
        t = s
        gsub(/\\/, "\\\\", t)
        gsub(/"/, "\\\"", t)
        return "\"" t "\""
    }
    function systemd_dq(s,    t) {
        t = s
        gsub(/\\/, "\\\\", t)
        gsub(/"/, "\\\"", t)
        return "\"" t "\""
    }
    function add_env(key, value) {
        if (key == "" || value == "") return
        if (!(key in env_seen)) env_order[++env_count] = key
        env_seen[key] = 1
        env[key] = value
    }
    function add_port(value) {
        if (value == "" || value in port_seen) return
        port_seen[value] = 1
        ports[++port_count] = value
    }
    function add_named_volume(name) {
        if (name == "" || name in named_seen) return
        named_seen[name] = 1
        named_volumes[++named_count] = name
    }
    function add_volume(value, source) {
        if (value == "" || value in volume_seen) return
        volume_seen[value] = 1
        volumes[++volume_count] = value
        if (source !~ /^[/.$~]/ && source !~ /\//) add_named_volume(source)
    }
    function add_cap(value) {
        if (value == "" || value in cap_seen) return
        cap_seen[value] = 1
        caps[++cap_count] = value
    }
    function add_device(value) {
        if (value == "" || value in device_seen) return
        device_seen[value] = 1
        devices[++device_count] = value
    }
    function add_group(value) {
        if (value == "" || value in group_seen) return
        group_seen[value] = 1
        groups[++group_count] = value
    }
    function split_csv(value, out,    n, i, part) {
        n = split(value, out, ",")
        for (i = 1; i <= n; i++) out[i] = trim(out[i])
        return n
    }
    function skip_env_key(key) {
        return key == "INJECT_OVERWRITE" || \
            key ~ /_PUBLISH_HOST$/ || key ~ /_PUBLISH_PORT$/ || \
            key ~ /_CAPABILITIES$/ || key ~ /_DEVICES$/ || \
            key ~ /_VOLUMES$/ || key ~ /_GROUP_ADD$/
    }
    /^[[:space:]]*($|#)/ { next }
    {
        line = $0
        sub(/\r$/, "", line)
        sub(/^[[:space:]]*export[[:space:]]+/, "", line)
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*=/) next
        key = line
        sub(/=.*/, "", key)
        value = line
        sub(/^[^=]*=/, "", value)
        value = clean_value(value)
        if (!(key in values)) order[++value_count] = key
        values[key] = value
        next
    }
    END {
        default_publish_host = values["HOST"]
        if (default_publish_host == "") default_publish_host = "127.0.0.1"

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            value = values[key]
            if (!skip_env_key(key)) add_env(key, value)
        }

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            if (key !~ /_PUBLISH_PORT$/) continue
            prefix = key
            sub(/_PUBLISH_PORT$/, "", prefix)
            port = values[prefix "_PORT"]
            if (port == "") port = values[key]
            host = values[prefix "_PUBLISH_HOST"]
            if (host == "") host = default_publish_host
            add_port(host ":" values[key] ":" port)
            add_env(prefix "_PUBLISH_HOST", host)
            add_env(prefix "_PUBLISH_PORT", values[key])
        }

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            value = values[key]
            if (key ~ /_CAPABILITIES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) add_cap(items[j])
            } else if (key ~ /_DEVICES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) add_device(items[j])
            } else if (key ~ /_VOLUMES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) {
                    split(items[j], parts, ":")
                    add_volume(items[j], parts[1])
                }
            } else if (key ~ /_GROUP_ADD$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) add_group(items[j])
            }
        }

        print "services:" > "compose.yml"
        print "  fedora43-ai:" >> "compose.yml"
        print "    build:" >> "compose.yml"
        print "      context: ." >> "compose.yml"
        print "      dockerfile: Containerfile" >> "compose.yml"
        print "    image: localhost/fedora43-ai:latest" >> "compose.yml"
        print "    container_name: ${INSTANCE:-fedora43-ai}" >> "compose.yml"
        print "    ports:" >> "compose.yml"
        for (i = 1; i <= port_count; i++) print "      - " yaml_dq(ports[i]) >> "compose.yml"
        print "    env_file:" >> "compose.yml"
        print "      - .env" >> "compose.yml"
        print "    environment:" >> "compose.yml"
        for (i = 1; i <= env_count; i++) print "      - " yaml_dq(env_order[i] "=" env[env_order[i]]) >> "compose.yml"
        print "    volumes:" >> "compose.yml"
        print "      - " yaml_dq("${HOST_HOME_DIR:-home}:/home") >> "compose.yml"
        print "      - " yaml_dq("${HOST_SRV_DIR:-" home "/fedora43-ai/srv}:/srv") >> "compose.yml"
        print "      - " yaml_dq("${HOST_ROOT_DIR:-root}:/root") >> "compose.yml"
        print "      - " yaml_dq("/tmp/.X11-unix:/tmp/.X11-unix") >> "compose.yml"
        for (i = 1; i <= volume_count; i++) print "      - " yaml_dq(volumes[i]) >> "compose.yml"
        if (group_count > 0) {
            print "    group_add:" >> "compose.yml"
            for (i = 1; i <= group_count; i++) print "      - " groups[i] >> "compose.yml"
        }
        if (cap_count > 0) {
            print "    cap_add:" >> "compose.yml"
            for (i = 1; i <= cap_count; i++) print "      - " caps[i] >> "compose.yml"
        }
        if (device_count > 0) {
            print "    devices:" >> "compose.yml"
            for (i = 1; i <= device_count; i++) print "      - " devices[i] >> "compose.yml"
        }
        print "volumes:" >> "compose.yml"
        print "  home: {}" >> "compose.yml"
        print "  root: {}" >> "compose.yml"
        for (i = 1; i <= named_count; i++) print "  " named_volumes[i] ": {}" >> "compose.yml"

        print "[Container]" > "fedora43-ai.container"
        print "ContainerName=fedora43-ai" >> "fedora43-ai.container"
        print "Image=localhost/fedora43-ai:latest" >> "fedora43-ai.container"
        print "EnvironmentFile=" cwd "/.env" >> "fedora43-ai.container"
        for (i = 1; i <= env_count; i++) print "Environment=" systemd_dq(env_order[i] "=" env[env_order[i]]) >> "fedora43-ai.container"
        for (i = 1; i <= port_count; i++) print "PublishPort=" ports[i] >> "fedora43-ai.container"
        print "Volume=" home "/fedora43-ai/srv:/srv" >> "fedora43-ai.container"
        for (i = 1; i <= volume_count; i++) print "Volume=" volumes[i] >> "fedora43-ai.container"
        for (i = 1; i <= cap_count; i++) print "AddCapability=" caps[i] >> "fedora43-ai.container"
        for (i = 1; i <= device_count; i++) print "AddDevice=" devices[i] >> "fedora43-ai.container"
        for (i = 1; i <= group_count; i++) print "PodmanArgs=--group-add=" groups[i] >> "fedora43-ai.container"
        print "" >> "fedora43-ai.container"
        print "[Service]" >> "fedora43-ai.container"
        print "Restart=always" >> "fedora43-ai.container"
        print "TimeoutStartSec=60" >> "fedora43-ai.container"
        print "" >> "fedora43-ai.container"
        print "[Install]" >> "fedora43-ai.container"
        print "WantedBy=default.target" >> "fedora43-ai.container"
    }
    ' "$input"
}

# Generate compose.yml and the Quadlet from merge.conf.
echo "  Generating compose.yml..."
echo "  Generating fedora43-ai.container..."
render_compose_from_conf

echo "  Generating systemd runtime env header..."
"$SHARED_IMAGE_DIR/systemd_pass_environment.sh" \
    "$SCRIPT_DIR/services/runtime-pass-environment.local.conf" \
    "$SCRIPT_DIR/.env" \
    "$SCRIPT_DIR/config.conf"

$CONFIG_ONLY && echo "" && echo "  Config done." && exit 0
$NO_BUILD && echo "" && echo "  Staging done." && exit 0

# Build or pull the image.
DOCKER_IO_IMAGE="docker.io/safrano9999/fedora43-ai:latest"
LOCAL_IMAGE="localhost/fedora43-ai:latest"

if $BUILD_ONLY && [ -z "$IMG_CHOICE" ]; then
    echo ""
    echo "  Image source:"
    echo "    (1) Pull from docker.io  [$DOCKER_IO_IMAGE]"
    echo "    (2) Build locally"
    echo ""
    read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
    IMG_CHOICE="${IMG_CHOICE:-2}"
elif [ -z "$IMG_CHOICE" ]; then
    IMG_CHOICE=2
fi

case "$IMG_CHOICE" in
    1)
        echo ""
        echo "  Pulling $DOCKER_IO_IMAGE ..."
        podman pull "$DOCKER_IO_IMAGE"
        sed -i '/^\s*build:/,/^\s*dockerfile:/d' "$SCRIPT_DIR/compose.yml"
        sed -i "s|image: .*|image: $DOCKER_IO_IMAGE|" "$SCRIPT_DIR/compose.yml"
        sed -i "s|^Image=.*|Image=$DOCKER_IO_IMAGE|" "$SCRIPT_DIR/fedora43-ai.container"
        echo "  Done. Image ready: $DOCKER_IO_IMAGE"
        ;;
    2)
        echo ""
        if $NO_CACHE; then
            echo "  Building $LOCAL_IMAGE with --no-cache ..."
            podman build --pull=always --no-cache -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
        else
            echo "  Building $LOCAL_IMAGE ..."
            HOST_SRV_DIR="/srv/$INSTANCE"
            export INSTANCE HOST_SRV_DIR
            podman-compose \
                -f "$SCRIPT_DIR/compose.yml" \
                build
        fi
        echo "  Done. Image ready: $LOCAL_IMAGE"
        ;;
    *)
        echo "Invalid image choice: $IMG_CHOICE" >&2
        exit 2
        ;;
esac
