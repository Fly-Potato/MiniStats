#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-debug}"
bash scripts/build.sh "$CONFIGURATION"
if [ "$CONFIGURATION" = debug ]; then
    open "dist/MiniStats Dev.app"
else
    open dist/MiniStats.app
fi
