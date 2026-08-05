#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="$ROOT/fedora44-ai-core-pre"
CORE="$ROOT/fedora44-ai-core"
BASE="$ROOT/fedora44-ai-base"
SAFRANO="$ROOT/fedora44-ai-safrano9999"

fail() {
    echo "Fedora chain check failed: $*" >&2
    exit 1
}

for file in \
    "$PRE/Containerfile" \
    "$CORE/Containerfile" \
    "$BASE/Containerfile" \
    "$SAFRANO/Containerfile"; do
    [ -f "$file" ] || fail "missing $file"
done

grep -Fq 'FROM quay.io/fedora/fedora:44 AS ai-core-pre' "$PRE/Containerfile"
grep -Fq 'FROM ${AI_CORE_PRE_IMAGE} AS ai-core' "$CORE/Containerfile"
grep -Fq 'FROM ${AI_CORE_IMAGE} AS ai-base' "$BASE/Containerfile"
grep -Fq 'FROM ${AI_BASE_IMAGE} AS ai-safrano9999' "$SAFRANO/Containerfile"
if rg -n 'core2|AI_CORE2' \
    "$CORE/Containerfile" \
    "$PRE/Containerfile" \
    "$BASE/Containerfile" \
    "$SAFRANO/Containerfile" \
    "$CORE/build.conf" \
    "$PRE/build.conf" \
    "$BASE/build.conf" \
    "$SAFRANO/build.conf"; then
    fail "legacy Core2 reference remains in the final chain"
fi
if rg -n '^COPY[[:space:]]+SCRIPTS([[:space:]]|$)' \
    "$PRE/Containerfile" "$CORE/Containerfile" "$BASE/Containerfile" \
    "$SAFRANO/Containerfile"; then
    fail "a complete SCRIPTS tree is copied into an image"
fi

if rg -n 'OPENCLAW_EPHEMERAL_IMAGE|openclaw-ephemeral-source|COPY --from=.*openclaw-ephemeral' \
    "$CORE/Containerfile" "$CORE/build.conf" "$CORE/build-local.sh"; then
    fail "Ephemeral container-image donor remains in Core"
fi
grep -Fq 'COPY build/vendor/openclaw-deterministic/' "$CORE/Containerfile"
grep -Fq 'COPY build/vendor/openclaw-ephemeral/' "$CORE/Containerfile"
grep -Fq 'COPY build/vendor/note/note-latest.zip' "$CORE/Containerfile"
grep -Fq 'USER root' "$PRE/Containerfile"
grep -Fq 'USER root' "$CORE/Containerfile"
grep -Fq 'USER root' "$BASE/Containerfile"
grep -Fq 'USER root' "$SAFRANO/Containerfile"
grep -Fq 'systemctl mask cockpit.socket' "$CORE/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' "$CORE/image/systemd/openclaw-config.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' "$CORE/image/systemd/hermes.service"
grep -Fq 'mcp_servers_config' "$CORE/image/runtime.d/hermes-ephemeral.py"
grep -Fq 'io.safrano9999.parent="fedora44-ai-core-pre"' "$CORE/Containerfile"
! grep -Fq '/opt/safrano9999' "$PRE/Containerfile" ||
    fail "Core-pre contains a Safrano project tree"

for setup in "$CORE/setup.sh"; do
    for marker in \
        'Image source:' \
        'Build locally' \
        'read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE' \
        'IMG_CHOICE="${IMG_CHOICE:-2}"'; do
        grep -Fq "$marker" "$setup" ||
            fail "missing established image-source marker in $setup: $marker"
    done
done
for layer in "$BASE" "$SAFRANO"; do
    setup="$layer/setup.sh"
    shared_setup="$layer/image/setup.d/layer-setup.sh"
    grep -Fq 'exec bash "$ROOT/image/setup.d/layer-setup.sh" "$@"' "$setup" ||
        fail "layer setup wrapper does not delegate to the shared setup: $setup"
    for marker in \
        'Image source:' \
        'Build locally' \
        'read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE' \
        'IMG_CHOICE="${IMG_CHOICE:-2}"'; do
        grep -Fq "$marker" "$setup" "$shared_setup" ||
            fail "missing established image-source marker in $setup or $shared_setup: $marker"
    done
done
while IFS= read -r setup; do
    grep -Fq 'podman pull --retry 10 --retry-delay 5s' "$setup" ||
        fail "Podman pull lacks the bounded GHCR retry contract: $setup"
done < <(
    rg -l 'podman[[:space:]]+pull' \
        "$CORE" "$BASE" "$SAFRANO" \
        --glob '*.sh' --glob '!SCRIPTS/**' | sort
)

for script in \
    "$PRE/build-local.sh" \
    "$PRE/prepare-build-context.sh" \
    "$PRE/build/resolve-build-inputs.sh" \
    "$CORE/setup.sh" \
    "$CORE/build-local.sh" \
    "$CORE/prepare-build-context.sh" \
    "$CORE/image/runtime.d/fedora44-ai-init.sh" \
    "$CORE/image/runtime.d/fedora44-runtime-environment-generator.sh" \
    "$CORE/image/runtime.d/named_volume_links.sh" \
    "$CORE/image/runtime.d/tailscale-state-up.sh" \
    "$CORE/optional_persistence.sh" \
    "$BASE/setup.sh" \
    "$BASE/build-local.sh" \
    "$BASE/prepare-build-context.sh" \
    "$BASE/optional_persistence.sh" \
    "$BASE/sqlite_persistence.sh" \
    "$BASE/image/build.d/apply-contributions.sh" \
    "$BASE/image/setup.d/layer-setup.sh" \
    "$BASE/image/setup.d/sync-sources.sh" \
    "$SAFRANO/setup.sh" \
    "$SAFRANO/build-local.sh" \
    "$SAFRANO/prepare-build-context.sh" \
    "$SAFRANO/optional_persistence.sh" \
    "$SAFRANO/sqlite_persistence.sh" \
    "$SAFRANO/image/build.d/apply-contributions.sh" \
    "$SAFRANO/image/build.d/stage-release-plugin.sh" \
    "$SAFRANO/image/setup.d/layer-setup.sh" \
    "$SAFRANO/image/setup.d/sync-sources.sh"; do
    bash -n "$script"
done

python3 - "$CORE" "$BASE" "$SAFRANO" <<'PY'
import ast
import pathlib
import sys

for root in map(pathlib.Path, sys.argv[1:]):
    for source in sorted((root / "image").rglob("*.py")):
        ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
PY

assert_unique_keys() {
    local layer="$1"
    shift
    local duplicates
    duplicates="$(
        awk -F= '
            /^[A-Za-z_][A-Za-z0-9_]*=/ {
                count[$1]++
                locations[$1] = locations[$1] " " FILENAME
            }
            END {
                for (key in count) {
                    if (count[key] > 1) print key ":" locations[key]
                }
            }
        ' "$@" | sort
    )"
    [ -z "$duplicates" ] || fail "$layer duplicate example keys: $duplicates"
}

assert_unique_keys core "$CORE"/*example
assert_unique_keys base "$BASE"/examples.d/core/*example "$BASE"/*example
assert_unique_keys safrano \
    "$SAFRANO"/examples.d/core/*example \
    "$SAFRANO"/examples.d/base/*example \
    "$SAFRANO"/*example

for name in config.fedora44-ai-core.conf_example env.fedora44-ai-core.example container.fedora44-ai-core.example; do
    cmp -s "$CORE/$name" "$BASE/examples.d/core/$name" ||
        fail "Base Core example snapshot drifted: $name"
    cmp -s "$BASE/examples.d/core/$name" "$SAFRANO/examples.d/core/$name" ||
        fail "Safrano Core example snapshot drifted: $name"
done
for name in \
    config.fedora44-ai-base.conf_example \
    config.cloudflare.conf_example \
    env.cloudflare.example \
    env.fedora44-ai-base.example; do
    cmp -s "$BASE/$name" "$SAFRANO/examples.d/base/$name" ||
        fail "Safrano Base example snapshot drifted: $name"
done

consumer_manifest="$CORE/tests/example-key-consumers.tsv"
mapfile -t example_keys < <(
    awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ {print $1}' \
        "$CORE/config.fedora44-ai-core.conf_example" \
        "$CORE/env.fedora44-ai-core.example" \
        "$CORE/container.fedora44-ai-core.example" \
        "$CORE/fedora44-ai-core.build.conf_example" \
        "$BASE/config.fedora44-ai-base.conf_example" \
        "$BASE/config.cloudflare.conf_example" \
        "$BASE/env.cloudflare.example" \
        "$BASE/env.fedora44-ai-base.example" \
        "$BASE/fedora44-ai-base.build.conf_example" \
        "$SAFRANO/config.fedora44-ai.conf_example" \
        "$SAFRANO/container.fedora44-ai.example" \
        "$SAFRANO/fedora44-ai-safrano9999.build.conf_example" |
        LC_ALL=C sort -u
)
mapfile -t consumer_keys < <(
    awk -F '\t' '!/^#/ && NF {print $1}' "$consumer_manifest" |
        LC_ALL=C sort
)
[ -z "$(comm -3 \
    <(printf '%s\n' "${example_keys[@]}") \
    <(printf '%s\n' "${consumer_keys[@]}"))" ] ||
    fail "example consumer manifest does not exactly cover the canonical example keys"
[ "$(printf '%s\n' "${consumer_keys[@]}" | uniq -d | wc -l)" -eq 0 ] ||
    fail "duplicate keys in example consumer manifest"

while IFS=$'\t' read -r key kind consumer; do
    [[ "$key" == \#* || -z "$key" ]] && continue
    [ -n "$consumer" ] || fail "example key $key has no documented consumer"
    case "$kind" in
        source)
            [ -f "$ROOT/$consumer" ] ||
                fail "example key $key names missing consumer $consumer"
            grep -Fq "$key" "$ROOT/$consumer" ||
                fail "example key $key is absent from consumer $consumer"
            ;;
        generator)
            [ "$consumer" = fedora44-ai-core/config.sh ] ||
                fail "example key $key names an unknown generator"
            case "$key" in
                *_PUBLISH_PORT) grep -Fq '*_PUBLISH_PORT' "$ROOT/$consumer" ;;
                *_CAPABILITIES) grep -Fq '*_CAPABILITIES' "$ROOT/$consumer" ;;
                *_DEVICES) grep -Fq '*_DEVICES' "$ROOT/$consumer" ;;
                *_VOLUMES) grep -Fq '*_VOLUMES' "$ROOT/$consumer" ;;
                *) grep -Fq "$key" "$ROOT/$consumer" ;;
            esac || fail "example key $key lacks its generic generator"
            ;;
        directive)
            grep -Fq "$key=" "$ROOT/$consumer" &&
                grep -Fq '#named-volume:' "$ROOT/$consumer" ||
                fail "example key $key lacks its named-volume directive"
            ;;
        injection)
            [ -n "$consumer" ] ||
                fail "example key $key lacks an explicit injection purpose"
            ;;
        *) fail "unknown example consumer kind for $key: $kind" ;;
    esac
done < "$consumer_manifest"

! rg -n 'HERMES_DASHBOARD_BASIC_AUTH_|POSTGRES_(URL|PORT|DB|USER|PW)' \
    "$CORE"/*example "$BASE"/*example "$SAFRANO"/*example ||
    fail "unsupported runtime variables remain in canonical examples"
grep -Fq 'OPENAI_V1_URL=http://169.254.1.2' "$CORE/env.fedora44-ai-core.example"
grep -Fq 'OPENAI_V1_PORT=4000' "$CORE/env.fedora44-ai-core.example"
grep -Fq 'OPENAI_V1_STREAM=true' "$CORE/env.fedora44-ai-core.example"
grep -Fq 'OPENCLAW_MODEL=' "$CORE/config.fedora44-ai-core.conf_example"
grep -Fq 'NOTE_DB_BACKEND=' "$CORE/env.fedora44-ai-core.example"
grep -Fq \
    '#named-volume: /named_volumes/NOTE_SQLITE /named_volumes/NOTE_SQLITE /root/.openclaw/extensions/note/sqlite dir' \
    "$CORE/env.fedora44-ai-core.example"
grep -Fq 'CLOUDFLARED_START=' "$CORE/config.fedora44-ai-core.conf_example"
grep -Fq \
    '#repeat-group: MCP_SERVER suffix02 MCP_SERVER_NAME MCP_SERVER_URL MCP_SERVER_BEARER' \
    "$CORE/env.fedora44-ai-core.example"
grep -Fq \
    '#repeat-optional-complete: MCP_SERVER_NAME MCP_SERVER_BEARER' \
    "$CORE/env.fedora44-ai-core.example"
python3 "$CORE/tests/test-hermes-mcp-ephemeral.py"

base_repos="$(
    awk -F '\t' '!/^#/ && NF {sub(/@.*/, "", $1); print $1}' \
        "$BASE/image/contributions.tsv" | sort
)"
safrano_repos="$(
    awk -F '\t' '!/^#/ && NF {sub(/@.*/, "", $1); print $1}' \
        "$SAFRANO/image/contributions.tsv" | sort
)"
[ "$(printf '%s\n' "$base_repos" | wc -l)" -eq 5 ] ||
    fail "Base contribution count is not five"
[ "$(printf '%s\n' "$safrano_repos" | wc -l)" -eq 11 ] ||
    fail "Safrano contribution count is not eleven"
! grep -Fxq NOTE <<< "$base_repos" || fail "NOTE remains a Base contribution"
[ -z "$(comm -12 <(printf '%s\n' "$base_repos") <(printf '%s\n' "$safrano_repos"))" ] ||
    fail "a repository is processed by both downstream layers"
grep -Fq 'safrano9999-paper' "$BASE/prepare-build-context.sh" ||
    fail "Base build preparation does not fetch safrano9999-paper"
grep -Fq 'safrano9999-paper' "$BASE/setup.sh" ||
    fail "Base setup does not fetch safrano9999-paper"
grep -Fq \
    'COPY safrano9999/safrano9999-paper /opt/safrano9999/safrano9999-paper' \
    "$BASE/Containerfile" ||
    fail "Base Containerfile does not retain the paper source"
grep -Fq '/README/paper.pdf' "$BASE/Containerfile" ||
    fail "Base Containerfile does not link the paper into /README"

grep -Fq 'After=openclaw-config.service' \
    "$BASE/image/systemd/openclaw-safrano9999-base.service"
grep -Fq 'After=openclaw-config.service openclaw-safrano9999-base.service vikai-bootstrap-openclaw-agents.service' \
    "$SAFRANO/image/systemd/openclaw-safrano9999.service"
grep -Fq 'After=openclaw-config.service' \
    "$SAFRANO/image/systemd/vikai-bootstrap-openclaw-agents.service"
grep -Fq 'VIKAI_OPENCLAW_LLM OPENAI_V1_PROVIDER' \
    "$SAFRANO/image/systemd/vikai-bootstrap-openclaw-agents.service"
grep -Fq 'Requires=vikai-bootstrap-openclaw-agents.service openclaw-safrano9999.service' \
    "$SAFRANO/image/systemd/openclaw.service.d/30-safrano9999.conf"

python3 - "$SAFRANO/image/runtime.d/vikai-bootstrap-openclaw-agents.py" <<'PY'
import importlib.util
import os
from pathlib import Path
import sys

source = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("vikai_bootstrap", source)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

os.environ["VIKAI_OPENCLAW_LLM"] = "luna"
os.environ.pop("OPENAI_V1_PROVIDER", None)
config = {
    "models": {
        "providers": {
            "litellm": {
                "models": [
                    {"id": "luna", "name": "luna"},
                    {"id": "sol", "name": "sol"},
                ]
            }
        }
    }
}
assert module.configured_openclaw_model(config) == "litellm/luna"

os.environ["VIKAI_OPENCLAW_LLM"] = "custom/luna"
assert module.configured_openclaw_model(config) == "custom/luna"
PY

if command -v systemd-analyze >/dev/null 2>&1; then
    verify_output="$(
        SYSTEMD_UNIT_PATH="$SAFRANO/image/systemd:$BASE/image/systemd:$CORE/image/systemd:/usr/lib/systemd/system" \
            systemd-analyze verify \
            "$CORE/image/systemd/fedora44-ai.service" \
            "$CORE/image/systemd/openclaw-config.service" \
            "$CORE/image/systemd/openclaw.service" \
            "$CORE/image/systemd/hermes.service" \
            "$BASE/image/systemd/openclaw-safrano9999-base.service" \
            "$SAFRANO/image/systemd/vikai-bootstrap-openclaw-agents.service" \
            "$SAFRANO/image/systemd/openclaw-safrano9999.service" 2>&1 ||
            true
    )"
    verify_output="$(
        grep -vE 'Command /usr/local/(bin|libexec)/[^ ]+ is not executable: No such file or directory' \
            <<< "$verify_output" || true
    )"
    [ -z "$verify_output" ] || fail "systemd verification: $verify_output"
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/fedora-chain-test.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary"
}
trap cleanup EXIT

for layer in base safrano; do
    source_root="$temporary/source-prune-$layer"
    mkdir -p "$source_root/SELECTED" "$source_root/STALE"
    printf 'keep\n' > "$source_root/SELECTED/source.txt"
    printf 'remove\n' > "$source_root/STALE/source.txt"
    sync_script="$BASE/image/setup.d/sync-sources.sh"
    [ "$layer" = safrano ] &&
        sync_script="$SAFRANO/image/setup.d/sync-sources.sh"
    FEDORA44_AI_SOURCE_DIR="$source_root" \
        bash "$sync_script" --offline --no-cache sync SELECTED@main
    [ -f "$source_root/SELECTED/source.txt" ] ||
        fail "$layer source pruning removed a selected repository"
    [ ! -e "$source_root/STALE" ] ||
        fail "$layer source pruning retained an unselected repository"
done

for layer in base safrano; do
    sqlite_root="$temporary/sqlite-$layer"
    mkdir -p \
        "$sqlite_root/repos/ACTIVE" \
        "$sqlite_root/repos/NOTE" \
        "$sqlite_root/repos/fedora44-ai-base" \
        "$sqlite_root/config"
    printf 'ACTIVE_DB_BACKEND=sqlite\n' \
        > "$sqlite_root/repos/ACTIVE/env.example"
    printf 'NOTE_DB_BACKEND=sqlite\n' \
        > "$sqlite_root/repos/NOTE/env.example"
    printf 'NOTE_DB_BACKEND=sqlite\n' \
        > "$sqlite_root/repos/fedora44-ai-base/env.example"
    printf 'ACTIVE_DB_BACKEND=sqlite\nNOTE_DB_BACKEND=sqlite\n' \
        > "$sqlite_root/config/.env"

    sqlite_script="$BASE/sqlite_persistence.sh"
    [ "$layer" = safrano ] &&
        sqlite_script="$SAFRANO/sqlite_persistence.sh"
    FEDORA_LAYER_REPOS=$'ACTIVE@main\nMISSING' \
        bash "$sqlite_script" init \
            --repo-root "$sqlite_root/repos" \
            --config-dir "$sqlite_root/config"
    [ -d "$sqlite_root/repos/ACTIVE/sqlite" ] ||
        fail "$layer sqlite initializer skipped the selected repository"
    [ ! -e "$sqlite_root/repos/NOTE/sqlite" ] ||
        fail "$layer sqlite initializer consumed stale NOTE staging"
    [ ! -e "$sqlite_root/repos/fedora44-ai-base/sqlite" ] ||
        fail "$layer sqlite initializer consumed stale Base staging"

    sqlite_mounts="$(
        FEDORA_LAYER_REPOS=$'ACTIVE@main\nMISSING' \
            bash "$sqlite_script" mounts \
                --repo-root "$sqlite_root/repos" \
                --config-dir "$sqlite_root/config" \
                --container chain-note
    )"
    [ "$sqlite_mounts" = \
        'chain-note-active-sqlite:/opt/safrano9999/ACTIVE/sqlite:Z' ] ||
        fail "$layer sqlite mounts were not limited to FEDORA_LAYER_REPOS: $sqlite_mounts"
done

note_mounts="$(
    NOTE_DB_BACKEND=sqlite CONFIG_CONTAINER_NAME=chain-note \
        bash "$CORE/optional_persistence.sh" mounts \
            --config-dir "$CORE" \
            --container chain-note
)"
[ "$(grep -Fxc \
    'chain-note-note-sqlite:/named_volumes/NOTE_SQLITE:Z' \
    <<< "$note_mounts")" -eq 1 ] ||
    fail "NOTE sqlite did not render exactly one reusable named volume"
note_links="$(
    NOTE_DB_BACKEND=sqlite CONFIG_CONTAINER_NAME=chain-note \
        bash "$CORE/optional_persistence.sh" entries \
            --config-dir "$CORE"
)"
grep -Fq \
    '/named_volumes/NOTE_SQLITE|/named_volumes/NOTE_SQLITE|/root/.openclaw/extensions/note/sqlite|dir' \
    <<< "$note_links" ||
    fail "NOTE sqlite named-volume link does not target the installed extension"
file_mounts="$(
    NOTE_DB_BACKEND=file CONFIG_CONTAINER_NAME=chain-note \
        bash "$CORE/optional_persistence.sh" mounts \
            --config-dir "$CORE" \
            --container chain-note
)"
! grep -Fq '/named_volumes/NOTE_SQLITE' <<< "$file_mounts" ||
    fail "NOTE sqlite volume was enabled for the file backend"

note_source="$temporary/named-volumes/NOTE_SQLITE"
note_target="$temporary/root/.openclaw/extensions/note/sqlite"
mkdir -p "$note_source" "$note_target"
printf 'existing note state\n' > "$note_target/note.sqlite3"
NAMED_VOLUME_LINKS="$note_source|$note_source|$note_target|dir" \
    bash "$CORE/image/runtime.d/named_volume_links.sh"
[ -L "$note_target" ] ||
    fail "NOTE sqlite runtime target was not projected as a symlink"
[ "$(readlink "$note_target")" = "$note_source" ] ||
    fail "NOTE sqlite runtime target points to the wrong named-volume path"
grep -Fxq 'existing note state' "$note_source/note.sqlite3" ||
    fail "NOTE sqlite runtime projection did not preserve existing state"

package_mount="$temporary/package-volume/OPENCLAW"
declared_source="$package_mount/extensions/note/sqlite"
declared_target="$temporary/package-root/.openclaw/extensions/note/sqlite"
undeclared_target="$temporary/package-root/.openclaw/openclaw.json"
mkdir -p "$declared_source" "$(dirname "$declared_target")"
printf 'declared note state\n' > "$declared_source/note.sqlite3"
printf 'must remain unlinked\n' > "$package_mount/openclaw.json"
NAMED_VOLUME_LINKS="$package_mount|$declared_source|$declared_target|dir" \
    bash "$CORE/image/runtime.d/named_volume_links.sh"
[ -L "$declared_target" ] ||
    fail "explicit nested named-volume path was not projected"
[ ! -e "$undeclared_target" ] ||
    fail "undeclared package-root state was linked implicitly"

mkdir -p \
    "$temporary/fake-gh-bin" \
    "$temporary/fake-release" \
    "$temporary/release-source/plugin" \
    "$temporary/release-target/hermes" \
    "$temporary/release-target/fedora44-ai-container" \
    "$temporary/release-target/fedora44-ai-container/systemd"
printf '%s\n' \
    '{"id":"release-test","name":"Release test","configSchema":{"type":"object"}}' \
    > "$temporary/release-source/plugin/openclaw.plugin.json"
printf '%s\n' 'release payload' \
    > "$temporary/release-source/plugin/release-only.txt"
printf '%s\n' 'checkout source' \
    > "$temporary/release-target/checkout-only.txt"
printf '%s\n' 'name: release-test' \
    > "$temporary/release-target/hermes/plugin.yaml"
printf '%s\n' 'hermes' \
    > "$temporary/release-target/fedora44-ai-container/source-overlay.list"
cat > "$temporary/release-target/fedora44-ai-container/systemd/release-test.service" <<'UNIT'
[Unit]
Description=Release staging contribution test

[Service]
Type=oneshot
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
UNIT
python3 - "$temporary/release-source" "$temporary/fake-release/release-test.zip" <<'PY'
from pathlib import Path
import sys
from zipfile import ZIP_DEFLATED, ZipFile

source = Path(sys.argv[1])
with ZipFile(sys.argv[2], "w", compression=ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(source))
PY
(
    cd "$temporary/fake-release"
    sha256sum release-test.zip > release-test.zip.sha256
)
cat > "$temporary/fake-gh-bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
    exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = download ]; then
    destination=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dir) destination="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$destination" ]
    cp -a -- "$FAKE_GH_RELEASE_DIR/." "$destination/"
    exit 0
fi
echo "Unexpected fake gh invocation: $*" >&2
exit 2
GH
chmod 0755 "$temporary/fake-gh-bin/gh"
PATH="$temporary/fake-gh-bin:$PATH" \
FAKE_GH_RELEASE_DIR="$temporary/fake-release" \
    bash "$SAFRANO/image/build.d/stage-release-plugin.sh" \
        test-owner/test-repository \
        release-test.zip \
        "$temporary/release-target"
test -f "$temporary/release-target/openclaw.plugin.json" ||
    fail "release plugin payload was not staged"
test -f "$temporary/release-target/release-only.txt" ||
    fail "release plugin content was not staged"
test ! -e "$temporary/release-target/checkout-only.txt" ||
    fail "release staging did not replace checkout-only content"
test -f "$temporary/release-target/fedora44-ai-container/systemd/release-test.service" ||
    fail "release staging discarded the repository Fedora contribution"
test -f "$temporary/release-target/hermes/plugin.yaml" ||
    fail "release staging discarded a declared source-only adapter"

mkdir -p \
    "$temporary/stage/ONE/fedora44-ai-container/build.d" \
    "$temporary/stage/ONE/fedora44-ai-container/rootfs/usr/local/share/fedora44-ai" \
    "$temporary/stage/ONE/fedora44-ai-container/runtime.d" \
    "$temporary/stage/ONE/fedora44-ai-container/systemd" \
    "$temporary/stage/TWO" \
    "$temporary/stage/THREE" \
    "$temporary/image-root"
printf '%s\n' \
    'enter this to trigger webhook from inside container' \
    'curl -sS http://example.invalid/one' \
    > "$temporary/stage/ONE/README.md"
printf '%s\n' \
    'enter this to trigger webhook from inside container' \
    'curl -sS http://example.invalid/two' \
    > "$temporary/stage/TWO/README.md"
cat > "$temporary/stage/THREE/index.js" <<'PLUGIN'
const webhookPath = "/plugins/three";
api.registerHttpRoute({
  path: webhookPath,
  auth: "gateway",
});
PLUGIN
printf 'ONE\tstandalone\tyes\tyes\nTWO\tstandalone\tyes\tyes\nTHREE\tplugin\tyes\tyes\n' \
    > "$temporary/contributions.tsv"
printf 'rootfs contribution\n' \
    > "$temporary/stage/ONE/fedora44-ai-container/rootfs/usr/local/share/fedora44-ai/rootfs-marker"
cat > "$temporary/stage/ONE/fedora44-ai-container/systemd/one.service" <<'UNIT'
[Unit]
Description=ONE contribution test

[Service]
Type=oneshot
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
UNIT
cat > "$temporary/stage/ONE/fedora44-ai-container/runtime.d/20-one.sh" <<'RUNTIME'
#!/usr/bin/env bash
set -euo pipefail
RUNTIME
cat > "$temporary/stage/ONE/fedora44-ai-container/build.d/10-one.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$FEDORA44_AI_IMAGE_ROOT/usr/local/share/fedora44-ai"
printf 'build contribution\n' \
    > "$FEDORA44_AI_IMAGE_ROOT/usr/local/share/fedora44-ai/build-marker"
BUILD
chmod 0755 \
    "$temporary/stage/ONE/fedora44-ai-container/runtime.d/20-one.sh" \
    "$temporary/stage/ONE/fedora44-ai-container/build.d/10-one.sh"

run_contributions() {
    SAFRANO9999_WEBHOOK_SCRIPT="$temporary/webhooks" \
    SAFRANO9999_FULLRUN_SCRIPT="$temporary/fullrun" \
        bash "$BASE/image/build.d/apply-contributions.sh" \
            --stage "$temporary/stage" \
            --root "$temporary/root" \
            --image-root "$temporary/image-root" \
            --manifest "$temporary/contributions.tsv"
}
run_contributions
first="$(
    sha256sum \
        "$temporary/webhooks" \
        "$temporary/fullrun" \
        "$temporary/root/WEBHOOK-RUNNER/index.js"
)"
run_contributions
second="$(
    sha256sum \
        "$temporary/webhooks" \
        "$temporary/fullrun" \
        "$temporary/root/WEBHOOK-RUNNER/index.js"
)"
[ "$first" = "$second" ] || fail "contribution application is not idempotent"
[ "$(grep -c '^curl -sS' "$temporary/webhooks")" -eq 3 ] ||
    fail "contribution commands were duplicated"
grep -Fq 'http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/plugins/three' \
    "$temporary/fullrun" ||
    fail "variable-backed plugin webhook path was not discovered"
grep -Fxq 'rootfs contribution' \
    "$temporary/image-root/usr/local/share/fedora44-ai/rootfs-marker" ||
    fail "repository rootfs contribution was not installed"
grep -Fxq 'build contribution' \
    "$temporary/image-root/usr/local/share/fedora44-ai/build-marker" ||
    fail "repository build contribution did not run"
[ -x "$temporary/image-root/usr/local/share/fedora44-ai/init.d/ONE-20-one.sh" ] ||
    fail "repository runtime contribution was not installed"
[ -f "$temporary/image-root/etc/systemd/system/one.service" ] ||
    fail "repository systemd contribution was not installed"
[ "$(readlink "$temporary/image-root/etc/systemd/system/multi-user.target.wants/one.service")" = ../one.service ] ||
    fail "repository systemd contribution was not enabled"

check_setup_idempotence() {
    local source="$1"
    local name="$2"
    shift 2
    local checkout="$temporary/setup-$name"
    local instance="chain-test-$name"
    local first second
    local repository repository_dir
    local -a arguments=(--config-only "$instance")

    mkdir -p "$checkout"
    cp -a "$source"/. "$checkout"/
    mkdir -p "$checkout/CONTAINER/$instance"
    printf '%s\n' \
        'OPENAI_V1_KEY=test-only-key' \
        'OPENAI_V1_API_KEY_ALIAS=OPENAI_V1_KEY' \
        'OPENCLAW_TELEGRAMTOKEN=test-only-token' \
        'OPENCLAW_TELEGRAM_CHAT_ID=0' \
        'NOTE_DB_BACKEND=sqlite' \
        > "$checkout/CONTAINER/$instance/$instance.env"
    if [ "$name" != core ]; then
        arguments=(--offline --config-only "$instance")
        mkdir -p \
            "$checkout/safrano9999" \
            "$checkout/safrano9999/NOTE" \
            "$checkout/safrano9999/fedora44-ai-base"
        printf 'NOTE_DB_BACKEND=sqlite\n' \
            > "$checkout/safrano9999/NOTE/env.example"
        printf 'NOTE_DB_BACKEND=sqlite\n' \
            > "$checkout/safrano9999/fedora44-ai-base/env.example"
        for repository; do
            repository="${repository%@*}"
            repository_dir="$checkout/safrano9999/$repository"
            mkdir -p "$repository_dir"
            if [ "$repository" = NaturalGrounding-Tiktok-Ying-Video-Manager ]; then
                cat > "$repository_dir/config.conf_example" <<'EXAMPLE'
#required: NaturalGrounding video storage path
#mount-bind: NATURALGROUNDING_VIDEOS_DIR:/opt/safrano9999/NaturalGrounding-Tiktok-Ying-Video-Manager/VIDEOS
NATURALGROUNDING_VIDEOS_DIR=VIDEOS
EXAMPLE
            else
                printf '# test-only example\n' > "$repository_dir/env.$repository.example"
            fi
            if [ "$name" = safrano ]; then
                mkdir -p "$checkout/safrano9999-examples"
                (
                    cd "$repository_dir"
                    zip -q -r \
                        "$checkout/safrano9999-examples/$repository-examplefiles.zip" .
                )
            fi
        done
    fi

    (
        cd "$checkout"
        bash ./setup.sh "${arguments[@]}" </dev/null
    ) > "$temporary/setup-$name-first.log" 2>&1 || {
        sed -n '1,240p' "$temporary/setup-$name-first.log" >&2
        fail "$name setup failed on its first noninteractive run"
    }
    first="$(
        find "$checkout/CONTAINER/$instance" -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    )"
    (
        cd "$checkout"
        bash ./setup.sh "${arguments[@]}" </dev/null
    ) > "$temporary/setup-$name-second.log" 2>&1 || {
        sed -n '1,240p' "$temporary/setup-$name-second.log" >&2
        fail "$name setup failed on its second noninteractive run"
    }
    second="$(
        find "$checkout/CONTAINER/$instance" -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    )"
    [ "$first" = "$second" ] || fail "$name setup is not idempotent"
}

check_setup_idempotence "$CORE" core
check_setup_idempotence "$BASE" base \
    WELCOME CODEANALYST CITADEL DIESDAS- NEXTCLOUD safrano9999-paper
check_setup_idempotence "$SAFRANO" safrano \
    JUGO VikAI PV_D-A-CH KIWIX_BRIDGE \
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES \
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW \
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual \
    DAILYNEWS ZEROINBOX SPANKER KACHELMANN

for name in core base safrano; do
    instance="chain-test-$name"
    quadlet="$temporary/setup-$name/CONTAINER/$instance/$instance.container"
    [ "$(grep -Fxc \
        "Volume=$instance-note-sqlite:/named_volumes/NOTE_SQLITE:Z" \
        "$quadlet")" -eq 1 ] ||
        fail "$name Quadlet does not contain exactly one NOTE sqlite volume"
    ! grep -Eq \
        'Volume=.*:/opt/safrano9999/(NOTE|fedora44-ai-base)/sqlite:Z$' \
        "$quadlet" ||
        fail "$name Quadlet leaked stale NOTE sqlite staging mounts"
    grep -Fq \
        '/named_volumes/NOTE_SQLITE|/named_volumes/NOTE_SQLITE|/root/.openclaw/extensions/note/sqlite|dir' \
        "$quadlet" ||
        fail "$name Quadlet does not project NOTE sqlite into the installed extension"
done

if ! grep -Fqx \
    "Volume=$temporary/setup-safrano/CONTAINER/chain-test-safrano/VIDEOS:/opt/safrano9999/NaturalGrounding-Tiktok-Ying-Video-Manager/VIDEOS:Z" \
    "$temporary/setup-safrano/CONTAINER/chain-test-safrano/chain-test-safrano.container"; then
    grep '^Volume=' \
        "$temporary/setup-safrano/CONTAINER/chain-test-safrano/chain-test-safrano.container" \
        >&2 || true
    fail "explicit repository bind target was not rendered"
fi

echo "Fedora image chain checks passed"
