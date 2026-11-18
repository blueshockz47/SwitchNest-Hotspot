"""Qt desktop preview for the installed v7.1 manager. Run as an ordinary user."""
import json
import ipaddress
import re
import shutil
import stat
import os
import sys
import threading
from v8 import updates
if os.name!="nt":
    from v8 import autostart
from pathlib import Path
from v8.ftp_browser import Browser
from PySide6.QtCore import QObject, Signal, Slot, Property, QLockFile, QStandardPaths, QProcess, QTimer, QUrl
from PySide6.QtGui import QGuiApplication, QDesktopServices
from PySide6.QtQml import QQmlApplicationEngine

class Controller(QObject):
    refreshed = Signal(str)
    message = Signal(str)
    busyChanged = Signal(bool)
    updateResult = Signal(str)
    updateBusy = Signal(bool)
    autostartChanged = Signal()

    def __init__(self):
        super().__init__()
        self.process = QProcess(self)
        self.process.finished.connect(self.finished)
        self.process.errorOccurred.connect(self.failed)
        self.kind = ""
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(10000)

    @Property(bool, notify=autostartChanged)
    def startOnLogin(self):
        return False if os.name=="nt" else autostart.enabled()

    @Slot(bool)
    def set_autostart(self, enabled):
        if os.name=="nt": return
        try:
            autostart.set_enabled(enabled)
            self.message.emit("Desktop autostart enabled" if enabled else "Desktop autostart disabled")
        except (OSError,RuntimeError) as exc:
            self.message.emit(str(exc))
        self.autostartChanged.emit()

    @Slot(str)
    def check_updates(self, channel):
        if getattr(self,"checking_updates",False): return
        self.checking_updates=True
        self.updateBusy.emit(True)
        def worker():
            try: result=updates.check(channel)
            except Exception as exc: result=str(exc)
            self.updateResult.emit(result)
            self.checking_updates=False
            self.updateBusy.emit(False)
        threading.Thread(target=worker,daemon=True).start()

    @Slot(bool)
    def open_updates(self, development):
        QDesktopServices.openUrl(QUrl(updates.DEVELOPMENT if development else updates.RELEASES))

    @Slot()
    def refresh(self):
        if self.process.state() != QProcess.NotRunning:
            return
        if os.name=="nt":
            self.refreshed.emit(json.dumps({"version":"Windows alpha.1","hotspot":{"state":"unknown"},"note":"Use Windows Mobile Hotspot or an existing local network. Isolation not managed."}))
            return
        self.kind = "refresh"
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.diagnostics"])

    @Slot()
    def windows_hotspot(self):
        if os.name=="nt": os.startfile("ms-settings:network-mobilehotspot")

    @Slot(str)
    def action(self, action):
        if os.name=="nt": return
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
        if os.name=="nt": return
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
        if os.name=="nt": return
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
    if hasattr(os,"geteuid") and os.geteuid() == 0:
        sys.exit("Run the control center as your normal desktop user, not root.")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("SwitchNest Control Center")
    runtime=Path(QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation if os.name=="nt" else QStandardPaths.RuntimeLocation))
    runtime.mkdir(parents=True,exist_ok=True)
    lock=QLockFile(str(runtime/"switchnest-control-center.lock"))
    if not lock.tryLock(0):
        print("SwitchNest is already running or the session lock is unavailable.")
        return 0
    engine = QQmlApplicationEngine()
    controller = Controller()
    engine.rootContext().setContextProperty("controller", controller)
    engine.rootContext().setContextProperty("windowsPreview", os.name=="nt")
    browser = Browser()
    engine.rootContext().setContextProperty("ftpBrowser", browser)
    app.aboutToQuit.connect(browser.cancel)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("ControlCenter.qml"))))
    if not engine.rootObjects():
        return 1
    QTimer.singleShot(0, controller.refresh)
    return app.exec()

if __name__ == "__main__":
    sys.exit(main())
