"""v8.0.8 non-network regression tests."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import wifi_reliability as wr
from v8 import diagnostics

class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.patches = [
            patch.object(wr, "BASE", root),
            patch.object(wr, "PRESETS", root / "presets.json"),
            patch.object(wr, "EVENTS", root / "events.json"),
        ]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def test_presets_never_store_password(self):
        wr.save_preset("Steam Machine", "SteamMachine", 1)
        self.assertEqual(wr.select_preset("Steam Machine"),
                         {"ssid": "SteamMachine", "channel": 1})
        self.assertNotIn("password", wr.PRESETS.read_text().lower())
        self.assertEqual(wr.PRESETS.stat().st_mode & 0o777, 0o600)

    def test_preset_validation(self):
        for name, ssid, channel in (("../bad", "SSID", 1),
                                    ("Valid", "", 1),
                                    ("Valid", "SSID", 13)):
            with self.assertRaises(ValueError):
                wr.save_preset(name, ssid, channel)

    def test_events_bounded_and_redacted(self):
        for _ in range(120):
            wr.event("restart_verified", "ok")
        self.assertEqual(len(wr.history()), 100)
        with self.assertRaises(ValueError):
            wr.event("restart_failed", "password123")
        self.assertEqual(wr.EVENTS.stat().st_mode & 0o777, 0o600)

    def test_health_is_read_only(self):
        healthy = {"hotspot": {"state": "on"}, "dns_service": {"output": "active"},
                   "hotspot_service": {"output": "active"}}
        self.assertEqual(wr.health(healthy)["state"], "healthy")
        healthy["dns_service"]["output"] = "inactive"
        self.assertEqual(wr.health(healthy)["state"], "attention")
        self.assertEqual(wr.health({"hotspot": {"state": "off"}})["state"], "inactive")

    def test_live_station_metrics_are_read_only(self):
        station = ("Station aa:bb:cc:dd:ee:ff (on wlan0)\\n"
                   "  signal: -52 dBm\\n"
                   "  connected time: 31 seconds\\n"
                   "  rx bytes: 2048\\n"
                   "  tx bytes: 1024\\n")
        def fake_probe(argv):
            if argv[:3] == ["nmcli", "-g", "connection.uuid"]:
                return {"ok": True, "output": "12345678-1234-1234-1234-123456789012"}
            if argv[:4] == ["nmcli", "-g", "UUID", "connection"]:
                return {"ok": True, "output": "12345678-1234-1234-1234-123456789012"}
            if "GENERAL.DEVICES" in argv:
                return {"ok": True, "output": "wlan0"}
            if argv[:2] == ["iw", "dev"]:
                return {"ok": True, "output": station}
            return {"ok": True, "output": "active"}
        with patch.object(diagnostics, "probe", side_effect=fake_probe), patch.object(diagnostics, "connected_clients", return_value=[{"mac": "aa:bb:cc:dd:ee:ff", "ip": None, "status": "Associated"}]):
            client = diagnostics.hotspot()["clients"][0]
        self.assertEqual(client["signal"], -52)
        self.assertEqual(client["connected_seconds"], 31)
        self.assertEqual(client["rx_bytes"], 2048)

    def test_client_view(self):
        report = {"hotspot": {"clients": [{"mac": "aa:bb", "signal": -50, "rx_bytes": 1024}]}}
        self.assertEqual(wr.live_clients(report)[0]["signal"], -50)

if __name__ == "__main__":
    unittest.main()
