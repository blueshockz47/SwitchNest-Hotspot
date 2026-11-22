"""Regression guards for phase 2b's non-invasive FTP queue projection."""
from pathlib import Path
import unittest
from v8.transfer_queue import TransferQueue, Status

ROOT = Path(__file__).resolve().parent


class Phase2bTests(unittest.TestCase):
    def test_queue_lifecycle_mirrors_top_level_transfers(self):
        queue = TransferQueue()
        queue.load(['alpha', 'beta'])
        self.assertEqual(queue.start_next(), 'alpha')
        queue.finish(Status.COMPLETED)
        self.assertEqual(queue.start_next(), 'beta')
        queue.finish(Status.INTERRUPTED, 'connection lost')
        self.assertEqual([x['status'] for x in queue.snapshot()], ['Completed', 'Interrupted'])
        self.assertEqual(queue.snapshot()[1]['error'], 'connection lost')

    def test_cancel_pending_does_not_mark_completed_entry(self):
        queue = TransferQueue()
        queue.load(['one', 'two', 'three'])
        queue.start_next()
        queue.finish(Status.COMPLETED)
        queue.cancel_waiting()
        self.assertEqual([x['status'] for x in queue.snapshot()], ['Completed', 'Cancelled', 'Cancelled'])

    def test_phase3a_dolphin_toolbar_preserves_actions(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        self.assertIn('ToolBar {', ui)
        self.assertIn('id: ftpActions', ui)
        self.assertIn('text: "More ▾"', ui)
        self.assertIn('page.transfer("local",page.localSelected)', ui)
        self.assertIn('page.transfer("remote",page.remoteSelected)', ui)
        self.assertIn('ftpBrowser.refresh()', ui)
        self.assertIn('page.editEntry("mkdir")', ui)
        self.assertIn('page.deleteSelected()', ui)
        self.assertIn('ftpBrowser.cancel()', ui)
        self.assertIn('queueDialog.open()', ui)
        self.assertIn('historyDialog.open()', ui)
        self.assertIn('page.copyFiles()', ui)
        self.assertIn('page.pasteFiles()', ui)
        self.assertIn('page.selectAll()', ui)
        self.assertIn('page.clearSelection()', ui)
        self.assertIn('page.dataState.busy', ui)
        self.assertEqual(ui.count('page.deleteSelected()'), 3)

    def test_phase3b_navigation_selection_and_docked_queue(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        for required in (
            'function selectRange(side, name, modifiers)',
            'Qt.ShiftModifier',
            'Qt.ControlModifier',
            'function openDirectory(side, name)',
            'page.openDirectory("local","..")',
            'page.openDirectory("remote","..")',
            'property bool queueExpanded: false',
            'text: page.queueExpanded ? "Hide queue" : "Show queue"',
            'visible: page.queueExpanded',
            'model: page.dataState.transferItems || []',
            'page.dataState.queueSummary',
            'page.notification = next',
        ):
            self.assertIn(required, ui)
        self.assertIn('ftpBrowser.tree_batch(', ui)
        self.assertIn('ftpBrowser.tree_batch_into(', ui)
        self.assertIn('ftpBrowser.delete_batch(', ui)
        self.assertIn('ftpBrowser.cancel()', ui)

    def test_switch2_quick_access(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        backend = (ROOT / 'ftp_browser.py').read_text()
        for token in ('function switchBookmarks()', 'function remoteSegments()',
                      'ftpBrowser.open_remote_path(modelData.path)',
                      'ftpBrowser.bookmark("remote")',
                      'ftpBrowser.open_bookmark(modelData.index)',
                      'ftpBrowser.copy_remote_path()',
                      'page.openDirectory("remote",modelData.name)'):
            self.assertIn(token, ui)
        for token in ('def open_remote_path(self, path):',
                      'def copy_remote_path(self):',
                      'remoteRecent=self.remote_recent',
                      'self.valid_name(part)'):
            self.assertIn(token, backend)

    def test_compact_switch_header_and_shortcut(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        for token in ('text: "📁 /switch"',
                      'ftpBrowser.open_remote_path("/switch/")',
                      'id: switchQuickMenu', 'id: switchActionsMenu',
                      'text: "Pin current folder"', 'text: "Copy current path"'):
            self.assertIn(token, ui)
        self.assertNotIn('id: switchPlacesExpanded', ui)
        self.assertNotIn('text: page.switchPlacesExpanded ?', ui)
        self.assertNotIn('text: page.switchTreeExpanded ?', ui)

    def test_phase3d_resizable_details_and_transfer_status(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        for token in ('SplitView {', 'id: fileSplit',
                      'SplitView.minimumWidth: 220',
                      'property bool showDetails: true',
                      'function typeText(row)', 'function fileLabel(row)',
                      'text: page.fileLabel(modelData)',
                      'text: "Details"', 'page.dataState.current || ""'):
            self.assertIn(token, ui)
        self.assertEqual(ui.count('text: page.fileLabel(modelData)'), 2)
        self.assertIn('page.finishDrag(parent, centroid.position)', ui)

    def test_cross_pane_selection_clears_inactive_highlight(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        self.assertIn('if (side === "local") { localSelected=result; remoteSelected=[] }', ui)
        self.assertIn('else { remoteSelected=result; localSelected=[] }', ui)
        self.assertIn('selected.indexOf(name) >= 0 ? selected.slice() : [name]', ui)

    def test_navigation_polish_preserves_shortcuts(self):
        ui = (ROOT / 'FtpPage.qml').read_text()
        self.assertEqual(ui.count('text: "↑  Up one level"'), 2)
        self.assertIn('highlighted: page.dataState.remote === "/"', ui)
        self.assertIn('highlighted: page.dataState.remote === "/switch/"', ui)
        self.assertIn('ftpBrowser.open_remote_path("/")', ui)
        self.assertIn('ftpBrowser.open_remote_path("/switch/")', ui)
        self.assertIn('page.openDirectory("local","..")', ui)
        self.assertIn('page.openDirectory("remote","..")', ui)
        self.assertIn('Behavior on color { ColorAnimation { duration: 120 } }', ui)

    def test_ui_and_backend_wiring_preserve_worker(self):
        backend = (ROOT / 'ftp_browser.py').read_text()
        ui = (ROOT / 'FtpPage.qml').read_text()
        self.assertIn('self.smart_queue = TransferQueue()', backend)
        self.assertIn('self.smart_queue.start_next()', backend)
        self.assertIn('self.smart_queue.finish(Status.COMPLETED)', backend)
        self.assertIn('tree.upload(local/name,remote)', backend)
        self.assertIn('tree.download(remote,name,local,allowed[name])', backend)
        self.assertIn('transferItems=self.transfer_items', backend)
        self.assertIn('queueSummary', backend)
        self.assertIn('queueSummary', ui)
        self.assertIn('page.finishDrag(parent, centroid.position)', ui)
        self.assertIn('selected.indexOf(name) >= 0 ? selected.slice() : [name]', ui)
        self.assertIn('transfer(side, names)', ui)
        self.assertEqual(ui.count('page.deleteSelected()'), 3)  # toolbar and both context menus
        self.assertEqual(ui.count('selected.indexOf(page.entryName) >= 0 && selected.length > 1'), 2)
        self.assertEqual(ui.count('page.editEntry("delete")'), 2)  # single-file fallback
        self.assertIn('ftpBrowser.cancel()', ui)


if __name__ == '__main__':
    unittest.main()
