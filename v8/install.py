"""Install the GUI from a trusted extracted checkout; never modify system networking."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

VERSION = "8.1.7"
ROOT = Path.home()/".local/share/switchnest"
SOURCE = Path(__file__).resolve().parent.parent

def point(name, target):
    temporary=ROOT/("."+name+"-"+uuid.uuid4().hex)
    temporary.symlink_to(target)
    os.replace(temporary, ROOT/name)

def current(name):
    p=ROOT/name
    if not p.is_symlink():
        return None
    q=p.resolve()
    if q.parent != ROOT/"releases" or not (q/"v8/control_center.py").is_file():
        raise RuntimeError("Invalid installed release pointer")
    return q

def run(*args):
    subprocess.run([str(a) for a in args],check=True)

def verify_installation(release=None):
    """Check managed application files only; no network changes."""
    release = release or current("current")
    if release is None:
        return {"ok": False, "issues": ["No active managed release"]}
    required = [release/"v8/control_center.py", release/"v8/ControlCenter.qml",
                release/"venv/bin/python", ROOT/"launch"]
    issues = [str(path.name) + " missing" for path in required if not path.is_file()]
    if not (ROOT/"launch").is_file() or not os.access(ROOT/"launch", os.X_OK):
        issues.append("Launcher not executable")
    return {"ok": not issues, "issues": issues}

def repair_application():
    """Repair the user-local launcher only."""
    active = current("current")
    if active is None:
        raise RuntimeError("No managed release to repair")
    required = [active/"v8/control_center.py", active/"v8/ControlCenter.qml",
                active/"venv/bin/python"]
    if not all(path.is_file() for path in required):
        raise RuntimeError("Application files missing; use rollback instead")
    launcher()
    result = verify_installation(active)
    if not result["ok"]:
        raise RuntimeError("Repair verification failed: " + ", ".join(result["issues"]))
    return result

def install():
    if not shutil.which("curl"):
        raise RuntimeError("curl is required")
    releases=ROOT/"releases"
    releases.mkdir(exist_ok=True)
    if releases.is_symlink() or releases.stat().st_uid!=os.getuid(): raise RuntimeError("Invalid releases directory")
    if shutil.disk_usage(releases).free < 2*1024**3: raise RuntimeError("At least 2 GiB free recommended for a new Qt environment")
    release=releases/(VERSION+"-"+uuid.uuid4().hex[:10])
    try:
        release.mkdir()
        shutil.copytree(SOURCE/"v8",release/"v8",ignore=shutil.ignore_patterns("__pycache__","*.pyc"))
        for name in ("LICENSE","THIRD_PARTY_NOTICES.md"):
            if (SOURCE/name).is_file(): shutil.copy2(SOURCE/name,release/name)
        if (SOURCE/"licenses").is_dir(): shutil.copytree(SOURCE/"licenses",release/"licenses")
        # Catch missing packaged test dependencies before installing Qt wheels.
        required_modules = ("ftp_install_smoketest.py", "homebrew_zip.py", "HomebrewPage.qml")
        missing = [name for name in required_modules if not (release/"v8"/name).is_file()]
        if missing:
            raise RuntimeError("Incomplete Homebrew Manager release: " + ", ".join(missing))
        run(sys.executable,"-m","venv",release/"venv")
        python=release/"venv/bin/python"
        run(python,"-m","pip","install","PySide6>=6.7,<7")
        run(python,"-m","compileall","-q",release/"v8")
        subprocess.run([str(python),"-m","unittest","-v","v8.test_ftp_tree","v8.test_install","v8.test_updates","v8.test_autostart","v8.test_v806","v8.test_v807","v8.test_v808","v8.test_v809","v8.test_v810","v8.test_v816"],cwd=release,check=True)
        run(python,"-c","from PySide6 import QtCore, QtGui, QtQml; print(QtCore.qVersion())")
        old=current("current")
        launcher()
        if old: point("previous",old)
        point("current",release)
        verification = verify_installation(release)
        if not verification["ok"]:
            if old:
                point("current", old)
                launcher()
            else:
                (ROOT/"current").unlink(missing_ok=True)
            raise RuntimeError("Post-install verification failed: " + ", ".join(verification["issues"]))
    except BaseException:
        if not (ROOT/"current").is_symlink() or (ROOT/"current").resolve()!=release:
            shutil.rmtree(release,ignore_errors=True)
        raise
    print("Installed release:",release.name)

def launcher():
    from v8.install_launcher import desktop_quote
    data=Path(os.environ.get("XDG_DATA_HOME",str(Path.home()/".local/share")))
    apps=data/"applications"
    apps.mkdir(parents=True,exist_ok=True)
    executable=ROOT/"launch"
    executable.write_text('#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")/current"\nexec ./venv/bin/python -m v8.control_center "$@"\n')
    executable.chmod(0o700)
    (apps/"switchnest-control-center.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=SwitchNest Control Center\n"
        "Comment=SwitchNest v8 Hotspot Manager\n"
        "Exec=" + desktop_quote(str(executable)) + "\n"
        "Path=" + str(ROOT / "current") + "\n"
        "Icon=" + str(ROOT/"current"/"v8"/"assets"/"switchnest-logo.svg") + "\n"
        "Terminal=false\n"
        "Categories=Network;Utility;\n"
        "StartupNotify=true\n"
    )
    print("Installed KDE application launcher:",apps/"switchnest-control-center.desktop")

def main():
    if os.geteuid()==0: raise SystemExit("Run without sudo")
    parser=argparse.ArgumentParser()
    parser.add_argument("action",choices=["install","rollback","status","verify","repair"],default="install",nargs="?")
    action=parser.parse_args().action
    ROOT.mkdir(parents=True,exist_ok=True)
    if ROOT.is_symlink() or ROOT.stat().st_uid!=os.getuid(): raise SystemExit("Invalid installation directory")
    with (ROOT/"install.lock").open("a") as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if action=="install": install()
        elif action=="rollback":
            old=current("current")
            previous=current("previous")
            if not previous or not old: raise SystemExit("No previous managed release")
            point("current",previous)
            point("previous",old)
            launcher()
            print("Rolled back to",previous.name)
        elif action=="verify":
            import json
            result = verify_installation()
            print(json.dumps(result))
            if not result["ok"]: raise SystemExit(1)
        elif action=="repair":
            import json
            print(json.dumps(repair_application()))
        else:
            for key in ("current","previous"):
                print(key, current(key) or "not installed")
if __name__=="__main__":
    main()
