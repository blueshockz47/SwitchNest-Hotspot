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
