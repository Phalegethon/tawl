#!/bin/bash
# Destructive installation tests are confined to disposable GitHub-hosted runners.
set -Eeuo pipefail

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

capture_failure() {
  local failure_status=$1 failure_line=$2
  # Let a failed command substitution report once through its parent command.
  if (( BASH_SUBSHELL > 0 )); then exit "$failure_status"; fi
  # Diagnostics must never retry the failed test or replace its exit status.
  trap - ERR
  set +e
  local diagnostic="$evidence/github-api-diagnostic"
  local installed_version="$version" reported_version http_status curl_status
  mkdir -p "$diagnostic"
  reported_version=$(tawl --version 2>/dev/null)
  if [[ "$reported_version" =~ ^tawl\ ([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    installed_version=${BASH_REMATCH[1]}
  fi
  # -q disables curlrc; no token or Authorization header is supplied. Match the
  # released updater's endpoint and headers, and retain at most 64 KiB of body.
  /usr/bin/curl -q --silent --show-error --connect-timeout 12 --max-time 35 \
    --header "User-Agent: tawl/$installed_version" \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --dump-header "$diagnostic/headers.txt" \
    https://api.github.com/repos/Phalegethon/tawl/releases/latest \
    2> "$diagnostic/curl-error.txt" | /usr/bin/head -c 65536 > "$diagnostic/body.txt"
  curl_status=${PIPESTATUS[0]}
  http_status=$(/usr/bin/awk 'toupper($1) ~ /^HTTP\// { code=$2 } END { print (code == "" ? "000" : code) }' "$diagnostic/headers.txt")
  {
    printf 'failed_exit_status=%s\nfailed_line=%s\n' "$failure_status" "$failure_line"
    printf 'user_agent=tawl/%s\nhttp_status=%s\ncurl_exit_status=%s\n' "$installed_version" "$http_status" "$curl_status"
    printf 'body_limit_bytes=65536\n'
  } > "$diagnostic/status.txt"
  echo '::group::GitHub API failure diagnostic (separate unauthenticated request)'
  cat "$diagnostic/status.txt"
  /usr/bin/grep -Ei '^(HTTP/|x-ratelimit-[^:]*:|retry-after:|x-github-request-id:)' "$diagnostic/headers.txt"
  /usr/bin/head -c 4096 "$diagnostic/body.txt"
  printf '\n'
  cat "$diagnostic/curl-error.txt"
  echo '::endgroup::'
  exit "$failure_status"
}
trap 'capture_failure "$?" "$LINENO"' ERR

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
tawl update check
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
