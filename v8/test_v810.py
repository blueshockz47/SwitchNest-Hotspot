import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import homebrew

class HomebrewTests(unittest.TestCase):
    def test_discovery_rejects_untrusted_names(self):
        def fetch(_):
            return {"items": [{"full_name": "owner/valid", "id": 1}, {"full_name": "../../evil", "id": 2}]}
        self.assertEqual([x["repo"] for x in homebrew.discover("retroarch", fetch)], ["owner/valid"])
    def test_release_asset_filter(self):
        def fetch(_):
            return {"tag_name": "v1", "assets": [
                {"name": "demo.nro", "browser_download_url": "https://github.com/a/b/releases/download/v1/demo.nro", "size": 4, "digest": "sha256:" + "a"*64},
                {"name": "../evil.nro", "browser_download_url": "https://github.com/a/b/releases/download/v1/evil.nro", "size": 4},
                {"name": "bad.nro", "browser_download_url": "https://evil.test/x", "size": 4}]}
        self.assertEqual(len(homebrew.release_assets("a/b", fetch)["assets"]), 1)
    def test_auto_install_is_denied_without_curated_repo(self):
        asset = {"name": "demo.nro", "digest": "sha256:" + "a"*64}
        self.assertFalse(homebrew.automatic_allowed(123, asset, "/switch/demo.nro"))
        with self.assertRaises(PermissionError):
            homebrew.install_nro(asset, "/switch/demo.nro", "10.42.60.99", 1337)
    def test_system_destinations_rejected(self):
        for dest in ("/atmosphere/demo.nro", "/switch/../demo.nro", "/switch/demo.kip"):
            with self.assertRaises(ValueError):
                homebrew.validate_destination("demo.nro", dest)
    def test_digest_and_size_enforced(self):
        class Response(io.BytesIO):
            def geturl(self): return "https://github.com/a/b/releases/download/v1/demo.nro"
            def __enter__(self): return self
            def __exit__(self, *args): self.close()
        import hashlib
        digest = hashlib.sha256(b"data").hexdigest()
        asset = {"name": "demo.nro", "url": "https://github.com/a/b/releases/download/v1/demo.nro", "size": 4, "digest": "sha256:" + digest}
        with tempfile.TemporaryDirectory() as d:
            path = homebrew.download_asset(asset, d, lambda req, timeout: Response(b"data"))
            self.assertEqual(path.read_bytes(), b"data")
            path.unlink()
            asset["digest"] = "sha256:" + "0"*64
            with self.assertRaises(ValueError):
                homebrew.download_asset(asset, d, lambda req, timeout: Response(b"data"))
    def test_existing_file_not_overwritten(self):
        import hashlib
        asset = {"name": "demo.nro", "size": 4, "digest": "sha256:" + hashlib.sha256(b"data").hexdigest()}
        class FakeTree:
            def __init__(self, *args): pass
            def entries(self, path): return {"demo.nro": False}
        def fetch(asset, temp):
            p = Path(temp)/"incoming"
            p.write_bytes(b"data")
            return p
        with self.assertRaises(FileExistsError):
            homebrew.install_nro(asset, "/switch/demo.nro", "10.42.60.99", 1337, confirmed=True, fetcher=fetch, tree_factory=FakeTree)

if __name__ == "__main__":
    unittest.main()
