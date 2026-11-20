"""Read-only diagnostics, bounded recovery decisions and safe support exports.

No privileged operations, hotspot mutations, or FTP changes live here.
"""
import json
import os
from pathlib import Path
import re
import tempfile
import time
from datetime import datetime, timezone

from v8 import wifi_reliability

MAX_EXPORT_BYTES = 256 * 1024
RETRY_LIMIT = 1
RECOVERY_COOLDOWN_SECONDS = 120
SENSITIVE = re.compile(r"(?i)(password|passwd|psk|secret|token|authorization|cookie|api[_-]?key|credential)")
MAC = re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b")
IPV4 = re.compile(r"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])")
SAFE_KEYS = {"state", "ok", "exit_code", "status", "signal", "connected_seconds",
             "rx_bytes", "tx_bytes", "event", "detail", "time", "version",
             "healthy", "attention", "inactive", "note", "issues", "checks",
             "hotspot", "dns", "hotspot_service", "http_service", "dns_service",
             "ipv4_forwarding", "ipv6_forwarding", "network_mode", "interface",
             "stations", "clients", "security", "ip", "ssid", "mac", "output",
             "category", "result", "label", "available", "reason"}

def _redact_text(value):
    value = MAC.sub("[redacted-mac]", value)
    value = IPV4.sub("[redacted-ip]", value)
    return value[:512]

def redact(value, key=""):
    """Allow only bounded, structured diagnostic values; no raw command dumps."""
    if SENSITIVE.search(str(key)):
        return "[redacted]"
    if isinstance(value, dict):
        return {str(k): redact(v, str(k)) for k, v in value.items()
                if str(k) in SAFE_KEYS and not SENSITIVE.search(str(k))}
    if isinstance(value, list):
        return [redact(item, key) for item in value[:100]]
    if isinstance(value, bool) or value is None or isinstance(value, (int, float)):
        return value
    if key in ("ssid", "security", "output"):
        # SSIDs and command output may contain sensitive values; never export them.
        return "[omitted]"
    if isinstance(value, str):
        return _redact_text(value)
    return "[unsupported]"

def self_test(report, profile=None):
    """Read-only status checks. A healthy service is NOT an isolation proof."""
    hot = report.get("hotspot", {})
    state = hot.get("state", "unknown")
    def check(label, ok, reason):
        return {"label": label, "result": "pass" if ok else "attention",
                "reason": "" if ok else reason}
    checks = [
        check("NetworkManager AP", state == "on", "Hotspot profile is not active"),
        check("Wi-Fi interface", bool(hot.get("interface")), "No active AP interface"),
        check("DHCP service", report.get("hotspot_service", {}).get("output") == "active",
              "Hotspot service not reported active"),
        check("DNS service", report.get("dns_service", {}).get("output") == "active",
              "DNS service not reported active"),
        check("Gateway IPv4", bool(hot.get("ip")), "No gateway IPv4 reported"),
        check("Firewall visibility", report.get("firewall", {}).get("ok") is True,
              "Firewall inspection unavailable"),
        check("FTP client", bool(hot.get("clients")), "No associated client; FTP not probed"),
    ]
    # Profile capabilities are optional; no active network probes or changes.
    if profile is not None:
        checks.append(check("Wi-Fi profile", profile.get("ap_profile") is True,
                            "AP profile unavailable or invalid"))
    return {"state": "attention" if any(x["result"] != "pass" for x in checks) else "healthy",
            "checks": checks,
            "note": "Read-only checks only. No isolation, DHCP lease, or FTP reachability guarantee."}

def recovery_allowed(attempts, last_attempt, now=None, cooldown=RECOVERY_COOLDOWN_SECONDS):
    """One bounded recovery attempt, with cooldown; never react to client disconnects."""
    now = time.monotonic() if now is None else now
    return attempts < RETRY_LIMIT and (last_attempt is None or now - last_attempt >= cooldown)

def export_report(report, destination, profile=None, history=None):
    """Atomic, private JSON report; reject symlink targets and untrusted folders."""
    destination = Path(destination)
    if destination.suffix.lower() != ".json" or destination.is_symlink():
        raise ValueError("Choose a regular .json report path")
    parent = destination.parent
    if not parent.is_dir() or parent.is_symlink():
        raise ValueError("Invalid report directory")
    payload = {
        "version": "8.0.9",
        "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "checks": self_test(report, profile)["checks"],
        "hotspot": redact(report.get("hotspot", {})),
        "events": [{"time": _redact_text(str(x.get("time", ""))),
                    "event": _redact_text(str(x.get("event", ""))),
                    "detail": _redact_text(str(x.get("detail", "")))}
                   for x in (history if history is not None else wifi_reliability.history())[-100:]
                   if isinstance(x, dict)],
        "note": "Read-only snapshot; sensitive values omitted. Review before sharing.",
    }
    # Explicit allowlist for event fields; event strings from storage may be untrusted.
    for event in payload["events"]:
        if event["event"] not in wifi_reliability.ALLOWED_EVENTS:
            event["event"] = "[redacted]"
        if event["detail"] not in ("", "ok", "failed", "timeout",
                                   "authorization_required", "profile_inactive",
                                   "verification_failed"):
            event["detail"] = "[redacted]"
    serialized = json.dumps(payload, indent=2, ensure_ascii=False)
    if len(serialized.encode("utf-8")) > MAX_EXPORT_BYTES:
        raise ValueError("Report exceeds size limit")
    fd, tmp = tempfile.mkstemp(prefix=".switchnest-report-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(serialized)
        os.chmod(tmp, 0o600)
        os.replace(tmp, destination)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return destination
