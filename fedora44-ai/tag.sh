#!/usr/bin/env bash
set -euo pipefail

remote="${REMOTE:-origin}"
workflow="image.yml"
latest_tag="latest"
month_prefix="$(date +%Y.%-m)"

monthly_tag() {
  local mode="$1" refs ref suffix number highest=0

  refs="$(git ls-remote --tags --refs "$remote" "refs/tags/${month_prefix}.*")"
  while read -r _ ref; do
    suffix="${ref#refs/tags/${month_prefix}.}"
    [[ "$suffix" =~ ^[0-9]+$ ]] || continue
    number=$((10#$suffix))
    ((number > highest)) && highest="$number"
  done <<< "$refs"
  if [ "$mode" = check ] && ((highest > 0)); then
    printf '%s.%d\n' "$month_prefix" "$highest"
  else
    printf '%s.%d\n' "$month_prefix" "$((highest + 1))"
  fi
}

select_scope() {
  local requested="${1:-}" answer

  case "$requested" in
    safrano9999|safrano|saf) printf 'safrano9999\n' ;;
    base) printf 'base\n' ;;
    all) printf 'all\n' ;;
    "")
      printf '%s\n' \
        '  Build:' \
        '    (1) Safrano layer only' \
        '    (2) Base + Safrano layer' \
        '    (3) Base layer only' >&2
      read -rp '  Choose [1-3] (default: 1): ' answer
      case "${answer:-1}" in
        1) printf 'safrano9999\n' ;;
        2) printf 'all\n' ;;
        3) printf 'base\n' ;;
        *) echo "Invalid build choice: $answer" >&2; return 2 ;;
      esac
      ;;
    *) echo "Usage: ./tag.sh [safrano9999|base|all|--check]" >&2; return 2 ;;
  esac
}

command -v gh >/dev/null || { echo 'gh is required' >&2; exit 1; }
gh auth status --hostname github.com >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https

if [ "${1:-}" = "--check" ]; then
  tag="$(monthly_tag check)"
  gh run list --workflow "$workflow" --branch "$tag" --limit 1
  exit 0
fi

scope="$(select_scope "${1:-}")"
tag="${TAG:-$(monthly_tag next)}"
[ "$tag" != "$latest_tag" ] || { echo "$latest_tag is reserved for the moving tag" >&2; exit 2; }

git tag -d "$tag" 2>/dev/null || true
git tag "$tag"
git tag -f "$latest_tag"
git push --atomic "$remote" \
  "refs/tags/$tag:refs/tags/$tag" \
  "+refs/tags/$latest_tag:refs/tags/$latest_tag"

gh workflow run "$workflow" --ref "$tag" \
  -f "image_tag=$tag" \
  -f "build_scope=$scope" \
  -f push_latest=true
printf 'Tagged %s; dispatched %s build\n' "$tag" "$scope"
