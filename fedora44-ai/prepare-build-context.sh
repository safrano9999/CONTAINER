#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

CONTEXT="$(cd "${1:-.}" && pwd)"
MODE="${2:-}"
SCRIPTS_ROOT="${DEV_SCRIPTS_DIR:-${SCRIPTS_ROOT:-}}"
if [ -z "$SCRIPTS_ROOT" ]; then
    for candidate in "$CONTEXT/../../SCRIPTS" "$CONTEXT/SCRIPTS" "$CONTEXT/../SCRIPTS"; do
        if [ -f "$candidate/safrano9999/merge.sh" ]; then
            SCRIPTS_ROOT="$candidate"
            break
        fi
    done
fi
[ -n "$SCRIPTS_ROOT" ] || { echo "SCRIPTS checkout not found" >&2; exit 1; }
SCRIPTS_ROOT="$(cd "$SCRIPTS_ROOT" && pwd)"
SOT="$SCRIPTS_ROOT/safrano9999/image/fedora44-ai"
BUILD="$CONTEXT/build"
REPOS="$CONTEXT/safrano9999"

BASE_REPOS=(WELCOME CODEANALYST CITADEL DIESDAS- NEXTCLOUD)
SAFRANO_REPOS=(
    JUGO VikAI PV_D-A-CH KIWIX_BRIDGE
    NAPOLEON_HILLS_AI_MASTERMIND_CLASSES SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
    NaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual
    DAILYNEWS ZEROINBOX SPANKER KACHELMANN
)
RELEASE_PLUGIN_ASSETS=(
    "KACHELMANN=kachelmann-latest.zip"
)

link_file() {
    local source="$1" target="$2"
    [ -f "$source" ] || { echo "Missing SOT build file: $source" >&2; exit 1; }
    mkdir -p "$(dirname "$target")"
    [ -e "$target" ] && [ "$source" -ef "$target" ] || ln -f "$source" "$target"
}

relink_build_files() {
    local name
    local -a layer_services=(
        bip39.service
        citadel-scan.service
        citadel.service
        codeanalyst.service
        jugo.service
        kiwix-bridge.service
        napoleon.service
        naturalgrounding.service
        openclaw-safrano9999-build.py
        openclaw-safrano9999.py
        openclaw-safrano9999.service
        pvdach-qgis-webhook.service
        pvdach.service
        vikai-bootstrap-openclaw-agents.py
    )

    rm -rf "$BUILD"
    mkdir -p "$BUILD/services/systemd/openclaw.service.d"
    for name in "${layer_services[@]}"; do
        link_file "$SOT/services/$name" "$BUILD/services/$name"
    done
    link_file "$SOT/resolve-build-inputs.sh" "$BUILD/resolve-build-inputs.sh"
    link_file "$SOT/build-local.sh" "$CONTEXT/build-local.sh"
    link_file "$SOT/prepare-build-context.sh" "$CONTEXT/prepare-build-context.sh"
    [ -f "$CONTEXT/build.conf" ] || { echo "Missing build.conf in $CONTEXT" >&2; exit 1; }

    local shared="$SCRIPTS_ROOT/safrano9999/image/services"
    link_file "$shared/openclaw/openclaw_common.py" "$BUILD/services/openclaw_common.py"
    link_file "$shared/openclaw/safrano9999_plugins.py" "$BUILD/services/safrano9999_plugins.py"
    link_file "$shared/readme/safrano9999-welcome.service" "$BUILD/services/safrano9999-welcome.service"
    link_file "$shared/openclaw/openclaw.service.d/20-safrano9999.conf" \
        "$BUILD/services/systemd/openclaw.service.d/20-safrano9999.conf"
}

stage_scripts() {
    local target="$CONTEXT/SCRIPTS"
    [ "$SCRIPTS_ROOT" -ef "$target" ] 2>/dev/null && return 0
    rm -rf "$target"
    cp -al "$SCRIPTS_ROOT" "$target"
    rm -rf "$target/.git"
    find "$target" -type d -name __pycache__ -prune -exec rm -rf {} +
}

repo_name() { printf '%s\n' "${1%@*}"; }
repo_branch() { [[ "$1" == *@* ]] && printf '%s\n' "${1#*@}" || true; }

sync_repo() {
    local spec="$1" repo branch path
    repo="$(repo_name "$spec")"
    branch="$(repo_branch "$spec")"
    path="$REPOS/$repo"
    if [ "${NO_CACHE:-0}" = 1 ]; then rm -rf "$path"; fi
    if [ -d "$path/.git" ]; then
        if [ -n "$branch" ]; then
            git -C "$path" fetch --quiet --depth 1 origin "$branch"
            git -C "$path" checkout --quiet -B "$branch" FETCH_HEAD
        else
            git -C "$path" pull --quiet --ff-only
        fi
        printf '  [%s] updated\n' "$repo"
        return
    fi
    rm -rf "$path"
    if [ -n "$branch" ]; then
        git clone --quiet --depth 1 --branch "$branch" \
            "https://github.com/safrano9999/$repo" "$path"
    else
        git clone --quiet --depth 1 "https://github.com/safrano9999/$repo" "$path"
    fi
    printf '  [%s] cloned\n' "$repo"
}

write_manifest() {
    local output="$1"
    shift
    local temporary="${output}.tmp" spec repo path refs version version_commit staged_commit
    printf 'repository\tversion_tag\tversion_commit\tstaged_commit\n' > "$temporary"
    for spec; do
        repo="$(repo_name "$spec")"
        path="$REPOS/$repo"
        refs="$(git -C "$path" ls-remote --tags --refs origin 'refs/tags/20*.*.*')"
        version="$(awk '$2 ~ /^refs\/tags\/20[0-9][0-9][.][0-9]+[.][0-9]+$/ {sub(/^refs\/tags\//, "", $2); print $2}' \
            <<< "$refs" | sort -V | tail -n 1)"
        version_commit="$(awk -v ref="refs/tags/$version" '$2 == ref {print $1; exit}' <<< "$refs")"
        staged_commit="$(git -C "$path" rev-parse HEAD)"
        printf '%s\t%s\t%s\t%s\n' "$repo" "${version:-untagged}" \
            "${version_commit:--}" "$staged_commit" >> "$temporary"
    done
    refs="$(git -C "$SCRIPTS_ROOT" ls-remote --tags --refs origin 'refs/tags/20*.*.*')"
    version="$(awk '$2 ~ /^refs\/tags\/20[0-9][0-9][.][0-9]+[.][0-9]+$/ {sub(/^refs\/tags\//, "", $2); print $2}' \
        <<< "$refs" | sort -V | tail -n 1)"
    version_commit="$(awk -v ref="refs/tags/$version" '$2 == ref {print $1; exit}' <<< "$refs")"
    staged_commit="$(git -C "$SCRIPTS_ROOT" rev-parse HEAD)"
    printf 'SCRIPTS\t%s\t%s\t%s\n' "${version:-untagged}" \
        "${version_commit:--}" "$staged_commit" >> "$temporary"
    mv -f "$temporary" "$output"
}

stage_release_plugins() (
    local mapping repo asset repository target download_dir archive checksum expected
    local temporary extract_root payload backup
    local restore_target="" restore_backup=""
    local -a entries=()
    local -A seen_repositories=()

    command -v gh >/dev/null || {
        echo "Missing command for release plugin staging: gh" >&2
        exit 1
    }
    gh auth status --hostname github.com >/dev/null 2>&1 || {
        echo "GitHub CLI authentication is required for release plugin staging" >&2
        exit 1
    }

    temporary="$(mktemp -d "$REPOS/.release-plugins.XXXXXX")"
    cleanup_release_plugin_stage() {
        if [ -n "$restore_target" ] && [ ! -e "$restore_target" ] \
            && [ -d "$restore_backup" ]; then
            mv -- "$restore_backup" "$restore_target" || true
        fi
        rm -rf -- "$temporary"
    }
    trap cleanup_release_plugin_stage EXIT
    trap 'exit 1' HUP INT TERM

    for mapping in "${RELEASE_PLUGIN_ASSETS[@]}"; do
        repo="${mapping%%=*}"
        asset="${mapping#*=}"
        [ "$repo" != "$mapping" ] && [ -n "$repo" ] && [ -n "$asset" ] || {
            echo "Invalid release plugin mapping: $mapping" >&2
            exit 1
        }
        [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
            echo "Invalid release plugin repository name: $repo" >&2
            exit 1
        }
        [[ "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*[.]zip$ ]] || {
            echo "Invalid release plugin asset name: $asset" >&2
            exit 1
        }
        [ -z "${seen_repositories[$repo]+x}" ] || {
            echo "Duplicate release plugin repository: $repo" >&2
            exit 1
        }
        seen_repositories["$repo"]=1

        repository="safrano9999/$repo"
        target="$REPOS/$repo"
        [ -d "$target" ] && [ ! -L "$target" ] || {
            echo "Cloned plugin repository is unavailable: $target" >&2
            exit 1
        }

        download_dir="$temporary/$repo-download"
        extract_root="$temporary/$repo-extracted"
        archive="$download_dir/$asset"
        checksum="$download_dir/$asset.sha256"
        mkdir -p "$download_dir" "$extract_root"

        gh release download --repo "$repository" \
            --pattern "$asset" \
            --pattern "$asset.sha256" \
            --dir "$download_dir"
        [ -f "$archive" ] && [ -f "$checksum" ] || {
            echo "Release assets are incomplete for $repository: $asset" >&2
            exit 1
        }
        expected="$(awk 'NR == 1 {print $1; exit}' "$checksum")"
        [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || {
            echo "Invalid release checksum for $repository: $asset.sha256" >&2
            exit 1
        }
        printf '%s  %s\n' "$expected" "$asset" \
            | (cd "$download_dir" && sha256sum --check --status -) || {
                echo "Release checksum mismatch for $repository: $asset" >&2
                exit 1
            }

        python3 - "$archive" "$extract_root" <<'PY'
from pathlib import Path, PurePosixPath
import stat
import sys
from zipfile import BadZipFile, ZipFile

archive_path = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()
maximum_uncompressed_bytes = 2 * 1024 * 1024 * 1024

try:
    with ZipFile(archive_path) as archive:
        entries = archive.infolist()
        if not entries:
            raise ValueError("release archive is empty")

        seen = set()
        total_size = 0
        for entry in entries:
            name = entry.filename
            path = PurePosixPath(name)
            parts = path.parts
            if (
                not name
                or "\\" in name
                or path.is_absolute()
                or not parts
                or any(part in {"", ".", ".."} for part in parts)
                or ".git" in parts
            ):
                raise ValueError(f"unsafe archive path: {name!r}")

            normalized = "/".join(parts)
            if normalized in seen:
                raise ValueError(f"duplicate archive path: {name!r}")
            seen.add(normalized)

            file_type = stat.S_IFMT(entry.external_attr >> 16)
            if file_type not in {0, stat.S_IFREG, stat.S_IFDIR}:
                raise ValueError(f"unsupported archive entry: {name!r}")
            if entry.flag_bits & 0x1:
                raise ValueError(f"encrypted archive entry: {name!r}")

            total_size += entry.file_size
            if total_size > maximum_uncompressed_bytes:
                raise ValueError("release archive exceeds extraction limit")

        archive.extractall(destination)
except (BadZipFile, OSError, ValueError) as error:
    raise SystemExit(f"Invalid release plugin archive: {error}") from error
PY

        shopt -s dotglob nullglob
        entries=("$extract_root"/*)
        shopt -u dotglob nullglob
        payload="$extract_root"
        if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}" ] \
            && [ -f "${entries[0]}/openclaw.plugin.json" ]; then
            payload="${entries[0]}"
        fi
        [ -f "$payload/openclaw.plugin.json" ] || {
            echo "Release asset is not an OpenClaw plugin: $repository/$asset" >&2
            exit 1
        }
        python3 -m json.tool "$payload/openclaw.plugin.json" >/dev/null

        backup="$temporary/$repo-source"
        restore_target="$target"
        restore_backup="$backup"
        mv -- "$target" "$backup"
        if ! mv -- "$payload" "$target"; then
            mv -- "$backup" "$target" || {
                echo "Failed to restore cloned plugin repository: $target" >&2
                exit 1
            }
            restore_target=""
            restore_backup=""
            echo "Failed to stage release plugin: $repository/$asset" >&2
            exit 1
        fi
        restore_target=""
        restore_backup=""
        printf '  [%s] staged release asset %s\n' "$repo" "$asset"
    done
)

merge_requirements_and_reference() {
    local merge="$SCRIPTS_ROOT/safrano9999/merge.sh"
    (
        cd "$CONTEXT"
        bash "$merge" "${BASE_REPOS[@]}"
        python3 "$SCRIPTS_ROOT/safrano9999/image/readme/welcome_ref.py" \
            "$CONTEXT" "$CONTEXT/ref.base.conf"
        mv -f requirements.txt requirements.base.txt
        bash "$merge" "${SAFRANO_REPOS[@]}"
        mv -f requirements.txt requirements.safrano9999.txt
        bash "$merge"
        python3 "$SCRIPTS_ROOT/safrano9999/image/readme/welcome_ref.py" \
            "$CONTEXT" "$CONTEXT/ref.safrano9999.conf"
        rm -f requirements.txt env.example config.conf_example container.example ref.conf
    )
}

for command in curl git jq python3 sha256sum; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

relink_build_files
[ "$MODE" != "--links-only" ] || { printf 'Build links refreshed: %s\n' "$CONTEXT"; exit 0; }
stage_scripts
mkdir -p "$REPOS"
for repo in "${BASE_REPOS[@]}" "${SAFRANO_REPOS[@]}"; do sync_repo "$repo"; done
write_manifest "$CONTEXT/.fedora44-ai-base-source-tags.tsv" "${BASE_REPOS[@]}"
write_manifest "$CONTEXT/.safrano9999-source-tags.tsv" "${SAFRANO_REPOS[@]}"
stage_release_plugins
merge_requirements_and_reference
"$BUILD/resolve-build-inputs.sh" \
    "$CONTEXT/.resolved-build.env" \
    "$CONTEXT/.safrano9999-source-tags.tsv" \
    "$CONTEXT/.fedora44-ai-base-source-tags.tsv"
printf 'Build context ready: %s\n' "$CONTEXT"
