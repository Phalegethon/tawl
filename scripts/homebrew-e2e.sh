#!/bin/bash
# Destructive installation tests are confined to disposable GitHub-hosted runners.
set -euo pipefail

if [[ ${GITHUB_ACTIONS:-} != true || ${RUNNER_ENVIRONMENT:-} != github-hosted || ${RUNNER_OS:-} != macOS ]]; then
  echo "This test only runs on disposable GitHub-hosted macOS runners." >&2
  exit 2
fi

version=${REQUESTED_VERSION:-${PUBLISHED_TAG#v}}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
test "$(uname -m)" = "$EXPECTED_ARCHITECTURE"
test "$version" != 0.1.0
root=$(cd "$(dirname "$0")/.." && pwd)
evidence="$RUNNER_TEMP/tawl-homebrew-e2e"
mkdir -p "$evidence"
exec > >(tee "$evidence/commands.log") 2>&1

# Never shadow a pre-existing installation or rely on ./tawl in the checkout.
if command -v tawl >/dev/null 2>&1; then
  echo "Expected a clean runner without tawl on PATH." >&2
  exit 1
fi
if brew tap | /usr/bin/grep -qx 'phalegethon/tawl'; then
  echo "Expected a clean runner without the TAWL tap." >&2
  exit 1
fi
cd "$RUNNER_TEMP"

echo "::group::README fresh installation"
brew tap phalegethon/tawl https://github.com/Phalegethon/tawl
brew install phalegethon/tawl/tawl
brew readall --os=all --arch=all phalegethon/tawl
prefix=$(brew --prefix)
tap=$(brew --repo phalegethon/tawl)
current_tap_commit=$(git -C "$tap" rev-parse HEAD)
printf 'Published tap commit: %s\n' "$current_tap_commit"
test "$(git -C "$tap" branch --show-current)" = main
test -z "$(git -C "$tap" status --porcelain)"

check_install() {
  local scenario=$1
  test "$(command -v tawl)" = "$prefix/bin/tawl"
  test "$(tawl --version)" = "tawl $version"
  brew test phalegethon/tawl/tawl
  brew list --versions phalegethon/tawl/tawl
  python3 "$root/Tests/Interaction/installed_tui_pty.py" \
    --expected-version "$version" --expected-architecture "$EXPECTED_ARCHITECTURE" \
    --brew-prefix "$prefix" --output "$evidence/$scenario"
  tawl status --sample 0.1s
}

check_install fresh-install
tawl update check
echo "::endgroup::"

# The baseline is the official 0.1.0 formula after its Homebrew 7 fix.
# Only this disposable runner's tap checkout is moved; no remote ref is changed.
baseline_commit=6eecd0e5f7db5de3272d340c299abaed73632084
seed_previous_release() {
  local restore_commit
  test "$(git -C "$tap" branch --show-current)" = main
  restore_commit=$(git -C "$tap" rev-parse HEAD)
  # Upgrades may retain an unlinked old keg; remove all TAWL versions before
  # reseeding so the next install really starts from the historical release.
  brew uninstall --force phalegethon/tawl/tawl
  test ! -d "$prefix/Cellar/tawl"
  git -C "$tap" fetch --depth=1 origin "$baseline_commit"
  git -C "$tap" checkout --detach "$baseline_commit"
  brew install phalegethon/tawl/tawl
  test "$(tawl --version)" = 'tawl 0.1.0'
  test "$(/usr/bin/lipo -archs "$(command -v tawl)")" = "$EXPECTED_ARCHITECTURE"
  git -C "$tap" checkout main
  test "$(git -C "$tap" rev-parse HEAD)" = "$restore_commit"
  printf 'Upgrade baseline installed: %s\n' "$(tawl --version)"
}

echo "::group::README brew upgrade from 0.1.0"
seed_previous_release
brew update
brew upgrade phalegethon/tawl/tawl
check_install brew-upgrade
echo "::endgroup::"

echo "::group::TAWL-managed Homebrew update from 0.1.0"
seed_previous_release
tawl update check
# The released updater requires a terminal and an explicit confirmation.
python3 "$root/Tests/Interaction/installed_tui_pty.py" \
  --confirm-update --previous-version 0.1.0 \
  --expected-version "$version" --expected-architecture "$EXPECTED_ARCHITECTURE" \
  --brew-prefix "$prefix" --output "$evidence/tawl-update-confirmation"
check_install tawl-update
tawl update check
echo "::endgroup::"

printf 'PASS: %s fresh install, brew upgrade and tawl update -> %s; bare tawl opens and exits in every scenario.\n' \
  "$EXPECTED_ARCHITECTURE" "$version" | tee "$evidence/result.txt"
