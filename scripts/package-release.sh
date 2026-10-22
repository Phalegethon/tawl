#!/bin/bash
set -euo pipefail
fail() { printf 'tawl package: %s\n' "$*" >&2; exit 1; }
script_dir=$(cd "$(dirname "$0")" && pwd -P)
binary="$script_dir/../tawl"
output="$script_dir/../work/release"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary|--output)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a path"
      if [[ "$1" == --binary ]]; then binary=$2; else output=$2; fi
      shift 2 ;;
    --help|-h) printf 'Usage: %s [--binary PATH] [--output DIR]\n' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ $(uname -s) == Darwin ]] || fail 'release packaging requires macOS 15 or newer'
os_version=$(sw_vers -productVersion)
[[ ${os_version%%.*} -ge 15 ]] || fail 'release packaging requires macOS 15 or newer'
architecture=$(uname -m)
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || fail "unsupported architecture: $architecture"
[[ -f "$binary" && -x "$binary" && ! -L "$binary" ]] || fail 'provide a regular executable build with --binary'
description=$(/usr/bin/file -b "$binary")
[[ "$description" == *Mach-O* && "$description" == *"$architecture"* ]] || fail 'binary does not match the host macOS architecture'
version_output=$("$binary" --version)
[[ "$version_output" =~ ^tawl\ ([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?)$ ]] || fail 'binary --version must report tawl followed by a semantic version'
version=${BASH_REMATCH[1]}
stem="tawl-$version-macos-$architecture"
mkdir -p "$output"
output=$(cd "$output" && pwd -P)
[[ ! -e "$output/$stem" && ! -e "$output/$stem.tar.gz" ]] || fail 'release asset already exists; choose a fresh output directory'
stage=$(mktemp -d "$output/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp "$binary" "$stage/tawl"
chmod 755 "$stage/tawl"
cp "$script_dir/install.sh" "$script_dir/uninstall.sh" "$stage/"
cp "$script_dir/../LICENSE" "$stage/LICENSE"
chmod 755 "$stage/install.sh" "$stage/uninstall.sh"
cat > "$stage/README.txt" <<EOF
TAWL $version — macOS 15 or newer, $architecture

Verify this archive against SHA256SUMS from the same release before extracting.
Install: ./install.sh
Custom prefix: ./install.sh --prefix '/absolute/path with spaces'
Run: tawl
Uninstall: ./uninstall.sh --prefix '/same/installation/prefix'

Default prefix: \$HOME/.local. The installer prints PATH setup when needed and
does not modify shell configuration. Uninstall preserves recordings.

Release notes state whether this build is Developer ID signed and notarized.
An ad-hoc build is not Developer ID signed or notarized; macOS may block it.
Respect macOS security prompts. No quarantine or Gatekeeper bypass is included.

Source and documentation: https://github.com/Phalegethon/tawl
License: MIT. Keep the accompanying LICENSE notice with redistributed copies.
EOF
cp "$stage/tawl" "$output/$stem"
cp "$stage/LICENSE" "$output/LICENSE"
tar -czf "$output/$stem.tar.gz" -C "$stage" tawl install.sh uninstall.sh README.txt LICENSE
(cd "$output" && shasum -a 256 "$stem" "$stem.tar.gz" LICENSE) > "$output/SHA256SUMS"
printf 'Packaged %s\n' "$output/$stem"
