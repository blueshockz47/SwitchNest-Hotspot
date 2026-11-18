"""Offscreen UI construction check. Does not start or modify the hotspot."""
import os
import sys
from pathlib import Path

def main():
    os.environ.setdefault("QT_QPA_PLATFORM","offscreen")
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    from v8.control_center import Controller
    from v8.ftp_browser import Browser
    app=QGuiApplication.instance() or QGuiApplication(["switchnest-smoke"])
    engine=QQmlApplicationEngine()
    controller=Controller()
    controller.timer.stop()
    browser=Browser()
    engine.rootContext().setContextProperty("controller",controller)
    engine.rootContext().setContextProperty("ftpBrowser",browser)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("ControlCenter.qml"))))
    if not engine.rootObjects():
        raise SystemExit("QML failed to create a window")
    browser.cancel()
    print("QML window created successfully")
if __name__=="__main__":
    main()
