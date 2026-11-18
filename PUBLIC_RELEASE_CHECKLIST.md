# Public release checklist — SwitchNest Linux v8.0.0

**Do not change repository visibility or publish a GitHub Release until these checks are complete.**

## Security / privacy
- [ ] Audit **entire Git history**, all branches, tags, GitHub Actions logs, and committed media for credentials, private IPs that should remain private, tokens, personal names, location metadata, and copyrighted assets. Making a repo public exposes historical commits and other branches, including experimental Windows work.
- [ ] Review every installer and privileged helper for command injection, file ownership and permissions, network side effects, and rollback safety.
- [ ] Confirm LICENSE, THIRD_PARTY_NOTICES.md and bundled licenses are accurate for all copied/adapted code and imagery.
- [ ] Run GitHub secret scanning and dependency/security review. If secrets were committed, rotate them before publication; deleting the current file is insufficient.

## Testing
- [ ] Run `python3 -m unittest -v v8.test_ftp_tree v8.test_install v8.test_updates v8.test_autostart`
- [ ] Run `QT_QPA_PLATFORM=offscreen python3 -m v8.smoke_qml` after installing PySide6
- [ ] Confirm GitHub Actions checks pass for the exact release commit.
- [ ] Test clean install, upgrade, rollback and desktop autostart on SteamOS.
- [ ] Test hotspot ON/OFF, DNS, IPv4/IPv6 isolation, Wi-Fi security, and Sunshine on target hardware.
- [ ] Test FTP transfers, recursive deletion, cancel, retries, and conflicts using disposable files.

## Publication
- [ ] Merge reviewed `release/v8.0.0` to `main` using a PR and green checks.
- [ ] Create immutable annotated tag `v8.0.0` from tested commit and publish release notes.
- [ ] Provide downloadable source archive and optional checksummed installer artifacts.
- [ ] Only then change repository visibility from Private to Public in GitHub Settings > General > Danger Zone.
- [ ] Verify anonymous visitor can see README, LICENSE, install instructions, and GitHub Release.
- [ ] Update release checker references to published tag and test unauthenticated lookup.

## Known limitations
v8 UI requires existing v7.1 backend. FTP is plaintext; checks are size-based, not hashes. No byte-level resume or unattended updater. Network isolation has not been independently certified. Windows branch is not part of Linux v8 release.
