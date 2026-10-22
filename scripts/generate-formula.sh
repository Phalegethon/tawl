#!/bin/bash
set -euo pipefail
fail() { printf 'tawl formula: %s\n' "$*" >&2; exit 1; }
version=''
checksums=''
output=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" ]] || fail 'expected --version VERSION --checksums FILE --output FILE'
  case "$1" in
    --version) version=$2 ;;
    --checksums) checksums=$2 ;;
    --output) output=$2 ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'provide a stable semantic version'
[[ -f "$checksums" && -n "$output" ]] || fail 'provide checksums and output paths'
arm_sha=''
intel_sha=''
while read -r digest asset extra; do
  [[ -z "$extra" ]] || fail 'checksum entries must contain a digest and asset name only'
  case "$asset" in
    "tawl-$version-macos-arm64.tar.gz") [[ -z "$arm_sha" ]] || fail 'duplicate arm64 checksum'; arm_sha=$digest ;;
    "tawl-$version-macos-x86_64.tar.gz") [[ -z "$intel_sha" ]] || fail 'duplicate x86_64 checksum'; intel_sha=$digest ;;
  esac
done < "$checksums"
[[ "$arm_sha" =~ ^[a-f0-9]{64}$ && "$intel_sha" =~ ^[a-f0-9]{64}$ ]] || fail 'both architecture archive checksums are required'
mkdir -p "$(dirname "$output")"
stage=$(mktemp "$(dirname "$output")/.tawl-formula.XXXXXX")
trap 'rm -f "$stage"' EXIT
cat > "$stage" <<EOF
# Generated from the checksums of the final release assets.
class Tawl < Formula
  desc "macOS terminal system monitor and flight recorder"
  homepage "https://github.com/Phalegethon/tawl"
  version "$version"
  license "MIT"

  depends_on :macos

  on_macos do
    depends_on macos: :sequoia
  end

  on_arm do
    url "https://github.com/Phalegethon/tawl/releases/download/v$version/tawl-$version-macos-arm64.tar.gz"
    sha256 "$arm_sha"
  end

  on_intel do
    url "https://github.com/Phalegethon/tawl/releases/download/v$version/tawl-$version-macos-x86_64.tar.gz"
    sha256 "$intel_sha"
  end

  def install
    bin.install "tawl"
    pkgshare.install "LICENSE"
  end

  test do
    assert_equal "tawl #{version}", shell_output("#{bin}/tawl --version").strip
  end
end
EOF
mv -f "$stage" "$output"
printf 'Generated %s for v%s\n' "$output" "$version"
