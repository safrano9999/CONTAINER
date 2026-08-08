# fedora44-ai-base

`ghcr.io/safrano9999/fedora44-ai-base` is built directly from
`fedora44-ai-core`. Its Containerfile adds only the five repositories listed in
`image/contributions.tsv`, their requirements, Base services, and the Base
OpenClaw contribution hook.

`prepare-build-context.sh` stages those repositories plus
`safrano9999-paper` into the ignored `safrano9999/` directory and records
immutable source commits. The Containerfile retains the paper source and links
its versioned `paper.pdf` into the ephemeral `/README` directory. The
contribution runner is deterministic and idempotent; it does not clone or
download during the image build.

Each listed repository may own an optional `fedora44-ai-container/` directory.
The contribution runner applies it in this fixed order:

1. `rootfs/` is copied onto the image root.
2. Units in `systemd/` are installed and their `[Install] WantedBy=` links are
   created.
3. Executable `.sh` or `.py` files from `runtime.d/` are installed into the
   Core init directory with a repository-name prefix.
4. Executable `.sh` or `.py` files from `build.d/` run lexically with
   `FEDORA44_AI_REPOSITORY_DIR` and `FEDORA44_AI_IMAGE_ROOT`.

Symlinks, special files, unsafe names, unsupported executable types, and
non-executable hooks fail the image build.

The cumulative `fedora44-ai-base.*_example` triple is generated from the
Base additional triple, the current Core triple, and the repositories listed
in `fedora44-ai-base-additional.repos`. `setup.sh` uses those local files
directly and keeps generated instances below `CONTAINER/<name>/`; it performs
no example download or merge. Use `--config-only`, `--pull`, or `--build`.
