"""Read-only SteamOS diagnostics. No privilege escalation or network changes."""
import json
import ipaddress
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

def connected_clients(interface, stations):
    """Only currently associated stations; IP mapping is best-effort neighbor data."""
    if not stations:
        return []
    neighbors = probe(["ip", "-4", "neigh", "show", "dev", interface])
    addresses = {}
    if neighbors["ok"]:
        for line in neighbors["output"].splitlines():
            fields = line.split()
            if len(fields) < 4 or "lladdr" not in fields:
                continue
            try:
                address = str(ipaddress.IPv4Address(fields[0]))
                mac = fields[fields.index("lladdr") + 1].lower()
            except (ValueError, IndexError):
                continue
            if fields[-1] not in ("FAILED", "INCOMPLETE"):
                addresses[mac] = address
    return [{"mac": mac, "ip": addresses.get(mac), "status": "Associated"}
            for mac in stations]

def hotspot():
    name = "SteamDeck-Switch2"
    profile = probe(["nmcli", "-g", "connection.uuid", "connection", "show", name])
    result = {"state": "unknown", "ssid": None, "ip": None, "security": None,
              "interface": None, "stations": None, "clients": []}
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
    result["clients"] = connected_clients(iface, result["stations"])
    # Read-only association metadata; fields may be unavailable on some drivers.
    if stations["ok"]:
        details = {}
        current = None
        for line in stations["output"].splitlines():
            match = re.match(r"^Station ([0-9a-fA-F:]{17})\s", line)
            if match:
                current = match.group(1).lower()
                details[current] = {}
                continue
            if current:
                for key, pattern in (("signal", r"^\s*signal:\s*(-?\d+)\s*dBm"),
                                     ("connected_seconds", r"^\s*connected time:\s*(\d+)\s*seconds"),
                                     ("rx_bytes", r"^\s*rx bytes:\s*(\d+)"),
                                     ("tx_bytes", r"^\s*tx bytes:\s*(\d+)")):
                    value = re.match(pattern, line)
                    if value:
                        details[current][key] = int(value.group(1))
        for client in result["clients"]:
            client.update(details.get(client["mac"].lower(), {}))
    return result

def collect():
    return {
        "version": "8.1.0",
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
