# fedora44-ai-safrano9999

Private runtime configuration for `ghcr.io/safrano9999/fedora44-ai-safrano9999`.

`setup.sh` manages any number of full Safrano container instances below `CONTAINER/<name>/`. Its merged environment, config, container, Compose and Quadlet behavior matches the former full `fedora44-ai` setup. Every normal setup run asks whether to pull the private GHCR image or build it locally through the sibling `fedora44-ai` build repository. `--pull` and `--build` are the explicit non-interactive alternatives.

Setup pulls and distills the complete `fedora44-ai-base` examples first. The local variant examples contain only Safrano-specific overrides and additions.
