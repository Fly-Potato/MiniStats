#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TOOL="$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
if [ ! -x "$TOOL" ]; then
    echo "请先执行 swift package resolve" >&2
    exit 1
fi
"$TOOL" --account MiniStats-updates
PUBLIC_KEY="$("$TOOL" --account MiniStats-updates -p)"
if [ -f config/sparkle-public-key.txt ] && [ "$(cat config/sparkle-public-key.txt)" != "$PUBLIC_KEY" ]; then
    echo "钥匙串公钥与仓库不匹配，请恢复原私钥；不会覆盖已有公钥。" >&2
    exit 1
fi
printf '%s\n' "$PUBLIC_KEY" > config/sparkle-public-key.txt
