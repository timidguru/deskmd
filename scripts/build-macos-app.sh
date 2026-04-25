#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/DeskMD.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EDITOR_DIR="$RESOURCES_DIR/Editor"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
ICON_FILE="$ROOT_DIR/macos/AppIcon.icns"
SIGNING_IDENTITY="${DESKMD_SIGN_IDENTITY:--}"
CODESIGN_RUNTIME="${DESKMD_CODESIGN_RUNTIME:-0}"
ENTITLEMENTS_FILE="${DESKMD_CODESIGN_ENTITLEMENTS:-}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$EDITOR_DIR" "$MODULE_CACHE_DIR"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

if [ ! -f "$ICON_FILE" ]; then
  node "$ROOT_DIR/scripts/generate-app-icon.js"
fi

clang "$ROOT_DIR/macos/App.m" \
  -o "$MACOS_DIR/DeskMD" \
  -fobjc-arc \
  -framework Cocoa \
  -framework WebKit \
  -framework UniformTypeIdentifiers

cp "$ROOT_DIR/macos/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/index.html" "$ROOT_DIR/styles.css" "$ROOT_DIR/app.js" "$EDITOR_DIR/"
cp -R "$ROOT_DIR/vendor" "$EDITOR_DIR/"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

chmod +x "$MACOS_DIR/DeskMD"

if command -v codesign >/dev/null 2>&1; then
  codesign_args=(--force --deep --sign "$SIGNING_IDENTITY")
  if [ "$CODESIGN_RUNTIME" = "1" ]; then
    codesign_args+=(--options runtime --timestamp)
  fi
  if [ -n "$ENTITLEMENTS_FILE" ]; then
    codesign_args+=(--entitlements "$ENTITLEMENTS_FILE")
  fi
  codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
fi

rm -rf "$MODULE_CACHE_DIR"

echo "$APP_DIR"
