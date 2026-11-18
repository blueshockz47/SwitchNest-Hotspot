# Experimental filtered internet mode (Switch 1 / Switch 2 / PS5 / PCs)

This is an **early hardware-testing prototype**, not a production 90DNS replacement. It is **not integrated into the v8 GUI** and does **not guarantee Nintendo or Sony server isolation**. The initial Nintendo domain list is intentionally incomplete. Do not use this as your sole protection against console online services.

## Preconditions
- Working SwitchNest v7.1 backend and v8 Control Center on SteamOS.
- A separate, connected Ethernet uplink (e.g. `enp5s0`); hotspot stays on Wi-Fi.
- IPv4 forwarding deliberately enabled for the test. IPv6 forwarding remains blocked.
- Existing firewall policy must permit forwarded traffic. Other nftables/firewalld rules may still block it.
- Existing Wi-Fi clients should reconnect after mode change.
- **Do not run the normal v7.1 manager install/ON/OFF actions while filtered mode is enabled**: the manager reinstalls its offline guard, and the prototype cannot coordinate that state.

## Test on a Switch 1
From the extracted feature-branch ZIP, in Konsole:

```bash
nmcli -t -f DEVICE,TYPE,STATE device status
sudo sysctl -w net.ipv4.ip_forward=1
sudo bash experimental/filtered-internet.sh enable enp5s0
sudo bash experimental/filtered-internet.sh status
```

Replace `enp5s0` with your **actual Ethernet** device. Connect the Switch 1 to `SteamDeck-Switch2` and use **automatic IP and DNS**. Test ordinary internet access and local FTP. Do **not** sign in to Nintendo or attempt online play as a way to verify filtering. A DNS lookup returning 0.0.0.0 for a blocked Nintendo domain is only a basic smoke test, not proof of isolation.

## Restore offline mode
```bash
sudo bash experimental/filtered-internet.sh disable
sudo sysctl -w net.ipv4.ip_forward=0
```

Only disable IPv4 forwarding if you enabled it specifically for this test and no other services require it. The helper backs up the offline dnsmasq config, replaces only the SwitchNest nftables guard, and adds a dedicated NAT table. It restores the offline DNS configuration and forwarding guard on disable.

**Known limitations:** No GUI toggle yet; no persistent mode across reboot; no automatic fail-closed rollback if services are restarted externally; incomplete Nintendo blocklist; no PSN blocklist; hardcoded IP, VPN, encrypted DNS-over-HTTPS and alternative paths may bypass filtering; upstream DNS requires internet access from the SteamOS host. The connectivity-check HTTP responder remains local. Test on a non-critical console/network first.
