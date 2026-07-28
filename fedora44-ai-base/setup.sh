#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFRANO_DIR="$SCRIPT_DIR/safrano9999"
SCRIPTS_DIR="$SCRIPT_DIR/SCRIPTS"
SAFRANO_SCRIPTS_DIR="$SCRIPTS_DIR/safrano9999"
IMAGE_SCRIPTS_DIR="$SAFRANO_SCRIPTS_DIR/image"
SQLITE_PERSISTENCE="$SAFRANO_SCRIPTS_DIR/sqlite_persistence.sh"
OPTIONAL_PERSISTENCE="$SAFRANO_SCRIPTS_DIR/optional_persistence.sh"
DEV_SCRIPTS_DIR="${DEV_SCRIPTS_DIR:-$SCRIPT_DIR/../../SCRIPTS}"
OPENCLAW_PATCH_STAGE="$SCRIPT_DIR/openclaw-deterministic-patch"
RESOLVED_BUILD_FILE="$SCRIPT_DIR/.resolved-build.env"
BUILD_RESOLVER="$SCRIPT_DIR/services/resolve-build-inputs.sh"
SOURCE_TAG_MANIFEST="$SCRIPT_DIR/.safrano9999-source-tags.tsv"
BASE_SOURCE_TAG_MANIFEST="$SCRIPT_DIR/.fedora44-ai-base-source-tags.tsv"
VARIANT_FILE="$SCRIPT_DIR/.fedora44-ai-variant"
FEDORA44_AI_VARIANT="${FEDORA44_AI_VARIANT:-$(tr -d '[:space:]' < "$VARIANT_FILE" 2>/dev/null || printf 'build')}"
case "$FEDORA44_AI_VARIANT" in
    build|base|safrano9999) ;;
    *) echo "Invalid fedora44-ai variant: $FEDORA44_AI_VARIANT" >&2; exit 2 ;;
esac

CONFIG_ONLY=false
NO_CONFIG=false
NO_CACHE=false
NO_BUILD=false
IMG_CHOICE=""
INSTANCE=""

show_help() {
    if [ "$FEDORA44_AI_VARIANT" != build ]; then
        cat <<EOF
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --config-only       Stop after staging, merging, config, Compose and Quadlet
  --no-config         Merge and render without running config.sh
  --no-cache          Reclone sources; local builds disable the build cache
  --build-only        Skip config.sh, then ask interactively for pull/build
  --pull              Pull the registry image without asking
  --build             Build the image locally without asking
  --help              Show this help and exit

This repository manages the $FEDORA44_AI_VARIANT runtime variant. A normal run
always asks whether to pull from GHCR or build through the sibling fedora44-ai
build repository. INSTANCE selects or creates one entry below CONTAINER/.
EOF
        return
    fi
    cat <<'EOF'
Usage: ./setup.sh [OPTIONS] [INSTANCE]

Options:
  --build-only        Skip config.sh, then ask interactively for pull/build
  --no-cache          Reclone staged repos; local builds use --pull=always --no-cache
  --config-only       Stop after staging, merging, config, compose and quadlet
  --help              Show this help and exit

INSTANCE defaults to fedora44-ai and is used by compose build metadata.
Without options, setup runs the complete config flow and then asks whether to pull or build.
EOF
}

fix_instance_paths() {
    local file item

    for file in "$COMPOSE_FILE" "$QUADLET_FILE"; do
        [ -f "$file" ] || continue
        for item in "${INSTANCE_FILES[@]}"; do
            sed -i "s#${SCRIPT_DIR}/${item}#${INSTANCE_DIR}/${item}#g" "$file"
        done
    done
}

persist_instance_files() {
    local file

    fix_instance_paths
    for file in "${INSTANCE_FILES[@]}"; do
        [ ! -f "$SCRIPT_DIR/$file" ] || mv -f "$SCRIPT_DIR/$file" "$INSTANCE_DIR/$file"
    done
}

for arg in "$@"; do
    case "$arg" in
        --help)      show_help; exit 0 ;;
        --config|--config-only) CONFIG_ONLY=true ;;
        --build-only) NO_CONFIG=true ;;
        --no-cache)  NO_CACHE=true ;;
        --no-config) NO_CONFIG=true ;;
        --no-build|--stage-only) NO_BUILD=true; NO_CONFIG=true ;;
        --pull)      IMG_CHOICE=1 ;;
        --build)     IMG_CHOICE=2 ;;
        --*)         echo "Unknown argument: $arg" >&2; exit 2 ;;
        *) INSTANCE="$arg" ;;
    esac
done

INSTANCE_ROOT="$SCRIPT_DIR/CONTAINER"
SELECT_ARGS=("$SCRIPT_DIR")
[ -z "${CONFIG_CONTAINER_NAME:-$INSTANCE}" ] || SELECT_ARGS+=(--name "${CONFIG_CONTAINER_NAME:-$INSTANCE}")
RUNTIME_CONTAINER_NAME="$(python3 "$SAFRANO_SCRIPTS_DIR/container_instance.py" "${SELECT_ARGS[@]}")"
export CONFIG_CONTAINER_NAME="$RUNTIME_CONTAINER_NAME"
INSTANCE="$RUNTIME_CONTAINER_NAME"
INSTANCE_DIR="$INSTANCE_ROOT/$RUNTIME_CONTAINER_NAME"
mkdir -p "$INSTANCE_DIR"
ENV_FILE="$SCRIPT_DIR/$RUNTIME_CONTAINER_NAME.env"
CONFIG_FILE="$SCRIPT_DIR/${RUNTIME_CONTAINER_NAME}_config.conf"
CONTAINER_CONFIG_FILE="$SCRIPT_DIR/${RUNTIME_CONTAINER_NAME}_container.conf"
BUILD_FILE="$SCRIPT_DIR/${RUNTIME_CONTAINER_NAME}_build.conf"
COMPOSE_FILE="$SCRIPT_DIR/$RUNTIME_CONTAINER_NAME-compose.yml"
QUADLET_FILE="$SCRIPT_DIR/$RUNTIME_CONTAINER_NAME.container"
INSTANCE_FILES=("$RUNTIME_CONTAINER_NAME.env" "${RUNTIME_CONTAINER_NAME}_config.conf" "${RUNTIME_CONTAINER_NAME}_container.conf" "${RUNTIME_CONTAINER_NAME}_build.conf" "$RUNTIME_CONTAINER_NAME-compose.yml" "$RUNTIME_CONTAINER_NAME.container")
for file in "${INSTANCE_FILES[@]}"; do [ ! -f "$INSTANCE_DIR/$file" ] || cp -f "$INSTANCE_DIR/$file" "$SCRIPT_DIR/$file"; done
trap persist_instance_files EXIT

$NO_CACHE && rm -rf "$SAFRANO_DIR"

github_repo_url() {
    local repo="$1"

    printf 'https://github.com/safrano9999/%s' "$repo"
}

ensure_ghcr_login() {
    local username

    podman login --get-login ghcr.io >/dev/null 2>&1 && return 0
    command -v gh >/dev/null || { echo "gh is required to authenticate to private GHCR images" >&2; return 1; }
    username="$(gh api user --jq .login)"
    gh auth token | podman login ghcr.io --username "$username" --password-stdin
}

build_runtime_image() {
    local build_repo="${FEDORA44_AI_BUILD_REPO:-$SCRIPT_DIR/../fedora44-ai}"
    local -a arguments=("$FEDORA44_AI_VARIANT")

    [ -x "$build_repo/build-local.sh" ] || {
        echo "Missing Fedora build helper: $build_repo/build-local.sh" >&2
        echo "Set FEDORA44_AI_BUILD_REPO to the fedora44-ai build checkout." >&2
        return 1
    }
    $NO_CACHE && arguments+=(--no-cache)
    "$build_repo/build-local.sh" "${arguments[@]}"
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
            git -C "$SAFRANO_DIR/$repo" checkout --quiet -B "$branch" FETCH_HEAD
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
BASE_REPOS=(
    WELCOME
    CODEANALYST
    CITADEL
    DIESDAS-
    NEXTCLOUD
    NOTE
)

SAFRANO_REPOS=(
    JUGO
    VikAI
    PV_D-A-CH
    KIWIX_BRIDGE
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual
    DAILYNEWS
    ZEROINBOX
    SPANKER
    KACHELMANN
)

case "$FEDORA44_AI_VARIANT" in
    base) REPOS=("${BASE_REPOS[@]}") ;;
    *) REPOS=("${BASE_REPOS[@]}" "${SAFRANO_REPOS[@]}") ;;
esac

write_source_tag_manifest() {
    local output="$1"
    shift
    local temporary="${output}.tmp"
    local spec repo path refs version version_commit staged_commit

    printf 'repository\tversion_tag\tversion_commit\tstaged_commit\n' > "$temporary"
    for spec in "$@"; do
        repo="${spec%@*}"
        path="$SAFRANO_DIR/$repo"
        refs="$(git -C "$path" ls-remote --tags --refs origin 'refs/tags/20*.*.*')"
        version="$(awk '
            $2 ~ /^refs\/tags\/20[0-9][0-9][.][0-9]+[.][0-9]+$/ {
                sub(/^refs\/tags\//, "", $2)
                print $2
            }
        ' <<< "$refs" | sort -V | tail -n 1)"
        version_commit="$(awk -v ref="refs/tags/$version" '$2 == ref {print $1; exit}' <<< "$refs")"
        staged_commit="$(git -C "$path" rev-parse HEAD)"
        printf '%s\t%s\t%s\t%s\n' \
            "$repo" "${version:-untagged}" "${version_commit:--}" "$staged_commit" >> "$temporary"
    done

    if git -C "$DEV_SCRIPTS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        refs="$(git -C "$DEV_SCRIPTS_DIR" ls-remote --tags --refs origin 'refs/tags/20*.*.*')"
        version="$(awk '
            $2 ~ /^refs\/tags\/20[0-9][0-9][.][0-9]+[.][0-9]+$/ {
                sub(/^refs\/tags\//, "", $2)
                print $2
            }
        ' <<< "$refs" | sort -V | tail -n 1)"
        version_commit="$(awk -v ref="refs/tags/$version" '$2 == ref {print $1; exit}' <<< "$refs")"
        staged_commit="$(git -C "$DEV_SCRIPTS_DIR" rev-parse HEAD)"
        printf 'SCRIPTS\t%s\t%s\t%s\n' \
            "${version:-untagged}" "${version_commit:--}" "$staged_commit" >> "$temporary"
    fi
    mv -f "$temporary" "$output"
    echo "  Written source tag manifest: $(basename "$output")"
}

relink_dev_scripts() {
    local source target path tree

    [ -d "$DEV_SCRIPTS_DIR/.git" ] || return 0
    for tree in safrano9999 safrano9999-lib; do
        [ -d "$DEV_SCRIPTS_DIR/$tree" ] || {
            echo "Missing shared SCRIPTS tree: $tree" >&2
            exit 1
        }
        while IFS= read -r -d '' source; do
            path="${source#"$DEV_SCRIPTS_DIR"/}"
            target="$SCRIPTS_DIR/$path"
            mkdir -p "$(dirname "$target")"
            [ -e "$target" ] && [ "$source" -ef "$target" ] || ln -f "$source" "$target"
        done < <(
            find "$DEV_SCRIPTS_DIR/$tree" -type f \
                ! -path '*/__pycache__/*' \
                ! -name '*.pyc' \
                -print0
        )
    done
    ln -f "$SAFRANO_SCRIPTS_DIR/merge.sh" "$SCRIPT_DIR/merge.sh"
    ln -f "$SAFRANO_SCRIPTS_DIR/quadlet_finish.py" "$SCRIPT_DIR/quadlet_finish.py"
}

relink_dev_scripts
mkdir -p "$SAFRANO_DIR"
rm -rf "$SAFRANO_DIR/CALENDAR"
for repo in "${REPOS[@]}"; do sync_repo "$repo"; done
write_source_tag_manifest "$BASE_SOURCE_TAG_MANIFEST" "${BASE_REPOS[@]}"
[ "$FEDORA44_AI_VARIANT" = base ] || \
    write_source_tag_manifest "$SOURCE_TAG_MANIFEST" "${SAFRANO_REPOS[@]}"
"$IMAGE_SCRIPTS_DIR/relink_shared.sh" \
    config.sh python_header.py openai_v1.py \
    openclaw-config.service openclaw.service openclaw_common.py \
    safrano9999_plugins.py tailscale-up.service tailscaled.service \
    hermes.service hermes-dashboard.service \
    safrano9999-welcome.service readme_welcome.py welcome_ref.py \
    cockpit.service \
    cloudflared.service env.cloudflare.example config.cloudflare.conf_example config.cloudflare.container \
    sqlite_persistence.sh optional_persistence.sh \
    named_volume_links.sh named_volume_links_hermes.sh named_volume_links_openclaw.sh \
    10-tailscale-ssh.conf 10-fedora-openai-v1.conf 20-safrano9999.conf

# Merge and deduplicate every example class and requirements.
echo "  Merging examples + requirements.txt..."
case "$FEDORA44_AI_VARIANT" in
    build)
        bash "$SCRIPT_DIR/merge.sh" "${BASE_REPOS[@]}"
        cp -f "$SCRIPT_DIR/requirements.txt" "$SCRIPT_DIR/requirements.base.txt"
        bash "$SCRIPT_DIR/merge.sh" "${SAFRANO_REPOS[@]}"
        cp -f "$SCRIPT_DIR/requirements.txt" "$SCRIPT_DIR/requirements.safrano9999.txt"
        bash "$SCRIPT_DIR/merge.sh" "${REPOS[@]}"
        ;;
    base) bash "$SCRIPT_DIR/merge.sh" "${BASE_REPOS[@]}" ;;
    safrano9999) bash "$SCRIPT_DIR/merge.sh" "${REPOS[@]}" ;;
esac
python3 "$SAFRANO_SCRIPTS_DIR/image/readme/welcome_ref.py" "$SCRIPT_DIR" "$SCRIPT_DIR/ref.conf"

if ! $NO_CONFIG; then
    echo ""
    (cd "$SCRIPT_DIR" && bash "$SAFRANO_SCRIPTS_DIR/config.sh")
    rm -f "$QUADLET_FILE" "$COMPOSE_FILE"
    (cd "$SCRIPT_DIR" && bash "$SAFRANO_SCRIPTS_DIR/legacy.sh" "$SCRIPT_DIR")
fi

configured_container_name() {
    printf '%s\n' "$RUNTIME_CONTAINER_NAME"
}

build_setting() {
    local key="$1"
    local fallback="$2"
    local file value=""

    for file in "$BUILD_FILE" "$SCRIPT_DIR/fedora.build.conf_example"; do
        [ -f "$file" ] || continue
        value="$(awk -F= -v key="$key" '
            $1 == key {
                value = substr($0, index($0, "=") + 1)
                sub(/^[[:space:]]+/, "", value)
                sub(/[[:space:]]+$/, "", value)
                print value
                exit
            }
        ' "$file")"
        [ -n "$value" ] && break
    done
    printf '%s\n' "${value:-$fallback}"
}

stage_build_certificates() {
    local source="$BUILD_CERTS"
    local stage cert fingerprint
    local count=0

    [[ "$source" == /* ]] || {
        echo "CERTS must be an absolute path: $source" >&2
        return 1
    }
    stage="$SCRIPT_DIR/${source#/}"
    rm -rf "$stage"
    mkdir -p "$stage"

    if [ ! -d "$source" ]; then
        echo "  ! CERTS path not found; building without custom certificates: $source"
        return 0
    fi
    command -v openssl >/dev/null 2>&1 || {
        echo "openssl is required to stage CERTS" >&2
        return 1
    }

    while IFS= read -r -d '' cert; do
        openssl x509 -in "$cert" -noout >/dev/null 2>&1 || continue
        fingerprint="$(openssl x509 -in "$cert" -noout -fingerprint -sha256 \
            | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
        install -m 0644 "$cert" "$stage/fedora44-ai-${fingerprint}.crt"
        count=$((count + 1))
    done < <(find "$source" -type f \( -name '*.crt' -o -name '*.pem' \) -print0)
    echo "  Staged $count custom certificate(s) from $source"
}

stage_openclaw_deterministic_patch() {
    local releases archive_url checksum_url archive checksum token temporary version digest
    local -a auth=()

    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [ -z "$token" ] && command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
        token="$(gh auth token)"
    fi
    [ -n "$token" ] && auth=(-H "Authorization: Bearer $token" -H "X-GitHub-Api-Version: 2022-11-28")

    mkdir -p "$OPENCLAW_PATCH_STAGE"
    temporary="$(mktemp -d)"
    releases="$(curl -fsSL --retry 3 "${auth[@]}" 'https://api.github.com/repos/safrano9999/openclaw/releases?per_page=100')"
    IFS=$'\t' read -r archive_url checksum_url < <(jq -r 'first(.[] | select(.draft == false) | .assets as $assets | ($assets[] | select(.name | test("^openclaw-.*-deterministic-.*\\.tar\\.gz$"))) as $archive | ($assets[] | select(.name == ($archive.name + ".sha256"))) as $checksum | [$archive.browser_download_url, $checksum.browser_download_url] | @tsv)' <<<"$releases")
    [ -n "$archive_url" ] && [ -n "$checksum_url" ] || { echo "OpenClaw deterministic patch release not found" >&2; exit 1; }
    archive="${archive_url##*/}"
    checksum="${checksum_url##*/}"
    curl -fsSL --retry 3 -L "${auth[@]}" "$archive_url" -o "$temporary/$archive"
    curl -fsSL --retry 3 -L "${auth[@]}" "$checksum_url" -o "$temporary/$checksum"
    (cd "$temporary" && sha256sum -c "$checksum")
    version="${archive#openclaw-}"
    version="${version%%-deterministic-*}"
    [[ "$version" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "Invalid OpenClaw patch version: $version" >&2; exit 1; }
    digest="$(awk 'NR == 1 {print $1}' "$temporary/$checksum")"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid OpenClaw patch checksum" >&2; exit 1; }
    find "$OPENCLAW_PATCH_STAGE" -mindepth 1 -depth -delete
    install -m 0644 "$temporary/$archive" "$OPENCLAW_PATCH_STAGE/patch.tar.gz"
    printf '%s  patch.tar.gz\n' "$digest" > "$OPENCLAW_PATCH_STAGE/patch.tar.gz.sha256"
    printf '%s\n' "$version" > "$OPENCLAW_PATCH_STAGE/openclaw.version"
    printf '%s\n' "$archive" > "$OPENCLAW_PATCH_STAGE/source.name"
    find "$temporary" -mindepth 1 -depth -delete
    rmdir "$temporary"
    echo "  Staged OpenClaw deterministic patch: $archive"
}

render_compose_from_conf() {
    local image="$1"
    local include_build="$2"
    local runtime_name
    local sqlite_volumes
    local persistent_volumes persistent_entries
    local has_container_conf=false
    local inputs=()
    runtime_name="$(configured_container_name)"
    sqlite_volumes="$("$SQLITE_PERSISTENCE" mounts \
        --repo-root "$SAFRANO_DIR" \
        --config-dir "$SCRIPT_DIR" \
        --container "$runtime_name" | paste -sd, -)"
    persistent_volumes="$("$OPTIONAL_PERSISTENCE" mounts \
        --config-dir "$SCRIPT_DIR" \
        --container "$runtime_name" | paste -sd, -)"
    persistent_entries="$("$OPTIONAL_PERSISTENCE" entries \
        --config-dir "$SCRIPT_DIR" | awk -F '\t' '{print $1 "=" $2}' | paste -sd, -)"
    [ -f "$SCRIPT_DIR/config.conf_example" ] && inputs+=("$SCRIPT_DIR/config.conf_example")
    [ -f "$SCRIPT_DIR/container.example" ] && inputs+=("$SCRIPT_DIR/container.example")
    [ -f "$CONFIG_FILE" ] && inputs+=("$CONFIG_FILE")
    if [ -f "$CONTAINER_CONFIG_FILE" ]; then
        inputs+=("$CONTAINER_CONFIG_FILE")
        has_container_conf=true
    fi
    [ "${#inputs[@]}" -gt 0 ] || { echo "No config/container example or conf files" >&2; exit 1; }

    (
    cd "$SCRIPT_DIR"
    awk -v cwd="$SCRIPT_DIR" -v home="$HOME" -v image="$image" -v include_build="$include_build" -v has_container_conf="$has_container_conf" -v configured_name="$runtime_name" -v runtime_env="$ENV_FILE" -v runtime_config="$CONFIG_FILE" -v runtime_container="$CONTAINER_CONFIG_FILE" -v sqlite_volumes="$sqlite_volumes" -v persistent_volumes="$persistent_volumes" -v persistent_entries="$persistent_entries" -v extra_port_range="$BUILD_PORT_RANGE" \
        -v build_certs="$BUILD_CERTS" -v resolved_build_file="$RESOLVED_BUILD_FILE" \
        -v electrum_version="$BUILD_ELECTRUM_VERSION" \
        -v lnd_version="$BUILD_LND_VERSION" -v geth_version="$BUILD_GETH_VERSION" \
        -v geth_commit="$BUILD_GETH_COMMIT" -v webhook_version="$BUILD_WEBHOOK_VERSION" '
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
    function expand_container_name(s, name,    token, pos) {
        token = "${CONTAINER_NAME}"
        while ((pos = index(s, token)) > 0) {
            s = substr(s, 1, pos - 1) name substr(s, pos + length(token))
        }
        return s
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
    function add_identity_port(host, port) {
        if (!(host in identity_host_seen)) identity_hosts[++identity_host_count] = host
        identity_ports[host SUBSEP port] = 1
    }
    function emit_identity_range(host, first, last) {
        if (first == last) add_port(host ":" first ":" first)
        else add_port(host ":" first "-" last ":" first "-" last)
    }
    function flush_identity_ports(    h, host, port, first, last) {
        for (h = 1; h <= identity_host_count; h++) {
            host = identity_hosts[h]
            first = last = 0
            for (port = 1; port <= 65535; port++) {
                if (!((host SUBSEP port) in identity_ports)) continue
                if (first == 0) {
                    first = last = port
                } else if (port == last + 1) {
                    last = port
                } else {
                    emit_identity_range(host, first, last)
                    first = last = port
                }
            }
            if (first != 0) emit_identity_range(host, first, last)
        }
    }
    function project_port(port, nr) {
        return nr * 10000 + (port % 10000)
    }
    function add_disabled_port(value) {
        if (value == "" || value in disabled_port_seen) return
        disabled_port_seen[value] = 1
        disabled_ports[++disabled_port_count] = value
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
    function add_disabled_named_volume(name) {
        if (name == "" || name in disabled_named_seen) return
        disabled_named_seen[name] = 1
        disabled_named_volumes[++disabled_named_count] = name
    }
    function add_disabled_volume(value, source) {
        if (value == "" || value in disabled_volume_seen) return
        disabled_volume_seen[value] = 1
        disabled_volumes[++disabled_volume_count] = value
        if (source !~ /^[/.$~]/ && source !~ /\//) add_disabled_named_volume(source)
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
    function add_additional_line(value) {
        if (value == "" || tolower(value) == "blank" || tolower(value) == "null" || value in additional_line_seen) return
        additional_line_seen[value] = 1
        additional_lines[++additional_line_count] = value
    }
    function split_csv(value, out,    n, i, part) {
        n = split(value, out, ",")
        for (i = 1; i <= n; i++) out[i] = trim(out[i])
        return n
    }
    function skip_env_key(key) {
        return key ~ /_PUBLISH_HOST$/ || key ~ /_PUBLISH_PORT$/ || \
            key ~ /_CAPABILITIES$/ || key ~ /_DEVICES$/ || \
            key ~ /_VOLUMES$/ || key ~ /_GROUP_ADD$/ || \
            key ~ /^ADDITIONAL_LINE(_[0-9]+)?$/
    }
    /^[[:space:]]*$/ { next }
    {
        line = $0
        sub(/\r$/, "", line)
        disabled = 0
        if (line ~ /^[[:space:]]*#/) {
            disabled = 1
            sub(/^[[:space:]]*#[[:space:]]*/, "", line)
        } else {
            sub(/[[:space:]]+#.*/, "", line)
        }
        sub(/^[[:space:]]*export[[:space:]]+/, "", line)
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*=/) next
        key = line
        sub(/=.*/, "", key)
        value = line
        sub(/^[^=]*=/, "", value)
        value = clean_value(value)
        if (disabled) {
            if (key ~ /_VOLUMES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) {
                    split(items[j], parts, ":")
                    add_disabled_volume(items[j], parts[1])
                }
            }
            next
        }
        if (!(key in values)) order[++value_count] = key
        values[key] = value
        next
    }
    END {
        runtime_name = configured_name
        quadlet_output = runtime_name ".container"
        volume_prefix = runtime_name
        gsub(/[^A-Za-z0-9_.-]/, "-", volume_prefix)

        default_publish_host = values["FASTAPI_HOST"]
        if (default_publish_host == "") default_publish_host = "127.0.0.1"

        tunnel_only = toupper(values["CONTAINER_NR"]) == "TUN"
        container_nr = values["CONTAINER_NR"] ~ /^[2-5]$/ ? values["CONTAINER_NR"] + 0 : 0
        if (!tunnel_only && extra_port_range != "" && tolower(extra_port_range) != "blank") {
            if (extra_port_range !~ /^[0-9]+-[0-9]+$/) {
                print "Invalid FEDORA44_AI_PORT_RANGE: " extra_port_range > "/dev/stderr"
                exit 2
            }
            split(extra_port_range, range_parts, "-")
            range_start = range_parts[1] + 0
            range_end = range_parts[2] + 0
            if (range_start < 1 || range_end > 65535 || range_start > range_end || range_end - range_start > 255) {
                print "Invalid FEDORA44_AI_PORT_RANGE: " extra_port_range > "/dev/stderr"
                exit 2
            }
            published_range = extra_port_range
            if (container_nr != 0) {
                if (range_end >= 20000) {
                    print "FEDORA44_AI_PORT_RANGE must stay below 20000: " extra_port_range > "/dev/stderr"
                    exit 2
                }
                published_range = project_port(range_start, container_nr) "-" project_port(range_end, container_nr)
            }
            add_port(default_publish_host ":" published_range ":" extra_port_range)
        }

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            value = values[key]
            if (!skip_env_key(key)) add_env(key, value)
        }

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            if (key !~ /_PUBLISH_PORT$/) continue
            if (tunnel_only) {
                add_disabled_port(key "=")
                continue
            }
            prefix = key
            sub(/_PUBLISH_PORT$/, "", prefix)
            port = values[prefix "_PORT"]
            if (port == "") port = values[key]
            host = values[prefix "_PUBLISH_HOST"]
            if (host == "") host = default_publish_host
            if (values[key] == "" || port == "") {
                add_disabled_port(key "=")
            } else if (values[key] ~ /^[0-9]+$/ && port ~ /^[0-9]+$/ && values[key] == port) {
                add_identity_port(host, port + 0)
            } else {
                add_port(host ":" values[key] ":" port)
            }
            add_env(prefix "_PUBLISH_HOST", host)
            add_env(prefix "_PUBLISH_PORT", values[key])
        }
        flush_identity_ports()

        for (i = 1; i <= value_count; i++) {
            key = order[i]
            value = values[key]
            if (key ~ /^ADDITIONAL_LINE(_[0-9]+)?$/) {
                add_additional_line(value)
            } else if (key ~ /_CAPABILITIES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) add_cap(items[j])
            } else if (key ~ /_DEVICES$/) {
                n = split_csv(value, items)
                for (j = 1; j <= n; j++) add_device(items[j])
            } else if (key ~ /_VOLUMES$/) {
                value = expand_container_name(value, volume_prefix)
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

        n = split_csv(sqlite_volumes, items)
        for (i = 1; i <= n; i++) {
            split(items[i], parts, ":")
            add_volume(items[i], parts[1])
        }
        n = split_csv(persistent_volumes, items)
        for (i = 1; i <= n; i++) {
            split(items[i], parts, ":")
            add_volume(items[i], parts[1])
        }

        print "services:" > "compose.yml"
        print "  " runtime_name ":" >> "compose.yml"
        if (include_build == "true") {
            print "    build:" >> "compose.yml"
            print "      context: " yaml_dq(cwd) >> "compose.yml"
            print "      dockerfile: Containerfile" >> "compose.yml"
            print "      args:" >> "compose.yml"
            print "        CERTS: " yaml_dq(build_certs) >> "compose.yml"
            print "        ELECTRUM_VERSION: " yaml_dq(electrum_version) >> "compose.yml"
            print "        LND_VERSION: " yaml_dq(lnd_version) >> "compose.yml"
            print "        GETH_VERSION: " yaml_dq(geth_version) >> "compose.yml"
            print "        GETH_COMMIT: " yaml_dq(geth_commit) >> "compose.yml"
            print "        WEBHOOK_VERSION: " yaml_dq(webhook_version) >> "compose.yml"
            while ((getline resolved_line < resolved_build_file) > 0) {
                equals = index(resolved_line, "=")
                if (equals < 2) continue
                resolved_key = substr(resolved_line, 1, equals - 1)
                resolved_value = substr(resolved_line, equals + 1)
                print "        " resolved_key ": " yaml_dq(resolved_value) >> "compose.yml"
            }
            close(resolved_build_file)
        }
        print "    image: " image >> "compose.yml"
        print "    labels:" >> "compose.yml"
        print "      - " yaml_dq("io.containers.autoupdate=registry") >> "compose.yml"
        print "    container_name: " yaml_dq(runtime_name) >> "compose.yml"
        print "    command: [\"/sbin/init\"]" >> "compose.yml"
        print "    ports:" >> "compose.yml"
        for (i = 1; i <= disabled_port_count; i++) print "      # " disabled_ports[i] >> "compose.yml"
        for (i = 1; i <= port_count; i++) print "      - " yaml_dq(ports[i]) >> "compose.yml"
        print "    env_file:" >> "compose.yml"
        print "      - " runtime_config >> "compose.yml"
        if (has_container_conf == "true") print "      - " runtime_container >> "compose.yml"
        print "      - " runtime_env >> "compose.yml"
        n = split_csv(persistent_entries, items)
        if (n > 0 && items[1] != "") {
            print "    environment:" >> "compose.yml"
            for (i = 1; i <= n; i++) print "      - " yaml_dq(items[i]) >> "compose.yml"
        }
        print "    volumes:" >> "compose.yml"
        print "      - " yaml_dq("${HOST_HOME_DIR:-home}:/home") >> "compose.yml"
        print "      - " yaml_dq("${HOST_ROOT_DIR:-root}:/root") >> "compose.yml"
        print "      - " yaml_dq("/tmp/.X11-unix:/tmp/.X11-unix") >> "compose.yml"
        for (i = 1; i <= disabled_volume_count; i++) print "      # - " yaml_dq(disabled_volumes[i]) >> "compose.yml"
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
        for (i = 1; i <= disabled_named_count; i++) print "  # " disabled_named_volumes[i] ": {}" >> "compose.yml"
        for (i = 1; i <= named_count; i++) print "  " named_volumes[i] ": {}" >> "compose.yml"

        print "[Container]" > quadlet_output
        print "ContainerName=" runtime_name >> quadlet_output
        print "Image=" image >> quadlet_output
        print "Exec=/sbin/init" >> quadlet_output
        print "AutoUpdate=registry" >> quadlet_output
        print "EnvironmentFile=" runtime_config >> quadlet_output
        if (has_container_conf == "true") print "EnvironmentFile=" runtime_container >> quadlet_output
        print "EnvironmentFile=" runtime_env >> quadlet_output
        n = split_csv(persistent_entries, items)
        for (i = 1; i <= n; i++) if (items[i] != "") print "Environment=" systemd_dq(items[i]) >> quadlet_output
        for (i = 1; i <= disabled_port_count; i++) print "# " disabled_ports[i] >> quadlet_output
        for (i = 1; i <= port_count; i++) print "PublishPort=" ports[i] >> quadlet_output
        for (i = 1; i <= disabled_volume_count; i++) print "# Volume=" disabled_volumes[i] >> quadlet_output
        for (i = 1; i <= volume_count; i++) print "Volume=" volumes[i] >> quadlet_output
        for (i = 1; i <= cap_count; i++) print "AddCapability=" caps[i] >> quadlet_output
        for (i = 1; i <= device_count; i++) print "AddDevice=" devices[i] >> quadlet_output
        for (i = 1; i <= group_count; i++) print "PodmanArgs=--group-add=" groups[i] >> quadlet_output
        for (i = 1; i <= additional_line_count; i++) print additional_lines[i] >> quadlet_output
        print "" >> quadlet_output
        print "[Service]" >> quadlet_output
        print "Restart=always" >> quadlet_output
        print "TimeoutStartSec=60" >> quadlet_output
        print "" >> quadlet_output
        print "[Install]" >> quadlet_output
        print "WantedBy=default.target" >> quadlet_output
    }
    ' "${inputs[@]}"
    [ compose.yml -ef "$COMPOSE_FILE" ] || mv -f compose.yml "$COMPOSE_FILE"
    [ "$runtime_name.container" -ef "$QUADLET_FILE" ] || mv -f "$runtime_name.container" "$QUADLET_FILE"
    )
}

BUILD_ARGS=(
)
BUILD_CERTS=""
BUILD_ELECTRUM_VERSION=""
BUILD_LND_VERSION=""
BUILD_GETH_VERSION=""
BUILD_GETH_COMMIT=""
BUILD_WEBHOOK_VERSION=""
BUILD_PORT_RANGE=""
if [ "$FEDORA44_AI_VARIANT" = build ]; then
    BUILD_CERTS="$(build_setting CERTS /srv/shared/certs)"
    BUILD_NODE_REQUESTED="$(build_setting NODE_VERSION stable)"
    BUILD_ELECTRUM_VERSION="$(build_setting ELECTRUM_VERSION 4.7.2)"
    BUILD_LND_VERSION="$(build_setting LND_VERSION v0.20.1-beta)"
    BUILD_GETH_VERSION="$(build_setting GETH_VERSION 1.17.2)"
    BUILD_GETH_COMMIT="$(build_setting GETH_COMMIT be4dc0c4)"
    BUILD_WEBHOOK_VERSION="$(build_setting WEBHOOK_VERSION 2.8.3)"
    BUILD_PORT_RANGE="$(build_setting FEDORA44_AI_PORT_RANGE "")"
    stage_build_certificates
    stage_openclaw_deterministic_patch
    "$BUILD_RESOLVER" "$RESOLVED_BUILD_FILE" "$BUILD_NODE_REQUESTED" \
        "$OPENCLAW_PATCH_STAGE" "$SOURCE_TAG_MANIFEST" "$BASE_SOURCE_TAG_MANIFEST"
    BUILD_ARGS=(
        --build-arg "CERTS=$BUILD_CERTS"
        --build-arg "ELECTRUM_VERSION=$BUILD_ELECTRUM_VERSION"
        --build-arg "LND_VERSION=$BUILD_LND_VERSION"
        --build-arg "GETH_VERSION=$BUILD_GETH_VERSION"
        --build-arg "GETH_COMMIT=$BUILD_GETH_COMMIT"
        --build-arg "WEBHOOK_VERSION=$BUILD_WEBHOOK_VERSION"
    )
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "Invalid resolved build argument: $key" >&2; exit 1; }
        BUILD_ARGS+=(--build-arg "$key=$value")
    done < "$RESOLVED_BUILD_FILE"
fi

case "$FEDORA44_AI_VARIANT" in
    base)
        REGISTRY_IMAGE="ghcr.io/safrano9999/fedora44-ai-base:latest"
        LOCAL_IMAGE="localhost/fedora44-ai-base:latest"
        ;;
    *)
        REGISTRY_IMAGE="ghcr.io/safrano9999/fedora44-ai-safrano9999:latest"
        LOCAL_IMAGE="localhost/fedora44-ai-safrano9999:latest"
        ;;
esac
EXISTING_IMAGE="$(awk -F= '$1 == "Image" { print substr($0, index($0, "=") + 1); exit }' "$QUADLET_FILE" 2>/dev/null || true)"
RENDER_IMAGE="${EXISTING_IMAGE:-$REGISTRY_IMAGE}"
RENDER_BUILD=false
[ "$FEDORA44_AI_VARIANT" != build ] || [ "$RENDER_IMAGE" != "$LOCAL_IMAGE" ] || RENDER_BUILD=true

# Generate the named compose file and Quadlet from merged config.
echo "  Generating $(basename "$COMPOSE_FILE")..."
echo "  Generating $(basename "$QUADLET_FILE")..."
render_compose_from_conf "$RENDER_IMAGE" "$RENDER_BUILD"

$CONFIG_ONLY && fix_instance_paths && echo "" && echo "  Config done." && exit 0
$NO_BUILD && fix_instance_paths && echo "" && echo "  Staging done." && exit 0

# Setup contract: normal interactive runs always ask for the image source.
# Only explicit --pull or --build arguments may preselect this decision.
if [ -z "$IMG_CHOICE" ]; then
    echo ""
    echo "  Image source:"
    echo "    (1) Pull from GHCR  [$REGISTRY_IMAGE]"
    echo "    (2) Build locally"
    echo ""
    read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
    IMG_CHOICE="${IMG_CHOICE:-2}"
fi

case "$IMG_CHOICE" in
    1)
        echo ""
        echo "  Pulling $REGISTRY_IMAGE ..."
        ensure_ghcr_login
        podman pull "$REGISTRY_IMAGE"
        render_compose_from_conf "$REGISTRY_IMAGE" false
        echo "  Done. Image ready: $REGISTRY_IMAGE"
        ;;
    2)
        echo ""
        if [ "$FEDORA44_AI_VARIANT" = build ]; then
            render_compose_from_conf "$LOCAL_IMAGE" true
            if $NO_CACHE; then
                echo "  Building $LOCAL_IMAGE with --no-cache ..."
                podman build --pull=always --no-cache "${BUILD_ARGS[@]}" -t "$LOCAL_IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
            else
                echo "  Building $LOCAL_IMAGE ..."
                HOST_SRV_DIR="/srv/$INSTANCE"
                export INSTANCE HOST_SRV_DIR
                podman-compose \
                    -f "$COMPOSE_FILE" \
                    build --pull-always
            fi
        else
            build_runtime_image
            render_compose_from_conf "$LOCAL_IMAGE" false
        fi
        echo "  Done. Image ready: $LOCAL_IMAGE"
        ;;
    *)
        echo "Invalid image choice: $IMG_CHOICE" >&2
        exit 2
        ;;
esac

fix_instance_paths
python3 "$SCRIPT_DIR/quadlet_finish.py" "$INSTANCE_DIR/$(basename "$COMPOSE_FILE")" "$INSTANCE_DIR/$(basename "$QUADLET_FILE")" "$RUNTIME_CONTAINER_NAME"
