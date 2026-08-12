# fedora44-ai-kachelmann

`ghcr.io/safrano9999/fedora44-ai-kachelmann` is a private image built directly
from `fedora44-ai-base`. It adds only the KACHELMANN repository, its Python
requirements, and its owner-maintained `image/runtime/` rootfs overlay.
`EXTENSIONS=KACHELMANN` and the empty `STANDALONE` value in `build.conf` are the
sole repository source of truth. OpenClaw discovery is delegated to the shared
Ephemeral integrator. Preparation rejects unsafe paths, types, symlinks,
permissions, and overlay collisions, then emits the runtime file manifest and
systemd enable list directly from that exact checkout.

Optional `image/buildtime/host/run` and `image/buildtime/container/run`
entrypoints follow the same generic owner contract as every other repository.
Inherited container hooks are rerun against Kachelmann's cumulative example
triple without any repository-specific call in this layer.

The cumulative `fedora44-ai-kachelmann.*_example` triple is generated from the
Kachelmann additional triple, the current Base triple, and KACHELMANN's latest
example asset. `setup.sh` uses those local files directly. Generated instances
live below `CONTAINER/<name>/`; examples are symlinked and shared setup files
are hardlinked.

With SQLite selected, setup creates a dedicated KACHELMANN SQLite volume.
Mutable Markdown, images, and document uploads use
`${CONTAINER_NAME}-kachelmann`, mounted at `/var/lib/kachelmann:z`; the runtime
path is always `/var/lib/kachelmann/content`. The lowercase `z` is intentional:
the matching `kachelmann-mcp` sidecar must mount that exact named volume too.
`KACHELMANN_CONTENT_GID=10001` gives both processes the shared 2770/0660 group
contract. Fresh instances default to `${CONTAINER_NAME}-kachelmann`. The
existing SSH-1 installation already owns the normalized legacy volume
`fedora44-ai-ssh-1-kachelmann`; set that exact value during migration so its
content is reused. A `fedora44-ai-safrano9999-ucore` instance uses
`fedora44-ai-safrano9999-ucore-kachelmann`.

Use `./setup.sh` for an instance, `./build/build-local.sh` for a local image, or the
`fedora44-ai-kachelmann-image.yml` workflow for the private GHCR image.
