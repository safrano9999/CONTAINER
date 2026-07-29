#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

stage=""
root=""
manifest=""
image_root=""
crontab_file=""

usage() {
    echo "Usage: apply-contributions.sh --stage DIR --root DIR --image-root DIR --manifest FILE [--crontab-file FILE]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --stage) stage="${2:-}"; shift 2 ;;
        --root) root="${2:-}"; shift 2 ;;
        --image-root) image_root="${2:-}"; shift 2 ;;
        --manifest) manifest="${2:-}"; shift 2 ;;
        --crontab-file) crontab_file="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

[ -d "$stage" ] && [ -n "$root" ] && [ -n "$image_root" ] &&
    [ -d "$image_root" ] && [ -f "$manifest" ] || {
    usage
    exit 2
}
[[ "$stage" == /* && "$root" == /* && "$image_root" == /* ]] || {
    echo "Contribution stage, repository root, and image root must be absolute paths" >&2
    exit 2
}

repo_name() {
    printf '%s\n' "${1%@*}"
}

copy_repo() {
    local spec="$1" repo source target
    repo="$(repo_name "$spec")"
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
        echo "Invalid contribution repository: $repo" >&2
        return 2
    }
    source="$stage/$repo"
    target="$root/$repo"
    [ -d "$source" ] || {
        echo "Missing staged contribution: $source" >&2
        return 1
    }
    rm -rf -- "$target"
    mkdir -p -- "$root"
    cp -a -- "$source" "$target"
    rm -rf -- "$target/.git"
}

safe_contribution_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9@._-]*$ ]]
}

validate_container_contribution() {
    local directory="$1" invalid

    invalid="$(
        find "$directory" -mindepth 1 \
            \( -type l -o \( ! -type d ! -type f \) \) \
            -print -quit
    )"
    [ -z "$invalid" ] || {
        echo "Unsafe Fedora container contribution entry: $invalid" >&2
        return 1
    }
}

install_contribution_rootfs() {
    local directory="$1/rootfs"

    [ -d "$directory" ] || return 0
    cp -a -- "$directory/." "$image_root/"
}

install_contribution_systemd() {
    local repository="$1"
    local directory="$2/systemd"
    local destination="$image_root/etc/systemd/system"
    local source unit target

    [ -d "$directory" ] || return 0
    mkdir -p -- "$destination"
    while IFS= read -r -d '' source; do
        unit="${source##*/}"
        safe_contribution_name "$unit" &&
            [[ "$unit" =~ \.(service|timer|socket|path|target)$ ]] || {
                echo "Invalid systemd contribution name for $repository: $unit" >&2
                return 2
            }
        install -m 0644 "$source" "$destination/$unit"
        while IFS= read -r target; do
            [ -n "$target" ] || continue
            safe_contribution_name "$target" &&
                [[ "$target" =~ \.(target|service)$ ]] || {
                    echo "Invalid WantedBy target in $repository/$unit: $target" >&2
                    return 2
                }
            mkdir -p -- "$destination/$target.wants"
            ln -sfn "../$unit" "$destination/$target.wants/$unit"
        done < <(
            awk '
                /^\[Install\][[:space:]]*$/ { in_install = 1; next }
                /^\[/ { in_install = 0 }
                in_install && /^WantedBy=/ {
                    sub(/^WantedBy=/, "")
                    gsub(/[[:space:]]+/, "\n")
                    print
                }
            ' "$source"
        )
    done < <(
        find "$directory" -mindepth 1 -maxdepth 1 -type f -print0 |
            sort -z
    )
}

install_contribution_runtime_hooks() {
    local repository="$1"
    local directory="$2/runtime.d"
    local destination="$image_root/usr/local/share/fedora44-ai/init.d"
    local source name

    [ -d "$directory" ] || return 0
    mkdir -p -- "$destination"
    while IFS= read -r -d '' source; do
        name="${source##*/}"
        safe_contribution_name "$name" &&
            [[ "$name" =~ \.(sh|py)$ ]] || {
                echo "Invalid runtime contribution for $repository: $name" >&2
                return 2
            }
        [ -x "$source" ] || {
            echo "Runtime contribution is not executable: $repository/$name" >&2
            return 1
        }
        install -m 0755 "$source" "$destination/$repository-$name"
    done < <(
        find "$directory" -mindepth 1 -maxdepth 1 -type f -print0 |
            sort -z
    )
}

run_contribution_build_hooks() {
    local repository="$1"
    local repository_dir="$2"
    local directory="$repository_dir/fedora44-ai-container/build.d"
    local source name

    [ -d "$directory" ] || return 0
    while IFS= read -r -d '' source; do
        name="${source##*/}"
        safe_contribution_name "$name" &&
            [[ "$name" =~ \.(sh|py)$ ]] || {
                echo "Invalid build contribution for $repository: $name" >&2
                return 2
            }
        [ -x "$source" ] || {
            echo "Build contribution is not executable: $repository/$name" >&2
            return 1
        }
        (
            cd "$repository_dir"
            export FEDORA44_AI_REPOSITORY_DIR="$repository_dir"
            export FEDORA44_AI_IMAGE_ROOT="$image_root"
            case "$name" in
                *.sh) /bin/bash "$source" ;;
                *.py) /usr/bin/python3 "$source" ;;
            esac
        )
    done < <(
        find "$directory" -mindepth 1 -maxdepth 1 -type f -print0 |
            sort -z
    )
}

apply_repo_container_contribution() {
    local repository="$1"
    local repository_dir="$root/$repository"
    local directory="$repository_dir/fedora44-ai-container"

    [ -d "$directory" ] || return 0
    validate_container_contribution "$directory"
    install_contribution_rootfs "$directory"
    install_contribution_systemd "$repository" "$directory"
    install_contribution_runtime_hooks "$repository" "$directory"
    run_contribution_build_hooks "$repository" "$repository_dir"
    printf 'Applied Fedora container contribution: %s\n' "$repository"
}

readme_curl() {
    local readme="$1/README.md"
    [ -f "$readme" ] || return 1
    awk '
        tolower($0) ~ /enter this to trigger webhook from inside container/ {
            wanted = 1
            next
        }
        wanted && /^[[:space:]]*curl[[:space:]]/ {
            sub(/^[[:space:]]*/, "")
            print
            exit
        }
    ' "$readme"
}

webhook_curl() {
    local repo_dir="$1" command path=""
    local manifest_path="$repo_dir/openclaw.plugin.json"
    local index_path="$repo_dir/index.js"

    command="$(readme_curl "$repo_dir" || true)"
    [ -z "$command" ] || {
        printf '%s\n' "$command"
        return
    }
    if [ -f "$manifest_path" ]; then
        path="$(python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
properties = payload.get("configSchema", {}).get("properties", {})
print(properties.get("webhook", {}).get("properties", {}).get("path", {}).get("default", ""))
PY
)"
    fi
    if [ -z "$path" ] && [ -f "$index_path" ]; then
        path="$(python3 - "$index_path" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    source = handle.read()
match = re.search(
    r"registerHttpRoute\s*\(\s*\{.*?path:\s*[\"']([^\"']+)[\"']",
    source,
    re.S,
)
if match is None:
    route = re.search(
        r"registerHttpRoute\s*\(\s*\{.*?\bpath\s*:\s*"
        r"([A-Za-z_$][A-Za-z0-9_$]*)\s*[,}]",
        source,
        re.S,
    )
    if route is not None:
        identifier = re.escape(route.group(1))
        match = re.search(
            rf"\b(?:const|let|var)\s+{identifier}\s*=\s*"
            r"[\"']([^\"']+)[\"']",
            source,
        )
path = match.group(1) if match else ""
print(path if path.startswith("/") else "")
PY
)"
    fi
    [ -z "$path" ] || printf \
        'curl -sS -X POST -H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}" "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}%s"\n' \
        "$path"
}

append_commands() {
    local output="$1"
    shift
    local repo command

    if [ ! -f "$output" ]; then
        mkdir -p "$(dirname "$output")"
        printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' > "$output"
    fi
    for repo in "$@"; do
        command="$(webhook_curl "$root/$repo" || true)"
        [ -n "$command" ] || {
            [ "$output" != "${SAFRANO9999_FULLRUN_SCRIPT:-/usr/local/bin/safrano9999-fullrun}" ] ||
                {
                    echo "Missing webhook curl: $repo" >&2
                    return 1
                }
            continue
        }
        grep -Fqx -- "$command" "$output" || printf '%s\n' "$command" >> "$output"
    done
    chmod 0755 "$output"
}

write_webhook_runner() {
    local runner="$root/WEBHOOK-RUNNER"
    mkdir -p "$runner"
    printf '%s\n' \
        '{"name":"safrano9999-webhooks","version":"0.1.0","private":true,"type":"module","dependencies":{},"openclaw":{"extensions":["./index.js"]}}' \
        > "$runner/package.json"
    printf '%s\n' \
        '{"id":"safrano9999-webhooks","name":"safrano9999 webhooks","description":"Runs deterministic safcontainer webhooks for managed cron events.","activation":{"onStartup":true},"configSchema":{"type":"object","additionalProperties":false}}' \
        > "$runner/openclaw.plugin.json"
    printf '%s\n' \
        'import { execFile } from "node:child_process";' \
        'import { promisify } from "node:util";' \
        'import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";' \
        '' \
        'const execFileAsync = promisify(execFile);' \
        'const cronToken = "__safrano9999_webhooks__";' \
        'const script = process.env.SAFRANO9999_FULLRUN_SCRIPT || process.env.SAFRANO9999_WEBHOOK_SCRIPT || "/usr/local/bin/safrano9999-fullrun";' \
        '' \
        'export default definePluginEntry({' \
        '  id: "safrano9999-webhooks",' \
        '  name: "safrano9999 webhooks",' \
        '  description: "Runs deterministic safcontainer webhooks for managed cron events.",' \
        '  register(api) {' \
        '    api.on("before_agent_reply", async (event) => {' \
        '      if (!event.cleanedBody?.includes(cronToken)) return undefined;' \
        '      await execFileAsync(script);' \
        '      return { handled: true, reason: "safrano9999 webhooks completed" };' \
        '    });' \
        '  },' \
        '});' \
        > "$runner/index.js"
}

declare -A seen=()
declare -a plugins=() webhooks=() fullrun=()
while IFS=$'\t' read -r spec kind add_webhook add_fullrun extra ||
    [ -n "${spec}${kind}${add_webhook}${add_fullrun}${extra}" ]; do
    [[ -z "$spec" || "$spec" == \#* ]] && continue
    [ -z "$extra" ] || {
        echo "Invalid contribution manifest row: $spec" >&2
        exit 2
    }
    repo="$(repo_name "$spec")"
    [ -z "${seen[$repo]+x}" ] || {
        echo "Duplicate contribution repository: $repo" >&2
        exit 2
    }
    seen["$repo"]=1
    case "$kind" in
        standalone) ;;
        plugin) plugins+=("$repo") ;;
        *) echo "Invalid contribution kind for $repo: $kind" >&2; exit 2 ;;
    esac
    case "$add_webhook" in
        yes) webhooks+=("$repo") ;;
        no) ;;
        *) echo "Invalid webhook flag for $repo: $add_webhook" >&2; exit 2 ;;
    esac
    case "$add_fullrun" in
        yes) fullrun+=("$repo") ;;
        no) ;;
        *) echo "Invalid fullrun flag for $repo: $add_fullrun" >&2; exit 2 ;;
    esac
    copy_repo "$spec"
    apply_repo_container_contribution "$repo"
done < "$manifest"

if [ "${#webhooks[@]}" -gt 0 ]; then
    append_commands "${SAFRANO9999_WEBHOOK_SCRIPT:-/usr/local/bin/safrano9999-webhooks}" \
        "${webhooks[@]}"
    write_webhook_runner
fi
if [ "${#fullrun[@]}" -gt 0 ]; then
    append_commands "${SAFRANO9999_FULLRUN_SCRIPT:-/usr/local/bin/safrano9999-fullrun}" \
        "${fullrun[@]}"
fi
if [ -n "$crontab_file" ]; then
    [ -s "$crontab_file" ] || {
        echo "Missing contribution crontab: $crontab_file" >&2
        exit 1
    }
    install -m 0644 "$crontab_file" "$root/.openclaw-crontab"
fi

printf 'Applied %d repository contribution(s)' "${#seen[@]}"
[ "${#plugins[@]}" -eq 0 ] || printf '; %d OpenClaw plugin(s)' "${#plugins[@]}"
printf '\n'
