#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="$ROOT/image/runtime.d/rootfs"
HOOK_ROOT="$RUNTIME_ROOT/usr/local/share/openclaw-ephemeral/runtime.d"

mapfile -d '' shell_files < <(
  find "$ROOT/setup-lib" "$ROOT/image" -type f \
    \( -name '*.sh' -o -name 'safrano9999-routines' -o -name 'openclaw-crontabs' \) \
    -print0
)
shell_files+=("$ROOT/setup.sh" "$0")
for file in "${shell_files[@]}"; do bash -n "$file"; done

for file in \
  config.sh \
  merge.sh \
  quadlet_finish.py \
  container_instance.py \
  optional_persistence.sh \
  sqlite_persistence.sh \
  image/install/github_auth.sh; do
  [ -f "$ROOT/setup-lib/$file" ]
done

expected_hooks=(
  post-config.d/10-register-plugins.sh
  post-config.d/20-zeroinbox.sh
  post-config.d/30-kachelmann.sh
  post-config.d/40-citadel.sh
  pre-config.d/10-named-volumes.sh
  pre-config.d/20-tailscale.sh
  pre-gateway.d/10-schedules.sh
)
mapfile -t actual_hooks < <(
  find "$HOOK_ROOT" -mindepth 2 -maxdepth 2 -type f -printf '%P\n' | sort
)
[ "${actual_hooks[*]}" = "${expected_hooks[*]}" ]
for hook in "${actual_hooks[@]}"; do
  [ -x "$HOOK_ROOT/$hook" ]
  [[ "${hook##*/}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
done

grep -Fq 'COPY image/build.d/lib/safrano9999_plugins.py' "$ROOT/Containerfile"
grep -Fq 'COPY image/runtime.d/rootfs/ /' "$ROOT/Containerfile"
! grep -Eq '^(ENTRYPOINT|CMD)([[:space:]]|$)' "$ROOT/Containerfile"

grep -Fq 'find Containerfile requirements.txt setup-lib image -type f' "$ROOT/setup.sh"
grep -Fq $'SAFRANO9999-OPENCLAW-LOCAL\\trepo-local\\trepo-local' "$ROOT/setup.sh"
! grep -Fq 'repos/safrano9999/SCRIPTS' "$ROOT/setup.sh"
merge_line="$(grep -n 'bash "$SETUP_LIB_DIR/merge.sh"' "$ROOT/setup.sh" | cut -d: -f1)"
source_tag_line="$(grep -n '^append_repo_local_source_tag$' "$ROOT/setup.sh" | cut -d: -f1)"
[ "$merge_line" -lt "$source_tag_line" ]
grep -Fq 'podman pull --retry 10 --retry-delay 5s "$DOCKER_IO_IMAGE"' "$ROOT/setup.sh"

grep -Fq '#named-volume: /named_volumes/OPENCLAW /named_volumes/OPENCLAW/workspace /root/.openclaw/workspace dir' \
  "$ROOT/env.safrano9999-openclaw.example"
grep -Fq '#named-volume: /named_volumes/OPENCLAW /named_volumes/OPENCLAW/agents /root/.openclaw/agents dir' \
  "$ROOT/env.safrano9999-openclaw.example"

temporary="$(mktemp -d "${TMPDIR:-/tmp}/debian-note-persistence.XXXXXX")"
cleanup() {
  rm -rf -- "$temporary"
}
trap cleanup EXIT
mkdir -p "$temporary/plugin" "$temporary/releases" "$temporary/config"
printf '%s\n' \
  '{"id":"note","name":"NOTE","configSchema":{"type":"object"}}' \
  > "$temporary/plugin/openclaw.plugin.json"
printf 'NOTE_DB_BACKEND=sqlite\n' > "$temporary/plugin/env.example"
printf 'NOTE_DB_BACKEND=sqlite\n' > "$temporary/config/.env"
python3 - "$temporary/plugin" "$temporary/releases/note-latest.zip" <<'PY'
from pathlib import Path
import sys
from zipfile import ZIP_DEFLATED, ZipFile

source = Path(sys.argv[1])
with ZipFile(sys.argv[2], "w", compression=ZIP_DEFLATED) as archive:
    for path in sorted(source.iterdir()):
        archive.write(path, path.name)
PY
debian_note_mount="$(
  CONFIG_CONTAINER_NAME=debian-note \
    bash "$ROOT/setup-lib/sqlite_persistence.sh" mounts \
      --zip-root "$temporary/releases" \
      --config-dir "$temporary/config" \
      --container debian-note \
      --target-root /root/.openclaw/extensions
)"
[ "$debian_note_mount" = \
  'debian-note-note-sqlite:/root/.openclaw/extensions/note/sqlite:Z' ]

"$ROOT/setup.sh" --help >/dev/null
echo "safrano9999-openclaw repo-local static checks passed"
