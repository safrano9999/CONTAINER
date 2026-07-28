# fedora44-ai-base

Private runtime configuration for `ghcr.io/safrano9999/fedora44-ai-base`.

`setup.sh` manages any number of Base container instances below `CONTAINER/<name>/` and merges the shared Base examples on every run. Every normal setup run asks whether to pull the private GHCR image or build it locally through the sibling `fedora44-ai` build repository. `--pull` and `--build` are the explicit non-interactive alternatives.
