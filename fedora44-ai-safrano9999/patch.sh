#!/usr/bin/env bash
set -euo pipefail

for config in ./*_config.conf; do
    [ -f "$config" ] || continue
    name="${config#./}"
    name="${name%_config.conf}"
    mkdir -p "CONTAINER/$name"
    for file in "$name.env" "${name}_config.conf" "${name}_container.conf"; do
        [ ! -f "$file" ] || mv -n "$file" "CONTAINER/$name/"
    done
done
