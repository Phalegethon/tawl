#!/bin/bash
set -euo pipefail
fail() { printf 'tawl uninstall: %s\n' "$*" >&2; exit 1; }
prefix=${PREFIX:-"$HOME/.local"}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) [[ $# -ge 2 && -n "$2" ]] || fail '--prefix requires a path'; prefix=$2; shift 2 ;;
    --help|-h) printf 'Usage: %s [--prefix PATH]\n' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ $(uname -s) == Darwin ]] || fail 'this uninstaller requires macOS'
[[ "$prefix" == /* ]] || prefix="$(pwd -P)/$prefix"
while [[ "$prefix" == */ && "$prefix" != / ]]; do prefix=${prefix%/}; done
[[ "$prefix" != / ]] || fail 'refusing prefix /'
case "$prefix/" in */../*|*/./*) fail 'prefix must not contain . or .. path components' ;; esac
target="$prefix/bin/tawl"
receipt="$prefix/share/tawl/install.json"
for checked in "$target" "$receipt"; do
  while [[ "$checked" != / && -n "$checked" ]]; do
    [[ ! -L "$checked" ]] || fail "refusing symbolic link: $checked"
    checked=${checked%/*}
  done
done
[[ -f "$receipt" && -f "$target" ]] || fail 'no complete standalone installation exists at this prefix'
[[ $(/usr/bin/plutil -extract schemaVersion raw -o - "$receipt" 2>/dev/null) == 1 &&
   $(/usr/bin/plutil -extract method raw -o - "$receipt" 2>/dev/null) == standalone &&
   $(/usr/bin/plutil -extract repository raw -o - "$receipt" 2>/dev/null) == Phalegethon/tawl ]] || fail 'receipt does not identify this standalone TAWL installation'
description=$(/usr/bin/file -b "$target")
[[ "$description" == *Mach-O* && "$description" == *"$(uname -m)"* ]] || fail 'installed file is not a native macOS executable'
version=$("$target" --version) || fail 'installed binary could not report its version'
[[ "$version" =~ ^tawl\ [0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || fail 'installed binary does not identify itself as tawl'
rm "$target"
rm "$receipt"
# Remove only empty directories; recordings and all other user files stay intact.
rmdir "$prefix/share/tawl" 2>/dev/null || true
printf 'Removed %s from %s. User recordings and shell configuration were preserved.\n' "$version" "$prefix"
