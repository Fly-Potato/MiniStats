#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/ministats-clang-cache"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
    debug) APP_NAME="MiniStats Dev"; BUNDLE_ID="local.ministats.app.dev" ;;
    release) APP_NAME="MiniStats"; BUNDLE_ID="local.ministats.app" ;;
    *) echo "用法：bash scripts/build.sh [debug|release]" >&2; exit 2 ;;
esac
swift build -c "$CONFIGURATION" --disable-sandbox -Xlinker -rpath -Xlinker @executable_path/../Frameworks
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --disable-sandbox)"
APP="dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MiniStats" "$APP/Contents/MacOS/MiniStats"
python3 scripts/write-plist.py "$CONFIGURATION" "$APP/Contents/Info.plist"
bash scripts/build-icon.sh "$APP/Contents/Resources/AppIcon.icns"
SPARKLE_FRAMEWORK="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle framework missing: $SPARKLE_FRAMEWORK" >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
