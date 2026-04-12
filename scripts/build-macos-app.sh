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

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$EDITOR_DIR" "$MODULE_CACHE_DIR"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

clang "$ROOT_DIR/macos/App.m" \
  -o "$MACOS_DIR/DeskMD" \
  -fobjc-arc \
  -framework Cocoa \
  -framework WebKit \
  -framework UniformTypeIdentifiers

cp "$ROOT_DIR/macos/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/index.html" "$ROOT_DIR/styles.css" "$ROOT_DIR/app.js" "$EDITOR_DIR/"
cp -R "$ROOT_DIR/vendor" "$EDITOR_DIR/"

chmod +x "$MACOS_DIR/DeskMD"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

rm -rf "$MODULE_CACHE_DIR"

echo "$APP_DIR"
