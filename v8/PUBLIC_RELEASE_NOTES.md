# SwitchNest Linux v8.0.0

**Linux / SteamOS KDE Desktop** — v8 Control Center for the SwitchNest v7.1 local hotspot backend.

### Highlights
- Refreshed desktop Control Center with hotspot status and adjacent ON/OFF toggle
- Local FTP file browser for Nintendo Switch 2 homebrew FTP endpoints
- Recursive folder upload/download and deletion, multi-selection, queue, conflict handling, bookmarks, history, transfer progress and retry
- Sunshine Flatpak start/stop controls
- Manual GitHub Releases update lookup
- Opt-in desktop-login autostart
- Managed user-local installer with rollback to the previous managed version

### Install
1. Install and verify the v7.1 SwitchNest hotspot backend from README first.
2. Download the Linux v8.0.0 source ZIP and extract it.
3. As your normal SteamOS desktop user, run `bash install-switchnest-v8.sh`.
4. Launch `~/.local/share/switchnest/launch`.

### Compatibility and cautions
SteamOS KDE Desktop is the intended platform; other Linux distributions are unverified. The UI alone does not install the backend. FTP traffic is unencrypted. The application does not certify network isolation, and cancelling destructive FTP operations may leave partial changes. Do not test deletion on irreplaceable files. Windows is not included.

### Validation status
Source prepared for public review. Final CI, SteamOS hardware checks and privacy audit must be completed before production-stable publication.
