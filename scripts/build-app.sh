#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_CONFIG="${1:-release}"
APP_NAME="Claude Remainder"
EXECUTABLE_NAME="ClaudeRemainder"
BUNDLE_PATH="$ROOT_DIR/dist/${APP_NAME}.app"
ICON_JPEG_PATH="$ROOT_DIR/Resources/icon.jpeg"
ICON_ICNS_PATH="$ROOT_DIR/Resources/AppIcon.icns"

swift build -c "$BUILD_CONFIG" --product "$EXECUTABLE_NAME"

BIN_PATH="$ROOT_DIR/.build/${BUILD_CONFIG}/${EXECUTABLE_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Expected executable not found at $BIN_PATH" >&2
  exit 1
fi

rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS" "$BUNDLE_PATH/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$BUNDLE_PATH/Contents/Info.plist"

if [[ -f "$ICON_JPEG_PATH" ]]; then
  TMP_ICONSET="$(mktemp -d)"
  ICONSET_DIR="$TMP_ICONSET/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"

  render_icon() {
    local size="$1"
    local output="$2"
    sips -s format png -z "$size" "$size" "$ICON_JPEG_PATH" --out "$output" >/dev/null
  }

  render_icon 16 "$ICONSET_DIR/icon_16x16.png"
  render_icon 32 "$ICONSET_DIR/icon_16x16@2x.png"
  render_icon 32 "$ICONSET_DIR/icon_32x32.png"
  render_icon 64 "$ICONSET_DIR/icon_32x32@2x.png"
  render_icon 128 "$ICONSET_DIR/icon_128x128.png"
  render_icon 256 "$ICONSET_DIR/icon_128x128@2x.png"
  render_icon 256 "$ICONSET_DIR/icon_256x256.png"
  render_icon 512 "$ICONSET_DIR/icon_256x256@2x.png"
  render_icon 512 "$ICONSET_DIR/icon_512x512.png"
  render_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"
  cp "$ICON_ICNS_PATH" "$BUNDLE_PATH/Contents/Resources/AppIcon.icns"

  rm -rf "$TMP_ICONSET"
fi

chmod +x "$BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
# Ad-hoc signing ("-") changes identity on every build, so macOS forgets
# "Always Allow" Keychain grants. Set CODESIGN_IDENTITY to a real certificate
# (e.g. "Apple Development: Your Name (TEAMID)") to keep the grant across builds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$CODESIGN_IDENTITY" "$BUNDLE_PATH" >/dev/null 2>&1 || true

echo "Built app bundle: $BUNDLE_PATH"
