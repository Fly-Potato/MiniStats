#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/.build/checkouts/Sparkle/sparkle-cli"
FRAMEWORKS="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
OUTPUT="$PWD/dist/update-tools"
mkdir -p "$OUTPUT"
mkdir -p "$OUTPUT/Frameworks"
ditto "$FRAMEWORKS/Sparkle.framework" "$OUTPUT/Frameworks/Sparkle.framework"
python3 - "$OUTPUT/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({'CFBundleIdentifier': 'local.ministats.update-test-cli',
                  'CFBundleName': 'MiniStats Update Test CLI', 'LSUIElement': True,
                  'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}}, stream)
PY
xcrun clang -fobjc-arc -DSPU_OBJC_DIRECT_MEMBERS= -DSPU_OBJC_DIRECT= \
    -F "$FRAMEWORKS" -framework Sparkle -framework Cocoa \
    -Wl,-rpath,@executable_path/Frameworks \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$OUTPUT/Info.plist" \
    "$SOURCE/main.m" "$SOURCE/SPUCommandLineDriver.m" "$SOURCE/SPUCommandLineUserDriver.m" \
    -o "$OUTPUT/sparkle"
codesign --force --sign - "$OUTPUT/sparkle"
