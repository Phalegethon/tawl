#!/bin/bash
set -euo pipefail
fail() { printf 'tawl draft release: %s\n' "$*" >&2; exit 1; }
tag=''
commit=''
assets=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" ]] || fail 'expected --tag vX.Y.Z --commit SHA --assets DIR'
  case "$1" in
    --tag) tag=$2 ;;
    --commit) commit=$2 ;;
    --assets) assets=$2 ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$commit" =~ ^[a-f0-9]{40}$ && -d "$assets" ]] || fail 'provide a stable version tag, full commit SHA and assets directory'
version=${tag#v}
for item in "tawl-$version-macos-arm64" "tawl-$version-macos-arm64.tar.gz" \
            "tawl-$version-macos-x86_64" "tawl-$version-macos-x86_64.tar.gz" \
            SHA256SUMS tawl.rb LICENSE SIGNING-arm64.txt SIGNING-x86_64.txt release-notes.md; do
  [[ -f "$assets/$item" ]] || fail "missing release file: $item"
done

# A draft may be refreshed, but an existing tag must still identify the build.
# Fetch only into FETCH_HEAD so a checkout's lightweight tag stays untouched.
# Peel the retrieved remote object, which may be an annotated tag, to its commit.
tag_reference=$(git ls-remote --tags origin "refs/tags/$tag")
if [[ -n "$tag_reference" ]]; then
  git fetch --no-tags origin "refs/tags/$tag"
  [[ $(git rev-parse "FETCH_HEAD^{commit}") == "$commit" ]] || fail 'existing tag does not point to the commit used for these binaries'
fi
metadata=$(mktemp)
trap 'rm -f "$metadata"' EXIT
if gh release view "$tag" --json isDraft > "$metadata" 2>/dev/null; then
  [[ $(/usr/bin/plutil -extract isDraft raw -o - "$metadata") == true ]] || fail 'published releases are immutable; use a new version'
  # For a draft whose tag is not created yet, align its future tag with the build.
  gh release edit "$tag" --draft --target "$commit" --title "TAWL $tag" --notes-file "$assets/release-notes.md"
else
  gh release create "$tag" --draft --target "$commit" --title "TAWL $tag" --notes-file "$assets/release-notes.md"
fi
gh release upload "$tag" \
  "$assets/tawl-$version-macos-arm64" "$assets/tawl-$version-macos-arm64.tar.gz" \
  "$assets/tawl-$version-macos-x86_64" "$assets/tawl-$version-macos-x86_64.tar.gz" \
  "$assets/SHA256SUMS" "$assets/tawl.rb" "$assets/LICENSE" "$assets/SIGNING-arm64.txt" "$assets/SIGNING-x86_64.txt" --clobber
printf 'Draft prepared. Publishing requires maintainer review in GitHub Releases.\n'
