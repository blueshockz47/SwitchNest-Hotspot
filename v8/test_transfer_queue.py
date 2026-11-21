"""Regression tests for Phase 2 queue lifecycle; no FTP or hotspot needed."""
import unittest
from v8.transfer_queue import TransferQueue, Status


class TransferQueueTests(unittest.TestCase):
    def test_sequential_and_progress(self):
        q = TransferQueue()
        q.load(["one.nro", "two.nro"])
        self.assertEqual(q.start_next(), "one.nro")
        q.progress(5, 10)
        self.assertEqual(q.snapshot()[0]["bytesDone"], 5)
        q.finish(Status.COMPLETED)
        self.assertEqual(q.start_next(), "two.nro")
        q.finish(Status.COMPLETED)
        self.assertIsNone(q.start_next())

    def test_reject_parallel_and_invalid_progress(self):
        q = TransferQueue()
        q.load(["a"])
        q.start_next()
        with self.assertRaises(RuntimeError):
            q.start_next()
        with self.assertRaises(ValueError):
            q.progress(11, 10)

    def test_cancel_only_waiting(self):
        q = TransferQueue()
        q.load(["a", "b"])
        q.start_next()
        q.cancel_waiting()
        self.assertEqual(q.entries[0].status, Status.ACTIVE)
        self.assertEqual(q.entries[1].status, Status.CANCELLED)

    def test_bounded_retry_and_no_implicit_resume(self):
        q = TransferQueue()
        q.load(["a"])
        q.start_next()
        q.progress(50, 100)
        q.finish(Status.FAILED, "connection lost")
        q.retry(0, max_attempts=2)
        self.assertEqual(q.entries[0].bytes_done, 0)
        q.start_next()
        q.finish(Status.FAILED)
        with self.assertRaises(ValueError):
            q.retry(0, max_attempts=2)

    def test_validation_and_active_queue_protection(self):
        q = TransferQueue()
        for names in ([], ["a", "a"], ["../escape"], ["a/b"]):
            with self.assertRaises(ValueError):
                q.load(names)
        q.load(["a"])
        q.start_next()
        with self.assertRaises(RuntimeError):
            q.load(["b"])

    def test_terminal_transition_validation(self):
        q = TransferQueue()
        q.load(["a"])
        q.start_next()
        with self.assertRaises(ValueError):
            q.finish(Status.ACTIVE)
        q.finish(Status.CANCELLED)
        self.assertEqual(q.entries[0].status, Status.CANCELLED)


if __name__ == "__main__":
    unittest.main()
