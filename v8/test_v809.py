"""v8.0.9 regression suite: offline and no privileged network changes."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from v8 import stability, install, diagnostics, updates

class StabilityTests(unittest.TestCase):
    def test_recovery_bounded_and_cooldown(self):
        self.assertTrue(stability.recovery_allowed(0, None, now=100))
        self.assertFalse(stability.recovery_allowed(1, None, now=100))
        self.assertFalse(stability.recovery_allowed(0, 50, now=100))
        self.assertTrue(stability.recovery_allowed(0, 50, now=170))

    def test_self_test_is_read_only(self):
        report = {"hotspot": {"state": "on", "interface": "wlan0",
                              "ip": "10.42.60.1/24", "clients": [{"mac": "aa:bb:cc:dd:ee:ff"}]},
                  "hotspot_service": {"output": "active"},
                  "dns_service": {"output": "active"},
                  "firewall": {"ok": True}}
        with patch.object(diagnostics, "probe", side_effect=AssertionError("Must not probe")):
            result = stability.self_test(report)
        self.assertEqual(result["state"], "healthy")
        report["dns_service"]["output"] = "inactive"
        self.assertEqual(stability.self_test(report)["state"], "attention")

    def test_export_redacts_private_fields_and_is_private(self):
        report = {"hotspot": {"state": "on", "ssid": "PrivateSSID",
                              "mac": "aa:bb:cc:dd:ee:ff", "ip": "10.42.60.1",
                              "password": "password123"},
                  "dns_service": {"output": "active"},
                  "hotspot_service": {"output": "active"}}
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/"report.json"
            stability.export_report(report, path, history=[{"event": "restart_verified", "detail": "ok", "time": "2026-11-20T10:00:00Z"}])
            raw = path.read_text()
            for secret in ("PrivateSSID", "aa:bb:cc:dd:ee:ff", "10.42.60.1", "password123"):
                self.assertNotIn(secret, raw)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(raw)["version"], "8.0.9")

    def test_export_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d)/"report.json"
            dest.symlink_to(Path(d)/"other")
            with self.assertRaises(ValueError):
                stability.export_report({}, dest, history=[])

    def test_installer_verification_and_repair_is_scoped(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            release = root/"releases"/"v809"
            (release/"v8").mkdir(parents=True)
            for name in ("control_center.py", "ControlCenter.qml"):
                (release/"v8"/name).write_text("")
            (release/"venv/bin").mkdir(parents=True)
            (release/"venv/bin/python").write_text("")
            (root/"launch").write_text("launcher")
            (root/"launch").chmod(0o700)
            with patch.object(install, "ROOT", root):
                self.assertTrue(install.verify_installation(release)["ok"])
                (release/"v8"/"ControlCenter.qml").unlink()
                self.assertFalse(install.verify_installation(release)["ok"])

    def test_telemetry_and_version(self):
        self.assertEqual(updates.VERSION, "8.0.9")
        self.assertEqual(install.VERSION, "8.0.9")
        self.assertEqual(diagnostics.collect.__module__, "v8.diagnostics")

if __name__ == "__main__":
    unittest.main()
