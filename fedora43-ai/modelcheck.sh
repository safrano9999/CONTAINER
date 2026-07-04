#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
set -a
source "$SCRIPT_DIR/.env"
set +a

PYTHONPATH="$SCRIPT_DIR/SCRIPTS/safrano9999${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
from python_header import openai_v1_models, openai_v1_providers

for provider in openai_v1_providers():
    label = provider.provider or provider.key
    for model in openai_v1_models(provider):
        print(f"{label}\t{model}")
PY
