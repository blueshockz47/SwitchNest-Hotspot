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

    def test_overview_status_tiles_and_station_table(self):
        qml = (ROOT / "ControlCenter.qml").read_text()
        for token in ('text: "Network overview"', 'heading: "HOTSPOT"',
                      'heading: "DNS"', 'heading: "HTTP"',
                      'heading: "ISOLATION"', 'text: "Connected devices"',
                      'model: root.clients', 'modelData.mac || "Unavailable"',
                      'modelData.ip || "Unavailable"',
                      'text: "Refresh devices"',
                      'association does not prove FTP connectivity',
                      'Network isolation remains unverified'):
            self.assertIn(token, qml)
        self.assertIn('controller.action(root.hotspot.state === "on" ? "off" : "on")', qml)

    def test_phase3_ftp_windows_style_preserves_transfer_interactions(self):
        qml = (ROOT / "FtpPage.qml").read_text()
        for token in ('text: "FTP File Manager"',
                      'text: "THIS PC  /  FILE EXPLORER"',
                      'text: "NINTENDO SWITCH 2  /  FTP"',
                      'text: "Host"', 'text: "Port"',
                      'id: fileSplit', 'page.fileLabel(modelData)',
                      'page.localSelected.indexOf(modelData.name) >= 0',
                      'page.remoteSelected.indexOf(modelData.name) >= 0',
                      'page.finishDrag(parent, centroid.position)',
                      'ftpBrowser.open_remote_path("/switch/")',
                      'function transfer(side, names)',
                      'function deleteSelected()'):
            self.assertIn(token, qml)
        self.assertEqual(qml.count('implicitHeight: 34'), 2)
        self.assertEqual(qml.count('Behavior on color { ColorAnimation { duration: 100 } }'), 2)

    def test_phase4_homebrew_catalog_preserves_release_safety(self):
        qml = (ROOT / "HomebrewPage.qml").read_text()
        for token in ('text: "Homebrew Manager"', 'text: "RELEASE MONITOR"',
                      'text: "APP CATALOG"', 'id: categoryBox',
                      'model: home.categoryGroups', 'columns: 3',
                      'sourceComponent: homebrewCard', 'color: "#1d293a"',
                      'home.installableRepos[home.actionRepo] === true',
                      'controller.homebrew_monitor_refresh(true)',
                      'controller.homebrew_releases(actionRepo)',
                      'ftpBrowser.connect_to(ftpHost.text, ftpPort.text)',
                      'home.selectApp(projectCard.modelData)',
                      'downloadOnlyDialog.open()', 'installDialog.open()',
                      'ZIP File — Manual Install Required'):
            self.assertIn(token, qml)

    def test_hotspot_and_diagnostics_controls_remain(self):
        qml = (ROOT / "ControlCenter.qml").read_text()
        for token in ('controller.action(', 'controller.refresh()', 'controller.wifi_restart()', 'controller.install_update()', 'controller.sunshine("start")'):
            self.assertIn(token, qml)
        self.assertIn('color: "#10151e"', qml)
        self.assertIn('visible: navEntry.selected', qml)

if __name__ == "__main__":
    unittest.main()
