#!/bin/zsh
# Builds PortMaster.app into ./dist and a shareable zip.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0.0

# Universal binary (Apple Silicon + Intel) so the zip runs on any Mac.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN=.build/apple/Products/Release
else
    echo "Universal build unavailable, falling back to native arch"
    swift build -c release
    BIN=.build/release
fi

APP=dist/PortMaster.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN/PortMaster" "$APP/Contents/MacOS/PortMaster"

# Bundled resources (fonts) — Bundle.module finds this in Contents/Resources.
mkdir -p "$APP/Contents/Resources"
cp -R "$BIN/PortMaster_PortMaster.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.robel.portmaster</string>
    <key>CFBundleName</key>
    <string>PortMaster</string>
    <key>CFBundleDisplayName</key>
    <string>PortMaster</string>
    <key>CFBundleExecutable</key>
    <string>PortMaster</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: required on Apple Silicon, no Apple Developer account needed.
codesign --force --deep --sign - "$APP"

# Zip that preserves the bundle structure and signature (use this to share).
ditto -c -k --keepParent "$APP" "dist/PortMaster-${VERSION}.zip"

echo ""
echo "Built  $APP  ($(lipo -archs "$APP/Contents/MacOS/PortMaster" 2>/dev/null || echo unknown))"
echo "Share  dist/PortMaster-${VERSION}.zip"
