#!/usr/bin/env python3
"""Write bundle metadata from the single release configuration."""
import json
import pathlib
import plistlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
config = json.loads((root / "config/release.json").read_text())
configuration, output = sys.argv[1:]
development = configuration == "debug"
info = {
    "CFBundleExecutable": "MiniStats",
    "CFBundleIdentifier": "local.ministats.app.dev" if development else "local.ministats.app",
    "CFBundleName": "MiniStats Dev" if development else "MiniStats",
    "CFBundleDisplayName": "MiniStats Dev" if development else "MiniStats",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": config["version"],
    "CFBundleVersion": config["build"],
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": True,
    "NSHighResolutionCapable": True,
}
if not development:
    key = (root / "config/sparkle-public-key.txt").read_text().strip()
    info.update({
        "SUFeedURL": config["feedURL"],
        "SUPublicEDKey": key,
        "SUScheduledCheckInterval": 86400,
        "SUAutomaticallyUpdate": False,
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
    })
with open(output, "wb") as stream:
    plistlib.dump(info, stream)
