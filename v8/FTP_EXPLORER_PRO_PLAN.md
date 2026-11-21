# SwitchNest v8.1.8 — FTP Explorer Pro

Development base: tested v8.1.7 branch (PR #28). This branch deliberately does not change the hotspot backend.

## Phased delivery and acceptance criteria

1. **Smart Transfer Queue** — queue multiple operations; show individual status, speed, progress and ETA; reorder waiting items; retry failures; never silently overwrite.
2. **Folder Synchronization** — compare local and remote directories and show a dry-run preview; copy only missing/changed entries; no implicit deletions; detect ambiguous/conflicting entries.
3. **Transfer Verification** — verify final sizes where available; offer checksums only if the FTP server supports a reliable mechanism; report unverifiable files rather than claiming success.
4. **Modern Explorer** — adjustable pane sizes, breadcrumb navigation, compact actions, selection improvements, collapsible activity log; preserve existing drag-to-folder geometry.
5. **Homebrew shortcut** — explicit opt-in to copy selected .nro into /switch; confirm destination, filename, overwrite policy; reject unsupported file types and unsafe paths.

## Guardrails
- Preserve v8.1.7 drag-to-folder behavior, confirmation dialog and transfer conflict policies.
- No changes to hotspot, DHCP, DNS, firewall, IP configuration or unrelated homebrew discovery.
- Use a draft PR and staged commits; test each phase with automated regressions and a disposable file on SteamOS.
- Do not merge without explicit user approval.
