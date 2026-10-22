#!/bin/bash
set -euo pipefail

fail() { printf 'tawl install: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s [--prefix PATH] [--binary PATH]\n' "$0"; }
script_dir=$(cd "$(dirname "$0")" && pwd -P)
prefix=${PREFIX:-"$HOME/.local"}
binary="$script_dir/tawl"
if [[ ! -f "$binary" && -f "$script_dir/../tawl" ]]; then binary="$script_dir/../tawl"; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|--binary)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a path"
      if [[ "$1" == --prefix ]]; then prefix=$2; else binary=$2; fi
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
done

[[ $(uname -s) == Darwin ]] || fail 'macOS 15 or newer is required'
os_version=$(sw_vers -productVersion)
[[ ${os_version%%.*} -ge 15 ]] || fail 'macOS 15 or newer is required'
architecture=$(uname -m)
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || fail "unsupported architecture: $architecture"
[[ "$prefix" == /* ]] || prefix="$(pwd -P)/$prefix"
while [[ "$prefix" == */ && "$prefix" != / ]]; do prefix=${prefix%/}; done
[[ "$prefix" != / ]] || fail 'choose an installation prefix other than /'
case "$prefix/" in */../*|*/./*) fail 'prefix must not contain . or .. path components' ;; esac

no_symlinks() {
  local path=$1
  while [[ "$path" != / && -n "$path" ]]; do
    [[ ! -L "$path" ]] || fail "refusing symbolic link: $path"
    path=${path%/*}
  done
}
native_binary() {
  local description
  [[ -f "$1" && ! -L "$1" ]] || fail "not a regular binary: $1"
  description=$(/usr/bin/file -b "$1")
  [[ "$description" == *Mach-O* && "$description" == *"$architecture"* ]] || fail "binary is not a macOS $architecture executable: $1"
}
owned_receipt() {
  [[ -f "$receipt" && ! -L "$receipt" ]] || fail "existing installation has no ownership receipt: $receipt"
  [[ $(/usr/bin/plutil -extract schemaVersion raw -o - "$receipt" 2>/dev/null) == 1 &&
     $(/usr/bin/plutil -extract method raw -o - "$receipt" 2>/dev/null) == standalone &&
     $(/usr/bin/plutil -extract repository raw -o - "$receipt" 2>/dev/null) == Phalegethon/tawl ]] || fail "receipt does not identify this standalone TAWL installation"
}
product_version() {
  local output
  output=$("$1" --version) || fail "binary could not report its version: $1"
  [[ "$output" =~ ^tawl\ [0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || fail "binary does not identify itself as tawl: $1"
  printf '%s' "$output"
}

target="$prefix/bin/tawl"
receipt="$prefix/share/tawl/install.json"
no_symlinks "$target"
no_symlinks "$receipt"
native_binary "$binary"
if [[ -e "$target" ]]; then
  owned_receipt
  native_binary "$target"
  product_version "$target" >/dev/null
elif [[ -e "$receipt" ]]; then
  owned_receipt
fi

mkdir -p "$prefix/bin" "$prefix/share/tawl"
stage=$(mktemp "$prefix/bin/.tawl.install.XXXXXX")
receipt_stage=''
created_receipt=0
installed=0
cleanup() {
  rm -f "$stage"
  [[ -z "$receipt_stage" ]] || rm -f "$receipt_stage"
  if [[ "$created_receipt" == 1 && "$installed" == 0 ]]; then rm -f "$receipt"; fi
}
trap cleanup EXIT
cp "$binary" "$stage"
chmod 755 "$stage"
version=$(product_version "$stage")
if [[ ! -e "$receipt" ]]; then
  receipt_stage=$(mktemp "$prefix/share/tawl/.install.json.XXXXXX")
  printf '{"schemaVersion":1,"method":"standalone","repository":"Phalegethon/tawl"}\n' > "$receipt_stage"
  chmod 644 "$receipt_stage"
  mv -f "$receipt_stage" "$receipt"
  created_receipt=1
fi
# Same-directory rename keeps readers on either the old or complete new binary.
mv -f "$stage" "$target"
installed=1
printf 'Installed %s at %s\n' "$version" "$target"
case ":${PATH:-}:" in
  *":$prefix/bin:"*) ;;
  *) # The printed command must expand PATH in the user's shell, not here.
     # shellcheck disable=SC2016
     printf 'To use tawl in this shell, run:\n  export PATH=%q:"$PATH"\n' "$prefix/bin"
     printf 'To keep it available, add that line to your shell configuration. No shell files were changed.\n' ;;
esac
