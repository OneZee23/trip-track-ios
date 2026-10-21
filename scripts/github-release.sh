#!/bin/zsh
# Publish a GitHub release for a version that is already live on the App Store.
#
#   scripts/github-release.sh 0.9.1 <commit-the-archive-was-built-from> ["Title suffix"]
#
# Tags the commit (vX.Y.Z), pushes ONLY that tag (never --mirror: refs/t3 must
# stay local) and creates the release from the matching CHANGELOG section,
# marked Latest. Add an English summary afterwards with `gh release edit`.
set -euo pipefail
version=$1; commit=$2; suffix=${3:-}
tag="v$version"
cd "$(dirname "$0")/.."
section=$(awk -v v="$version" '
  $0 ~ "^## \\[?" v "[] ]" { on = 1; next }
  on && /^## / { exit }
  on { print }' CHANGELOG.md)
[[ -n "$section" ]] || { echo "No CHANGELOG section for $version" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git tag -a "$tag" "$commit" -m "$tag"
git push origin "refs/tags/$tag"
notes=$(mktemp)
printf '%s\n\n---\n[App Store](https://apps.apple.com/app/triptrack-road-journal/id6760650361) · [trip-track.app](https://trip-track.app)\n' "$section" > "$notes"
title="$version${suffix:+ — $suffix}"
gh release create "$tag" --verify-tag --latest --title "$title" --notes-file "$notes"
rm -f "$notes"
