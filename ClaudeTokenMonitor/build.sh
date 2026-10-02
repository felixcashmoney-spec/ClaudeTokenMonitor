#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ClaudeTokenMonitor"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Build release configuration
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=macOS' \
  build

# Find and copy the .app bundle
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo "ERROR: $APP_NAME.app not found in build output"
  exit 1
fi

# Copy to build/ root for easy access
cp -R "$APP_PATH" "$BUILD_DIR/$APP_NAME.app"

echo ""
echo "Build complete: $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To install:"
echo "  cp -R \"$BUILD_DIR/$APP_NAME.app\" ~/Applications/"
echo ""
echo "To run:"
echo "  open \"$BUILD_DIR/$APP_NAME.app\""
