#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/DeskMD.app"
ZIP_PATH="$BUILD_DIR/DeskMD.app.zip"
DEFAULT_BUNDLE_ID="local.deskmd"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
APPLE_NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
DESKMD_NOTARY_PRIMARY_BUNDLE_ID="${DESKMD_NOTARY_PRIMARY_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
DESKMD_CODESIGN_ENTITLEMENTS="${DESKMD_CODESIGN_ENTITLEMENTS:-}"

usage() {
  cat <<'EOF'
Usage: ./scripts/notarize-macos-app.sh

Required environment variables:
  DEVELOPER_ID_APPLICATION       Developer ID Application certificate name.

Notary authentication:
  Prefer:
    APPLE_NOTARY_PROFILE         notarytool keychain profile name
  Or provide all of:
    APPLE_ID
    APPLE_TEAM_ID
    APPLE_APP_SPECIFIC_PASSWORD

Optional environment variables:
  DESKMD_NOTARY_PRIMARY_BUNDLE_ID  Primary bundle identifier for notary submission.
  DESKMD_CODESIGN_ENTITLEMENTS     Optional entitlements plist for codesign.

Example:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
  APPLE_NOTARY_PROFILE="deskmd-notary" \
  npm run release:mac
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ "${1:-}" = "--help" ]]; then
  usage
  exit 0
fi

require_command clang
require_command codesign
require_command ditto
require_command xcrun

if [ -z "$DEVELOPER_ID_APPLICATION" ]; then
  echo "DEVELOPER_ID_APPLICATION is required for release signing." >&2
  usage >&2
  exit 1
fi

has_notary_profile=0
if [ -n "$APPLE_NOTARY_PROFILE" ]; then
  has_notary_profile=1
fi

has_notary_credentials=0
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
  has_notary_credentials=1
fi

if [ "$has_notary_profile" -ne 1 ] && [ "$has_notary_credentials" -ne 1 ]; then
  echo "Notary authentication is required. Set APPLE_NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD." >&2
  usage >&2
  exit 1
fi

echo "Building DeskMD.app with Developer ID signing..."
DESKMD_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
DESKMD_CODESIGN_RUNTIME=1 \
DESKMD_CODESIGN_ENTITLEMENTS="$DESKMD_CODESIGN_ENTITLEMENTS" \
"$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

echo "Creating notarization zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Submitting zip for notarization..."
notary_args=(notarytool submit "$ZIP_PATH" --wait --progress --output-format json)
if [ "$has_notary_profile" -eq 1 ]; then
  notary_args+=(--keychain-profile "$APPLE_NOTARY_PROFILE")
else
  notary_args+=(
    --apple-id "$APPLE_ID"
    --team-id "$APPLE_TEAM_ID"
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
    --primary-bundle-id "$DESKMD_NOTARY_PRIMARY_BUNDLE_ID"
  )
fi

xcrun "${notary_args[@]}"

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"

echo "Release build complete:"
echo "$APP_DIR"
echo "$ZIP_PATH"
