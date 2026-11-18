"""Install a user-local launcher referencing the current checkout."""
import os
import shlex
from pathlib import Path

def desktop_quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'

def main():
    if os.geteuid() == 0:
        raise SystemExit("Run without sudo")
    root = Path(__file__).resolve().parent.parent
    python = Path.home() / ".local/share/switchnest-v8-venv/bin/python"
    if not python.is_file():
        raise SystemExit("Create the v8 virtual environment first")
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    apps = data / "applications"
    apps.mkdir(parents=True, exist_ok=True)
    icon = data / "icons/switchnest.svg"
    icon.parent.mkdir(parents=True, exist_ok=True)
    icon.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#161c25"/><g fill="none" stroke="#52e0ae" stroke-width="5" stroke-linecap="round"><path d="M10 24 Q32 5 54 24 M18 33 Q32 20 46 33 M26 42 Q32 36 38 42"/></g><circle cx="32" cy="49" r="3" fill="#52e0ae"/></svg>')
    launcher = apps / "switchnest-control-center.desktop"
    command = "cd " + shlex.quote(str(root)) + " && exec " + shlex.quote(str(python)) + " -m v8.control_center"
    launcher.write_text("[Desktop Entry]\nType=Application\nName=SwitchNest Control Center\nExec=/bin/sh -c " + desktop_quote(command) + "\nIcon=" + str(icon) + "\nTerminal=false\nCategories=Network;Utility;\n")
    print("Installed:", launcher)
    print("Open SwitchNest Control Center from the KDE application menu.")

if __name__ == "__main__":
    main()
