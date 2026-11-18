"""Local FTP browser, with asynchronous curl and no privileged changes."""
import ipaddress
import json
import datetime
import time
import os
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import quote
from PySide6.QtCore import QObject, Signal, Slot, Property, QProcess, QSettings

class Browser(QObject):
    changed = Signal()
    def __init__(self):
        super().__init__()
        self.settings = QSettings("SwitchNest", "FTP")
        self.host = str(self.settings.value("host", "10.42.60.99"))
        self.port = str(self.settings.value("port", "1337"))
        self.local = Path.home() / "Downloads"
        if not self.local.is_dir():
            self.local = Path.home()
        self.remote = "/"
        self.local_rows = []
        self.remote_rows = []
        self.status = "Connect to a local FTP server."
        self.progress = 0.0
        self.busy = False
        self.connected = False
        self.job = ""
        self.queue = []
        self.total = 0
        self.completed = 0
        self.current_name = ""
        self.history = []
        self.transfer_size = 0
        self.started = 0
        self.speed = 0
        self.bytes_done = 0
        self.temp = None
        self.dest = None
        self.cancelled = False
        self.proc = QProcess(self)
        self.proc.finished.connect(self.finished)
        self.proc.errorOccurred.connect(self.error)
        self.proc.readyReadStandardError.connect(self.stderr)
        self.err = ""
        self.refresh_local()

    @Property(str, notify=changed)
    def state(self):
        return json.dumps(dict(host=self.host, port=self.port, local=str(self.local),
            remote=self.remote, localRows=self.local_rows, remoteRows=self.remote_rows,
            status=self.status, progress=self.progress, busy=self.busy, connected=self.connected, total=self.total, completed=self.completed, current=self.current_name, history=self.history, speed=self.speed, bytesDone=self.bytes_done, transferSize=self.transfer_size))

    def refresh_local(self):
        try:
            self.local_rows = sorted([dict(name=p.name, directory=p.is_dir(), size=p.stat().st_size if p.is_file() else None, date=datetime.datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d"))
                for p in self.local.iterdir() if not p.is_symlink()],
                key=lambda x: (not x["directory"], x["name"].lower()))
        except OSError as e:
            self.status = str(e)
        self.changed.emit()

    def valid_name(self, name):
        return bool(name and name not in (".", "..") and "/" not in name
                    and not any(ord(c) < 32 or ord(c) == 127 for c in name))

    def url(self, name="", directory=False):
        path = self.remote + name
        return "ftp://" + self.host + ":" + self.port + quote(path, safe="/") + ("/" if directory and not path.endswith("/") else "")

    def start(self, job, args):
        if self.busy:
            return
        curl = shutil.which("curl")
        if not curl:
            self.status = "curl unavailable"
            self.cleanup()
            self.changed.emit()
            return
        self.job = job
        self.started = time.monotonic()
        self.speed = self.bytes_done = 0
        self.busy = True
        self.cancelled = False
        self.progress = 0
        self.err = ""
        self.status = job.capitalize() + " in progress"
        self.changed.emit()
        base = ["-q", "--globoff", "--noproxy", "*", "--disable-epsv",
                "--ftp-skip-pasv-ip", "--connect-timeout", "8",
                "--speed-limit", "1", "--speed-time", "30", "--proto", "=ftp",
                "--progress-bar", "--show-error"]
        if job == "list":
            base += ["--retry", "2", "--retry-delay", "1", "--retry-connrefused", "--max-time", "40"]
        self.proc.start(curl, base + args)

    @Slot(str, str)
    def connect_to(self, host, port):
        if self.busy:
            return
        try:
            ip = ipaddress.IPv4Address(host.strip())
            n = int(port)
            if ip not in ipaddress.IPv4Network("10.42.60.0/24") or int(ip) & 255 in (0, 1, 255) or not 1 <= n <= 65535:
                raise ValueError()
        except ValueError:
            self.status = "Enter a local client address and valid port."
            self.changed.emit()
            return
        self.host, self.port = str(ip), str(n)
        self.settings.setValue("host", self.host)
        self.settings.setValue("port", self.port)
        self.remote = "/"
        self.list_remote()

    def list_remote(self):
        self.connected = False
        self.remote_rows = []
        self.start("list", ["--", self.url(directory=True)])

    @Slot(str)
    def local_open(self, name):
        if self.busy:
            return
        p = self.local.parent if name == ".." else self.local / name
        if (name == ".." or self.valid_name(name)) and p.is_dir() and not p.is_symlink():
            self.local = p
            self.refresh_local()

    @Slot(str)
    def remote_open(self, name):
        if self.busy or not self.connected:
            return
        if name == "..":
            self.remote = self.remote.rstrip("/").rsplit("/", 1)[0] + "/"
        elif self.valid_name(name) and any(x["name"] == name and x["directory"] for x in self.remote_rows):
            self.remote += name + "/"
        else:
            return
        self.list_remote()

    @Slot()
    def refresh(self):
        if not self.busy:
            self.refresh_local()
            self.list_remote()

    @Slot(str)
    def download(self, name):
        if self.busy or not self.connected or not self.valid_name(name):
            return
        if not any(x["name"] == name and not x["directory"] for x in self.remote_rows):
            return
        try:
            self.dest = self.local / name
            if os.path.lexists(self.dest):
                raise OSError("Destination exists; choose a different local folder.")
            fd, path = tempfile.mkstemp(prefix=".switchnest-", dir=self.local)
            os.close(fd)
            self.temp = Path(path)
            self.start("download", ["--output", str(self.temp), "--", self.url(name)])
        except OSError as e:
            self.status = str(e)
            self.changed.emit()

    @Slot(str, bool)
    def upload(self, name, confirmed):
        if self.busy or not self.connected or not confirmed or not self.valid_name(name):
            return
        p = self.local / name
        if not p.is_file() or p.is_symlink():
            return
        self.start("upload", ["--upload-file", str(p), "--", self.url(name)])

    @Slot(str, str)
    def batch(self, direction, raw):
        if self.busy or not self.connected or direction not in ("upload", "download"):
            return
        try:
            names = json.loads(raw)
            if not isinstance(names, list) or not names or len(names) > 1000:
                raise ValueError("Invalid selection")
            rows = self.local_rows if direction == "upload" else self.remote_rows
            allowed = {x["name"] for x in rows if not x["directory"]}
            if any(not isinstance(n, str) or n not in allowed or not self.valid_name(n) for n in names):
                raise ValueError("Invalid selection")
            names = list(dict.fromkeys(names))
            if direction == "download" and any(os.path.lexists(self.local / n) for n in names):
                raise ValueError("Local destination exists; choose another folder.")
            self.queue = [(direction, n) for n in names]
            self.total = len(names)
            self.completed = 0
            self.next_file()
        except (ValueError, TypeError, OSError) as e:
            self.status = str(e)
            self.changed.emit()

    def next_file(self):
        direction, name = self.queue.pop(0)
        self.current_name = name
        rows = self.local_rows if direction == "upload" else self.remote_rows
        self.transfer_size = next((x.get("size") or 0 for x in rows if x["name"] == name), 0)
        if direction == "upload":
            self.upload(name, True)
        else:
            self.download(name)
        if not self.busy:
            self.queue.clear()
            self.status = "Batch stopped: " + self.status
            self.changed.emit()

    @Slot(str, str, str, str)
    def manage(self, side, action, name, new_name):
        if self.busy or side not in ("local", "remote") or action not in ("mkdir", "rename", "delete"):
            return
        try:
            rows = self.local_rows if side == "local" else self.remote_rows
            existing = {x["name"]: x for x in rows}
            if action != "mkdir" and (not self.valid_name(name) or name not in existing):
                raise ValueError("Select an existing entry.")
            if action != "delete" and (not self.valid_name(new_name) or new_name in existing):
                raise ValueError("Invalid or existing destination name.")
            if side == "local":
                p = self.local / name
                target = self.local / new_name
                if action == "mkdir":
                    target.mkdir()
                elif p.is_symlink():
                    raise ValueError("Symbolic links are not supported.")
                elif action == "rename":
                    if os.path.lexists(target):
                        raise ValueError("Destination exists.")
                    p.rename(target)
                elif p.is_dir():
                    p.rmdir()
                else:
                    p.unlink()
                self.status = "Local operation complete"
                self.refresh_local()
            elif self.connected:
                # Absolute FTP paths, with control characters rejected above.
                source = self.remote + name
                target = self.remote + new_name
                commands = ["MKD " + target] if action == "mkdir" else ["RNFR " + source, "RNTO " + target] if action == "rename" else [("RMD " if existing[name]["directory"] else "DELE ") + source]
                args = []
                for command in commands:
                    args += ["--quote", command]
                self.start("manage", args + ["--output", os.devnull, "--", self.url(directory=True)])
        except (OSError, ValueError) as e:
            self.status = str(e)
            self.changed.emit()

    @Slot()
    def cancel(self):
        if self.busy:
            self.queue.clear()
            self.cancelled = True
            self.proc.kill()

    def stderr(self):
        self.err = (self.err + bytes(self.proc.readAllStandardError()).decode(errors="replace"))[-8192:]
        matches = re.findall(r"(\d+(?:\.\d+)?)%", self.err)
        if matches:
            self.progress = min(100, float(matches[-1]))
            if self.job in ("upload", "download"):
                self.bytes_done = int(self.transfer_size * self.progress / 100)
                self.speed = int(self.bytes_done / max(0.1, time.monotonic() - self.started))
        self.changed.emit()

    def cleanup(self):
        if self.temp is not None:
            self.temp.unlink(missing_ok=True)
        self.temp = self.dest = None

    def error(self, error):
        if error == QProcess.ProcessError.FailedToStart:
            self.busy = False
            self.queue.clear()
            self.status = self.proc.errorString()
            self.cleanup()
            self.changed.emit()

    def finished(self, code, exit_status):
        self.stderr()
        output = bytes(self.proc.readAllStandardOutput()).decode(errors="replace")
        self.busy = False
        ok = code == 0 and exit_status == QProcess.ExitStatus.NormalExit and not self.cancelled
        try:
            if not ok:
                self.status = "Cancelled" if self.cancelled else "FTP failed: " + self.err[-500:]
                if self.job == "upload":
                    self.status += " — remote file may be incomplete."
            elif self.job == "list":
                rows = []
                for line in output.splitlines():
                    parts = line.split(maxsplit=8)
                    if len(parts) == 9 and parts[0][0] in "d-" and self.valid_name(parts[8]):
                        rows.append(dict(name=parts[8], directory=parts[0][0] == "d", size=int(parts[4]) if parts[4].isdigit() and parts[0][0] == "-" else None, date=" ".join(parts[5:8])))
                self.remote_rows = sorted(rows, key=lambda x: (not x["directory"], x["name"].lower()))
                self.connected = True
                self.status = "Directory listed" if rows or not output.strip() else "Listing format unsupported"
            elif self.job == "download":
                os.link(self.temp, self.dest)
                self.status = "Download complete"
                self.refresh_local()
            else:
                self.status = "Operation complete" if self.job == "manage" else "Upload complete"
            if ok:
                self.progress = 100
        except OSError as e:
            ok = False
            self.status = str(e)
        finally:
            self.cleanup()
            self.changed.emit()
        if self.job in ("upload", "download"):
            self.history = ([dict(name=self.current_name, direction=self.job, result="Completed" if ok else "Cancelled" if self.cancelled else "Failed", date=datetime.datetime.now().isoformat(timespec="seconds"))] + self.history)[:100]
        if self.job in ("upload", "download") and self.total:
            if ok:
                self.completed += 1
                if self.queue:
                    self.next_file()
                    return
                self.status = f"Batch complete: {self.completed}/{self.total}"
            else:
                self.queue.clear()
                self.status += f" ({self.completed}/{self.total} completed)"
            self.changed.emit()
        if ok and self.job in ("upload", "manage"):
            self.list_remote()
