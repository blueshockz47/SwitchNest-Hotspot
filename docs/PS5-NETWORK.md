# PS5 connectivity diagnostics (offline SwitchNest)

The SwitchNest hotspot is deliberately **offline**. A console's internet connectivity test may fail even when local LAN traffic works. Do not treat `NW-102205-0` alone as evidence of a failed Wi-Fi association.

## Read-only check

From the repository checkout on the SteamOS host:

```bash
sudo bash scripts/diagnose-ps5-network.sh
```

Run it **while the PS5 attempts to connect**, then run it once more immediately after the error. The script only reads system state; it does not restart NetworkManager, change DNS, alter firewall rules, or install packages.

## Interpretation

1. **New station absent:** Check PS5 Wi-Fi password and association logs. The hotspot's existing `bg` (2.4 GHz), channel 1, `wpa-psk` configuration is not itself proof of incompatibility.
2. **New station present:** Check whether it remains associated. An `ip neigh` entry marked REACHABLE is historical neighbor state, not proof of an active Wi-Fi connection.
3. **Associated with a DHCP address:** Verify address uniqueness and that the DHCP/DNS service is active. The hotspot is `10.42.60.1/24`; DHCP clients typically use `10.42.60.20–100`. Do not assign a manual address within that pool.
4. **Local communication succeeds but PS5 reports internet failure:** The internet test can be expected to fail on an isolated network. Test the actual local application, such as ProsperoSunshine, separately.
5. **Ping fails:** This alone does not prove disconnection; the client might block ICMP. Correlate station association, DHCP, and service logs.

The default DNS wildcard is Nintendo-oriented, not a validated PS5 connectivity-check implementation. Do not add PS5 DNS spoofing or nanoDNS until traffic captures establish which requests are needed. nanoDNS running on a PS5 is not a replacement for the SteamOS hotspot's DHCP server.

For live association changes:

```bash
watch -n 1 'sudo iw dev wlan0 station dump | grep -E "Station|authorized:|associated:|connected time:"'
```

The diagnostics do not alter a working Nintendo Switch 2 setup.
