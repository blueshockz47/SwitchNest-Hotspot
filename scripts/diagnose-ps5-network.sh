#!/usr/bin/env bash
# Read-only SwitchNest hotspot client diagnostics. Does not change networking.
set -u
AP_IF="${1:-wlan0}"
AP_IP="10.42.60.1"
echo "SwitchNest PS5 / client diagnostics (read-only)"
echo "Interface: $AP_IF  | Expected hotspot: $AP_IP"
echo
echo "== Interface and active connection =="
nmcli -f GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show "$AP_IF" 2>&1 || true
echo
echo "== AP mode, band, channel and security =="
CON="$(nmcli -g GENERAL.CONNECTION device show "$AP_IF" 2>/dev/null || true)"
if [[ -n "$CON" && "$CON" != "--" ]]; then
  nmcli -f 802-11-wireless.mode,802-11-wireless.band,802-11-wireless.channel,802-11-wireless-security.key-mgmt connection show "$CON" 2>&1 || true
fi
echo
echo "== Associated Wi-Fi clients (run while PS5 connects) =="
if command -v iw >/dev/null 2>&1; then
  iw dev "$AP_IF" station dump 2>&1 | grep -E 'Station |authorized:|authenticated:|associated:|signal:|connected time:' || true
else
  echo "iw not installed"
fi
echo
echo "== IPv4 neighbors (STALE does not prove current connectivity) =="
ip -4 neigh show dev "$AP_IF" 2>&1 || true
echo
echo "== Local DHCP/DNS and connectivity responder service states =="
for unit in steamdeck-switch2-hotspot.service steamdeck-switch2-dnsmasq.service steamdeck-switch2-http.service; do
  printf '%s: ' "$unit"
  systemctl is-active "$unit" 2>/dev/null || true
done
echo
echo "== UDP DNS/DHCP and TCP HTTP listeners =="
ss -lunt 2>&1 | grep -E '(:53|:67|:80)[[:space:]]' || true
echo
echo "== Recent NetworkManager messages (no password output) =="
journalctl -u NetworkManager --since '3 minutes ago' --no-pager -n 35 2>&1 || true
echo
echo "Note: PS5 NW-102205-0 can also reflect an expected failure of an internet check"
echo "on an intentionally offline hotspot. Do not disable the forwarding firewall."
