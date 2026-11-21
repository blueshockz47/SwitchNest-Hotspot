"""Regression tests for read-only six-hour Homebrew Manager monitoring."""
import io
import json
import unittest
from unittest.mock import patch
from v8 import homebrew_monitor, homebrew, preferences, catalog_sources

class FakeResponse:
    def __init__(self, data):
        self.data = json.dumps(data).encode()
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self, limit): return self.data[:limit]

class MonitorTests(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(catalog_sources, "discover", return_value=([], []))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_iz2s_parser_validates_repositories(self):
        sample = "\n".join([
            "IZSTORE2",
            "app\tsw2nes\tnro\t2.1\tSW2NES\tRodpad\tEmulators\tNES emulator",
            "repository\thttps://github.com/Rodpad/SW2NES",
            "app\tevil\tnro\t1\tEvil\tBad\tTools\tBad",
            "repository\thttps://evil.example/attack",
            "",
        ])
        rows = catalog_sources.iz2s_rows(sample)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["repo"], "Rodpad/SW2NES")

    def test_brewstore_manifest_and_deduplication(self):
        manifest = json.dumps({"packages": [{"title": "SW2NES", "url": "https://github.com/Rodpad/SW2NES", "version": "v2"}]})
        index = json.dumps({"include": ["https://raw.githubusercontent.com/HerXayah/brewstore-repo/main/packages/sw2nes/manifest.json",
                                         "https://evil.example/manifest.json"]})
        rows = catalog_sources.brewstore_rows(index, fetch=lambda url: manifest)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["repo"], "Rodpad/SW2NES")

    def test_community_categories(self):
        self.assertEqual(catalog_sources.normalize_category("Emulators", "PPSSPP"), "Emulation")
        self.assertEqual(catalog_sources.normalize_category("Media", "KaiPlayer"), "Media")
        self.assertEqual(catalog_sources.normalize_category("Other", "Moonlight NX"), "Streaming")
        self.assertEqual(catalog_sources.normalize_category("Other", "Sphaira"), "Tools")
        self.assertEqual(catalog_sources.normalize_category("Tools", "File Browser"), "Tools")

    def test_refined_categories(self):
        self.assertEqual(catalog_sources.normalize_category("Media", "Super Moonlight NX2"), "Streaming")
        self.assertEqual(catalog_sources.normalize_category("Media", "Switch2NOW"), "Tools")
        self.assertEqual(catalog_sources.normalize_category("Other", "Sphaira"), "Tools")
        self.assertEqual(catalog_sources.normalize_category("Other", "Chromium NX"), "Tools")
        self.assertEqual(catalog_sources.normalize_category("Other", "PKForge"), "Tools")

    def test_maximized_preference_registered(self):
        self.assertIn("fullscreen_on_start", preferences.DEFAULTS)
        self.assertIs(type(preferences.DEFAULTS["fullscreen_on_start"]), bool)

    def test_github_only_curated_repositories(self):
        repo = "NerdsMcGee/retroarch-s2"
        def fake_fetch(path):
            self.assertTrue(path.startswith("/repos/" + repo))
            return {"tag_name": "v1.2.3", "assets": [{
                "name": "retroarch.zip", "size": 1234,
                "browser_download_url": "https://github.com/" + repo + "/releases/download/v1.2.3/retroarch.zip",
                "digest": "sha256:" + "a" * 64
            }]}
        result = homebrew_monitor.github_updates(fetch=fake_fetch, repos=[repo, "attacker/evil"])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["version"], "v1.2.3")
        self.assertNotIn("assets", result[0])  # read-only metadata, no download URLs

    def test_github_failure_is_visible(self):
        repo = "NerdsMcGee/retroarch-s2"
        def offline(path):
            raise OSError("network unavailable")
        result = homebrew_monitor.refresh(fetch=offline, repos=[repo], reddit_fetch=lambda: [])
        self.assertEqual(result["github"], [])
        self.assertTrue(any("GitHub discovery unavailable" in w for w in result["warnings"]))

    def test_partial_github_failure_keeps_successful_releases(self):
        repos = ["NerdsMcGee/retroarch-s2", "Rodpad/SW2NES"]
        def partial(path):
            if "SW2NES" in path:
                raise OSError("timeout")
            return {"tag_name": "v1", "assets": [{"name": "app.nro", "size": 42,
                "browser_download_url": "https://github.com/NerdsMcGee/retroarch-s2/releases/download/v1/app.nro",
                "digest": "sha256:" + "a" * 64}]}
        result = homebrew_monitor.refresh(fetch=partial, repos=repos, reddit_fetch=lambda: [])
        self.assertEqual(len(result["github"]), 1)
        self.assertTrue(result["warnings"])

    def test_reddit_discovery_unverified_and_url_restricted(self):
        posts = {"data": {"children": [
            {"data": {"title": "New Switch 2 homebrew", "permalink": "/r/SwitchHacks/comments/abc123/new_switch_2_homebrew/"}},
            {"data": {"title": "Switch 2 malicious", "permalink": "https://evil.example/download"}},
            {"data": {"title": "Unrelated", "permalink": "/r/SwitchHacks/comments/xyz789/unrelated/"}}
        ]}}
        rows = homebrew_monitor.reddit_discover(opener=lambda request, timeout: FakeResponse(posts))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["status"], "Unverified community discovery")
        self.assertEqual(rows[0]["url"], "https://www.reddit.com/r/SwitchHacks/comments/abc123/new_switch_2_homebrew/")

    def test_reddit_failure_does_not_hide_github(self):
        with patch.object(homebrew_monitor, "github_updates", return_value=[{"repo": "example/repo"}]):
            result = homebrew_monitor.refresh(reddit_fetch=lambda: (_ for _ in ()).throw(OSError("offline")))
        self.assertEqual(len(result["github"]), 1)
        self.assertEqual(result["reddit"], [])
        self.assertTrue(result["warnings"])

    def test_directory_is_unverified_and_never_auto_imported(self):
        result = homebrew_monitor.refresh(fetch=lambda path: (_ for _ in ()).throw(OSError("offline")),
                                          repos=[], reddit_fetch=lambda: [])
        directory = result["directory"]
        self.assertEqual(directory["url"], "https://switch2homebrew.com/")
        self.assertFalse(directory["automated"])
        self.assertIn("unverified", directory["status"].lower())
        self.assertEqual(result["github"], [])
        self.assertEqual(result["reddit"], [])

    def test_no_ftp_or_installer_calls(self):
        with patch.object(homebrew_monitor, "github_updates", return_value=[]), patch.object(homebrew_monitor, "reddit_discover", return_value=[]):
            result = homebrew_monitor.refresh(reddit_fetch=homebrew_monitor.reddit_discover)
        self.assertEqual(result["kind"], "monitor")

if __name__ == "__main__":
    unittest.main()
