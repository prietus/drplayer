#!/bin/bash
# Build DrPlayer.app (universal) and a DMG in dist/.
#
# Usage: scripts/build-app.sh VERSION
#
# Signs with SIGN_IDENTITY if set (Developer ID, hardened runtime),
# otherwise ad-hoc. Notarization is a separate step (see
# .github/workflows/release.yml).
set -euo pipefail

VERSION="${1:?Usage: scripts/build-app.sh VERSION}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_DIR="$DIST_DIR/DrPlayer.app"
DMG_PATH="$DIST_DIR/DrPlayer-$VERSION.dmg"
ARCHS=(--arch arm64 --arch x86_64)

echo "==> Building DrPlayer v$VERSION (universal)..."
cd "$PROJECT_DIR/DrPlayer"
swift package clean
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

echo "==> Assembling .app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/DrPlayer" "$APP_DIR/Contents/MacOS/"
cp -R "$BIN_DIR/DrPlayer_DrPlayer.bundle" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$PROJECT_DIR/packaging/Info.plist" > "$APP_DIR/Contents/Info.plist"

echo "==> Signing..."
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        "$APP_DIR/Contents/Resources/DrPlayer_DrPlayer.bundle"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
    codesign --verify --strict --verbose=2 "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
    echo "    (ad-hoc — set SIGN_IDENTITY for a Developer ID signature)"
fi

echo "==> Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "DrPlayer" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

echo ""
echo "App: $APP_DIR"
echo "DMG: $DMG_PATH"
