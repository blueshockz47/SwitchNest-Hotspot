"""Unit tests for read-only Fedora security preflight."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fedora_security_preflight import diagnose, is_fedora


class FedoraPreflightTests(unittest.TestCase):
    def test_detect_fedora(self):
        self.assertTrue(is_fedora('NAME="Fedora Linux"\nID=fedora\nVERSION_ID=45'))
        self.assertTrue(is_fedora('ID=custom\nID_LIKE="fedora rhel"'))
        self.assertFalse(is_fedora('ID=steamos\nID_LIKE=arch'))

    def test_enforcing_firewall_running(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "os-release"
            path.write_text("ID=fedora\nVERSION_ID=45")
            with patch("fedora_security_preflight.shutil.which", return_value="/usr/bin/tool"), patch(
                "fedora_security_preflight._run", side_effect=["running", "Enforcing"]
            ):
                result = diagnose(str(path))
        self.assertTrue(result.fedora)
        self.assertEqual(result.firewalld, "running")
        self.assertEqual(result.selinux, "enforcing")
        self.assertEqual(len(result.recommendations), 2)

    def test_missing_tools(self):
        with patch("fedora_security_preflight.shutil.which", return_value=None):
            result = diagnose("/does/not/exist")
        self.assertEqual(result.firewalld, "unavailable")
        self.assertEqual(result.selinux, "unavailable")
        self.assertFalse(result.fedora)


if __name__ == "__main__":
    unittest.main()
