# Alpha.4 test checklist

Run from the repository root using the existing virtual environment. The v7.1 backend is unchanged.

- Verify hotspot ON/OFF and refresh.
- Streaming: start Sunshine Flatpak, confirm running status, open web interface, then stop (disconnects streams).
- Files: start an authorized local FTP server on a client in 10.42.60.0/24, enter its actual address and port, open Dolphin. Test with nonessential files. FTP is unencrypted and requires KDE FTP support.
- Settings: open existing manager in Konsole and use option 5 for Wi-Fi password. SSID editing is not implemented.
- Diagnostics: inspect service states and forwarding inventory. Global forwarding flags and visible tables do not prove isolation.

No new privileged helper, no changes to v7.1. Runtime validation pending.
