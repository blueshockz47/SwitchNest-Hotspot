"""Manage only the SwitchNest XDG autostart entry."""
import os
from pathlib import Path
import tempfile
from v8.install_launcher import desktop_quote

def entry():
    return Path(os.environ.get("XDG_CONFIG_HOME",str(Path.home()/".config")))/"autostart/switchnest-control-center.desktop"

def launcher():
    return Path.home()/".local/share/switchnest/launch"

def content():
    return "[Desktop Entry]\nType=Application\nName=SwitchNest Control Center\nExec="+desktop_quote(str(launcher()))+"\nTerminal=false\n"

def enabled():
    try: return entry().read_text()==content()
    except OSError: return False

def set_enabled(value):
    p=entry()
    if not value:
        p.unlink(missing_ok=True)
        return
    if not launcher().is_file() or not os.access(launcher(),os.X_OK):
        raise RuntimeError("Install SwitchNest using the managed installer first.")
    p.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix=".switchnest-",dir=p.parent)
    try:
        with os.fdopen(fd,"w") as f: f.write(content())
        os.replace(name,p)
    finally:
        Path(name).unlink(missing_ok=True)
