#!/bin/bash
set -euo pipefail
fail() { printf 'tawl signing: %s\n' "$*" >&2; exit 1; }
binary=''
status_file=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" ]] || fail 'expected --binary PATH --status-file PATH'
  case "$1" in
    --binary) binary=$2 ;;
    --status-file) status_file=$2 ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ $(uname -s) == Darwin && -f "$binary" && ! -L "$binary" && -n "$status_file" ]] || fail 'provide a regular macOS binary and status file path'
architecture=$(uname -m)
certificate=${TAWL_SIGNING_CERTIFICATE_BASE64:-}
certificate_password=${TAWL_SIGNING_CERTIFICATE_PASSWORD:-}
identity=${TAWL_SIGNING_IDENTITY:-}
apple_id=${TAWL_APPLE_ID:-}
apple_password=${TAWL_APPLE_APP_PASSWORD:-}
team_id=${TAWL_APPLE_TEAM_ID:-}

if [[ -z "$certificate$certificate_password$identity$apple_id$apple_password$team_id" ]]; then
  /usr/bin/codesign --force --sign - "$binary"
  /usr/bin/codesign --verify --strict "$binary"
  printf '%s: ad-hoc signature; not Developer ID signed; not notarized. macOS may block downloaded builds.\n' "$architecture" > "$status_file"
  exit 0
fi
[[ -n "$certificate" && -n "$certificate_password" && "$identity" == 'Developer ID Application:'* ]] || fail 'signing needs the certificate, certificate password and Developer ID Application identity'
if [[ -n "$apple_id$apple_password$team_id" ]]; then
  [[ -n "$apple_id" && -n "$apple_password" && -n "$team_id" ]] || fail 'notarization needs all three Apple account secrets'
fi
temporary=$(mktemp -d)
keychain="$temporary/signing.keychain-db"
keychain_password=$(/usr/bin/openssl rand -base64 32)
cleanup() {
  /usr/bin/security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$temporary"
}
trap cleanup EXIT
printf '%s' "$certificate" | /usr/bin/base64 -D > "$temporary/certificate.p12"
/usr/bin/security create-keychain -p "$keychain_password" "$keychain"
/usr/bin/security set-keychain-settings -lut 3600 "$keychain"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain"
/usr/bin/security import "$temporary/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
/usr/bin/codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity" "$binary"
/usr/bin/codesign --verify --strict "$binary"
if [[ -n "$apple_id" ]]; then
  /usr/bin/ditto -c -k --keepParent "$binary" "$temporary/notarization.zip"
  xcrun notarytool submit "$temporary/notarization.zip" --apple-id "$apple_id" --password "$apple_password" --team-id "$team_id" --wait --output-format json > "$temporary/notarization.json"
  [[ $(/usr/bin/plutil -extract status raw -o - "$temporary/notarization.json") == Accepted ]] || fail 'Apple did not accept the notarization submission'
  printf '%s: Developer ID signed and notarized (Apple Accepted). Standalone executables have no stapled ticket; Gatekeeper may need network access.\n' "$architecture" > "$status_file"
else
  printf '%s: Developer ID signed; not notarized (no notarization credentials configured).\n' "$architecture" > "$status_file"
fi
