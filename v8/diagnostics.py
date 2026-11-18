"""Read-only SteamOS diagnostics. No privilege escalation or network changes."""
import json
import re
import shutil
import subprocess

def probe(argv):
    if not shutil.which(argv[0]):
        return {"ok": False, "output": "command unavailable"}
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=8)
        return {"ok": p.returncode == 0, "output": (p.stdout or p.stderr).strip(), "exit_code": p.returncode}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "output": str(exc)}

def hotspot():
    name = "SteamDeck-Switch2"
    profile = probe(["nmcli", "-g", "connection.uuid", "connection", "show", name])
    result = {"state": "unknown", "ssid": None, "ip": None, "security": None,
              "interface": None, "stations": None}
    if not profile["ok"]:
        return result
    uuid = profile["output"]
    active = probe(["nmcli", "-g", "UUID", "connection", "show", "--active"])
    if not active["ok"]:
        return result
    result["state"] = "on" if uuid in active["output"].splitlines() else "off"
    for key, field in [("ssid", "802-11-wireless.ssid"),
                       ("security", "802-11-wireless-security.key-mgmt")]:
        value = probe(["nmcli", "-g", field, "connection", "show", uuid])
        if value["ok"]:
            result[key] = value["output"] or ("Open / unspecified" if key == "security" else None)
    if result["state"] != "on":
        return result
    device = probe(["nmcli", "-g", "GENERAL.DEVICES", "connection", "show", uuid])
    iface = device["output"]
    if not device["ok"] or not re.fullmatch(r"[a-zA-Z0-9_.-]+", iface):
        return result
    result["interface"] = iface
    ip = probe(["nmcli", "-g", "IP4.ADDRESS", "device", "show", iface])
    if ip["ok"]:
        result["ip"] = ip["output"]
    stations = probe(["iw", "dev", iface, "station", "dump"])
    if stations["ok"]:
        result["stations"] = sorted(set(re.findall(
            r"^Station ([0-9a-fA-F:]{17})\s", stations["output"], re.M)))
    return result

def collect():
    return {
        "version": "8.0-alpha.10",
        "sunshine_installed": probe(["flatpak", "info", "dev.lizardbyte.app.Sunshine"]),
        "sunshine_processes": probe(["flatpak", "ps", "--columns=application"]),
        "hotspot_service": probe(["systemctl", "is-active", "steamdeck-switch2-hotspot.service"]),
        "ipv4_forwarding": probe(["sysctl", "-n", "net.ipv4.ip_forward"]),
        "ipv6_forwarding": probe(["sysctl", "-n", "net.ipv6.conf.all.forwarding"]),
        "hotspot": hotspot(),
        "http_service": probe(["systemctl", "is-active", "steamdeck-switch2-http.service"]),
        "network_mode": "unverified",
        "active_connections": probe(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]),
        "dns_service": probe(["systemctl", "is-active", "steamdeck-switch2-dnsmasq.service"]),
        "ipv4_routes": probe(["ip", "-4", "route", "show"]),
        "ipv6_routes": probe(["ip", "-6", "route", "show"]),
        "firewall": probe(["nft", "list", "tables"]),
        "note": "Read-only inventory; not proof of network isolation. Output may contain local network details."
    }

if __name__ == "__main__":
    print(json.dumps(collect(), indent=2))
