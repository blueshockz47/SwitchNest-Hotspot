"""Transactional NetworkManager Wi-Fi profile editor.

Only modifies Wi-Fi SSID, WPA2 PSK, band and channel of the existing
SteamDeck-Switch2 profile. Does not touch IP, DNS, firewall, services or
hotspot activation. Requires existing NetworkManager authorization.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

PROFILE = "SteamDeck-Switch2"
BACKUP = Path.home() / ".local/share/switchnest/wifi-profile-backup.json"
FIELDS = ("802-11-wireless.ssid", "802-11-wireless.band",
          "802-11-wireless.channel", "802-11-wireless-security.psk")
ALLOWED_CHANNELS = {1, 6, 11}

def command(*args, secret=False):
    try:
        proc = subprocess.run(["nmcli", *args], capture_output=True, text=True,
                              timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError("NetworkManager command unavailable or timed out") from exc
    if proc.returncode:
        # Never expose stderr/stdout of a command that may contain a PSK.
        raise RuntimeError("NetworkManager rejected the operation" if secret
                           else "NetworkManager operation failed: " + proc.stderr.strip()[:300])
    return proc.stdout.strip()

def uuid():
    value = command("-g", "connection.uuid", "connection", "show", PROFILE)
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", value):
        raise RuntimeError("Expected hotspot profile is missing or ambiguous")
    return value

def read_field(identifier, field, secret=False):
    args = ["-s"] if secret else []
    return command(*args, "-g", field, "connection", "show", identifier, secret=secret)

def snapshot(identifier):
    return {field: read_field(identifier, field, secret=(field.endswith(".psk")))
            for field in FIELDS}

def validate(ssid, password, channel):
    if not isinstance(ssid, str) or not 1 <= len(ssid.encode("utf-8")) <= 32 or any(ord(c) < 32 or ord(c) == 127 for c in ssid):
        raise ValueError("SSID must be 1–32 UTF-8 bytes without control characters")
    if password and (not isinstance(password, str) or not (8 <= len(password) <= 63 and password.isascii() and password.isprintable())):
        raise ValueError("WPA2 password must be 8–63 printable ASCII characters")
    if type(channel) is not int or channel not in ALLOWED_CHANNELS:
        raise ValueError("Choose 2.4 GHz channel 1, 6 or 11")

def write_backup(identifier, values):
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if BACKUP.parent.is_symlink() or BACKUP.is_symlink():
        raise RuntimeError("Unsafe backup location")
    fd, name = tempfile.mkstemp(prefix=".wifi-", dir=BACKUP.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump({"uuid": identifier, "fields": values}, stream)
        os.chmod(name, 0o600)
        os.replace(name, BACKUP)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def restore_fields(identifier, fields):
    # Restore only the four Wi-Fi fields; never rewrite other profile settings.
    args = []
    for key in FIELDS:
        args.extend((key, fields[key]))
    command("connection", "modify", identifier, *args, secret=True)

def apply(ssid, password, channel):
    validate(ssid, password, channel)
    identifier = uuid()
    previous = snapshot(identifier)
    if not previous[FIELDS[3]]:
        raise RuntimeError("Cannot safely change Wi-Fi settings: existing WPA2 secret cannot be backed up")
    if read_field(identifier, "802-11-wireless-security.key-mgmt") != "wpa-psk":
        raise RuntimeError("Only existing WPA2-PSK hotspot profiles are supported")
    if read_field(identifier, "802-11-wireless.mode") != "ap":
        raise RuntimeError("Selected connection is not an access-point profile")
    write_backup(identifier, previous)
    args = ["802-11-wireless.ssid", ssid,
            "802-11-wireless.band", "bg",
            "802-11-wireless.channel", str(channel)]
    if password:
        args.extend(("802-11-wireless-security.psk", password))
    try:
        command("connection", "modify", identifier, *args, secret=bool(password))
        actual = snapshot(identifier)
        if actual[FIELDS[0]] != ssid or actual[FIELDS[1]] != "bg" or actual[FIELDS[2]] != str(channel) or (password and actual[FIELDS[3]] != password):
            raise RuntimeError("Profile verification failed")
    except Exception:
        try:
            restore_fields(identifier, previous)
        except Exception as exc:
            raise RuntimeError("Wi-Fi apply failed; automatic restoration also failed. Use Restore Previous Wi-Fi Settings.") from exc
        raise
    return {"ok": True, "message": "Wi-Fi profile saved. Restart the hotspot using the existing ON/OFF controls to activate changes. Connected devices may need to reconnect."}

def restore():
    if BACKUP.is_symlink() or not BACKUP.is_file():
        raise RuntimeError("No saved Wi-Fi settings")
    data = json.loads(BACKUP.read_text())
    identifier = uuid()
    if data.get("uuid") != identifier or set(data.get("fields", {})) != set(FIELDS):
        raise RuntimeError("Backup does not match the current hotspot profile")
    restore_fields(identifier, data["fields"])
    return {"ok": True, "message": "Previous Wi-Fi settings restored. Restart the hotspot using its existing ON/OFF controls."}

def capabilities():
    identifier = uuid()
    band = read_field(identifier, "802-11-wireless.band")
    channel = read_field(identifier, "802-11-wireless.channel")
    ssid = read_field(identifier, "802-11-wireless.ssid")
    mode = read_field(identifier, "802-11-wireless.mode")
    security = read_field(identifier, "802-11-wireless-security.key-mgmt")
    return {"ssid": ssid, "band": band, "channel": channel, "ap_profile": mode == "ap",
            "wpa2": security == "wpa-psk", "backup": BACKUP.is_file() and not BACKUP.is_symlink(),
            "note": "Channels 1, 6, 11 are offered for 2.4 GHz. Actual adapter/regulatory support must be verified on the host before applying."}

def main():
    import sys
    if os.geteuid() == 0:
        raise SystemExit("Run as desktop user, not root")
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        if action == "status":
            result = capabilities()
        elif action == "apply" and len(sys.argv) == 3:
            # Password comes via stdin, never command-line arguments.
            data = json.loads(sys.stdin.read(4096))
            result = apply(data["ssid"], data.get("password", ""), data["channel"])
        elif action == "restore":
            result = restore()
        else:
            raise ValueError("Unsupported operation")
        print(json.dumps(result))
    except (OSError, ValueError, RuntimeError, KeyError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)

if __name__ == "__main__":
    main()
