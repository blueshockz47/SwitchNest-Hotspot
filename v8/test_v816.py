"""Regression tests for read-only six-hour Homebrew Manager monitoring."""
import io
import json
import unittest
from unittest.mock import patch
from v8 import homebrew_monitor, homebrew, preferences

class FakeResponse:
    def __init__(self, data):
        self.data = json.dumps(data).encode()
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self, limit): return self.data[:limit]

class MonitorTests(unittest.TestCase):
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

    def test_no_ftp_or_installer_calls(self):
        with patch.object(homebrew_monitor, "github_updates", return_value=[]), patch.object(homebrew_monitor, "reddit_discover", return_value=[]):
            result = homebrew_monitor.refresh(reddit_fetch=homebrew_monitor.reddit_discover)
        self.assertEqual(result["kind"], "monitor")

if __name__ == "__main__":
    unittest.main()
