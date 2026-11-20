"""Qt desktop preview for the installed v7.1 manager. Run as an ordinary user."""
import json
import ipaddress
import re
import shutil
import stat
import os
import sys
import subprocess
import threading
from v8 import updates, autostart, preferences
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
    updateLog = Signal(str)
    updateInstalled = Signal(str)
    updateAvailable = Signal(str)
    updateProgress = Signal(str)
    preferencesChanged = Signal()
    rollbackCompleted = Signal()
    autostartChanged = Signal()
    wifiStatus = Signal(str)
    wifiResult = Signal(str)

    def __init__(self):
        super().__init__()
        self.process = QProcess(self)
        self.process.finished.connect(self.finished)
        self.process.readyReadStandardOutput.connect(self.read_stdout)
        self.process.readyReadStandardError.connect(self.read_stderr)
        self._process_output = []
        self._update_line_buffer = ""
        self.update_installed = False
        self.rollback_completed = False
        self.process.errorOccurred.connect(self.failed)
        self.kind = ""
        self.latestUpdateTag = None
        self.latestUpdateChannel = "stable"
        self.notifiedUpdateTag = None
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(10000)

    @Property(str, notify=preferencesChanged)
    def updatePreferences(self):
        return json.dumps(preferences.load())

    @Slot(str, bool)
    def set_update_preference(self, key, value):
        try:
            preferences.save(key, value)
            self.preferencesChanged.emit()
        except (ValueError, OSError, RuntimeError) as exc:
            self.message.emit("Unable to save update setting: " + str(exc))

    @Slot()
    def copy_diagnostics(self):
        if not hasattr(self, "last_report"):
            self.message.emit("Refresh diagnostics first.")
            return
        QGuiApplication.clipboard().setText(self.last_report)
        self.message.emit("Diagnostics copied. Review IP and MAC addresses before sharing.")

    @Property(bool, notify=busyChanged)
    def rollbackAvailable(self):
        base = Path.home() / ".local/share/switchnest"
        return (base / "previous").is_symlink() and (base / "current").is_symlink()

    @Slot()
    def rollback_update(self):
        if self.process.state() != QProcess.NotRunning or getattr(self, "installing_update", False):
            return
        if not self.rollbackAvailable:
            self.message.emit("No previous version is available.")
            return
        self.kind = "rollback"
        self._process_output = []
        self.busyChanged.emit(True)
        self.updateLog.emit("Restoring previous SwitchNest version...\n")
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.install", "rollback"])

    @Property(bool, notify=autostartChanged)
    def startOnLogin(self):
        return autostart.enabled()

    @Slot(bool)
    def set_autostart(self, enabled):
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
        self.latestUpdateTag = None
        self.latestUpdateChannel = channel
        def worker():
            try: result=updates.check(channel)
            except Exception as exc: result=str(exc)
            if result.startswith("Update available: "):
                self.latestUpdateTag = result.removeprefix("Update available: ").strip()
            if channel == "stable" and preferences.load()["show_update_popup"] and self.latestUpdateTag and self.latestUpdateTag != self.notifiedUpdateTag:
                self.notifiedUpdateTag = self.latestUpdateTag
                self.updateAvailable.emit(self.latestUpdateTag)
            self.updateResult.emit(result)
            self.checking_updates=False
            self.updateBusy.emit(False)
        threading.Thread(target=worker,daemon=True).start()

    @Slot()
    def install_update(self):
        if self.process.state() != QProcess.NotRunning or getattr(self, "installing_update", False):
            return
        if not self.latestUpdateTag or self.latestUpdateChannel != "stable":
            self.message.emit("Check for a stable update first.")
            return
        self.installing_update = True
        self.update_installed = False
        self._process_output = []
        self._update_line_buffer = ""
        self.kind = "install_update"
        self.updateLog.emit("Starting update download and installation...\n")
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-u", "-m", "v8.in_app_update"])
        
    def read_stdout(self):
        data = bytes(self.process.readAllStandardOutput()).decode(errors="replace")
        self._process_output.append(data)
        if self.kind == "install_update":
            self._update_line_buffer += data
            while "\n" in self._update_line_buffer:
                line, self._update_line_buffer = self._update_line_buffer.split("\n", 1)
                if line.startswith("SWITCHNEST_PROGRESS:"):
                    self.updateProgress.emit(line[len("SWITCHNEST_PROGRESS:"):])
                else:
                    self.updateLog.emit(line + "\n")

    def read_stderr(self):
        data = bytes(self.process.readAllStandardError()).decode(errors="replace")
        self._process_output.append(data)
        if self.kind in ("install_update", "rollback"):
            self.updateLog.emit(data)

    @Slot()
    def restart_after_update(self):
        if not (self.update_installed or self.rollback_completed) or self.process.state() != QProcess.NotRunning:
            self.message.emit("No completed update is ready to restart.")
            return
        launcher = Path.home() / ".local/share/switchnest/launch"
        if not launcher.is_file():
            self.message.emit("SwitchNest launcher is missing. Restart manually.")
            return
        # Delay startup so the current instance releases its single-instance lock.
        subprocess.Popen(
            ["/bin/sh", "-c", 'sleep 2; exec "$1"', "sh", str(launcher)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )
        QGuiApplication.instance().quit()

    @Slot()
    def download_update(self):
        tag = self.latestUpdateTag
        if not tag:
            self.message.emit("Check for updates first.")
            return
        try:
            url = updates.release_url(tag)
        except ValueError:
            self.message.emit("Invalid release version.")
            return
        QDesktopServices.openUrl(QUrl(url))

    @Slot(bool)
    def open_updates(self, development):
        QDesktopServices.openUrl(QUrl(updates.DEVELOPMENT if development else updates.RELEASES))

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
    def wifi_status(self):
        if self.process.state() != QProcess.NotRunning:
            return
        self.kind = "wifi_status"
        self._process_output = []
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.wifi_config", "status"])

    @Slot(str, str, int)
    def wifi_apply(self, ssid, password, channel):
        if self.process.state() != QProcess.NotRunning:
            self.message.emit("Another operation is in progress.")
            return
        from v8.wifi_config import validate
        try:
            validate(ssid, password, channel)
        except ValueError as exc:
            self.message.emit(str(exc))
            return
        self.kind = "wifi_apply"
        self._process_output = []
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.wifi_config", "apply", "stdin"])
        if not self.process.waitForStarted(5000):
            self.message.emit("Wi-Fi editor could not start.")
            self.busyChanged.emit(False)
            return
        self.process.write(json.dumps({"ssid": ssid, "password": password, "channel": channel}).encode())
        self.process.closeWriteChannel()

    @Slot()
    def wifi_restore(self):
        if self.process.state() != QProcess.NotRunning:
            return
        self.kind = "wifi_restore"
        self._process_output = []
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.wifi_config", "restore"])

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
        if self.kind == "install_update":
            self.updateLog.emit("Update process error: " + self.process.errorString() + "\n")
        if self.kind == "install_update":
            self.installing_update = False
        self.message.emit(self.process.errorString())
        self.busyChanged.emit(False)

    def finished(self, code, status):
        self.read_stdout()
        self.read_stderr()
        output = "".join(self._process_output).strip()
        kind = self.kind
        self._process_output = []
        if kind == "refresh" and code == 0:
            self.last_report = output
            self.refreshed.emit(output)
        elif kind in ("wifi_status", "wifi_apply", "wifi_restore"):
            try:
                result = json.loads(output)
            except ValueError:
                result = {"ok": False, "error": "Wi-Fi editor returned an invalid response"}
            if kind == "wifi_status":
                self.wifiStatus.emit(json.dumps(result))
            else:
                self.wifiResult.emit(json.dumps(result))
                self.message.emit(result.get("message", result.get("error", "Wi-Fi operation failed")))
        else:
            self.message.emit(("Completed: " if code == 0 else "Failed: ") + output)
        self.busyChanged.emit(False)
        if kind == "install_update":
            self.installing_update = False
            if code == 0 and status == QProcess.NormalExit and "Installed v" in output:
                self.update_installed = True
                self.updateInstalled.emit(output.split("Installed v")[-1].split(". Close")[0].strip())
            else:
                self.updateLog.emit("\nUpdate failed. Check the output above.\n")
        if kind == "rollback" and code == 0 and status == QProcess.NormalExit:
            self.rollback_completed = True
            self.rollbackCompleted.emit()
        if kind == "action":
            QTimer.singleShot(0, self.refresh)

def main():
    if os.geteuid() == 0:
        sys.exit("Run the control center as your normal desktop user, not root.")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("SwitchNest Control Center")
    runtime=Path(QStandardPaths.writableLocation(QStandardPaths.RuntimeLocation))
    lock=QLockFile(str(runtime/"switchnest-control-center.lock"))
    if not lock.tryLock(0):
        print("SwitchNest is already running or the session lock is unavailable.")
        return 0
    engine = QQmlApplicationEngine()
    controller = Controller()
    engine.rootContext().setContextProperty("controller", controller)
    browser = Browser()
    engine.rootContext().setContextProperty("ftpBrowser", browser)
    app.aboutToQuit.connect(browser.cancel)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("ControlCenter.qml"))))
    if not engine.rootObjects():
        return 1
    QTimer.singleShot(0, controller.refresh)
    if preferences.load()["check_at_startup"]:
        QTimer.singleShot(1500, lambda: controller.check_updates("stable" if preferences.load()["stable_only"] else "development"))
    return app.exec()

if __name__ == "__main__":
    sys.exit(main())
