# SteamDeck-Switch2-Offline-Hotspot

Local Wi-Fi between a Steam Deck running SteamOS and a Nintendo Switch 2, with Pico-compatible Nintendo connectivity-check responses, optional WPA2-Personal security and a separate KDE Plasma taskbar toggle.

**Review snapshot: v7.1.** The user confirmed the v7 open hotspot, Plasma 6.7.3 widget, Sunshine/Moonlight streaming and Steam Input mouse controls on their Steam Deck/Switch 2 setup. The newer v7.1 password feature has local syntax and mocked tests; WPA2 activation still needs hardware confirmation. This repository is being prepared for private review before any public release.

## Features

- SSID `SteamDeck-Switch2`; Steam Deck address `10.42.60.1/24`.
- Local DHCP and wildcard DNS, using host dnsmasq when available or a dedicated Podman dnsmasq container.
- Local HTTP responses for the same seven Nintendo connectivity-check hosts used by the Pico bridge.
- An nftables IPv4/IPv6 forwarding block on the hotspot interface.
- Optional WPA2-Personal password or OPEN mode, with password changes available without reinstalling.
- ON/OFF menu, optional boot startup, and best-effort restoration of the previous home Wi-Fi connection.
- Separate Plasma 6.7 panel widget for one-click ON/OFF.
- Optional Sunshine/Moonlight access configured separately; see [streaming setup](docs/SUNSHINE.md).

The connectivity checks receive local responses. This network does not provide internet access or Nintendo online services. The forwarding block does not isolate clients from other clients or from services running on the Steam Deck.

## Requirements

A SteamOS Desktop Mode session, administrator access through `sudo`, NetworkManager with an AP-capable Wi-Fi adapter, and `nmcli`, `nft`, `systemctl`, `flock`, `ss`, `python3`, plus either `dnsmasq` or `podman`. If firewalld is running, the installer uses the dedicated `steamdeck-switch2` zone.

The Podman fallback needs at least 2 GiB free under `/home` and an internet connection for the initial Debian/dnsmasq image build. Later starts use the local image. The installer does not install host packages or change SteamOS read-only settings. A single Wi-Fi adapter normally disconnects from home Wi-Fi when starting the hotspot.

## Install on a new Steam Deck

Download or clone this repository, open Konsole in its folder, and run:

```bash
sudo bash ./install-steamdeck-switch2-pico-connectivity-v7.1-password.sh
```

Choose **1**, select WPA2-Personal or OPEN, and follow the prompts. Choose **2** to start the hotspot if you did not start it during installation.

| Option | Action |
|---|---|
| 1 | Install/update hotspot, DNS and HTTP responder |
| 2 | Hotspot ON |
| 3 | Hotspot OFF, disable its boot startup, optionally restore previous Wi-Fi |
| 4 | Status and diagnostic commands |
| 5 | Set/change Wi-Fi security: WPA2-Personal or OPEN |
| 6 | Exit the menu |

## Upgrade an already-working v7 to add a password

Run the v7.1 installer above and choose **5**. Choose WPA2-Personal and enter an 8–63 character printable ASCII password twice. Confirm the security change. Connected devices will disconnect; an active hotspot is restarted, with a rollback attempt if startup fails. Reconnect the Switch with the new password; forgetting its saved network may be necessary.

For a password-only upgrade, use **Option 5**. Option 1 updates the wider service/firewall configuration and can reload firewalld. Option 5 preserves the connection UUID, addresses, DNS/HTTP setup and taskbar integration, and backs up the installed manager before replacing it.

The saved manager can be opened later with:

```bash
sudo bash /etc/steamdeck-switch2/manager.sh
```

## Connect Switch 2

Select `SteamDeck-Switch2`, enter the password if configured, and use automatic IP/DNS. Manual settings for a single Switch are:

| Setting | Value |
|---|---|
| IP address | `10.42.60.2` |
| Subnet mask | `255.255.255.0` |
| Gateway | `10.42.60.1` |
| Primary and secondary DNS | `10.42.60.1` |
| Proxy | Off |

DHCP leases use `10.42.60.20`–`10.42.60.100`. Give additional manually configured clients unique addresses outside that range.

## Add the taskbar toggle

![Steam Deck taskbar showing the Switch 2 Offline Hotspot toggle in the ON state](docs/images/taskbar-hotspot-on.jpeg)

*The taskbar toggle in use: ON — click to turn OFF and restore home Wi-Fi.*

After the hotspot is installed, run as your normal desktop user through sudo:

```bash
sudo bash ./install-steamdeck-switch2-plasma67-panel-toggle.sh
```

Right-click the taskbar, choose **Enter Edit Mode → Add Widgets**, find **Switch 2 Offline Hotspot Toggle**, and drag it onto the panel. If it does not appear, sign out and back into Desktop Mode.

- OFF → click: starts the hotspot using the same ON operation as menu Option 2.
- ON → click: stops it and attempts to restore the previous Wi-Fi, matching Option 3 with its prompts accepted.

This is a separate widget. It does not replace the compiled KDE network applet. Its polkit rule authorizes the installing, active local desktop user to run only the fixed helper, whose accepted actions are ON/OFF/toggle. See [security notes](docs/SECURITY.md).

To remove the widget, remove it from the panel and run:

```bash
sudo bash ./install-steamdeck-switch2-plasma67-panel-toggle.sh --remove
```

The hotspot remains installed. To stop the hotspot and disable boot startup, choose Option 3 in the manager.

## Documentation and checks

- [Sunshine/Moonlight](docs/SUNSHINE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Security and installed files](docs/SECURITY.md)
- [Validation and release readiness](docs/VALIDATION.md)
- [Changelog](CHANGELOG.md)
- [Third-party provenance](THIRD_PARTY_NOTICES.md)

Run local tests without changing Wi-Fi, firewall rules or system services:

```bash
python3 -m unittest discover -s tests -v
```

The two installer scripts are copied unchanged from the latest project files. Hardware behavior varies across SteamOS versions, Wi-Fi drivers and client firmware. Public release remains pending the owner's review and hardware checks.

## License

Project additions and the combined connectivity implementation are provided under GPL-2.0-or-later; see [LICENSE](LICENSE). The panel widget's metadata declares MIT; its component notice is in [licenses/panel-toggle-MIT.txt](licenses/panel-toggle-MIT.txt). Existing Pico/bridge MIT notices and GPL response provenance are retained separately. This project is not affiliated with Valve, Nintendo, KDE, Sunshine or Moonlight.
