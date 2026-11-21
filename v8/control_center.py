"""Qt desktop preview for the installed v7.1 manager. Run as an ordinary user."""
import json
import urllib.error
import ipaddress
import re
import shutil
import stat
import os
import sys
import subprocess
import threading
import time
from v8 import updates, autostart, preferences, wifi_reliability, stability, homebrew, homebrew_zip, homebrew_monitor, homebrew_release_cache
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
    wifiRestartSuggested = Signal()
    wifiRestartProgress = Signal(str)
    wifiPresets = Signal(str)
    networkEvents = Signal(str)
    wifiHealth = Signal(str)
    selfTestResult = Signal(str)
    homebrewResult = Signal(str)
    homebrewBusy = Signal(bool)
    homebrewProgress = Signal(str)
    homebrewMonitorResult = Signal(str)

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
        self.wifi_restart_phase = None
        self.wifi_recovery_attempted = False
        self.wifi_last_recovery = None
        self.wifi_pending_restore = False
        self.wifi_expected_ssid = None
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self._last_health_state = None
        self.timer.start(10000)

    @Property(str, constant=True)
    def version(self):
        return updates.VERSION

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
    def run_self_test(self):
        if not hasattr(self, "last_report"):
            self.message.emit("Refresh diagnostics first.")
            return
        try:
            result = stability.self_test(json.loads(self.last_report))
            self.selfTestResult.emit(json.dumps(result))
            self.message.emit("Self-test finished (read-only; FTP and isolation not proven).")
        except (ValueError, TypeError) as exc:
            self.message.emit("Self-test unavailable: " + str(exc))

    @Slot()
    def export_diagnostics(self):
        if not hasattr(self, "last_report"):
            self.message.emit("Refresh diagnostics first.")
            return
        try:
            destination = Path.home()/"Downloads"/f"switchnest-diagnostics-v{updates.VERSION}.json"
            destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            stability.export_report(json.loads(self.last_report), destination)
            self.message.emit("Redacted report saved to " + str(destination) + ". Review before sharing.")
        except (OSError, ValueError, RuntimeError) as exc:
            self.message.emit("Report export failed: " + str(exc))

    @Slot()
    def verify_application(self):
        from v8 import install
        result = install.verify_installation()
        self.message.emit("Application verification: " + ("OK" if result["ok"] else ", ".join(result["issues"])))

    @Slot()
    def repair_application(self):
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            return
        self.kind = "repair"
        self._process_output = []
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.install", "repair"])


    @Slot(bool)
    def homebrew_monitor_refresh(self, force=False):
        """Read-only background discovery; never triggers a download or FTP write."""
        if getattr(self, "_homebrew_monitor_busy", False):
            return
        cached = homebrew_monitor.load_cache()
        if cached is not None:
            self._community_repos = frozenset(row["repo"] for row in cached.get("catalog", []) if isinstance(row, dict) and row.get("repo"))
            self.homebrewMonitorResult.emit(json.dumps(cached))
            if not force and homebrew_monitor.cache_is_today(cached):
                return
        self._homebrew_monitor_busy = True
        self.homebrewMonitorResult.emit(json.dumps({"kind": "monitor_progress", "message": "Checking GitHub releases, Reddit and community catalogs..."}))
        def worker():
            try:
                data = homebrew_monitor.refresh()
                self._community_repos = frozenset(row["repo"] for row in data.get("catalog", []) if row.get("repo"))
                try:
                    homebrew_monitor.save_cache(data)
                except OSError:
                    pass
                self.homebrewMonitorResult.emit(json.dumps(data))
            except Exception as exc:
                self.homebrewMonitorResult.emit(json.dumps({
                    "kind": "monitor_error", "message": type(exc).__name__ + ": " + str(exc)[:160]}))
            finally:
                self._homebrew_monitor_busy = False
        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, str)
    def homebrew_search(self, query, category):
        """Local catalog filtering is immediate and must not be dropped during downloads."""
        try:
            rows = homebrew.catalog_search(query, category)
            self.homebrewResult.emit(json.dumps({
                "kind": "search", "items": rows, "category": category,
                "query": query}))
        except Exception as exc:
            self.homebrewResult.emit(json.dumps({
                "kind": "error", "message": str(exc)[:200]}))

    @Slot()
    def homebrew_cached_releases(self):
        """Restore release availability labels without contacting GitHub."""
        state = homebrew_release_cache._read()
        releases = {}
        entries = state.get("releases", {})
        if not isinstance(entries, dict):
            entries = {}
        for repo, entry in entries.items():
            if not isinstance(repo, str) or not homebrew_release_cache.REPO_PATTERN.fullmatch(repo):
                continue
            cached = homebrew_release_cache.get(repo)
            if cached:
                releases[repo] = {"assets": cached["data"]["assets"], "stale": cached["stale"]}
        self.homebrewResult.emit(json.dumps({"kind": "cached_releases", "releases": releases}))

    @Slot(str)
    def homebrew_releases(self, repo):
        """Read-only release preview: cached for 24h, with GitHub rate-limit cooldown."""
        if repo not in homebrew.SWITCH2_CANDIDATES and repo not in getattr(self, "_community_repos", frozenset()):
            self.homebrewResult.emit(json.dumps({"kind": "error", "message": "Repository not found in current catalog"}))
            return
        cached = homebrew_release_cache.get(repo)
        if cached and not cached["stale"]:
            self.homebrewResult.emit(json.dumps({"kind": "assets", "repo": repo, "cached": True, **cached["data"]}))
            return
        remaining = homebrew_release_cache.cooldown_remaining()
        if remaining:
            if cached:
                self.homebrewResult.emit(json.dumps({"kind": "assets", "repo": repo, "cached": True, "stale": True, **cached["data"]}))
            else:
                self.homebrewResult.emit(json.dumps({"kind": "rate_limited", "repo": repo,
                    "message": "GitHub API limit reached. Try again in about " + str((remaining + 59) // 60) + " minutes. Saved catalog remains available."}))
            return
        if getattr(self, "_homebrew_busy", False):
            return
        self._homebrew_busy = True
        self.homebrewBusy.emit(True)
        def worker():
            try:
                result = homebrew.release_assets(repo)
                try:
                    homebrew_release_cache.put(repo, result)
                except OSError:
                    pass
                self.homebrewResult.emit(json.dumps({"kind": "assets", "repo": repo, **result}))
            except urllib.error.HTTPError as exc:
                if exc.code in (403, 429):
                    try:
                        homebrew_release_cache.mark_limited()
                    except OSError:
                        pass
                    if cached:
                        self.homebrewResult.emit(json.dumps({"kind": "assets", "repo": repo, "cached": True, "stale": True, **cached["data"]}))
                    else:
                        self.homebrewResult.emit(json.dumps({"kind": "rate_limited", "repo": repo,
                            "message": "GitHub API limit reached (HTTP " + str(exc.code) + "). Saved catalog remains available; retry later."}))
                else:
                    self.homebrewResult.emit(json.dumps({"kind": "error", "message": str(exc)[:200]}))
            except Exception as exc:
                if cached:
                    self.homebrewResult.emit(json.dumps({"kind": "assets", "repo": repo, "cached": True, "stale": True, **cached["data"]}))
                else:
                    self.homebrewResult.emit(json.dumps({"kind": "error", "message": str(exc)[:200]}))
            finally:
                self._homebrew_busy = False
                self.homebrewBusy.emit(False)
        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, str, bool)
    def homebrew_install(self, repo, raw_asset, confirmed):
        if getattr(self, "_homebrew_busy", False):
            return
        # Only assets freshly obtained from GitHub are trusted; never accept a
        # QML-supplied download URL or checksum as the source of truth.
        if repo not in homebrew.SWITCH2_CANDIDATES and repo not in getattr(self, "_community_repos", frozenset()):
            self.homebrewResult.emit(json.dumps({"kind": "error", "message": "Repository not found in current catalog"}))
            return
        if not confirmed:
            self.homebrewResult.emit(json.dumps({"kind": "error", "message": "Confirm the installation first."}))
            return
        self._homebrew_busy = True
        self.homebrewBusy.emit(True)
        def worker():
            try:
                name = json.loads(raw_asset)["name"]
                result = homebrew.release_assets(repo)
                asset = next(a for a in result["assets"] if a["name"] == name)
                if not asset["name"].lower().endswith(".nro"):
                    raise ValueError("Plugins and system packages are not supported for automatic FTP installation")
                browser = self._homebrew_browser
                state = json.loads(browser.state)
                if not state.get("connected") or state.get("busy"):
                    raise RuntimeError("Connect the FTP browser and finish any active transfer first")
                destination = "/switch/" + asset["name"]
                def report(stage, done, total):
                    self.homebrewProgress.emit(json.dumps({
                        "status": stage, "name": asset["name"],
                        "done": done, "total": total}))
                message = homebrew.install_nro(
                    asset, destination, state["host"], state["port"],
                    confirmed=True, progress=report)
                self.homebrewResult.emit(json.dumps({"kind": "installed", "message": message}))
            except Exception as exc:
                self.homebrewResult.emit(json.dumps({"kind": "error", "message": str(exc)[:250]}))
            finally:
                self._homebrew_busy = False
                self.homebrewBusy.emit(False)
        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, str)
    def homebrew_download_only(self, repo, name):
        """Download a GitHub release asset locally; never invoke FTP or install."""
        if getattr(self, "_homebrew_busy", False):
            return
        self._homebrew_busy = True
        self.homebrewBusy.emit(True)
        def worker():
            try:
                if repo not in homebrew.SWITCH2_CANDIDATES and repo not in getattr(self, "_community_repos", frozenset()):
                    raise ValueError("Repository is not in the current Switch 2 catalog")
                asset = next(a for a in homebrew.release_assets(repo)["assets"]
                             if a["name"] == name)
                if not asset.get("digest"):
                    raise ValueError("Download disabled: GitHub SHA-256 digest unavailable")
                if name.lower().endswith(".zip"):
                    path = homebrew_zip.download_zip(asset, progress=lambda done, total: self.homebrewProgress.emit(json.dumps({"status": "Downloading", "name": name, "done": done, "total": total})))
                elif name.lower().endswith(".nro"):
                    directory = Path.home() / ".cache" / "switchnest" / "homebrew" / "downloads"
                    directory.mkdir(parents=True, exist_ok=True)
                    import tempfile
                    with tempfile.TemporaryDirectory(prefix="download-", dir=directory) as temp:
                        fetched = homebrew.download_asset(asset, temp, progress=lambda done, total: self.homebrewProgress.emit(json.dumps({"status": "Downloading", "name": name, "done": done, "total": total})))
                        target = directory / name
                        if target.exists():
                            import hashlib
                            with target.open("rb") as stream:
                                if hashlib.file_digest(stream, "sha256").hexdigest() != asset["digest"][7:].lower():
                                    raise FileExistsError("Different file already exists in Downloads cache")
                        else:
                            os.replace(fetched, target)
                        path = target
                else:
                    raise ValueError("Download-only supports verified ZIP and NRO releases")
                self.homebrewResult.emit(json.dumps({
                    "kind": "download_only_ready", "name": name,
                    "directory": str(path.parent), "path": str(path),
                    "message": "Download verified. No files were installed or uploaded."}))
            except Exception as exc:
                self.homebrewResult.emit(json.dumps({"kind": "error", "message": str(exc)[:250]}))
            finally:
                self._homebrew_busy = False
                self.homebrewBusy.emit(False)
        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def homebrew_open_download_directory(self, directory):
        base = (Path.home() / ".cache" / "switchnest" / "homebrew").resolve()
        candidate = Path(directory).resolve()
        if not candidate.is_dir() or not candidate.is_relative_to(base):
            self.homebrewResult.emit(json.dumps({"kind": "error", "message": "Invalid download directory"}))
            return
        if not QDesktopServices.openUrl(QUrl.fromLocalFile(str(candidate))):
            self.homebrewResult.emit(json.dumps({"kind": "error", "message": "Could not open file manager"}))

    @Slot(str, str)
    def homebrew_download_zip(self, repo, name):
        if getattr(self, "_homebrew_busy", False):
            return
        self._homebrew_busy = True
        self.homebrewBusy.emit(True)
        def worker():
            try:
                if repo not in homebrew.SWITCH2_CANDIDATES:
                    raise ValueError("Repository is not in the Switch 2 catalog")
                asset = next(a for a in homebrew.release_assets(repo)["assets"]
                             if a["name"] == name)
                path = homebrew_zip.download_zip(asset)
                plan = homebrew_zip.inspect_zip(path)
                self._homebrew_zip = {"repo": repo, "name": name,
                                      "digest": asset["digest"], "path": str(path),
                                      "plan": plan}
                self.homebrewResult.emit(json.dumps({
                    "kind": "zip_ready", "repo": repo, "name": name,
                    "count": plan["count"], "bytes": plan["bytes"],
                    "sample": plan["sample"]}))
            except Exception as exc:
                self.homebrewResult.emit(json.dumps({"kind": "error", "message": str(exc)[:250]}))
            finally:
                self._homebrew_busy = False
                self.homebrewBusy.emit(False)
        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, str, bool)
    def homebrew_install_zip(self, repo, name, confirmed):
        """ZIP installation is intentionally disabled; use manual download."""
        self.homebrewResult.emit(json.dumps({
            "kind": "error",
            "message": "ZIP installation is manual-only. Download the ZIP and open its folder."
        }))

    @Slot()
    def homebrew_cancel_install(self):
        event = getattr(self, "_homebrew_cancel", None)
        if event is not None and getattr(self, "_homebrew_busy", False):
            event.set()
            self.homebrewProgress.emit(json.dumps({"status": "Cancelling after current FTP operation..."}))

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
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            return
        self.kind = "refresh"
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.diagnostics"])

    @Slot(str)
    def action(self, action):
        if action not in ("on", "off") or self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
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

    def wifi_event(self, kind, detail=""):
        try:
            wifi_reliability.event(kind, detail)
            self.networkEvents.emit(json.dumps(wifi_reliability.history()))
        except (OSError, ValueError, RuntimeError):
            self.message.emit("Unable to record network event.")

    @Slot()
    def wifi_events(self):
        self.networkEvents.emit(json.dumps(wifi_reliability.history()))

    @Slot()
    def wifi_presets(self):
        self.wifiPresets.emit(json.dumps(wifi_reliability.presets()))

    @Slot(str, str, int)
    def wifi_save_preset(self, name, ssid, channel):
        try:
            wifi_reliability.save_preset(name, ssid, channel)
            self.wifi_presets()
            self.wifi_events()
            self.message.emit("Preset saved (SSID and channel only; no password).")
        except (ValueError, RuntimeError, OSError) as exc:
            self.message.emit("Preset not saved: " + str(exc))

    @Slot(str)
    def wifi_select_preset(self, name):
        try:
            item = wifi_reliability.select_preset(name)
            self.wifiStatus.emit(json.dumps({"ssid": item["ssid"], "channel": item["channel"],
                                             "note": "Preset loaded for editing; click Apply to save it."}))
            self.wifi_event("preset_applied")
        except (ValueError, RuntimeError) as exc:
            self.message.emit(str(exc))

    @Slot()
    def wifi_restart(self):
        """One confirmed OFF/ON cycle through the existing v7.1 helper only."""
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            self.message.emit("Wait for the current operation to finish.")
            return
        helper = Path("/etc/steamdeck-switch2-panel-toggle")
        try:
            st = helper.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_uid != 0 or st.st_mode & 0o022:
                raise OSError("Untrusted existing helper")
            if not Path("/usr/bin/pkexec").is_file():
                raise OSError("pkexec unavailable")
        except OSError as exc:
            self.message.emit("Existing v7.1 helper unavailable: " + str(exc))
            return
        self.wifi_recovery_attempted = False
        self._wifi_restart_step("off")

    def _wifi_restart_step(self, step):
        if self.process.state() != QProcess.NotRunning:
            self.message.emit("Another process is active; restart halted.")
            self.wifi_restart_phase = None
            return
        self.wifi_restart_phase = step
        self.kind = "wifi_restart_" + step
        self._process_output = []
        self.busyChanged.emit(True)
        self.wifiRestartProgress.emit("Stopping hotspot..." if step == "off" else "Starting hotspot...")
        self.wifi_event("restart_off" if step == "off" else "restart_on")
        self.process.start("/usr/bin/pkexec", ["/etc/steamdeck-switch2-panel-toggle", step])

    def _wifi_restart_failed(self, detail="failed"):
        self.wifi_restart_phase = None
        self.wifiRestartProgress.emit("Hotspot restart failed. Check the existing backend and use manual ON/OFF if needed.")
        self.wifi_event("restart_failed", detail)
        self.busyChanged.emit(False)
        # Only one automatic recovery attempt, and only after the user confirmed a restart.
        now = time.monotonic()
        if stability.recovery_allowed(int(self.wifi_recovery_attempted), self.wifi_last_recovery, now):
            self.wifi_recovery_attempted = True
            self.wifi_last_recovery = now
            self.wifi_pending_restore = True
            QTimer.singleShot(500, self.wifi_restore)
        else:
            self.wifiRestartProgress.emit("Recovery cooldown active or retry limit reached. Use manual controls.")

    @Slot()
    def wifi_status(self):
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            return
        self.kind = "wifi_status"
        self._process_output = []
        self.busyChanged.emit(True)
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.wifi_config", "status"])

    @Slot(str, str, int)
    def wifi_apply(self, ssid, password, channel):
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            self.message.emit("Another operation is in progress.")
            return
        from v8.wifi_config import validate
        try:
            validate(ssid, password, channel)
        except ValueError as exc:
            self.message.emit(str(exc))
            return
        self.wifi_expected_ssid = ssid
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
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
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

    def _wifi_verify(self):
        if self.wifi_restart_phase != "verify" or self.process.state() != QProcess.NotRunning:
            return
        self.kind = "wifi_restart_verify"
        self._process_output = []
        self.wifiRestartProgress.emit("Verifying hotspot status...")
        self.process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
        self.process.start(sys.executable, ["-m", "v8.diagnostics"])

    @Slot()
    def restart_control_center(self):
        if self.process.state() != QProcess.NotRunning or self.wifi_restart_phase:
            self.message.emit("Wait for hotspot restart to finish.")
            return
        launcher = Path.home() / ".local/share/switchnest/launch"
        if not launcher.is_file():
            self.message.emit("SwitchNest launcher missing.")
            return
        subprocess.Popen(["/bin/sh", "-c", 'sleep 2; exec "$1"', "sh", str(launcher)],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        QGuiApplication.instance().quit()

    def failed(self, error):
        if self.kind == "install_update":
            self.updateLog.emit("Update process error: " + self.process.errorString() + "\n")
        if self.kind == "install_update":
            self.installing_update = False
        self.message.emit(self.process.errorString())
        if self.kind.startswith("wifi_restart_"):
            self._wifi_restart_failed()
        self.busyChanged.emit(False)

    def finished(self, code, status):
        self.read_stdout()
        self.read_stderr()
        output = "".join(self._process_output).strip()
        kind = self.kind
        self._process_output = []
        if kind in ("refresh", "wifi_restart_verify") and code == 0:
            self.last_report = output
            self.refreshed.emit(output)
            try:
                report = json.loads(output)
                health = wifi_reliability.health(report)
                self.wifiHealth.emit(json.dumps(health))
                if health["state"] != self._last_health_state:
                    if health["state"] == "attention":
                        self.wifi_event("health_warning")
                    self._last_health_state = health["state"]
                if kind == "wifi_restart_verify":
                    self.wifi_restart_phase = None
                    expected = getattr(self, "wifi_expected_ssid", None)
                    active = report.get("hotspot", {})
                    if active.get("state") == "on" and (not expected or active.get("ssid") == expected):
                        self.wifiRestartProgress.emit("Hotspot verified. Restarting SwitchNest Control Center...")
                        self.wifi_event("restart_verified", "ok")
                        QTimer.singleShot(1500, self.restart_control_center)
                    else:
                        self._wifi_restart_failed("verification_failed")
            except (ValueError, TypeError):
                if kind == "wifi_restart_verify":
                    self._wifi_restart_failed("verification_failed")
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
                if result.get("ok"):
                    self.wifi_event("wifi_saved" if kind == "wifi_apply" else "wifi_restored", "ok")
                    if kind == "wifi_apply":
                        self.wifiRestartSuggested.emit()
                    if kind == "wifi_restore" and self.wifi_pending_restore:
                        self.wifi_pending_restore = False
                        self.wifi_expected_ssid = None
                        self.wifiRestartProgress.emit("Previous Wi-Fi profile restored. Attempting one recovery restart...")
                        QTimer.singleShot(1200, lambda: self._wifi_restart_step("off"))
                else:
                    self.wifi_event("wifi_failed", "failed")
                    self.wifi_pending_restore = False
        else:
            self.message.emit(("Completed: " if code == 0 else "Failed: ") + output)
        self.busyChanged.emit(False)
        if kind == "wifi_restart_off":
            if code == 0 and status == QProcess.NormalExit:
                QTimer.singleShot(1200, lambda: self._wifi_restart_step("on"))
            else:
                self._wifi_restart_failed("authorization_required" if code != 0 else "failed")
        elif kind == "wifi_restart_on":
            if code == 0 and status == QProcess.NormalExit:
                self.wifi_restart_phase = "verify"
                QTimer.singleShot(2500, self._wifi_verify)
            else:
                self._wifi_restart_failed("authorization_required" if code != 0 else "failed")
        elif kind == "wifi_restart_verify" and code != 0:
            self._wifi_restart_failed("verification_failed")
        if kind == "install_update":
            self.installing_update = False
            if code == 0 and status == QProcess.NormalExit and "Installed v" in output:
                self.update_installed = True
                self.updateInstalled.emit(output.split("Installed v")[-1].split(". Close")[0].strip())
            else:
                self.updateLog.emit("\nUpdate failed. Check the output above.\n")
        if kind == "repair":
            self.message.emit("Application repair completed." if code == 0 else "Application repair failed: " + output[:250])
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
    controller._homebrew_browser = browser
    engine.rootContext().setContextProperty("ftpBrowser", browser)
    app.aboutToQuit.connect(browser.cancel)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("ControlCenter.qml"))))
    if not engine.rootObjects():
        return 1
    QTimer.singleShot(0, controller.refresh)
    QTimer.singleShot(300, controller.wifi_presets)
    QTimer.singleShot(400, controller.wifi_events)
    if preferences.load()["check_at_startup"]:
        QTimer.singleShot(1500, lambda: controller.check_updates("stable" if preferences.load()["stable_only"] else "development"))
    return app.exec()

if __name__ == "__main__":
    sys.exit(main())
