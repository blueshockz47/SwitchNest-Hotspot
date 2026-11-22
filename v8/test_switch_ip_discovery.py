"""Regression checks for shared, read-only Switch 2 FTP endpoint discovery."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent


class DiscoveryWiringTests(unittest.TestCase):
    def test_backend_is_async_bounded_and_does_not_auto_connect(self):
        source = (ROOT / "ftp_browser.py").read_text()
        for token in ("def find_switch_ip(self):", "ThreadPoolExecutor(max_workers=32)", 'range(2, 255)', "socket.create_connection", "self.discovery_finished.emit(matches)", "def _apply_discovery(self, matches):", "self.settings.setValue(\"host\", self.host)"):
            self.assertIn(token, source)
        block = source.split("def _apply_discovery(self, matches):", 1)[1].split("def queue_summary(self):", 1)[0]
        self.assertNotIn("self.connect_to(", block)

    def test_both_managers_expose_shared_discovery(self):
        for filename in ("FtpPage.qml", "HomebrewPage.qml"):
            ui = (ROOT / filename).read_text()
            self.assertIn('"Find Switch 2 IP"', ui)
            self.assertIn("ftpBrowser.find_switch_ip()", ui)
            self.assertIn("discoveryStatus", ui)
            self.assertIn("discoveryBusy", ui)


if __name__ == "__main__":
    unittest.main()
