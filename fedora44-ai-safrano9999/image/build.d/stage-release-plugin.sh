#!/usr/bin/env bash
set -euo pipefail

repository="${1:?missing repository}"
asset="${2:?missing asset name}"
target="${3:?missing target directory}"

[[ "$repository" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || {
    echo "Invalid release repository: $repository" >&2
    exit 2
}
[[ "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*[.]zip$ ]] || {
    echo "Invalid release asset: $asset" >&2
    exit 2
}
command -v gh >/dev/null 2>&1 || {
    echo "GitHub CLI is required for release plugin staging" >&2
    exit 1
}
gh auth status --hostname github.com >/dev/null 2>&1 || {
    echo "GitHub CLI authentication is required for release plugin staging" >&2
    exit 1
}

temporary="$(mktemp -d "${TMPDIR:-/tmp}/fedora-release-plugin.XXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
download="$temporary/download"
extract="$temporary/extract"
mkdir -p "$download" "$extract"

gh release download \
    --repo "$repository" \
    --pattern "$asset" \
    --pattern "$asset.sha256" \
    --dir "$download"
[ -f "$download/$asset" ] && [ -f "$download/$asset.sha256" ] || {
    echo "Release assets are incomplete: $repository/$asset" >&2
    exit 1
}
expected="$(awk 'NR == 1 {print $1; exit}' "$download/$asset.sha256")"
[[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "Invalid release checksum: $repository/$asset.sha256" >&2
    exit 1
}
printf '%s  %s\n' "$expected" "$asset" |
    (cd "$download" && sha256sum --check --status -) || {
        echo "Release checksum mismatch: $repository/$asset" >&2
        exit 1
    }

payload="$(python3 - "$download/$asset" "$extract" <<'PY'
from pathlib import Path, PurePosixPath
import stat
import sys
from zipfile import BadZipFile, ZipFile

archive_path = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()
limit = 2 * 1024 * 1024 * 1024

try:
    with ZipFile(archive_path) as archive:
        entries = archive.infolist()
        if not entries:
            raise ValueError("release archive is empty")
        seen: set[str] = set()
        total = 0
        for entry in entries:
            path = PurePosixPath(entry.filename)
            parts = path.parts
            if (
                not entry.filename
                or "\\" in entry.filename
                or path.is_absolute()
                or not parts
                or any(part in {"", ".", ".."} for part in parts)
                or ".git" in parts
            ):
                raise ValueError(f"unsafe archive path: {entry.filename!r}")
            normalized = "/".join(parts)
            if normalized in seen:
                raise ValueError(f"duplicate archive path: {entry.filename!r}")
            seen.add(normalized)
            file_type = stat.S_IFMT(entry.external_attr >> 16)
            if file_type not in {0, stat.S_IFREG, stat.S_IFDIR}:
                raise ValueError(f"unsupported archive entry: {entry.filename!r}")
            if entry.flag_bits & 0x1:
                raise ValueError(f"encrypted archive entry: {entry.filename!r}")
            total += entry.file_size
            if total > limit:
                raise ValueError("release archive exceeds extraction limit")
        archive.extractall(destination)
except (BadZipFile, OSError, ValueError) as error:
    raise SystemExit(f"Invalid release plugin archive: {error}") from error

children = list(destination.iterdir())
payload = children[0] if len(children) == 1 and children[0].is_dir() else destination
if not (payload / "openclaw.plugin.json").is_file():
    raise SystemExit("Release asset is not an OpenClaw plugin")
print(payload)
PY
)"

python3 -m json.tool "$payload/openclaw.plugin.json" >/dev/null
parent="$(dirname -- "$target")"
mkdir -p "$parent"
staged="$parent/.${target##*/}.release-stage"
rm -rf -- "$staged"
mv -- "$payload" "$staged"
rm -rf -- "$target"
mv -- "$staged" "$target"
printf '  [%s] staged release asset %s\n' "${repository##*/}" "$asset"
