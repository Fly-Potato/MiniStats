#!/usr/bin/env python3
"""Prepare signed release assets locally; create a draft only when explicitly asked."""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "Fly-Potato/MiniStats"
TOOLS = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
ACCOUNT = "MiniStats-updates"
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def prepare(notes):
    config = json.loads((ROOT / "config/release.json").read_text())
    version, build = config["version"], config["build"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise SystemExit("版本必须为 x.y.z，构建号必须为正整数")
    public_key = run(str(TOOLS / "generate_keys"), "--account", ACCOUNT, "-p", capture_output=True, text=True).stdout.strip()
    if public_key != (ROOT / "config/sparkle-public-key.txt").read_text().strip():
        raise SystemExit("发布钥匙串与应用内置公钥不匹配")
    # Preserve compatible older releases and refuse duplicate/decreasing build numbers.
    releases = json.loads(run("gh", "release", "list", "--repo", REPO, "--exclude-drafts", "--exclude-pre-releases",
                             "--json", "tagName,isLatest", capture_output=True, text=True).stdout)
    latest = next((item for item in releases if item["isLatest"]), None)
    folder = ROOT / "dist/releases" / version
    if folder.exists():
        raise SystemExit(f"输出目录已存在，请检查后移走再重试：{folder}")
    folder.mkdir(parents=True)
    if latest:
        run("gh", "release", "download", latest["tagName"], "--repo", REPO, "--pattern", "appcast.xml", "--dir", str(folder))
        run(str(TOOLS / "sign_update"), "--account", ACCOUNT, "--verify", str(folder / "appcast.xml"))
        tree = ET.parse(folder / "appcast.xml")
        builds = [int(item.text) for item in tree.findall(".//sparkle:version", NS)]
        if not builds or int(build) <= max(builds):
            raise SystemExit("构建号必须高于现有更新清单中的所有版本")
    run("bash", "scripts/build.sh", "release")
    archive = folder / f"MiniStats-{version}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(ROOT / "dist/MiniStats.app"), str(archive))
    shutil.copyfile(notes, folder / f"MiniStats-{version}.md")
    run(str(TOOLS / "generate_appcast"), "--account", ACCOUNT, "--maximum-deltas", "0",
        "--maximum-versions", "0", "--embed-release-notes", "--download-url-prefix",
        f"https://github.com/{REPO}/releases/download/v{version}/", str(folder))
    verify_assets(folder, version, build)
    commit = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    (folder / "source-commit.txt").write_text(commit + "\n")
    print(f"已生成签名附件：{folder}；尚未上传或发布")


def verify_assets(folder, version, build):
    run(str(TOOLS / "sign_update"), "--account", ACCOUNT, "--verify", str(folder / "appcast.xml"))
    items = ET.parse(folder / "appcast.xml").findall("./channel/item")
    item = next(item for item in items if item.findtext("sparkle:version", namespaces=NS) == build)
    run(str(TOOLS / "sign_update"), "--account", ACCOUNT, "--verify", str(folder / f"MiniStats-{version}.zip"),
        item.find("enclosure").attrib[f"{{{NS['sparkle']}}}edSignature"])


def draft():
    if run("git", "status", "--porcelain", capture_output=True, text=True).stdout.strip():
        raise SystemExit("请先提交相关改动，再创建 Release 草稿")
    version = json.loads((ROOT / "config/release.json").read_text())["version"]
    folder = ROOT / "dist/releases" / version
    commit = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    if (folder / "source-commit.txt").read_text().strip() != commit:
        raise SystemExit("当前提交与打包提交不一致，请重新准备发布包")
    verify_assets(folder, version, json.loads((ROOT / "config/release.json").read_text())["build"])
    run("gh", "release", "create", f"v{version}", "--repo", REPO, "--draft", "--target", commit,
        "--title", f"MiniStats {version}", "--notes-file", str(folder / f"MiniStats-{version}.md"),
        str(folder / f"MiniStats-{version}.zip"), str(folder / "appcast.xml"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--notes", type=pathlib.Path, required=True)
    commands.add_parser("draft")
    args = parser.parse_args()
    if args.command == "prepare":
        if not args.notes.is_file():
            parser.error("更新说明文件不存在")
        if run("git", "status", "--porcelain", capture_output=True, text=True).stdout.strip():
            parser.error("发布包必须来自干净且已提交的工作区")
        prepare(args.notes.resolve())
    else:
        draft()
