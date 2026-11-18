# SwitchNest Linux v8.0.0 — release build

Platform: SteamOS KDE Desktop (Linux), user-local PySide6 GUI. Requires previously installed v7.1 SteamDeck-Switch2 backend and toggle helper. Does **not** replace or modify existing hotspot, DNS, firewall, or systemd configuration.

## Features
- Hotspot status with adjacent ON/OFF button, diagnostics, Wi-Fi password manager shortcut
- Sunshine Flatpak start/stop and local UI link
- Local/remote FTP file browser, recursive transfers, file conflict policy, size verification, queue/retry, folder properties, bookmarks, history, recursive deletion
- Updates page checks **published GitHub releases only** (private repo needs authenticated gh CLI); manual ZIP install
- Opt-in XDG Desktop autostart; managed per-user installer and previous-version rollback

## Install
Download the `release/v8.0.0` branch ZIP from the private repository. Extract it and, as a **normal user**, run `bash install-switchnest-v8.sh` from its root. Internet required for first-time PySide6 installation, at least 2 GiB free space. Launch `~/.local/share/switchnest/launch`. Previous managed version is preserved for rollback.

## Rollback
From the extracted checkout: `python3 -m v8.install rollback`. Only available if an older managed release was installed. Use `python3 -m v8.install status` to inspect pointers.

## Verification before calling the release production-tested
1. Linux CI compilation, 15 regression tests, offscreen QML smoke all pass (see workflow run; **not yet verified here**).
2. Clean install, update over RC.3, desktop shortcut, and rollback on target SteamOS.
3. UI renders on small display; hotspot button stays aligned; ON/OFF only with v7.1 helper.
4. Connect Switch 2 FTP and test upload/download, folders, conflicts, cancellation, deletion on **disposable** data.
5. Validate autostart after KDE login, disable and reboot; verify no duplicate instance.
6. Validate private GitHub update lookup, offline errors and browser fallback.
7. Independently test offline network isolation, DNS and firewall; GUI diagnostic 'Unverified' is not a certification.

## Limitations
- FTP is plaintext; transfers are size-verified, not cryptographic checksum verified.
- Failed transfer retry restarts; byte-level resume is not implemented.
- Cancelled uploads/deletions may leave partial changes.
- Remote storage capacity may be unavailable.
- No automatic in-app download/install or automatic startup update checks.
- Qt and system network behavior must be tested on real SteamOS hardware before public stable promotion.
