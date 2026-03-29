#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$PROJECT_DIR/DrPlayer"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/DrPlayer.app"

echo "Building DrPlayer v$VERSION..."

# Build release binary
cd "$BUILD_DIR"
swift build -c release

# Create app bundle
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/DrPlayer "$APP_DIR/Contents/MacOS/"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DrPlayer</string>
    <key>CFBundleDisplayName</key>
    <string>DrPlayer</string>
    <key>CFBundleIdentifier</key>
    <string>com.drplayer.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>DrPlayer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Copy icon if exists
if [ -f "$PROJECT_DIR/dist/DrPlayer.app/Contents/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/dist/DrPlayer.app/Contents/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

# Ad-hoc code sign (avoids "damaged app" on quarantined downloads)
codesign --deep --force --sign - "$APP_DIR"

# Create DMG
DMG_PATH="$DIST_DIR/DrPlayer-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "DrPlayer" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"

echo ""
echo "Done!"
echo "  App: $APP_DIR"
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "To install: open the DMG and drag DrPlayer to /Applications"
echo ""
echo "Note: unsigned app — users need to right-click → Open on first launch"
echo "For signed builds, get Apple Developer Account and use:"
echo "  codesign --deep --force --sign 'Developer ID Application: ...' DrPlayer.app"
echo "  xcrun notarytool submit DrPlayer.dmg --apple-id ... --team-id ... --password ..."
