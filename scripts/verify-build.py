#!/usr/bin/env python3
"""Validate both bundled apps without launching UI or checking the update feed."""
import json
import pathlib
import platform
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "config/release.json").read_text())
PUBLIC_KEY = (ROOT / "config/sparkle-public-key.txt").read_text().strip()
SDK_VERSION = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-version"],
                             capture_output=True, text=True, check=True).stdout.strip()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


for development in (True, False):
    name = "MiniStats Dev" if development else "MiniStats"
    app = ROOT / "dist" / f"{name}.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {
        "CFBundleIdentifier": "local.ministats.app.dev" if development else "local.ministats.app",
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleExecutable": "MiniStats",
        "CFBundleShortVersionString": CONFIG["version"],
        "CFBundleVersion": CONFIG["build"],
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
    }
    if development:
        require(not any(key.startswith("SU") for key in info), "开发版不应配置更新源")
    else:
        require(CONFIG["feedURL"].startswith("https://"), "生产更新源必须使用 HTTPS")
        expected.update({
            "SUFeedURL": CONFIG["feedURL"],
            "SUPublicEDKey": PUBLIC_KEY,
            "SUScheduledCheckInterval": 86400,
            "SUAutomaticallyUpdate": False,
            "SUVerifyUpdateBeforeExtraction": True,
            "SURequireSignedFeed": True,
        })
    for key, value in expected.items():
        require(info.get(key) == value, f"{name}: {key} 应为 {value!r}")

    framework = app / "Contents/Frameworks/Sparkle.framework"
    require((framework / "Sparkle").is_file(), f"{name}: 缺少 Sparkle framework")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    executable = app / "Contents/MacOS/MiniStats"
    build_metadata = subprocess.run(["xcrun", "vtool", "-show-build", str(executable)],
                                    capture_output=True, text=True, check=True).stdout
    linked_sdks = re.findall(r"^\s+sdk\s+(\S+)", build_metadata, re.MULTILINE)
    require(bool(linked_sdks) and all(sdk == SDK_VERSION for sdk in linked_sdks),
            f"{name}: 链接 SDK {linked_sdks} 与当前工具链 SDK {SDK_VERSION} 不一致")
    architectures = subprocess.run(["lipo", "-archs", str(executable)],
                                    capture_output=True, text=True, check=True).stdout.split()
    require(platform.machine() in architectures, f"{name}: 不支持当前架构")
    sample = subprocess.run([str(executable), "--sample"],
                            capture_output=True, text=True, check=True, timeout=20)
    require(f"App: {name}\n" in sample.stdout, f"{name}: 编译身份不正确")
    print(sample.stdout, end="")
    print(f"PASS: {name} 元数据、SDK {SDK_VERSION}、签名、架构及真实采样")
