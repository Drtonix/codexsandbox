#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/WaveKeyboard.app"
BIN_NAME="WaveKeyboardApp"
APP_EXECUTABLE="WaveKeyboard"

cd "$ROOT_DIR"

mkdir -p .build/module-cache
SWIFT_MODULECACHE_PATH=.build/module-cache \
CLANG_MODULE_CACHE_PATH=.build/module-cache \
swift build --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>WaveKeyboard</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.wavekeyboard</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WaveKeyboard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/.build/debug/$BIN_NAME" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE"
xattr -cr "$APP_DIR" || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo "Built app bundle: $APP_DIR"
echo "Run it with:"
echo "open \"$APP_DIR\""
