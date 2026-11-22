"""Regression checks for the Windows-inspired Linux Control Center shell."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent

class WindowsStyleShellTests(unittest.TestCase):
    def test_dedicated_sidebar_routes_to_existing_file_tabs(self):
        qml = (ROOT / "ControlCenter.qml").read_text()
        self.assertIn('NavButton { text: "▣    FTP Manager"; page: 3; fileTab: 0 }', qml)
        self.assertIn('NavButton { text: "◆    Homebrew"; page: 3; fileTab: 1 }', qml)
        self.assertIn('if (fileTab >= 0) fileTabs.currentIndex = fileTab', qml)
        self.assertIn('FtpPage {}', qml)
        self.assertIn('HomebrewPage {}', qml)
        self.assertIn('currentIndex: fileTabs.currentIndex', qml)

    def test_hotspot_and_diagnostics_controls_remain(self):
        qml = (ROOT / "ControlCenter.qml").read_text()
        for token in ('controller.action(', 'controller.refresh()', 'controller.wifi_restart()', 'controller.install_update()', 'controller.sunshine("start")'):
            self.assertIn(token, qml)
        self.assertIn('color: "#10151e"', qml)
        self.assertIn('visible: navEntry.selected', qml)

if __name__ == "__main__":
    unittest.main()
