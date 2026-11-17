# Attribution and license scope

The connectivity-check implementation retains the behavior and provenance from
the working v7/v7.1 Steam Deck installer, originating in the Pico 2 W bridge.
The full upstream notice embedded by the installer is reproduced unchanged in
[docs/UPSTREAM-NOTICES.md](docs/UPSTREAM-NOTICES.md). That historical notice also
describes firmware, USB/FTP tooling and dependencies not included here.

Upstream bridge: Jack Spence's CivSwitch-SerialBridge, commit
`b85ada8b8ec3ccd9bdae4bc903cbe5463f01631a`. Copyright (c) 2026 Jack Spence.
Pico port/additions: Copyright (c) 2026 favas0. Their MIT notice is retained in
`licenses/pico-MIT.txt`.

The original response attribution identifies 90DNS by Thesola10 as
GPL-2.0-or-later, via fernando-granco/switch2-homebrew. The installer preserves
that provenance; upstream links historically returned 404, so their current
contents have not been independently established here. GPL-covered material is
not relicensed as MIT.

The combined connectivity implementation and new repository additions are
provided under GPL-2.0-or-later. A complete GPL v2 text is in `LICENSE` and
`licenses/GPL-2.0.txt`; recipients may select a later GPL version where applicable.
The separate panel add-on declares MIT in its generated widget metadata;
`licenses/panel-toggle-MIT.txt` records that component's notice.

NetworkManager, dnsmasq, Podman, Debian, systemd, nftables, KDE Plasma, Python,
Sunshine and Moonlight are separate dependencies under their respective terms.
They are not bundled in this source repository. Podman setup may download a
Debian image and Debian packages after the installer's explicit prompt.

No console firmware, console loader, credentials, live system configuration or
user logs are included.
