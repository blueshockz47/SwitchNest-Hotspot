"""Read-only SteamOS diagnostics. No privilege escalation or network changes."""
import json
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

def collect():
    return {
        "version": "8.0-alpha.1",
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
