"""Wi-Fi reliability state, safe named presets and bounded event history.

No network writes or privilege escalation. Presets never store passwords.
"""
import json
import os
from pathlib import Path
import re
import tempfile
from datetime import datetime, timezone

BASE = Path.home() / ".config/switchnest"
PRESETS = BASE / "wifi-presets.json"
EVENTS = BASE / "network-events.json"
MAX_EVENTS = 100
MAX_PRESETS = 12
VALID_CHANNELS = (1, 6, 11)
ALLOWED_EVENTS = {"wifi_saved", "wifi_restored", "wifi_failed", "restart_requested",
                  "restart_off", "restart_on", "restart_failed", "restart_verified",
                  "recovery_requested", "health_warning", "preset_saved", "preset_applied"}

def _load(path, default):
    if path.is_symlink() or not path.is_file():
        return default
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, type(default)) else default
    except (ValueError, OSError):
        return default

def _save(path, data):
    BASE.mkdir(parents=True, exist_ok=True)
    if BASE.is_symlink() or path.is_symlink():
        raise RuntimeError("Unsafe settings location")
    fd, tmp = tempfile.mkstemp(prefix=".switchnest-", dir=BASE)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def event(kind, detail=""):
    if kind not in ALLOWED_EVENTS:
        raise ValueError("Invalid event type")
    # Details must never include passwords, command output, or arbitrary user input.
    if detail not in ("", "ok", "failed", "timeout", "authorization_required",
                      "profile_inactive", "verification_failed"):
        raise ValueError("Invalid event detail")
    items = _load(EVENTS, [])
    items.append({"time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                  "event": kind, "detail": detail})
    _save(EVENTS, items[-MAX_EVENTS:])
    return items[-MAX_EVENTS:]

def history():
    return _load(EVENTS, [])[-MAX_EVENTS:]

def validate_preset(name, ssid, channel):
    from v8.wifi_config import validate
    if not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9 _-]{1,32}", name):
        raise ValueError("Preset name must be 1–32 letters, numbers, spaces, _ or -")
    validate(ssid, "", channel)

def save_preset(name, ssid, channel):
    validate_preset(name, ssid, channel)
    presets = _load(PRESETS, {})
    if name not in presets and len(presets) >= MAX_PRESETS:
        raise ValueError("Preset limit reached")
    presets[name] = {"ssid": ssid, "channel": channel}
    _save(PRESETS, presets)
    event("preset_saved")
    return presets

def presets():
    return _load(PRESETS, {})

def select_preset(name):
    if not isinstance(name, str):
        raise ValueError("Invalid preset name")
    item = presets().get(name)
    if not isinstance(item, dict):
        raise ValueError("Preset not found")
    validate_preset(name, item.get("ssid"), item.get("channel"))
    return item

def health(report):
    hotspot = report.get("hotspot", {})
    state = hotspot.get("state", "unknown")
    dns = report.get("dns_service", {}).get("output", "unknown")
    dhcp = report.get("hotspot_service", {}).get("output", "unknown")
    issues = []
    if state == "on" and dns != "active":
        issues.append("DNS service not reported active")
    if state == "on" and dhcp != "active":
        issues.append("Hotspot service not reported active")
    return {"state": "attention" if issues else ("healthy" if state == "on" else "inactive"),
            "issues": issues, "hotspot": state, "dns": dns, "hotspot_service": dhcp,
            "note": "Service health is not proof of network isolation"}

def live_clients(report):
    clients = report.get("hotspot", {}).get("clients", [])
    return clients if isinstance(clients, list) else []
