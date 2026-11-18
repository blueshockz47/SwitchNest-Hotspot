"""Unprivileged profile state model; no network side effects."""
from dataclasses import dataclass
from enum import Enum

class Mode(str, Enum):
    OFFLINE = "offline"
    FILTERED = "filtered"

@dataclass(frozen=True)
class Evidence:
    hotspot_active: bool = False
    offline_guard_verified: bool = False
    dns_healthy: bool = False
    filtered_policy_verified: bool = False
    transport_policy_verified: bool = False
    recovery_ready: bool = False

def evaluate(requested: Mode, evidence: Evidence, *, experimental_enabled=False):
    """Return hypothetical effective state and required action."""
    if not evidence.hotspot_active:
        return {"effective": "inactive", "action": "keep_offline_default"}
    if requested == Mode.FILTERED and experimental_enabled:
        if all((evidence.dns_healthy, evidence.filtered_policy_verified,
                evidence.transport_policy_verified, evidence.recovery_ready)):
            return {"effective": "filtered", "action": "none"}
    if evidence.offline_guard_verified and evidence.dns_healthy:
        return {"effective": "offline", "action": "retain_offline"}
    return {"effective": "unverified", "action": "block_forwarding_or_stop_hotspot"}
