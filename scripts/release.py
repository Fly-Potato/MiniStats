#!/usr/bin/env python3
"""Prepare signed updates; publish a validated release tag after checking uploaded assets."""
import argparse
import hashlib
import json
import os
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
    # Only signing tools receive the secret, through stdin, never child env/argv.
    environment = {key: value for key, value in os.environ.items() if key != "SPARKLE_PRIVATE_KEY"}
    return subprocess.run(args, cwd=ROOT, check=True, env=environment, **kwargs)


def signing_run(tool, *args):
    if "SPARKLE_PRIVATE_KEY" in os.environ:
        key = os.environ["SPARKLE_PRIVATE_KEY"].strip()
        if not key:
            raise SystemExit("请配置 release 环境的 SPARKLE_PRIVATE_KEY Secret")
        return run(str(TOOLS / tool), "--ed-key-file", "-", *args, input=key, text=True)
    return run(str(TOOLS / tool), "--account", ACCOUNT, *args)


def validate_signing_key():
    if "SPARKLE_PRIVATE_KEY" in os.environ:
        key = os.environ["SPARKLE_PRIVATE_KEY"].strip()
        if not key:
            raise SystemExit("请配置 release 环境的 SPARKLE_PRIVATE_KEY Secret")
        run("swift", "scripts/validate-update-key.swift", str(ROOT / "config/sparkle-public-key.txt"),
            input=key, text=True)
    else:
        public_key = run(str(TOOLS / "generate_keys"), "--account", ACCOUNT, "-p", capture_output=True, text=True).stdout.strip()
        if public_key != (ROOT / "config/sparkle-public-key.txt").read_text().strip():
            raise SystemExit("发布钥匙串与应用内置公钥不匹配")


def release_config(requested_version=None):
    config = json.loads((ROOT / "config/release.json").read_text())
    if not re.fullmatch(r"\d+\.\d+\.\d+", config["version"]) or not re.fullmatch(r"[1-9]\d*", config["build"]):
        raise SystemExit("版本必须为 x.y.z，构建号必须为正整数")
    if requested_version is not None and requested_version != config["version"]:
        raise SystemExit("输入版本与 config/release.json 不一致，请先提交版本配置和更新说明")
    return config


def validate_tag(tag):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise SystemExit("发版 tag 必须为 vX.Y.Z，不支持预发布后缀")
    version = release_config(tag[1:])["version"]
    if not (ROOT / "docs/releases" / f"{version}.md").is_file():
        raise SystemExit("当前版本的更新说明不存在")
    commit = run("git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}", capture_output=True, text=True).stdout.strip()
    head = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    if commit != head:
        raise SystemExit("当前源码提交与 tag 不一致")
    try:
        run("git", "merge-base", "--is-ancestor", commit, "origin/main")
    except subprocess.CalledProcessError as error:
        if error.returncode == 1:
            raise SystemExit("发版提交必须已进入 origin/main") from None
        raise
    return version


def prepare(notes):
    config = release_config()
    version, build = config["version"], config["build"]
    validate_signing_key()
    # Preserve compatible older releases and refuse duplicate/decreasing build numbers.
    releases = json.loads(run("gh", "release", "list", "--repo", REPO, "--limit", "1000",
                             "--json", "tagName,isLatest,isDraft,isPrerelease", capture_output=True, text=True).stdout)
    if any(item["tagName"] == f"v{version}" for item in releases):
        raise SystemExit("此版本已有 Release（包括草稿），不能重复创建或覆盖附件")
    latest = next((item for item in releases if item["isLatest"] and not item["isDraft"] and not item["isPrerelease"]), None)
    if latest and re.fullmatch(r"v\d+\.\d+\.\d+", latest["tagName"]):
        if tuple(map(int, version.split("."))) <= tuple(map(int, latest["tagName"][1:].split("."))):
            raise SystemExit("版本号必须高于当前 Latest，不能回退更新源")
    folder = ROOT / "dist/releases" / version
    if folder.exists():
        raise SystemExit(f"输出目录已存在，请检查后移走再重试：{folder}")
    folder.mkdir(parents=True)
    if latest:
        run("gh", "release", "download", latest["tagName"], "--repo", REPO, "--pattern", "appcast.xml", "--dir", str(folder))
        signing_run("sign_update", "--verify", str(folder / "appcast.xml"))
        tree = ET.parse(folder / "appcast.xml")
        builds = [int(item.text) for item in tree.findall(".//sparkle:version", NS)]
        if not builds or int(build) <= max(builds):
            raise SystemExit("构建号必须高于现有更新清单中的所有版本")
    run("bash", "scripts/build.sh", "release")
    archive = folder / f"MiniStats-{version}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(ROOT / "dist/MiniStats.app"), str(archive))
    shutil.copyfile(notes, folder / f"MiniStats-{version}.md")
    signing_run("generate_appcast", "--maximum-deltas", "0",
        "--maximum-versions", "0", "--embed-release-notes", "--download-url-prefix",
        f"https://github.com/{REPO}/releases/download/v{version}/", str(folder))
    verify_assets(folder, version, build)
    commit = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    (folder / "source-commit.txt").write_text(commit + "\n")
    print(f"已生成签名附件：{folder}；尚未上传或发布")


def verify_assets(folder, version, build):
    signing_run("sign_update", "--verify", str(folder / "appcast.xml"))
    items = ET.parse(folder / "appcast.xml").findall("./channel/item")
    item = next(item for item in items if item.findtext("sparkle:version", namespaces=NS) == build)
    signing_run("sign_update", "--verify", str(folder / f"MiniStats-{version}.zip"),
        item.find("enclosure").attrib[f"{{{NS['sparkle']}}}edSignature"])


def draft(verify_tag=False):
    if run("git", "status", "--porcelain", capture_output=True, text=True).stdout.strip():
        raise SystemExit("请先提交相关改动，再创建 Release 草稿")
    config = release_config()
    version = config["version"]
    folder = ROOT / "dist/releases" / version
    commit = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    if (folder / "source-commit.txt").read_text().strip() != commit:
        raise SystemExit("当前提交与打包提交不一致，请重新准备发布包")
    validate_signing_key()
    verify_assets(folder, version, config["build"])
    tag_options = ["--verify-tag"] if verify_tag else []
    run("gh", "release", "create", f"v{version}", "--repo", REPO, "--draft", "--target", commit, *tag_options,
        "--title", f"MiniStats {version}", "--notes-file", str(folder / f"MiniStats-{version}.md"),
        str(folder / f"MiniStats-{version}.zip"), str(folder / "appcast.xml"))


def release_info(tag):
    result = json.loads(run("gh", "api", f"repos/{REPO}/releases/tags/{tag}",
                            capture_output=True, text=True).stdout)
    return {"tagName": result["tag_name"], "isDraft": result["draft"], "isPrerelease": result["prerelease"],
            "assets": result["assets"], "url": result["html_url"], "targetCommitish": result["target_commitish"]}


def verify_uploaded_assets(info, folder, version):
    if info["tagName"] != f"v{version}" or not info["isDraft"] or info["isPrerelease"]:
        raise SystemExit("Release 状态不符合预期，拒绝发布")
    assets = {asset["name"]: asset for asset in info["assets"]}
    names = {f"MiniStats-{version}.zip", "appcast.xml"}
    if set(assets) != names:
        raise SystemExit("草稿附件不完整或包含意外附件，拒绝发布")
    for name in names:
        asset = assets[name]
        file = folder / name
        digest = "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()
        if asset.get("state") != "uploaded" or asset.get("size") != file.stat().st_size or asset.get("digest") != digest:
            raise SystemExit(f"远端附件校验失败：{name}；草稿保持未公开")


def publish(tag):
    version = validate_tag(tag)
    draft(verify_tag=True)
    folder = ROOT / "dist/releases" / version
    info = release_info(tag)
    commit = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    if info["targetCommitish"] != commit:
        raise SystemExit("远端 Release 目标提交不一致，草稿保持未公开")
    verify_uploaded_assets(info, folder, version)
    run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest")
    published = release_info(tag)
    latest = run("gh", "api", f"repos/{REPO}/releases/latest", "--jq", ".tag_name", capture_output=True, text=True).stdout.strip()
    if published["isDraft"] or published["isPrerelease"] or latest != tag:
        raise SystemExit("发布后的状态异常，请核对 GitHub Release；不要覆盖附件或重打 tag")
    print(f"已正式发布并设为 Latest：{published['url']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--notes", type=pathlib.Path, required=True)
    commands.add_parser("draft")
    publish_parser = commands.add_parser("publish")
    publish_parser.add_argument("--tag", required=True)
    tag_parser = commands.add_parser("validate-tag")
    tag_parser.add_argument("--tag", required=True)
    validate_parser = commands.add_parser("validate")
    validate_parser.add_argument("--version", required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        if not args.notes.is_file():
            parser.error("更新说明文件不存在")
        if run("git", "status", "--porcelain", capture_output=True, text=True).stdout.strip():
            parser.error("发布包必须来自干净且已提交的工作区")
        prepare(args.notes.resolve())
    elif args.command == "draft":
        draft()
    elif args.command == "publish":
        publish(args.tag)
    elif args.command == "validate-tag":
        validate_tag(args.tag)
        print(f"tag、配置与 main 提交检查通过：{args.tag}")
    else:
        version = release_config(args.version)["version"]
        if not (ROOT / "docs/releases" / f"{version}.md").is_file():
            parser.error("当前版本的更新说明不存在")
        print(f"版本与更新说明检查通过：{version}")
