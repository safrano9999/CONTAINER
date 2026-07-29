# fedora44-ai-base

`ghcr.io/safrano9999/fedora44-ai-base` is built directly from
`fedora44-ai-core`. Its Containerfile adds only the five repositories listed in
`image/contributions.tsv`, their requirements, Base services, and the Base
OpenClaw contribution hook.

`prepare-build-context.sh` stages those repositories into the ignored
`safrano9999/` directory and records immutable source commits. The contribution
runner is deterministic and idempotent; it does not clone or download during
the image build.

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

The example cascade is `examples.d/core` followed by the small Base-owned
examples in this directory. `setup.sh` stages only Base sources and keeps
generated instances below `CONTAINER/<name>/`. Use `--offline --config-only`
to render from already staged sources, or select `--pull`/`--build`
noninteractively.

Run the whole Fedora chain check from
`../fedora44-ai-core/tests/check-build-context.sh`.
