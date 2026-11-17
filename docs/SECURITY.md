# Security and installed files

## Network behavior

The hotspot is local-only. dnsmasq uses `no-resolv`, `no-poll`, `no-hosts`, a wildcard address pointing to `10.42.60.1`, and a local wildcard zone. The HTTP responder returns fixed bodies for known Nintendo connectivity-check hosts and 404 for other hosts. It does not proxy requests upstream.

An nftables `inet` forward-hook chain drops packets entering or leaving the hotspot interface. The guard is installed before starting the AP. Failed disconnection retains the guard. This does not isolate peers from each other or from the host. Existing host services can still be reachable subject to the host firewall. Keep the hotspot OFF when not in use.

## Password handling

WPA2-Personal passwords must have 8–63 printable ASCII characters. Entry and confirmation are hidden; they are stored in NetworkManager's protected connection profile, not this project's settings file. The current implementation briefly passes the PSK in nmcli's process arguments while updating the connection. It should therefore not be described as immune to local process inspection. Do not run the installer with shell tracing enabled or paste secrets in issue reports.

OPEN mode has no Wi-Fi authentication. The installer makes that choice explicit. v7.1 attempts to restore previous security when a change or subsequent restart fails; hardware failure can still require manual recovery.

## Privileged widget helper

The panel add-on installs a fixed root-owned helper and a polkit rule allowing the installing, active local desktop user to invoke it. The helper accepts only `toggle`, `on` and `off`. It checks that the installed manager/configuration and directory are root-owned, not symlinks, and not writable by group/others before sourcing them. The user's click authorizes the helper's normal ON/OFF confirmations.

This delegation is installed only by running the add-on installer with sudo. Removing the add-on removes its helper and polkit rule. It does not uninstall the hotspot.

## Owned paths

| Path | Purpose |
|---|---|
| `/etc/steamdeck-switch2/` | Manager, settings, dnsmasq config, HTTP responder, notices and backups |
| `/var/lib/steamdeck-switch2/` | Previous Wi-Fi state |
| `/var/lib/steamdeck-switch2-dhcp/` | DHCP leases |
| `/home/<desktop-user>/steamdeck-switch2-podman/` | Dedicated container image storage, if used |
| `/etc/systemd/system/steamdeck-switch2-*.service` | Hotspot, DNS and HTTP units |
| nftables table `inet steamdeck_switch2_offline` | Hotspot forwarding guard |
| firewalld zone `steamdeck-switch2` | Local hotspot service permissions |
| `/etc/steamdeck-switch2-panel-toggle` | Fixed privileged panel helper |
| `/etc/polkit-1/rules.d/49-steamdeck-switch2-panel-toggle.rules` | Panel authorization rule |
| `~/.local/share/steamdeck-switch2-panel-toggle/` | User launcher/status helper |
| `~/.local/share/plasma/plasmoids/local.steamdeck.switch2.offlinehotspot/` | Panel widget |

Firewalld setup reloads permanent configuration and can discard unrelated runtime-only rules. Review those before using Option 1. The installer does not flush global nftables rules or disable SteamOS read-only protection.

## Review snapshot

Only project source, tests, documentation and license notices belong in the repository. Live configuration, PSKs, logs, DHCP leases, user identifiers and backups from a running system are excluded. No public release is authorized by this private-review upload.
