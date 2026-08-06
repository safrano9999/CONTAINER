#!/usr/bin/env bash
set -euo pipefail

runner=/usr/local/libexec/fedora44-ai/apply-contributions
[ -x "$runner" ] || {
    echo "Base contribution runner is missing: $runner" >&2
    exit 1
}
exec "$runner" "$@"
