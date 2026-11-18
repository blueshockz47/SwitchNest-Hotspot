"""Install the GUI from a trusted extracted checkout; never modify system networking."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

VERSION = "8.0-beta.2"
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

def install():
    if not shutil.which("curl"):
        raise RuntimeError("curl is required")
    releases=ROOT/"releases"
    releases.mkdir(exist_ok=True)
    release=releases/(VERSION+"-"+uuid.uuid4().hex[:10])
    try:
        release.mkdir()
        shutil.copytree(SOURCE/"v8",release/"v8",ignore=shutil.ignore_patterns("__pycache__","*.pyc"))
        run(sys.executable,"-m","venv",release/"venv")
        python=release/"venv/bin/python"
        run(python,"-m","pip","install","PySide6>=6.7,<7")
        run(python,"-m","compileall","-q",release/"v8")
        subprocess.run([str(python),"-m","unittest","-v","v8.test_ftp_tree"],cwd=release,check=True)
        old=current("current")
        if old: point("previous",old)
        point("current",release)
    except BaseException:
        if current("current")!=release: shutil.rmtree(release,ignore_errors=True)
        raise
    launcher()

def launcher():
    from v8.install_launcher import desktop_quote
    data=Path(os.environ.get("XDG_DATA_HOME",str(Path.home()/".local/share")))
    apps=data/"applications"
    apps.mkdir(parents=True,exist_ok=True)
    executable=ROOT/"launch"
    executable.write_text('#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")/current"\nexec ./venv/bin/python -m v8.control_center "$@"\n')
    executable.chmod(0o700)
    (apps/"switchnest-control-center.desktop").write_text("[Desktop Entry]\nType=Application\nName=SwitchNest Control Center\nExec="+desktop_quote(str(executable))+"\nIcon=network-wireless\nTerminal=false\nCategories=Network;Utility;\n")
    print("Installed KDE application launcher:",apps/"switchnest-control-center.desktop")

def main():
    if os.geteuid()==0: raise SystemExit("Run without sudo")
    parser=argparse.ArgumentParser()
    parser.add_argument("action",choices=["install","rollback","status"],default="install",nargs="?")
    action=parser.parse_args().action
    ROOT.mkdir(parents=True,exist_ok=True)
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
        else:
            for key in ("current","previous"):
                print(key, current(key) or "not installed")
if __name__=="__main__":
    main()
