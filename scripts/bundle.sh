#!/usr/bin/env bash
# Build and bundle Avero.app from the Swift package binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP_DIR="$REPO_ROOT/.build/Avero.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building release binary…"
swift build -c release --package-path "$REPO_ROOT" 2>&1

echo "Creating app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp "$BUILD_DIR/Avero" "$MACOS/Avero"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Avero</string>
    <key>CFBundleDisplayName</key>
    <string>Avero</string>
    <key>CFBundleIdentifier</key>
    <string>com.avero.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>Avero</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Avero needs screen recording access to capture your display.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Avero uses Apple Events to reveal files in Finder.</string>
</dict>
</plist>
PLIST

echo "Bundle created at $APP_DIR"
echo "Run with:  open $APP_DIR"
