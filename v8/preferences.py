"""Per-user preferences for update notifications; no privileged operations."""
import json
import os
from pathlib import Path

DEFAULTS = {"check_at_startup": True, "show_update_popup": True, "stable_only": True, "fullscreen_on_start": False}
PATH = Path.home() / ".config" / "switchnest" / "preferences.json"

def load():
    try:
        data = json.loads(PATH.read_text())
        if not isinstance(data, dict):
            return DEFAULTS.copy()
        return {key: data.get(key) if type(data.get(key)) is bool else default
                for key, default in DEFAULTS.items()}
    except (OSError, ValueError, TypeError):
        return DEFAULTS.copy()

def save(key, value):
    if key not in DEFAULTS or type(value) is not bool:
        raise ValueError("Invalid preference")
    settings = load()
    settings[key] = value
    PATH.parent.mkdir(parents=True, exist_ok=True)
    if PATH.parent.is_symlink() or PATH.is_symlink():
        raise RuntimeError("Unsafe preferences location")
    temp = PATH.with_suffix(".tmp")
    try:
        with temp.open("w") as stream:
            os.chmod(temp, 0o600)
            json.dump(settings, stream)
        os.replace(temp, PATH)
    finally:
        temp.unlink(missing_ok=True)
    return settings
