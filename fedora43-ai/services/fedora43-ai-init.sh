#!/usr/bin/env bash
set -euo pipefail

mkdir -p /persistent/bin /persistent/codex-auth
chmod 700 /persistent/codex-auth 2>/dev/null || true

if [ -d /usr/local/share/fedora43-ai/bin ]; then
    for script in /usr/local/share/fedora43-ai/bin/*; do
        [ -f "$script" ] || continue
        target="/persistent/bin/$(basename "$script")"
        [ -e "$target" ] || install -m 700 "$script" "$target"
    done
fi

find /persistent/bin -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -print \
    | sort \
    | while IFS= read -r script; do
        case "$script" in
            *.sh) /bin/bash "$script" ;;
            *.py) /usr/bin/python3 "$script" ;;
        esac
    done
