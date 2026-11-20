"""Nonprivileged Wi-Fi editor regression tests; no actual network changes."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import wifi_config as wifi

class WifiTests(unittest.TestCase):
    def test_ssid_utf8_bytes(self):
        wifi.validate("SwitchNest", "", 1)
        with self.assertRaises(ValueError):
            wifi.validate("🎮" * 9, "", 1)

    def test_password_and_channel_validation(self):
        for password in ("short", "a" * 64, "not\nprintable"):
            with self.assertRaises(ValueError):
                wifi.validate("SwitchNest", password, 1)
        with self.assertRaises(ValueError):
            wifi.validate("SwitchNest", "", 13)

    def test_backup_permissions_and_roundtrip(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(wifi, "BACKUP", Path(folder) / "backup.json"):
            previous = {key: "sample" for key in wifi.FIELDS}
            wifi.write_backup("123", previous)
            self.assertEqual(wifi.BACKUP.stat().st_mode & 0o777, 0o600)
            self.assertTrue(wifi.BACKUP.is_file())

    def test_apply_reverts_on_modify_failure(self):
        previous = {wifi.FIELDS[0]: "Original", wifi.FIELDS[1]: "bg", wifi.FIELDS[2]: "1", wifi.FIELDS[3]: "password123"}
        with patch.object(wifi, "uuid", return_value="identifier"), patch.object(wifi, "snapshot", return_value=previous), patch.object(wifi, "read_field", side_effect=["wpa-psk", "ap"]), patch.object(wifi, "write_backup"), patch.object(wifi, "adapter_check", return_value={"ap_supported": True, "channels": [1,6,11]}), patch.object(wifi, "command", side_effect=RuntimeError("denied")), patch.object(wifi, "restore_fields") as restore:
            with self.assertRaises(RuntimeError):
                wifi.apply("NewName", "", 6)
            restore.assert_called_once_with("identifier", previous)

if __name__ == "__main__":
    unittest.main()
