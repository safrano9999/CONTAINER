#!/usr/bin/env bash
set -euo pipefail

IFS=';' read -ra specs <<< "${NAMED_VOLUME_LINKS:-}"

resolve_target() {
    local target="$1" variable
    if [[ "$target" =~ ^@([A-Za-z_][A-Za-z0-9_]*)@(.*)$ ]]; then
        variable="${BASH_REMATCH[1]}"
        [ -n "${!variable:-}" ] || { echo "Missing $variable for named-volume target" >&2; exit 1; }
        target="${!variable}${BASH_REMATCH[2]}"
    fi
    printf '%s\n' "$target"
}

for spec in "${specs[@]}"; do
    IFS='|' read -r mount source target kind <<< "$spec"
    [ -z "${NAMED_VOLUME_ONLY_MOUNT:-}" ] || [ "$mount" = "$NAMED_VOLUME_ONLY_MOUNT" ] || continue
    case ";${NAMED_VOLUME_SKIP_MOUNTS:-};" in *";$mount;"*) continue ;; esac
    [ -n "$source" ] && [ -n "$target" ] || continue
    target="$(resolve_target "$target")"
    if [ -z "$kind" ]; then
        if [ -f "$source" ] || [ -f "$target" ]; then kind=file; else kind=dir; fi
    fi
    if [ "$kind" = link ]; then [ ! -d "$mount" ] || { rm -rf "$target"; ln -s "$source" "$target"; }; continue; fi
    mkdir -p "$(dirname "$source")"
    mkdir -p "$(dirname "$target")"
    if [ "$kind" = file ]; then
        if [ ! -e "$source" ]; then
            if [ -f "$target" ] && [ ! -L "$target" ]; then mv "$target" "$source"; else install -m 0600 /dev/null "$source"; fi
        fi
        rm -rf "$target"
        ln -sfn "$source" "$target"
    else
        mkdir -p "$source"
        if [ -d "$target" ] && [ ! -L "$target" ] && [ -z "$(find "$source" -mindepth 1 -print -quit)" ]; then
            cp -a "$target"/. "$source"/
        fi
        rm -rf "$target"
        ln -s "$source" "$target"
    fi
done
