#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export FEDORA_LAYER_ROOT="$ROOT"
export FEDORA_LAYER_REGISTRY_IMAGE=ghcr.io/safrano9999/fedora44-ai-kachelmann:latest
export FEDORA_LAYER_LOCAL_IMAGE=localhost/fedora44-ai-kachelmann:latest
export FEDORA_LAYER_OUTPUT_IMAGE_KEY=FEDORA44_AI_KACHELMANN_IMAGE
export FEDORA_LAYER_DEFAULT_INSTANCE=fedora44-ai-kachelmann
export FEDORA_LAYER_EXAMPLE_DIRS="$ROOT/examples.d/core:$ROOT/examples.d/base"
export FEDORA_LAYER_REPOS=$'WELCOME\nCODEANALYST\nCITADEL\nDIESDAS-\nNEXTCLOUD\nsafrano9999-paper\nKACHELMANN'

exec bash "$ROOT/image/setup.d/layer-setup.sh" "$@"
