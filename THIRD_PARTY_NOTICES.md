# Attribution and license scope

The **Pico-compatible DNS/HTTP behavior is based on [favas0/CivSwitch-Pico2W-SerialBridge](https://github.com/favas0/CivSwitch-Pico2W-SerialBridge)**. Credit goes to favas0 for the Pico 2 W port and its wildcard DNS/local Nintendo HTTP connectivity-check behavior, which this project adapts for Steam Deck using dnsmasq and Python.

The connectivity-check implementation retains the behavior and provenance from
the working v7/v7.1 Steam Deck installer, originating in the Pico 2 W bridge.
The full upstream notice embedded by the installer is reproduced unchanged in
[docs/UPSTREAM-NOTICES.md](docs/UPSTREAM-NOTICES.md). That historical notice also
describes firmware, USB/FTP tooling and dependencies not included here.

Upstream bridge: Jack Spence's CivSwitch-SerialBridge, commit
`b85ada8b8ec3ccd9bdae4bc903cbe5463f01631a`. Copyright (c) 2026 Jack Spence.
Pico port/additions: Copyright (c) 2026 favas0. Their MIT notice is retained in
`licenses/pico-MIT.txt`.

## Connectivity-response provenance reviewed 2026-11-17

- **favas0**: [Pico bridge source](https://github.com/favas0/CivSwitch-Pico2W-SerialBridge/blob/main/pico2w-bridge/pico2w-bridge.ino) and [third-party notices](https://github.com/favas0/CivSwitch-Pico2W-SerialBridge/blob/main/THIRD_PARTY_NOTICES.md) identify Jack Spence’s original bridge and credit connectivity responses through 90DNS and fernando-granco/switch2-homebrew.
- **Jack Spence (@jackspence7)**: [CivSwitch-SerialBridge](https://github.com/jackspence7/CivSwitch-SerialBridge), the original bridge underlying the Pico port. Its README preserves the same earlier response attribution.
- **fernando-granco**: [switch2-homebrew ESP bridge](https://github.com/fernando-granco/switch2-homebrew/tree/main/tools/esp-bridge), the intermediate response source named by the earlier bridges. Its current [source header](https://github.com/fernando-granco/switch2-homebrew/blob/main/tools/esp-bridge/src/main.cpp) credits 90DNS by Ave, Copyright (C) 2018 Ave, and declares GPL-2.0-or-later. The [ESP bridge license](https://github.com/fernando-granco/switch2-homebrew/blob/main/tools/esp-bridge/LICENSE) is GPL v2 with an or-later notice.
- **Ave / 90DNS**: [current project](https://gitlab.com/a/90dns); Fernando’s source cites revision `4d477d7181188690203aae5f4e56e287edd21734`. Credit: **Copyright (C) 2018 Ave**. The response provenance is GPL-2.0-or-later, as recorded in that source and license.

The older Pico/Jack notices link to `Thesola10/90dns` on GitHub and describe the Fernando project as MIT. That GitHub 90DNS link returned 404 during this review; the GitLab project is reachable. The Fernando repository is now reachable and its ESP bridge is GPL-2.0-or-later, with licenses varying across its other components. We preserve the old wording in `docs/UPSTREAM-NOTICES.md` as historical provenance, not as a statement of the current ESP bridge license. GPL-covered material is not relicensed as MIT.

## Associated upstream projects

- **Gezine / [CivSwitch](https://github.com/Gezine/CivSwitch)**: the console loader/project used by the bridge ecosystem. Its MIT license credits Copyright (c) 2026 Gezine. This hotspot installer includes no CivSwitch loader code.
- **Earle Philhower / [Arduino-Pico](https://github.com/earlephilhower/arduino-pico)**: framework used to build the upstream Pico firmware, including its Wi-Fi, DNS and HTTP libraries. It is not used to build or run this Steam Deck installer.
- **[pySerial contributors](https://github.com/pyserial/pyserial)**: serial library used by the upstream PC sender, not a dependency bundled with this hotspot installer.

These acknowledgements identify the upstream ecosystem separately from material adapted into this repository.

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
