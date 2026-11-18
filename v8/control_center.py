"""Qt desktop preview for the installed v7.1 manager. Run as an ordinary user."""
import json
import os
import sys
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, QProcess, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
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
