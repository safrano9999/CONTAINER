#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export FEDORA_LAYER_ROOT="$ROOT"
export FEDORA_LAYER_REGISTRY_IMAGE=ghcr.io/safrano9999/fedora44-ai-safrano9999:latest
export FEDORA_LAYER_LOCAL_IMAGE=localhost/fedora44-ai-safrano9999:latest
export FEDORA_LAYER_OUTPUT_IMAGE_KEY=FEDORA44_AI_SAFRANO9999_IMAGE
export FEDORA_LAYER_DEFAULT_INSTANCE=fedora44-ai-safrano9999
export FEDORA_LAYER_EXAMPLE_DIRS="$ROOT/examples.d/core:$ROOT/examples.d/base"
export FEDORA_LAYER_REPOS=$'JUGO\nVikAI\nPV_D-A-CH\nKIWIX_BRIDGE\nNAPOLEON_HILLS_AI_MASTERMIND_CLASSES\nSOLANA_AIRGAPPED_DEBIAN_WORKFLOW\nNaturalGrounding-Tiktok-Ying-Video-Manager@feature/webui-db-backend-dual\nDAILYNEWS\nZEROINBOX\nSPANKER\nKACHELMANN'

exec bash "$ROOT/image/setup.d/layer-setup.sh" "$@"
