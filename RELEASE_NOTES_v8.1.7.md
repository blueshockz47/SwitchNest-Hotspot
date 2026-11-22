# SwitchNest Hotspot Linux 8.1.7-Stable-Final

## Highlights
- Redesigned Linux Control Center with Overview, Network, Streaming, Homebrew Manager, FTP Manager, Diagnostics, Settings, and Updates.
- Refined sidebar branding with the bundled SwitchNest Infinity artwork, consistent KDE window icon, and streamlined page headings.
- Improved FTP file manager, including two-panel browsing, checkbox selection, drag-and-drop handling, removable-drive navigation, and clearer connection warnings.
- Homebrew Manager enhancements and clearer FTP connectivity feedback.
- Overview hotspot controls, connected-device status, setup instructions, and guidance for router Wi-Fi plus 90DNS workflows.
- Wi-Fi settings and update-preference UI refinements.

## Compatibility and safety
- SteamOS/Linux build only. The separate SwitchNest Windows repository is not part of this release.
- The SwitchNest hotspot is intended to operate offline; FTP and Homebrew Manager may also work over the same router LAN when the Switch 2 FTP server is running.
- 90DNS is not a guarantee of blocking Nintendo services.
- The existing DHCP, DNS, firewall, hotspot, and FTP backend must pass regression tests before publishing.

## Release checklist
- [ ] Run all v8 unit/regression tests on the release branch.
- [ ] Verify SteamOS GUI launch and KDE icon, FTP browse/upload, and removable drives.
- [ ] Verify hotspot start/stop/restart, DNS/HTTP status, and firewall isolation.
- [ ] Verify update ZIP workflow and release asset naming.
- [ ] Merge the release PR after checks pass.
- [ ] Create GitHub tag and release `8.1.7-Stable-Final` with `SwitchNest-Hotspot-Linux-v8.1.7.zip`.
- [ ] Verify the published ZIP is downloadable and the README link resolves.
