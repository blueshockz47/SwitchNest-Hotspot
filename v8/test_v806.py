"""Unit tests for v8.0.6 read-only client mapping and preferences."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import diagnostics, preferences

class ClientTests(unittest.TestCase):
    def test_clients_only_associated(self):
        with patch.object(diagnostics, "probe", return_value={"ok": True, "output": "10.42.60.20 dev wlan0 lladdr aa:bb:cc:dd:ee:ff REACHABLE\n10.42.60.21 dev wlan0 lladdr 11:22:33:44:55:66 STALE"}):
            clients = diagnostics.connected_clients("wlan0", ["aa:bb:cc:dd:ee:ff"])
        self.assertEqual(clients, [{"mac": "aa:bb:cc:dd:ee:ff", "ip": "10.42.60.20", "status": "Associated"}])

    def test_no_station_no_probe(self):
        with patch.object(diagnostics, "probe") as probe:
            self.assertEqual(diagnostics.connected_clients("wlan0", []), [])
            probe.assert_not_called()

class PreferenceTests(unittest.TestCase):
    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(preferences, "PATH", Path(folder) / "prefs.json"):
            self.assertEqual(preferences.load(), preferences.DEFAULTS)
            preferences.save("show_update_popup", False)
            self.assertFalse(preferences.load()["show_update_popup"])
            self.assertTrue(preferences.load()["stable_only"])

    def test_maximized_startup_preference_round_trip(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(preferences, "PATH", Path(folder) / "prefs.json"):
            self.assertFalse(preferences.load()["fullscreen_on_start"])
            preferences.save("fullscreen_on_start", True)
            self.assertTrue(preferences.load()["fullscreen_on_start"])
            preferences.save("fullscreen_on_start", False)
            self.assertFalse(preferences.load()["fullscreen_on_start"])

    def test_invalid_preference_rejected(self):
        with self.assertRaises(ValueError):
            preferences.save("unknown", True)
        with self.assertRaises(ValueError):
            preferences.save("stable_only", "no")

if __name__ == "__main__":
    unittest.main()
