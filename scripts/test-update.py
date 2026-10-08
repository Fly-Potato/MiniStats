#!/usr/bin/env python3
"""Exercise Sparkle against isolated test bundles over loopback, never the installed app."""
import functools
import argparse
import http.server
import pathlib
import plistlib
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--verify-only", action="store_true", help="只验证签名与损坏包拒绝，不执行安装")
args = parser.parse_args()


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="ministats-update-test-") as temporary:
    root = pathlib.Path(temporary)
    if not args.verify_only:
        # Keep the installer client outside macOS's protected Documents folder.
        run("ditto", str(ROOT / "dist/update-tools"), str(root / "tools"))
    cli = root / "tools/sparkle"
    bundle_id = "local.ministats.update-test." + root.name
    feed = root / "feed"
    feed.mkdir()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(feed))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/"
    try:
        for name, build in [("installed", "1"), ("new", "2")]:
            app = root / name / "MiniStats Update Test.app"
            run("ditto", str(ROOT / "dist/MiniStats.app"), str(app))
            plist = app / "Contents/Info.plist"
            info = plistlib.loads(plist.read_bytes())
            info.update({"CFBundleIdentifier": bundle_id,
                         "CFBundleName": "MiniStats Update Test", "CFBundleDisplayName": "MiniStats Update Test",
                         "CFBundleVersion": build, "CFBundleShortVersionString": f"0.0.{build}",
                         "SUFeedURL": url + "appcast.xml", "SUEnableAutomaticChecks": False,
                         "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}})
            plist.write_bytes(plistlib.dumps(info))
            run("codesign", "--force", "--sign", "-", str(app))
        archive = feed / "MiniStats-test.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(root / "new/MiniStats Update Test.app"), str(archive))
        run(str(TOOLS / "generate_appcast"), "--account", "MiniStats-updates", "--maximum-deltas", "0",
            "--download-url-prefix", url, str(feed))
        run(str(TOOLS / "sign_update"), "--account", "MiniStats-updates", "--verify", str(feed / "appcast.xml"))
        signature = ET.parse(feed / "appcast.xml").find("./channel/item/enclosure").attrib[f"{{{NS}}}edSignature"]
        run(str(TOOLS / "sign_update"), "--account", "MiniStats-updates", "--verify", str(archive), signature)
        damaged = root / "damaged.zip"
        damaged.write_bytes(archive.read_bytes() + b"tampered")
        rejected = subprocess.run([str(TOOLS / "sign_update"), "--account", "MiniStats-updates", "--verify", str(damaged), signature])
        if rejected.returncode == 0:
            raise SystemExit("FAIL: damaged archive was accepted")
        if args.verify_only:
            print("PASS: signed feed, archive verification, tamper rejection (installation not tested)")
        else:
            app = root / "installed/MiniStats Update Test.app"
            rejected_app = root / "rejected/MiniStats Update Test.app"
            run("ditto", str(app), str(rejected_app))
            run(str(cli), str(app), "--probe", "--verbose", timeout=60)
            run(str(cli), str(app), "--check-immediately", "--verbose", timeout=120)
            installed = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            assert installed["CFBundleVersion"] == "2", installed
            assert installed["CFBundleIdentifier"] == bundle_id
            run(str(app / "Contents/MacOS/MiniStats"), "--sample", timeout=15)
            def assert_old_version():
                info = plistlib.loads((rejected_app / "Contents/Info.plist").read_bytes())
                assert info["CFBundleVersion"] == "1", "Failed update modified the old app"

            def assert_signature_rejection(mode, error_code):
                result = subprocess.run([str(cli), str(rejected_app), mode, "--verbose"],
                                        timeout=120, capture_output=True, text=True)
                output = result.stdout + result.stderr
                print(output, end="")
                assert result.returncode != 0, "Tampered update was accepted"
                assert f"error {error_code} (SUSparkleErrorDomain)" in output, output
                assert "improperly signed" in output, output
                assert_old_version()

            feed_path = feed / "appcast.xml"
            original_feed = feed_path.read_bytes()
            # Alter signed version metadata, leaving the signature unchanged.
            tampered_feed = original_feed.replace(b"0.0.2", b"0.0.9")
            assert tampered_feed != original_feed
            feed_path.write_bytes(tampered_feed)
            assert_signature_rejection("--probe", 1000)
            feed_path.write_bytes(original_feed)

            original_archive = archive.read_bytes()
            archive.write_bytes(original_archive + b"tampered")
            assert_signature_rejection("--check-immediately", 4005)
            archive.write_bytes(original_archive)

            print("PASS: updater rejects tampered feed/archive, preserves old app, completes isolated 1 → 2 installation")
    finally:
        server.shutdown()
