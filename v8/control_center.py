"""Qt desktop preview for the installed v7.1 manager. Run as an ordinary user."""
import json
import ipaddress
import re
import shutil
import stat
import os
import sys
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, QProcess, QTimer, QUrl
from PySide6.QtGui import QGuiApplication, QDesktopServices
from PySide6.QtQml import QQmlApplicationEngine

class Controller(QObject):
    refreshed = Signal(str)
    message = Signal(str)
    busyChanged = Signal(bool)

    def __init__(self):
        super().__init__()
        self.process = QProcess(self)
        self.process.finished.connect(self.finished)
        self.process.errorOccurred.connect(self.failed)
        self.kind = ""
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(10000)

    @Slot()
    def refresh(self):
        if self.process.state() != QProcess.NotRunning:
            return
        self.kind = "refresh"
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.diagnostics"])

    @Slot(str)
    def action(self, action):
        if action not in ("on", "off") or self.process.state() != QProcess.NotRunning:
            return
        helper = "/etc/steamdeck-switch2-panel-toggle"
        if not os.path.isfile(helper) or not os.path.isfile("/usr/bin/pkexec"):
            self.message.emit("Install the existing v7.1 panel helper first.")
            return
        self.kind = "action"
        self.busyChanged.emit(True)
        self.process.start("/usr/bin/pkexec", [helper, action])

    @Slot(str)
    def sunshine(self, action):
        if action not in ("start", "stop") or self.process.state() != QProcess.NotRunning:
            return
        executable = shutil.which("flatpak")
        if not executable:
            self.message.emit("Flatpak is unavailable.")
            return
        app = "dev.lizardbyte.app.Sunshine"
        if action == "start":
            ok, _ = QProcess.startDetached(executable, ["run", app])
            self.message.emit("Sunshine launch requested." if ok else "Sunshine launch failed.")
            QTimer.singleShot(2000, self.refresh)
        else:
            self.kind = "action"
            self.busyChanged.emit(True)
            self.process.start(executable, ["kill", app])

    @Slot()
    def sunshine_web(self):
        QDesktopServices.openUrl(QUrl("https://localhost:47990"))

    @Slot(str, str)
    def open_ftp(self, host, port):
        try:
            address = ipaddress.IPv4Address(host.strip())
            number = int(port)
            if not 1 <= number <= 65535 or address not in ipaddress.IPv4Network("10.42.60.0/24"):
                raise ValueError()
            if address in (ipaddress.IPv4Address("10.42.60.0"), ipaddress.IPv4Address("10.42.60.1"), ipaddress.IPv4Address("10.42.60.255")):
                raise ValueError()
        except ValueError:
            self.message.emit("Enter a client IPv4 address in 10.42.60.0/24 and a valid port.")
            return
        dolphin = shutil.which("dolphin")
        if not dolphin:
            self.message.emit("KDE Dolphin is unavailable.")
            return
        ok, _ = QProcess.startDetached(dolphin, [f"ftp://{address}:{number}/"])
        self.message.emit("Dolphin launch requested. FTP is unencrypted." if ok else "Dolphin launch failed.")

    @Slot()
    def wifi_settings(self):
        manager = Path("/etc/steamdeck-switch2/manager.sh")
        try:
            st = manager.lstat()
            parent = manager.parent.lstat()
            if not stat.S_ISREG(st.st_mode) or not stat.S_ISDIR(parent.st_mode) or any(x.st_uid != 0 or x.st_mode & 0o022 for x in (st, parent)):
                raise OSError("Untrusted manager")
        except OSError as exc:
            self.message.emit(str(exc))
            return
        konsole = shutil.which("konsole")
        if not konsole:
            self.message.emit("Konsole unavailable.")
            return
        ok, _ = QProcess.startDetached(konsole, ["--hold", "-e", "/usr/bin/sudo", "/usr/bin/bash", str(manager)])
        self.message.emit("Use option 5 in the existing manager to change WPA2 settings." if ok else "Konsole launch failed.")

    def failed(self, error):
        self.message.emit(self.process.errorString())
        self.busyChanged.emit(False)

    def finished(self, code, status):
        output = bytes(self.process.readAllStandardOutput()).decode(errors="replace")
        errors = bytes(self.process.readAllStandardError()).decode(errors="replace")
        if self.kind == "refresh" and code == 0:
            self.refreshed.emit(output)
        else:
            self.message.emit(("Completed: " if code == 0 else "Failed: ") + (output + errors).strip())
        self.busyChanged.emit(False)
        if self.kind == "action":
            QTimer.singleShot(0, self.refresh)

def main():
    if os.geteuid() == 0:
        sys.exit("Run the control center as your normal desktop user, not root.")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("SwitchNest Control Center")
    engine = QQmlApplicationEngine()
    controller = Controller()
    engine.rootContext().setContextProperty("controller", controller)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("ControlCenter.qml"))))
    if not engine.rootObjects():
        return 1
    QTimer.singleShot(0, controller.refresh)
    return app.exec()

if __name__ == "__main__":
    sys.exit(main())
