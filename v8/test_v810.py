import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import homebrew

class HomebrewTests(unittest.TestCase):
    def test_expanded_catalog_and_filters(self):
        rows = homebrew.catalog_search()
        self.assertGreaterEqual(len(rows), 25)
        self.assertEqual([x["name"] for x in homebrew.catalog_search("retroarch")], ["RetroArch"])
        self.assertEqual([x["name"] for x in homebrew.catalog_search("moonlight")], ["Moonlight"])
        self.assertEqual(homebrew.catalog_search("moonlight")[0]["status"], "Browse-only")
        self.assertTrue(all(x["category"] == "Streaming" for x in homebrew.catalog_search(category="Streaming")))
        self.assertEqual(homebrew.catalog_search("unrelated-app"), [])
        with self.assertRaises(ValueError):
            homebrew.catalog_search(category="../invalid")


    def test_discovery_only_returns_switch2_candidates(self):
        seen = []
        def fetch(path):
            seen.append(path)
            return {"full_name": "NerdsMcGee/retroarch-s2", "id": 42}
        rows = homebrew.discover("retroarch", fetch)
        self.assertEqual([x["repo"] for x in rows], ["NerdsMcGee/retroarch-s2"])
        self.assertEqual(seen, ["/repos/NerdsMcGee/retroarch-s2"])
        self.assertFalse(rows[0]["verified"])

    def test_discovery_rejects_untrusted_metadata(self):
        def fetch(_):
            return {"full_name": "other/retroarch", "id": 42}
        self.assertEqual(homebrew.discover("retroarch", fetch), [])

    def test_unrelated_query_does_not_query_github(self):
        def fetch(_):
            raise AssertionError("Unrelated repository was queried")
        self.assertEqual(homebrew.discover("windows-retroarch", fetch), [])

    def test_large_zip_is_listed_but_install_rejected(self):
        import hashlib
        size = 504925907
        digest = "sha256:" + hashlib.sha256(b"test").hexdigest()
        def fetch(_):
            return {"tag_name": "switch2-v0.5.0", "assets": [{
                "name": "retroarch-switch2-v0.5.0.zip",
                "browser_download_url": "https://github.com/NerdsMcGee/retroarch-s2/releases/download/switch2-v0.5.0/retroarch-switch2-v0.5.0.zip",
                "size": size, "digest": digest
            }, {
                "name": "SHA256SUMS.txt",
                "browser_download_url": "https://github.com/NerdsMcGee/retroarch-s2/releases/download/switch2-v0.5.0/SHA256SUMS.txt",
                "size": 2909, "digest": digest
            }]}
        result = homebrew.release_assets("NerdsMcGee/retroarch-s2", fetch)
        self.assertEqual(result["version"], "switch2-v0.5.0")
        self.assertEqual([a["name"] for a in result["assets"]],
                         ["retroarch-switch2-v0.5.0.zip", "SHA256SUMS.txt"])
        self.assertTrue(all(a["system"] for a in result["assets"]))
        with self.assertRaises(ValueError):
            homebrew.install_nro(result["assets"][0],
                                 "/switch/retroarch-switch2-v0.5.0.zip",
                                 "10.42.60.99", 1337, confirmed=True)

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

class ZipWorkflowTests(unittest.TestCase):
    def test_smoketest_archive_is_isolated(self):
        from v8 import ftp_install_smoketest, homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            archive = Path(td) / "test.zip"
            plan = ftp_install_smoketest.build(archive)
            self.assertEqual(plan["count"], 3)
            self.assertTrue(all(x["path"].startswith("switch/switchnest-ftp-test-v810/")
                                for x in plan["files"]))
            self.assertEqual(plan, homebrew_zip.inspect_zip(archive))


    def make_zip(self, root, entries):
        import zipfile
        path = Path(root) / "package.zip"
        with zipfile.ZipFile(path, "w") as z:
            for name, payload in entries:
                z.writestr(name, payload)
        return path

    def test_safe_preview_and_confirmation(self):
        from v8 import homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            path = self.make_zip(td, [("switch/demo.nro", b"data")])
            plan = homebrew_zip.inspect_zip(path)
            self.assertEqual(plan["sample"], ["/switch/demo.nro"])
            with self.assertRaises(PermissionError):
                homebrew_zip.install_zip(path, plan, "10.42.60.99", 1337)

    def test_rejects_traversal_symlinks_and_duplicate_names(self):
        from v8 import homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            for name in ("../evil.nro", "/evil.nro", "switch/../../evil.nro"):
                path = self.make_zip(td, [(name, b"x")])
                with self.assertRaises(ValueError):
                    homebrew_zip.inspect_zip(path)
            path = self.make_zip(td, [("switch/DEMO.nro", b"a"), ("switch/demo.nro", b"b")])
            with self.assertRaises(ValueError):
                homebrew_zip.inspect_zip(path)

    def test_rejects_unverified_or_oversized_download(self):
        from v8 import homebrew_zip
        with self.assertRaises(ValueError):
            homebrew_zip.download_zip({"name": "demo.zip", "size": 10, "digest": ""})
        with self.assertRaises(ValueError):
            homebrew_zip.download_zip({"name": "demo.zip", "size": 2**31,
                "digest": "sha256:" + "a" * 64})

    def test_cancel_before_ftp_write(self):
        from v8 import homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            path = self.make_zip(td, [("demo.nro", b"data")])
            plan = homebrew_zip.inspect_zip(path)
            class FakeTree:
                def __init__(self, *args): pass
                def entries(self, directory): return {}
            with self.assertRaises(InterruptedError):
                homebrew_zip.install_zip(path, plan, "10.42.60.99", 1337,
                    confirmed=True, tree_factory=FakeTree, cancelled=lambda: True)

    def test_upload_progress_and_verified_resume(self):
        from v8 import homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            path = self.make_zip(td, [("demo.nro", b"data")])
            plan = homebrew_zip.inspect_zip(path)
            remote = {}
            updates = []
            class FakeTree:
                def __init__(self, *args):
                    self.metric = lambda *_: None
                def entries(self, directory):
                    return {name: False for name in remote}
                def sizes(self, directory):
                    return {name: len(data) for name, data in remote.items()}
                def upload(self, source, directory):
                    remote[source.name] = source.read_bytes()
                    self.metric(len(remote[source.name]), len(remote[source.name]), 100)
                def run(self, path, args, size=None):
                    if "--output" in args:
                        Path(args[args.index("--output") + 1]).write_bytes(
                            remote[path.rsplit("/", 1)[-1]])
            for _ in range(2):
                homebrew_zip.install_zip(path, plan, "10.42.60.99", 1337,
                    confirmed=True, tree_factory=FakeTree,
                    progress=lambda *args: updates.append(args))
            self.assertEqual(remote["demo.nro"], b"data")
            self.assertEqual(updates[-1][0], 4)
            self.assertEqual(updates[-1][-1], "Verified existing file")

    def test_preflight_rejects_existing_remote_file(self):
        from v8 import homebrew_zip
        with tempfile.TemporaryDirectory() as td:
            path = self.make_zip(td, [("demo.nro", b"data")])
            plan = homebrew_zip.inspect_zip(path)
            class FakeTree:
                def __init__(self, *args): pass
                def entries(self, path): return {"demo.nro": False}
                def sizes(self, path): return {"demo.nro": 999}
            with self.assertRaises(FileExistsError):
                homebrew_zip.install_zip(path, plan, "10.42.60.99", 1337,
                                         confirmed=True, tree_factory=FakeTree)

if __name__ == "__main__":
    unittest.main()
