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

# Copy bundled resources (menubar icon PNG, etc) into Contents/Resources
# so Bundle.main.url(forResource:…) can find them at runtime. SwiftPM's
# executable targets don't expose a clean way to forward resources into a
# manually-assembled .app, so we just stage them ourselves. `.DS_Store`
# files get filtered out so Finder metadata doesn't leak into shipped
# builds.
RES_SRC="Sources/JiraMenu/Resources"
if [ -d "$RES_SRC" ]; then
  rsync -a --exclude='.DS_Store' "$RES_SRC/" "$APP_BUNDLE/Contents/Resources/"
fi

# Codesign. Prefer a stable self-signed identity (set JIRAMENU_SIGN_IDENTITY,
# default "JiraMenu Dev") so Keychain ACLs survive rebuilds — ad-hoc signing
# produces a fresh hash each build and re-prompts on every access.
# See docs/setup-signing-cert.md for one-time cert creation.
SIGN_IDENTITY="${JIRAMENU_SIGN_IDENTITY:-JiraMenu Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  echo "==> Signing with stable identity: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "==> Identity '$SIGN_IDENTITY' not found in login keychain — using ad-hoc."
  echo "    To stop Keychain re-prompts on each rebuild, create a code-signing"
  echo "    cert named '$SIGN_IDENTITY' (see docs/setup-signing-cert.md)."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo ""
echo "Built: $APP_BUNDLE"
echo "Architectures:"
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | sed 's/^/  /'
