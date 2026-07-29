#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="${FEDORA44_AI_SOURCE_DIR:-$ROOT/safrano9999}"
OFFLINE=false
NO_CACHE=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --offline) OFFLINE=true; shift ;;
        --no-cache) NO_CACHE=true; shift ;;
        sync|manifest) command_name="$1"; shift; break ;;
        *) echo "Usage: sync-sources.sh [--offline] [--no-cache] sync REPO..." >&2; exit 2 ;;
    esac
done
command_name="${command_name:-}"

repo_name() {
    printf '%s\n' "${1%@*}"
}

repo_branch() {
    if [[ "$1" == *@* ]]; then
        printf '%s\n' "${1#*@}"
    fi
}

valid_repo() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

sync_one() {
    local spec="$1" repo branch path
    repo="$(repo_name "$spec")"
    branch="$(repo_branch "$spec")"
    valid_repo "$repo" || {
        echo "Invalid repository name: $repo" >&2
        return 2
    }
    path="$SOURCE_DIR/$repo"
    if $OFFLINE; then
        [ -d "$path" ] || {
            echo "Offline source is missing: $path" >&2
            return 1
        }
        return
    fi
    if $NO_CACHE && [ -e "$path" ]; then
        rm -rf -- "$path"
    fi
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
    [ ! -e "$path" ] || rm -rf -- "$path"
    if [ -n "$branch" ]; then
        git clone --quiet --depth 1 --branch "$branch" \
            "https://github.com/safrano9999/$repo" "$path"
    else
        git clone --quiet --depth 1 \
            "https://github.com/safrano9999/$repo" "$path"
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
        path="$SOURCE_DIR/$repo"
        [ -d "$path/.git" ] || {
            echo "Source is not a Git checkout: $path" >&2
            return 1
        }
        if $OFFLINE; then
            refs="$(git -C "$path" show-ref --tags 2>/dev/null || true)"
        else
            refs="$(git -C "$path" ls-remote --tags --refs origin 'refs/tags/20*.*.*')"
        fi
        version="$(awk '
            $2 ~ /^refs\/tags\/20[0-9][0-9][.][0-9]+[.][0-9]+$/ {
                sub(/^refs\/tags\//, "", $2)
                print $2
            }
        ' <<< "$refs" | sort -V | tail -n 1)"
        version_commit="$(awk -v ref="refs/tags/$version" \
            '$2 == ref {print $1; exit}' <<< "$refs")"
        staged_commit="$(git -C "$path" rev-parse HEAD)"
        printf '%s\t%s\t%s\t%s\n' \
            "$repo" "${version:-untagged}" "${version_commit:--}" "$staged_commit" \
            >> "$temporary"
    done
    mv -f -- "$temporary" "$output"
}

mkdir -p "$SOURCE_DIR"
case "$command_name" in
    sync)
        [ "$#" -gt 0 ] || { echo "No repositories selected" >&2; exit 2; }
        for spec; do sync_one "$spec"; done
        ;;
    manifest)
        [ "$#" -gt 1 ] || { echo "manifest requires OUTPUT REPO..." >&2; exit 2; }
        output="$1"
        shift
        write_manifest "$output" "$@"
        ;;
    *)
        echo "Usage: sync-sources.sh [--offline] [--no-cache] sync REPO..." >&2
        exit 2
        ;;
esac
