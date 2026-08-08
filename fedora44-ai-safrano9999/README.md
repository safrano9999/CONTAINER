# fedora44-ai-safrano9999

`ghcr.io/safrano9999/fedora44-ai-safrano9999` is built directly from
`fedora44-ai-base`. `EXTENSIONS` and `STANDALONE` in `build.conf` are the only
repository lists used for source synchronization, requirements, source
manifests, and owner runtime overlays.

Preparation safely merges each selected repository's rootfs-shaped
`image/runtime/` directory directly from the exact synchronized checkout and
generates a file manifest plus systemd enable list. Optional owner entrypoints
at `image/buildtime/host/run` and `image/buildtime/container/run` use the same
generic contract for every repository; inherited container hooks are rerun
against this layer's cumulative examples. OpenClaw manifests are discovered by
the shared Ephemeral integrator.

The VikAI bootstrap helper and service remain owned by VikAI; this layer
contains no local service or runtime copy.

The cumulative `fedora44-ai-safrano9999.*_example` triple is generated from
the Safrano additional triple, the current Base triple, and the repositories
listed in `fedora44-ai-safrano9999-additional.repos`. `setup.sh` uses those
local files directly and keeps generated instances below `CONTAINER/<name>/`;
it performs no example download or merge.
