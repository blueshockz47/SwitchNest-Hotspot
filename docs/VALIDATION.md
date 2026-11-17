# Validation and private-review status

Prepared 2026-11-17 from the latest saved v7.1 password installer and the working
Plasma 6.7 panel add-on. Both installers are byte-for-byte unchanged. Their source
checksums are in `SOURCE_SHA256SUMS.txt`.

## Local checks

`python3 -m unittest discover -s tests -v`: **15 tests passed** on Linux.

- Bash syntax of both installers and their generated shell helpers.
- Embedded Python compilation and widget metadata JSON/package ID.
- Live loopback HTTP responses for all seven Nintendo hosts, case-insensitive
  host matching and optional `:80`, HEAD/POST and unknown-host rejection.
- The responder's built-in direct-IP self-check.
- Hidden password confirmation, mismatch/short input, cancel and OPEN choices.
- WPA2/RSN nmcli arguments and removal of the security setting for OPEN mode.
- Mocked failure of restart after a security change, followed by restoration of
  the previous OPEN mode and a second startup attempt.

These tests do not invoke real NetworkManager, systemd, nftables, firewalld or
Podman. HTTP binds only loopback with a temporary port. They do not run the
Plasma widget on KDE.

A focused source review found no embedded Wi-Fi password, personal email, API
key, SSH private key or live NetworkManager profile in the upload set. Synthetic
test passwords are deliberately non-secret fixtures. This is a focused review,
not a third-party security audit.

## Hardware history

The user confirmed the Steam Deck v7 OPEN hotspot, Pico-compatible connectivity
checks and the separate taskbar toggle on Plasma 6.7.3. Sunshine/Moonlight was
confirmed after adding the streaming firewall rules separately; controller
mouse input was configured through Steam Input. These are user-reported results
for that setup, not a compatibility matrix for all devices.

The v7.1 password feature still needs Steam Deck/Switch 2 hardware verification.
The Windows preview is a separate experimental project and is not in this
SteamOS repository.

## Before a public release

- Confirm WPA2 association with the Switch 2 and a successful local check.
- Change WPA2 passwords while OFF and while ON; verify reconnect behavior.
- Verify the rollback/recovery path and original OPEN mode on hardware.
- Confirm the taskbar toggle works after upgrading to the v7.1 manager.
- Verify OFF restores the previous Wi-Fi when available and disables boot startup.
- Check packet-level IPv4/IPv6 forwarding isolation from a client, independently
  of the local Nintendo connectivity-check result.
- Verify a reboot with boot startup enabled, then with it disabled.
- Recheck documentation and third-party notices, and obtain the owner's decision
  before changing repository visibility or publishing a public release.
