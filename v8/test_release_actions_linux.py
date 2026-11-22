"""Regression tests for GitHub release action eligibility and integrity policy."""
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import homebrew

ROOT = Path(__file__).resolve().parent


class ReleaseActionsTests(unittest.TestCase):
    def test_right_click_probes_release_and_shows_digest_gated_actions(self):
        qml = (ROOT / "HomebrewPage.qml").read_text()
        self.assertIn("if (home.actionRepo) home.probeRelease(home.actionRepo)", qml)
        self.assertIn('text: "Download ZIP / NRO"', qml)
        self.assertIn('text: "Download && Install NRO"', qml)
        self.assertIn("!!asset.digest && asset.name.toLowerCase().endsWith(\".nro\")", qml)
        self.assertIn("!!asset.digest && asset.name.toLowerCase().endsWith(\".zip\")", qml)
        self.assertIn("controller.homebrew_releases(repo)", qml)

    def test_download_rejects_missing_digest_even_with_confirmation(self):
        asset = {"name": "test.nro", "url": "https://github.com/example/repo/releases/download/v1/test.nro",
                 "size": 3, "digest": ""}
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "SHA-256 digest required"):
                homebrew.download_asset(asset, folder, allow_unverified_nro=True)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_download_rejects_bad_digest(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def geturl(self): return "https://release-assets.githubusercontent.com/example"
            def read(self, size): return b"abc" if not hasattr(self, "done") else b""
        def opener(req, timeout):
            response = Response()
            original_read = response.read
            def read(size):
                if getattr(response, "done", False): return b""
                response.done = True
                return b"abc"
            response.read = read
            return response
        asset = {"name": "test.nro", "url": "https://github.com/example/repo/releases/download/v1/test.nro",
                 "size": 3, "digest": "sha256:" + "0" * 64}
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "integrity verification failed"):
                homebrew.download_asset(asset, folder, opener=opener)
            self.assertEqual(list(Path(folder).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
