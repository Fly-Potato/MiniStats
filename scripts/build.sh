#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/ministats-clang-cache"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
    debug) APP_NAME="MiniStats Dev"; BUNDLE_ID="local.ministats.app.dev" ;;
    release) APP_NAME="MiniStats"; BUNDLE_ID="local.ministats.app" ;;
    *) echo "用法：bash scripts/build.sh [debug|release]" >&2; exit 2 ;;
esac
swift build -c "$CONFIGURATION" --disable-sandbox
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --disable-sandbox)"
APP="dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MiniStats" "$APP/Contents/MacOS/MiniStats"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MiniStats</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
