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
                      'text: "Connected devices"',
                      'model: root.clients', 'modelData.mac || "Unavailable"',
                      'modelData.ip || "Unavailable"',
                      'text: "Refresh devices"',
                      'association does not prove FTP connectivity'):
            self.assertIn(token, qml)
        self.assertIn('controller.action(root.hotspot.state === "on" ? "off" : "on")', qml)

    def test_phase3_ftp_windows_style_preserves_transfer_interactions(self):
        qml = (ROOT / "FtpPage.qml").read_text()
        for token in ('text: "FTP File Manager"',
                      'text: "THIS PC  /  FILE EXPLORER"',
                      'text: "NINTENDO SWITCH 2  /  FTP"',
                      'text: "Host"', 'text: "Port"',
                      'id: fileSplit', 'contentItem: RowLayout',
                      'page.localSelected.indexOf(modelData.name) >= 0',
                      'page.remoteSelected.indexOf(modelData.name) >= 0',
                      'page.finishDrag(parent, centroid.position)',
                      'ftpBrowser.open_remote_path("/switch/")',
                      'function transfer(side, names)',
                      'function deleteSelected()'):
            self.assertIn(token, qml)
        self.assertEqual(qml.count('implicitHeight: 44'), 2)
        self.assertEqual(qml.count('Behavior on color { ColorAnimation { duration: 100 } }'), 2)
        self.assertIn('id: localSearch', qml)
        self.assertIn('id: remoteSearch', qml)
        self.assertIn('Layout.preferredWidth: 112', qml)

    def test_phase4_homebrew_catalog_preserves_release_safety(self):
        qml = (ROOT / "HomebrewPage.qml").read_text()
        for token in ('text: "Homebrew Manager"', 'text: "RELEASE MONITOR"',
                      'text: "APP CATALOG"', 'id: categoryBox',
                      'model: home.categoryGroups', 'columns: 3',
                      'sourceComponent: homebrewCard', 'projectCard.hovered ? "#293e55" : "#1d293a"',
                      'home.installableRepos[home.actionRepo] === true',
                      'controller.homebrew_monitor_refresh(true)',
                      'controller.homebrew_releases(repo)',
                      'ftpBrowser.connect_to(ftpHost.text, ftpPort.text)',
                      'home.selectApp(projectCard.modelData)',
                      'downloadOnlyDialog.open()', 'installDialog.open()',
                      'ZIP File — Manual Install Required'):
            self.assertIn(token, qml)

    def test_linux_overview_connection_reminder(self):
        shell = (ROOT / "ControlCenter.qml").read_text()
        for instruction in (
            "Before You Connect",
            "Follow these 5 quick steps",
            "1. Airplane Mode",
            "2. Start Services",
            "3. Test With Your Phone",
            "confirm you're offline",
            "4. Connect Your Switch 2",
            "disable IPv6 in its network settings",
            "5. Use at Your Own Risk!",
            "An offline phone test does not guarantee complete network isolation.",
        ):
            self.assertIn(instruction, shell)
        self.assertNotIn("Turn ON Windows Mobile Hotspot before starting", shell)
        self.assertLess(shell.index("Before You Connect"), shell.index('heading: "HOTSPOT"'))

    def test_phase5_responsive_layout_and_backend_separation(self):
        shell = (ROOT / "ControlCenter.qml").read_text()
        ftp = (ROOT / "FtpPage.qml").read_text()
        homebrew = (ROOT / "HomebrewPage.qml").read_text()
        self.assertIn('columns: root.width < 1180 ? 2 : 4', shell)
        self.assertIn('rowSpacing: 8', shell)
        self.assertIn('minimumWidth: 900', shell)
        self.assertIn('Layout.minimumWidth: 130', shell)
        self.assertIn('SplitView.minimumWidth: 220', ftp)
        self.assertIn('function finishDrag(source, point)', ftp)
        self.assertIn('function clearSelection()', ftp)
        self.assertIn('function updateCatalog()', homebrew)
        self.assertIn('home.choices = data.assets.filter', homebrew)
        self.assertIn('home.ftpState.connected ? "Disconnect" : "Connect"', homebrew)
        self.assertIn('if (home.ftpState.connected) ftpBrowser.disconnect()', homebrew)

    def test_hotspot_and_diagnostics_controls_remain(self):
        qml = (ROOT / "ControlCenter.qml").read_text()
        for token in ('controller.action(', 'controller.refresh()', 'controller.wifi_restart()', 'controller.install_update()', 'controller.sunshine("start")'):
            self.assertIn(token, qml)
        self.assertIn('color: "#10151e"', qml)
        self.assertIn('visible: navEntry.selected', qml)

if __name__ == "__main__":
    unittest.main()
