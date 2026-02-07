#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="$ROOT_DIR/SlopSandboxCpp"
BUILD_DIR="$CPP_DIR/build"
BIN_PATH="$BUILD_DIR/SlopSandboxCpp"
APP_DIR="$ROOT_DIR/SlopSandbox.app"
APP_EXECUTABLE="SlopSandbox"

cmake -S "$CPP_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
cmake --build "$BUILD_DIR" -j 8

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
    <string>SlopSandbox</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.slopsandboxcpp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SlopSandbox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLIST

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE"
xattr -cr "$APP_DIR" || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo "Built C++ Box2D app bundle: $APP_DIR"
echo "Run it with:"
echo "open \"$APP_DIR\""
