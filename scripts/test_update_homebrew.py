import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("update_homebrew", Path(__file__).with_name("update-homebrew.py"))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class HomebrewUpdateTests(unittest.TestCase):
    def sync(self, tag="v0.1.0+build.12", corrupt=False, draft=False, bad_digest=False):
        payload = b"fixture dmg"
        digest = hashlib.sha256(payload).hexdigest()
        name = "Codex-Widget-0.1.0-build.12-macOS-arm64.dmg"
        release = {"tagName": tag, "isDraft": draft, "isPrerelease": False,
                   "assets": [{"name": name, "digest": "sha256:" + ("0" * 64 if bad_digest else digest)}]}

        def download(args, **kwargs):
            root = Path(args[args.index("--dir") + 1])
            (root / name).write_bytes(payload)
            (root / "SHA256SUMS.txt").write_text(f"{'0' * 64 if corrupt else digest}  {name}\n")

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Casks/codex-widget.rb"
            with patch.object(updater.sys, "argv", ["update-homebrew.py", str(output)]), \
                 patch.object(updater.subprocess, "check_output", return_value=json.dumps(release)), \
                 patch.object(updater.subprocess, "run", side_effect=download):
                updater.main()
            return output.read_text()

    def test_version_includes_build_and_verified_digest(self):
        cask = self.sync()
        self.assertIn('version "0.1.0,12"', cask)
        self.assertIn(hashlib.sha256(b"fixture dmg").hexdigest(), cask)
        self.assertIn('app "Codex Widget.app"', cask)

    def test_rejects_invalid_or_unpublished_release(self):
        for args in [{"tag": "bad-tag"}, {"draft": True}]:
            with self.subTest(args=args), self.assertRaises(SystemExit):
                self.sync(**args)

    def test_rejects_checksum_mismatch(self):
        with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
            self.sync(corrupt=True)

    def test_rejects_asset_digest_mismatch(self):
        with self.assertRaisesRegex(SystemExit, "asset digest mismatch"):
            self.sync(bad_digest=True)
