#!/bin/bash
# Source this file to select and validate the repository's Xcode toolchain.
MINISTATS_XCODE_VERSION="$(cat "$(dirname "${BASH_SOURCE[0]}")/../.xcode-version")"
MINISTATS_XCODE_PATH="/Applications/Xcode_${MINISTATS_XCODE_VERSION}.app/Contents/Developer"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "$MINISTATS_XCODE_PATH" ]; then
    export DEVELOPER_DIR="$MINISTATS_XCODE_PATH"
fi
MINISTATS_ACTIVE_XCODE="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if [ "$MINISTATS_ACTIVE_XCODE" != "$MINISTATS_XCODE_VERSION" ]; then
    echo "需要 Xcode $MINISTATS_XCODE_VERSION，当前为 ${MINISTATS_ACTIVE_XCODE:-不可用}；请通过 DEVELOPER_DIR 指定正确的 Xcode。" >&2
    return 1 2>/dev/null || exit 1
fi
MINISTATS_MACOS_SDK="$(xcrun --sdk macosx --show-sdk-version)"
case "$MINISTATS_MACOS_SDK" in
    26.*) ;;
    *) echo "需要 macOS 26 SDK，当前为 $MINISTATS_MACOS_SDK。" >&2; return 1 2>/dev/null || exit 1 ;;
esac
xcodebuild -version
echo "macOS SDK: $MINISTATS_MACOS_SDK"
