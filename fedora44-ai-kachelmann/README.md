# fedora44-ai-kachelmann

`ghcr.io/safrano9999/fedora44-ai-kachelmann` is a private image built directly
from `fedora44-ai-base`. It adds only the KACHELMANN repository, its Python
requirements, OpenClaw and Hermes integrations, and the WebUI/MCP services.

The cumulative `fedora44-ai-kachelmann.*_example` triple is generated from the
Kachelmann additional triple, the current Base triple, and KACHELMANN's latest
example asset. `setup.sh` uses those local files directly. Generated instances
live below `CONTAINER/<name>/`; examples are symlinked and shared setup files
are hardlinked.

With SQLite selected, setup creates a dedicated KACHELMANN SQLite volume. When
`KACHELMANN_PERSISTENT=true`, mutable content below
`KACHELMANN/OBSIDIAN/KACHELMANN` is projected from a second named volume. The
application and plugin code remain immutable in the image.

Use `./setup.sh` for an instance, `./build-local.sh` for a local image, or the
`fedora44-ai-kachelmann-image.yml` workflow for the private GHCR image.
