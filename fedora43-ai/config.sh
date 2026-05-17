#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/env.example" ]; then
    DIR="$SCRIPT_DIR"
else
    DIR="$(pwd)"
fi
ENV="$DIR/.env"
EXAMPLE="$DIR/env.example"
PROJECT_NAME="$(basename "$DIR")"
CONTAINER_NAME="${PROJECT_NAME,,}"

[ ! -f "$EXAMPLE" ] && echo "No env.example" && exit 1

echo ""
echo "  Configuring $PROJECT_NAME"
echo ""

touch "$ENV"
declare -A seen_keys=()
required_next=false

while IFS= read -r line <&3; do
    stripped="${line#"${line%%[![:space:]]*}"}"
    if [[ "$stripped" == \#required:* ]]; then
        required_next=true
        continue
    fi
    if [[ -z "$stripped" || "$stripped" == \#* ]]; then
        required_next=false
        continue
    fi
    required="$required_next"
    required_next=false

    entry="${line%%#*}"
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ "$entry" != *=* ]] && continue

    key="${entry%%=*}"
    default="${entry#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    default="${default#"${default%%[![:space:]]*}"}"
    default="${default%"${default##*[![:space:]]}"}"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ -n "${seen_keys[$key]+x}" ]]; then
        echo "    duplicate $key in env.example" >&2
        continue
    fi
    seen_keys[$key]=1

    existing="$(grep "^${key}=" "$ENV" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [ -n "$existing" ]; then
        echo "    $key= exists"
        continue
    fi
    # Remove stale empty entry if present
    sed -i "/^${key}=$/d" "$ENV" 2>/dev/null || true

    while :; do
        used_prefill=false
        read_status=0
        if [ -n "$default" ] && [ -t 0 ]; then
            read -e -i "$default" -r -p "    $key: " val || read_status=$?
            used_prefill=true
        else
            if [ -n "$default" ]; then
                printf "    %s [%s]: " "$key" "$default"
            else
                printf "    %s: " "$key"
            fi
            read -r val || read_status=$?
        fi
        if [ "$used_prefill" != "true" ] && [ -z "$val" ]; then
            val="$default"
        fi
        if [ "$required" != "true" ] || [ -n "$val" ]; then
            break
        fi
        if [ "$read_status" -ne 0 ] && [ ! -t 0 ]; then
            echo "    $key required" >&2
            exit 1
        fi
        echo "    $key required"
    done

    if [ -z "$val" ]; then
        if [ "$used_prefill" = "true" ] && [ -n "$default" ]; then
            echo "$key=" >> "$ENV"
            echo "    $key= set empty"
            continue
        else
            echo "    $key= skipped"
            continue
        fi
    fi
    echo "$key=$val" >> "$ENV"
done 3< "$EXAMPLE"

echo ""
