# SwitchNest Hotspot

**A local Nintendo Switch 2 hotspot and file-management hub for SteamOS.**

*Connect locally. Play freely.*

SwitchNest turns your SteamOS PC or Steam Deck into a Wi-Fi hotspot for a Nintendo Switch 2. Use the desktop Control Center to manage the hotspot, transfer files over FTP, browse Switch 2 homebrew releases, and control Sunshine streaming.

**Current stable version: v8.1.5** · **[Download SwitchNest v8.1.5 for Linux (ZIP)](https://github.com/blueshockz47/SwitchNest-Hotspot/releases/download/v8.1.5/SwitchNest-Hotspot-Linux-v8.1.5.zip)** · [Release notes](https://github.com/blueshockz47/SwitchNest-Hotspot/releases/tag/v8.1.5) · [Report an issue](https://github.com/blueshockz47/SwitchNest-Hotspot/issues)

> **Important:** The default hotspot is **local-only**, not a Nintendo online connection. The PC can remain online through Ethernet while hotspot clients are intended to remain offline. Verify firewall isolation on your system; an *Isolation: Unverified* indicator is not proof of isolation. SwitchNest does not jailbreak your console or install kaiHEN.

## What can SwitchNest do?

| Feature | Description |
| --- | --- |
| **Offline Wi-Fi hotspot** | Connect your Switch 2 to your SteamOS PC without sharing the PC's internet connection. |
| **FTP File Manager** | Browse local files and transfer files to or from a compatible FTP server running on your Switch 2. |
| **Switch 2 Homebrew Manager** | Browse a categorized, three-column homebrew catalog, inspect GitHub releases, download eligible files, and install supported verified NRO files over FTP with confirmation. |
| **Sunshine / Moonlight** | Start or stop an existing Sunshine service and open its web interface for local game streaming. |
| **Wi-Fi settings** | Manage the hotspot SSID, WPA2 password, channel, and saved presets using the existing backend. |
| **Status and recovery** | View hotspot/DNS status, connected Wi-Fi stations, diagnostics, and restart controls. |
| **Updates and rollback** | Update the Control Center and return to a previous managed installation when available. |

**Homebrew safety:** Catalog entries are not automatically approved for installation. A compatible release with a verifiable SHA-256 digest is required for supported downloads. Some apps need additional setup or manual installation. ZIP files are download-only in the stable Homebrew Manager.

## Screenshots — v8.1.5

### Overview
See hotspot status, DNS activity, connected Wi-Fi devices, and network details.

![SwitchNest v8.1.5 Overview](docs/images/Overview.png)

### Switch 2 Homebrew Manager
Search or filter the homebrew catalog. Right-click an app to view its GitHub repository or available download actions.

![SwitchNest v8.1.5 Homebrew Manager](docs/images/HomebrewManager.png)

### FTP File Manager
Browse your PC's files and connect to the Switch 2 FTP server for transfers.

![SwitchNest v8.1.5 FTP File Manager](docs/images/FTP%20Manager.png)

### Settings
Manage Wi-Fi configuration, startup preferences, restart controls, and presets.

![SwitchNest v8.1.5 Settings](docs/images/Settings.png)

### Streaming
Control a separately installed Sunshine server for Moonlight streaming.

![SwitchNest v8.1.5 Streaming](docs/images/Streaming.png)

## Requirements

- **SteamOS with KDE Desktop Mode** and an access-point-capable Wi-Fi adapter.
- **NetworkManager** and the Linux tools required by the hotspot backend.
- **Administrator access** for backend/helper installation; install the Control Center as your regular user.
- An **Ethernet connection** is recommended so your PC can remain online while Wi-Fi is used as the hotspot.
- Internet access for the first Control Center dependency installation and for GitHub homebrew downloads.
- Approximately **2 GiB of free space** recommended for installation; more may be needed for downloaded homebrew.

Other Linux distributions and Windows are **not confirmed supported** by this Linux release.

## Install SwitchNest on SteamOS

Install in this order: **hotspot backend → control helper → Control Center**. If you already have a working v7.1 backend and helper, skip to Step 3.

### 1. Download the project

Download the **[SwitchNest Hotspot Linux v8.1.5 ZIP](https://github.com/blueshockz47/SwitchNest-Hotspot/releases/download/v8.1.5/SwitchNest-Hotspot-Linux-v8.1.5.zip)** and extract it. Use this stable release package rather than the development branch ZIP.

Open **Konsole** inside the extracted project folder. Run the commands below from that folder.

### 2. Install the hotspot backend and helper

Install the v7.1 hotspot backend:

```bash
sudo bash ./install-switchnest-pico-connectivity-v7.1-password.sh
```

Choose **Install/update hotspot**, then configure **WPA2-Personal** and your Wi-Fi password. The default SSID on a fresh backend installation is `SteamDeck-Switch2`; existing installations may use a different name.

Install the Control Center's privileged ON/OFF helper:

```bash
sudo bash ./install-switchnest-plasma67-panel-toggle.sh
```

The KDE taskbar toggle is optional, but this helper is required for the GUI's privileged hotspot controls.

### 3. Install the Control Center

**Do not use `sudo` for this command.**

```bash
bash ./install-switchnest-v8.sh
```

When installation finishes, open **SwitchNest Control Center** from the KDE application menu, or run:

```bash
~/.local/share/switchnest/launch
```

### 4. Connect your Nintendo Switch 2

1. In SwitchNest, open **Overview** and start the hotspot if necessary.
2. On the Switch 2, join the Wi-Fi network you configured during installation.
3. Use **automatic IP/DNS** unless your setup specifically requires manual network settings.
4. Confirm that the device appears under **Connected Wi-Fi stations**.

The hotspot is designed for local connectivity. It does not provide Nintendo online services.

## How to use the Homebrew Manager

1. Start SwitchNest and open **Files → Homebrew Manager**.
2. Use **Search** or the category filter to find an app.
3. **Right-click** an app card. Choose **View GitHub Repository**, **Download Only**, or **Download & Install**, depending on the available release and app requirements.
4. For **Download Only**, select an eligible verified release file and follow the project's installation instructions.
5. For **Download & Install**, first start a compatible FTP server on your Switch 2, enter the IP address and port shown on the console, and select **Connect**.
6. Choose an eligible **verified single-file NRO** release, review the destination and confirmation prompt, then approve the FTP transfer. Supported NRO installs target `/switch/`.
7. If an app requires a ZIP, plugin, extra files, or special setup, use the project's manual instructions instead of assuming a one-click installation will work.

**Example FTP connection:** `10.42.60.99` on port `1337` (from the maintainer's setup). Your console's IP and FTP port may be different.

> **No automatic homebrew installation:** The stable v8.1.5 Homebrew Manager is a curated catalog and verified-download workflow. Automatic GitHub/Reddit release monitoring is planned for **v8.1.6** and is **not** included in v8.1.5.

## How to use FTP and streaming

**FTP:** Launch a compatible FTP server on the Switch 2 (for example, OunceShell), open **Files → FTP File Manager**, enter the server IP and port, and click **Connect**. Browse the local and remote panels to manage transfers.

**Streaming:** Install and configure [Sunshine](https://github.com/LizardByte/Sunshine) on your PC and a compatible Moonlight client on your Switch 2. Open SwitchNest's **Streaming** page to control Sunshine. [Detailed streaming guide](docs/SUNSHINE.md).

## Updating and troubleshooting

Use the **Updates** page for supported Control Center updates. To inspect or roll back a managed installation from an extracted repository folder:

```bash
python3 -m v8.install status
python3 -m v8.install rollback
```

Rollback requires a previous managed release. The Control Center installer does not reinstall or replace your working hotspot backend.

| Problem | What to check |
| --- | --- |
| Switch 2 cannot see the hotspot | Check Wi-Fi adapter AP support, hotspot status, and configured SSID. |
| FTP won't connect | Start the FTP server on the console and confirm its actual IP and port. |
| No homebrew install option | The app may be manual-only or lack an eligible SHA-256-verified NRO release. |
| Sunshine is unavailable | Install/configure Sunshine separately; it is not bundled with SwitchNest. |
| **Invalid preference** when saving maximized startup | Known v8.1.5 issue; a fix is included in the v8.1.6 development work. |
| **Isolation: Unverified** | Check firewall forwarding rules and verify isolation independently. |

For additional help, see [Troubleshooting](docs/TROUBLESHOOTING.md), [Security](docs/SECURITY.md), and [Validation](docs/VALIDATION.md).

## Development status

- **v8.1.5 — stable:** Hotspot Control Center, FTP, Homebrew Manager, streaming controls, and settings.
- **v8.1.6 — in development:** Maximized startup preference fix and six-hour GitHub/Reddit homebrew discovery, with notifications and user-confirmed installation. See [PR #24](https://github.com/blueshockz47/SwitchNest-Hotspot/pull/24).

## Credits

SwitchNest's Pico-compatible local DNS/HTTP connectivity responses are based on work from [favas0's CivSwitch-Pico2W-SerialBridge](https://github.com/favas0/CivSwitch-Pico2W-SerialBridge), [Jack Spence's CivSwitch-SerialBridge](https://github.com/jackspence7/CivSwitch-SerialBridge), and related [Switch 2 bridge references](https://github.com/fernando-granco/switch2-homebrew). The project also acknowledges [90DNS](https://gitlab.com/a/90dns) and [Gezine's CivSwitch](https://github.com/Gezine/CivSwitch).

Thanks to the upstream authors and maintainers of NetworkManager, dnsmasq, Podman, KDE Plasma, Python/PySide6, Sunshine, Moonlight, and the homebrew projects linked from the catalog. See [Third-party notices](THIRD_PARTY_NOTICES.md) for further provenance and license information.
