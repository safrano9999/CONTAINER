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

IMG_CHOICE=""
SKIP_IMAGE_PROMPT=false
for argument in "$@"; do
    case "$argument" in
        --pull) IMG_CHOICE=1 ;;
        --build) IMG_CHOICE=2 ;;
        --config-only|--help|-h) SKIP_IMAGE_PROMPT=true ;;
    esac
done
if [ -z "$IMG_CHOICE" ] && ! $SKIP_IMAGE_PROMPT; then
    echo ""
    echo "  Image source:"
    echo "    (1) Pull $FEDORA_LAYER_REGISTRY_IMAGE"
    echo "    (2) Build locally [$FEDORA_LAYER_LOCAL_IMAGE]"
    read -rp "  Choose [1/2] (default: 2): " IMG_CHOICE
    IMG_CHOICE="${IMG_CHOICE:-2}"
    case "$IMG_CHOICE" in
        1) set -- "$@" --pull ;;
        2) set -- "$@" --build ;;
        *) echo "Invalid image choice: $IMG_CHOICE" >&2; exit 2 ;;
    esac
fi

exec bash "$ROOT/image/setup.d/layer-setup.sh" "$@"
