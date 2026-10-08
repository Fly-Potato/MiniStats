import base64
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", ROOT / "scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "config").mkdir()
        (self.root / "config/release.json").write_text(json.dumps({"version": "0.2.1", "build": "3"}))
        self.root_patch = patch.object(release, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def testRequestedVersionMustMatchCommittedConfig(self):
        with self.assertRaises(SystemExit):
            release.release_config("0.2.2")

    def testTagVersionAndHeadMustMatch(self):
        notes = self.root / "docs/releases/0.2.1.md"
        notes.parent.mkdir(parents=True)
        notes.write_text("测试更新说明")
        with patch.object(release, "run") as command:
            with self.assertRaises(SystemExit):
                release.validate_tag("v0.2.1-rc1")
            with self.assertRaises(SystemExit):
                release.validate_tag("v0.2.2")
            command.assert_not_called()
        results = [subprocess.CompletedProcess([], 0, stdout="tag-commit"), subprocess.CompletedProcess([], 0, stdout="other-commit")]
        with patch.object(release, "run", side_effect=results):
            with self.assertRaises(SystemExit):
                release.validate_tag("v0.2.1")

    def testAnnotatedTagRequiresMainAncestry(self):
        notes = self.root / "docs/releases/0.2.1.md"
        notes.parent.mkdir(parents=True)
        notes.write_text("测试更新说明")
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.root)], check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "user.name=Release Test", "-c", "user.email=test@example.com", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "user.name=Release Test", "-c", "user.email=test@example.com", "tag", "-a", "v0.2.1", "-m", "fixture"], cwd=self.root, check=True)
        self.assertEqual(release.validate_tag("v0.2.1"), "0.2.1")
        results = [subprocess.CompletedProcess([], 0, stdout="commit"), subprocess.CompletedProcess([], 0, stdout="commit"),
                   subprocess.CalledProcessError(1, ["git", "merge-base"])]
        with patch.object(release, "run", side_effect=results):
            with self.assertRaises(SystemExit):
                release.validate_tag("v0.2.1")

    def testVersionCannotDowngradeLatest(self):
        result = subprocess.CompletedProcess([], 0, stdout='[{"tagName":"v0.3.0","isLatest":true,"isDraft":false,"isPrerelease":false}]')
        with patch.object(release, "validate_signing_key"), patch.object(release, "run", return_value=result):
            with self.assertRaises(SystemExit):
                release.prepare(self.root / "notes.md")
            self.assertFalse((self.root / "dist/releases/0.2.1").exists())

    def upload_fixture(self):
        folder = self.root / "dist/releases/0.2.1"
        folder.mkdir(parents=True)
        assets = []
        for name in ("MiniStats-0.2.1.zip", "appcast.xml"):
            file = folder / name
            file.write_bytes(b"test uploaded bytes")
            assets.append({"name": name, "size": file.stat().st_size, "state": "uploaded",
                           "digest": "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()})
        return {"tagName": "v0.2.1", "isDraft": True, "isPrerelease": False, "assets": assets,
                "targetCommitish": "commit", "url": "https://example.com/release"}

    def testPublishChecksAttachmentsBeforeGoingPublic(self):
        info = self.upload_fixture()
        published = {**info, "isDraft": False}
        def fake_run(*args, **kwargs):
            value = "v0.2.1" if args[:2] == ("gh", "api") else "commit"
            return subprocess.CompletedProcess([], 0, stdout=value)
        with patch.object(release, "validate_tag", return_value="0.2.1"), patch.object(release, "draft") as draft, \
             patch.object(release, "release_info", side_effect=[info, published]), patch.object(release, "run", side_effect=fake_run) as command:
            release.publish("v0.2.1")
            draft.assert_called_once_with(verify_tag=True)
            edits = [call.args for call in command.call_args_list if call.args[:3] == ("gh", "release", "edit")]
            self.assertEqual(len(edits), 1)
            self.assertIn("--draft=false", edits[0])
            self.assertIn("--latest", edits[0])

    def testUploadMismatchLeavesDraftUnpublished(self):
        info = self.upload_fixture()
        info["assets"][0]["digest"] = "sha256:incorrect"
        with patch.object(release, "validate_tag", return_value="0.2.1"), patch.object(release, "draft"), \
             patch.object(release, "release_info", return_value=info), patch.object(release, "run", return_value=subprocess.CompletedProcess([], 0, stdout="commit")) as command:
            with self.assertRaises(SystemExit):
                release.publish("v0.2.1")
            self.assertFalse(any(call.args[:3] == ("gh", "release", "edit") for call in command.call_args_list))

    def testSecretOnlyPassedThroughStdin(self):
        with patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": "test-only"}), patch.object(release.subprocess, "run") as command:
            release.signing_run("sign_update", "--verify", "test.xml")
            args, kwargs = command.call_args
            self.assertNotIn("test-only", args[0])
            self.assertNotIn("SPARKLE_PRIVATE_KEY", kwargs["env"])
            self.assertEqual(kwargs["input"], "test-only")
            self.assertIn("--ed-key-file", args[0])

    def testEmptySecretNeverFallsBackToKeychain(self):
        with patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": ""}), patch.object(release, "run") as command:
            with self.assertRaises(SystemExit):
                release.validate_signing_key()
            command.assert_not_called()

    def testDuplicateReleaseStopsBeforeBuilding(self):
        result = subprocess.CompletedProcess([], 0, stdout='[{"tagName":"v0.2.1","isDraft":true}]')
        with patch.object(release, "validate_signing_key"), patch.object(release, "run", return_value=result) as command:
            with self.assertRaises(SystemExit):
                release.prepare(self.root / "notes.md")
            self.assertEqual(command.call_count, 1)
            self.assertFalse((self.root / "dist/releases/0.2.1").exists())

    def testOldBuildNumberCannotReplaceLatest(self):
        def fake_run(*args, **kwargs):
            if args[:3] == ("gh", "release", "list"):
                return subprocess.CompletedProcess([], 0, stdout='[{"tagName":"v0.2.0","isLatest":true,"isDraft":false,"isPrerelease":false}]')
            if args[:3] == ("gh", "release", "download"):
                folder = pathlib.Path(args[-1])
                (folder / "appcast.xml").write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>3</sparkle:version></item></channel></rss>')
                return subprocess.CompletedProcess([], 0)
            self.fail(f"不应进入构建或上传：{args[0]}")

        with patch.object(release, "validate_signing_key"), patch.object(release, "signing_run"), patch.object(release, "run", side_effect=fake_run):
            with self.assertRaises(SystemExit):
                release.prepare(self.root / "notes.md")

    def testDraftRejectsAssetsFromAnotherCommit(self):
        folder = self.root / "dist/releases/0.2.1"
        folder.mkdir(parents=True)
        (folder / "source-commit.txt").write_text("old-commit\n")
        results = [subprocess.CompletedProcess([], 0, stdout=""), subprocess.CompletedProcess([], 0, stdout="new-commit\n")]
        with patch.object(release, "run", side_effect=results), patch.object(release, "validate_signing_key") as validate:
            with self.assertRaises(SystemExit):
                release.draft()
            validate.assert_not_called()

    def testPublicKeyValidationAcceptsMatchAndRejectsMismatch(self):
        # Public RFC 8032 Ed25519 test vector; never uses a real release key.
        seed = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        file = self.root / "test-public-key.txt"
        for key, success in ((public, True), (bytes(32), False)):
            file.write_text(base64.b64encode(key).decode())
            result = subprocess.run(["swift", str(ROOT / "scripts/validate-update-key.swift"), str(file)],
                                    input=base64.b64encode(seed), capture_output=True, timeout=60)
            self.assertEqual(result.returncode == 0, success)
            self.assertNotIn(base64.b64encode(seed), result.stdout + result.stderr)

    def testSparkleAcceptsStdinKeyAndRejectsTamperedFiles(self):
        # Same public RFC 8032 vector; no Keychain access or production signing.
        key = base64.b64encode(bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
        tool = str(release.TOOLS / "sign_update")
        for name, contents in (("test.zip", b"test archive"), ("appcast.xml", b"<rss><channel><title>Test</title></channel></rss>")):
            file = self.root / name
            file.write_bytes(contents)
            signed = subprocess.run([tool, "--ed-key-file", "-", "-p", str(file)], input=key,
                                    capture_output=True, check=True, timeout=30)
            command = [tool, "--ed-key-file", "-", "--verify", str(file)]
            if name.endswith(".zip"):
                command.append(signed.stdout.decode().strip())
            subprocess.run(command, input=key, capture_output=True, check=True, timeout=30)
            if name.endswith(".zip"):
                file.write_bytes(file.read_bytes() + b"tampered")
            else:
                # Modify signed XML content, not bytes beyond its signature footer.
                file.write_bytes(file.read_bytes().replace(b"<title>Test</title>", b"<title>Evil</title>"))
            rejected = subprocess.run(command, input=key, capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertNotIn(key, signed.stdout + signed.stderr + rejected.stdout + rejected.stderr)

    def testGenerateAppcastSignsArchiveAndFeedFromStdin(self):
        seed = base64.b64encode(bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
        public = base64.b64encode(bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).decode()
        app = self.root / "Test.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", app / "Contents/MacOS/Test")
        (app / "Contents/MacOS/Test").chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Test", "CFBundleIdentifier": "local.ministats.ci-test",
            "CFBundleName": "Test", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "3", "CFBundleShortVersionString": "0.2.1",
            "LSMinimumSystemVersion": "13.0", "SUPublicEDKey": public,
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
        }))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], capture_output=True, check=True)
        feed = self.root / "feed"
        feed.mkdir()
        archive = feed / "Test.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
        subprocess.run([str(release.TOOLS / "generate_appcast"), "--ed-key-file", "-", "--maximum-deltas", "0",
                        "--download-url-prefix", "https://example.com/updates/", str(feed)],
                       input=seed, capture_output=True, check=True, timeout=60)
        enclosure = ET.parse(feed / "appcast.xml").find("./channel/item/enclosure")
        signature = enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
        for file, signatures in ((feed / "appcast.xml", []), (archive, [signature])):
            subprocess.run([str(release.TOOLS / "sign_update"), "--ed-key-file", "-", "--verify", str(file), *signatures],
                           input=seed, capture_output=True, check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
