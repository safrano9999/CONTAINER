# fedora44-ai-safrano9999

`ghcr.io/safrano9999/fedora44-ai-safrano9999` is built directly from
`fedora44-ai-base`. Its Containerfile adds only the eleven repositories listed
in `image/contributions.tsv`, their requirements and services, and the final
OpenClaw contribution hook.

Repositories use the same optional, fail-closed `fedora44-ai-container/`
contract documented by the Base layer for build, rootfs, systemd, and runtime
contributions.

The VikAI bootstrap is a separate oneshot service ordered after the fresh
Core OpenClaw configuration and before the Safrano contribution hook. Partial
VikAI token configuration fails explicitly; no tokens make it a no-op.

The cumulative `fedora44-ai-safrano9999.*_example` triple is generated from
the Safrano additional triple, the current Base triple, and the repositories
listed in `fedora44-ai-safrano9999-additional.repos`. `setup.sh` uses those
local files directly and keeps generated instances below `CONTAINER/<name>/`;
it performs no example download or merge.
