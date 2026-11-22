"""Pure state machine for SwitchNest FTP queue (no network or filesystem writes).

Phase 2 foundation. The FTP worker remains authoritative for actual transfers.
"""
from dataclasses import dataclass, field
from enum import Enum


class Status(str, Enum):
    WAITING = "Waiting"
    ACTIVE = "Active"
    COMPLETED = "Completed"
    FAILED = "Failed"
    CANCELLED = "Cancelled"
    INTERRUPTED = "Interrupted"


_TERMINAL = {Status.COMPLETED, Status.FAILED, Status.CANCELLED, Status.INTERRUPTED}


@dataclass
class QueueEntry:
    name: str
    status: Status = Status.WAITING
    bytes_done: int = 0
    bytes_total: int = 0
    attempts: int = 0
    error: str = ""

    def snapshot(self):
        return dict(name=self.name, status=self.status.value,
                    bytesDone=self.bytes_done, bytesTotal=self.bytes_total,
                    attempts=self.attempts, error=self.error)


@dataclass
class TransferQueue:
    entries: list[QueueEntry] = field(default_factory=list)
    active: int | None = None

    def load(self, names):
        if self.active is not None:
            raise RuntimeError("Cannot replace an active queue")
        if not names or len(names) > 1000 or any(not isinstance(n, str) or not n or n in (".", "..") or "/" in n or "\\x00" in n for n in names):
            raise ValueError("Invalid queue entries")
        if len(names) != len(set(names)):
            raise ValueError("Duplicate queue entries")
        self.entries = [QueueEntry(name=n) for n in names]

    def start_next(self):
        if self.active is not None:
            raise RuntimeError("Another transfer is active")
        for i, entry in enumerate(self.entries):
            if entry.status == Status.WAITING:
                self.active = i
                entry.status = Status.ACTIVE
                entry.attempts += 1
                return entry.name
        return None

    def progress(self, done, total):
        if self.active is None:
            raise RuntimeError("No active transfer")
        if not isinstance(done, int) or not isinstance(total, int) or total < 0 or not 0 <= done <= total:
            raise ValueError("Invalid progress")
        entry = self.entries[self.active]
        entry.bytes_done, entry.bytes_total = done, total

    def finish(self, status, error=""):
        if self.active is None:
            raise RuntimeError("No active transfer")
        status = Status(status)
        if status not in _TERMINAL:
            raise ValueError("Expected terminal status")
        entry = self.entries[self.active]
        entry.status = status
        entry.error = str(error)[:500]
        self.active = None

    def cancel_waiting(self):
        for entry in self.entries:
            if entry.status == Status.WAITING:
                entry.status = Status.CANCELLED

    def retry(self, index, max_attempts=3):
        if self.active is not None:
            raise RuntimeError("Wait until active transfer finishes")
        entry = self.entries[index]
        if entry.status not in (Status.FAILED, Status.INTERRUPTED):
            raise ValueError("Only failed or interrupted entries may be retried")
        if entry.attempts >= max_attempts:
            raise ValueError("Retry limit reached")
        entry.status = Status.WAITING
        entry.bytes_done = entry.bytes_total = 0
        entry.error = ""

    def snapshot(self):
        return [entry.snapshot() for entry in self.entries]
