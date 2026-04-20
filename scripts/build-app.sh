#!/usr/bin/env bash
# Builds JiraMenu.app bundle from the SPM executable.
# Usage: ./scripts/build-app.sh [version]  (default version: 0.0.0-dev)
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
APP_NAME="JiraMenu"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# Build universal binary (arm64 + x86_64)
echo "==> Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64

# Locate the binary produced by swift build (path varies by SDK version)
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Stamp Info.plist with the version and drop into bundle
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc codesign so macOS will launch it after quarantine is cleared
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Architectures:"
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | sed 's/^/  /'
