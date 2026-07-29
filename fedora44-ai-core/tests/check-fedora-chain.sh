#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE="$ROOT/fedora44-ai-core"
BASE="$ROOT/fedora44-ai-base"
SAFRANO="$ROOT/fedora44-ai-safrano9999"

fail() {
    echo "Fedora chain check failed: $*" >&2
    exit 1
}

for file in \
    "$CORE/Containerfile" \
    "$BASE/Containerfile" \
    "$SAFRANO/Containerfile"; do
    [ -f "$file" ] || fail "missing $file"
done

grep -Fq 'FROM quay.io/fedora/fedora:44 AS ai-core' "$CORE/Containerfile"
grep -Fq 'FROM ${AI_CORE_IMAGE} AS ai-base' "$BASE/Containerfile"
grep -Fq 'FROM ${AI_BASE_IMAGE} AS ai-safrano9999' "$SAFRANO/Containerfile"
if rg -n 'core2|AI_CORE2' \
    "$CORE/Containerfile" \
    "$BASE/Containerfile" \
    "$SAFRANO/Containerfile" \
    "$CORE/build.conf" \
    "$BASE/build.conf" \
    "$SAFRANO/build.conf"; then
    fail "legacy Core2 reference remains in the final chain"
fi
if rg -n '^COPY[[:space:]]+SCRIPTS([[:space:]]|$)' \
    "$CORE/Containerfile" "$BASE/Containerfile" "$SAFRANO/Containerfile"; then
    fail "a complete SCRIPTS tree is copied into an image"
fi

grep -Fq 'openclaw-ephemeral-source' "$CORE/Containerfile"
grep -Fq 'USER root' "$CORE/Containerfile"
grep -Fq 'USER root' "$BASE/Containerfile"
grep -Fq 'USER root' "$SAFRANO/Containerfile"
grep -Fq 'systemctl mask cockpit.socket' "$CORE/Containerfile"
grep -Fq 'openclaw-ephemeral.py configure' "$CORE/image/systemd/openclaw-config.service"
grep -Fq 'ExecStartPre=/usr/local/bin/hermes-ephemeral.py' "$CORE/image/systemd/hermes.service"

for setup in "$CORE/setup.sh" "$BASE/setup.sh" "$SAFRANO/setup.sh"; do
    for marker in \
        'Image source:' \
        'Build locally' \
        'read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE' \
        'IMG_CHOICE="${IMG_CHOICE:-2}"'; do
        grep -Fq "$marker" "$setup" ||
            fail "missing established image-source marker in $setup: $marker"
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
    "$BASE/image/build.d/apply-contributions.sh" \
    "$BASE/image/setup.d/layer-setup.sh" \
    "$BASE/image/setup.d/sync-sources.sh" \
    "$SAFRANO/setup.sh" \
    "$SAFRANO/build-local.sh" \
    "$SAFRANO/prepare-build-context.sh" \
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
grep -Fq 'OPENCLAW_MODEL=' "$CORE/config.fedora44-ai-core.conf_example"
grep -Fq 'NOTE_DB_BACKEND=' "$CORE/env.fedora44-ai-core.example"
grep -Fq 'CLOUDFLARED_START=' "$CORE/config.fedora44-ai-core.conf_example"

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

grep -Fq 'After=openclaw-config.service' \
    "$BASE/image/systemd/openclaw-safrano9999-base.service"
grep -Fq 'After=openclaw-config.service openclaw-safrano9999-base.service vikai-bootstrap-openclaw-agents.service' \
    "$SAFRANO/image/systemd/openclaw-safrano9999.service"
grep -Fq 'After=openclaw-config.service' \
    "$SAFRANO/image/systemd/vikai-bootstrap-openclaw-agents.service"
grep -Fq 'Requires=vikai-bootstrap-openclaw-agents.service openclaw-safrano9999.service' \
    "$SAFRANO/image/systemd/openclaw.service.d/30-safrano9999.conf"

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

mkdir -p \
    "$temporary/stage/ONE/fedora44-ai-container/build.d" \
    "$temporary/stage/ONE/fedora44-ai-container/rootfs/usr/local/share/fedora44-ai" \
    "$temporary/stage/ONE/fedora44-ai-container/runtime.d" \
    "$temporary/stage/ONE/fedora44-ai-container/systemd" \
    "$temporary/stage/TWO" \
    "$temporary/image-root"
printf '%s\n' \
    'enter this to trigger webhook from inside container' \
    'curl -sS http://example.invalid/one' \
    > "$temporary/stage/ONE/README.md"
printf '%s\n' \
    'enter this to trigger webhook from inside container' \
    'curl -sS http://example.invalid/two' \
    > "$temporary/stage/TWO/README.md"
printf 'ONE\tstandalone\tyes\tyes\nTWO\tstandalone\tyes\tyes\n' \
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
[ "$(grep -c '^curl -sS' "$temporary/webhooks")" -eq 2 ] ||
    fail "contribution commands were duplicated"
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
    local -a arguments=(--config-only "$instance")

    mkdir -p "$checkout"
    cp -a "$source"/. "$checkout"/
    mkdir -p "$checkout/CONTAINER/$instance"
    printf '%s\n' \
        'OPENAI_V1_KEY=test-only-key' \
        'OPENAI_V1_API_KEY_ALIAS=OPENAI_V1_KEY' \
        'OPENCLAW_TELEGRAMTOKEN=test-only-token' \
        'OPENCLAW_TELEGRAM_CHAT_ID=0' \
        > "$checkout/CONTAINER/$instance/$instance.env"
    if [ "$name" != core ]; then
        arguments=(--offline --config-only "$instance")
        mkdir -p "$checkout/safrano9999"
        for repository; do
            repository="${repository%@*}"
            mkdir -p "$checkout/safrano9999/$repository"
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
    WELCOME CODEANALYST CITADEL DIESDAS- NEXTCLOUD
check_setup_idempotence "$SAFRANO" safrano \
    JUGO VikAI PV_D-A-CH KIWIX_BRIDGE \
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES \
    SOLANA_AIRGAPPED_DEBIAN_WORKFLOW \
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual \
    DAILYNEWS ZEROINBOX SPANKER KACHELMANN

echo "Fedora image chain checks passed"
