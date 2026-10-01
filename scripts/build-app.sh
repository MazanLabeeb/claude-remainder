#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_CONFIG="${1:-release}"
APP_NAME="Claude Remainder"
EXECUTABLE_NAME="ClaudeRemainder"
BUNDLE_PATH="$ROOT_DIR/dist/${APP_NAME}.app"

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

chmod +x "$BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
codesign --force --sign - "$BUNDLE_PATH" >/dev/null 2>&1 || true

echo "Built app bundle: $BUNDLE_PATH"
