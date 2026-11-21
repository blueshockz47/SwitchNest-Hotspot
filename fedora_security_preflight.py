"""Read-only Fedora firewall/SELinux compatibility preflight.

No firewall or SELinux settings are changed by this module.
"""
from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SecurityPreflight:
    fedora: bool
    firewalld: str
    selinux: str
    recommendations: tuple[str, ...]


def _run(*args: str) -> str | None:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def is_fedora(os_release: str) -> bool:
    values = {}
    for line in os_release.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"')
    return values.get("ID", "").lower() == "fedora" or "fedora" in values.get("ID_LIKE", "").lower().split()


def diagnose(os_release_path: str = "/etc/os-release") -> SecurityPreflight:
    try:
        fedora = is_fedora(Path(os_release_path).read_text(encoding="utf-8"))
    except OSError:
        fedora = False

    fw = "unavailable"
    if shutil.which("firewall-cmd"):
        fw = "running" if _run("firewall-cmd", "--state") == "running" else "not-running-or-inaccessible"

    se = "unavailable"
    if shutil.which("getenforce"):
        value = _run("getenforce")
        if value in {"Enforcing", "Permissive", "Disabled"}:
            se = value.lower()
        else:
            se = "unknown"

    recommendations = []
    if fw == "running":
        recommendations.append("Inspect the hotspot interface zone, DHCP/DNS permissions and forwarding policy; do not disable firewalld.")
    if se == "enforcing":
        recommendations.append("Inspect AVC denials with journalctl or ausearch; do not disable SELinux or install blanket allow rules.")
    if not fedora:
        recommendations.append("Fedora-specific remediation is not applicable to this host.")
    return SecurityPreflight(fedora, fw, se, tuple(recommendations))


if __name__ == "__main__":
    import json
    from dataclasses import asdict
    print(json.dumps(asdict(diagnose()), indent=2))
