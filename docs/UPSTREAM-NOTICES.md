# Attribution and third-party notices

## Original serial bridge

This project is a Raspberry Pi Pico 2 W port of
[Jack Spence's CivSwitch-SerialBridge](https://github.com/jackspence7/CivSwitch-SerialBridge)
(`jackspence7`), based on commit
`b85ada8b8ec3ccd9bdae4bc903cbe5463f01631a`.

Original copyright: **Copyright (c) 2026 Jack Spence**.
The original project is distributed under the MIT License. Its copyright,
permission notice and disclaimer are retained in [LICENSE](LICENSE).
The original Git history and ESP32 sketch are retained for provenance.
Pico 2 W port and additions: **Copyright (c) 2026 favas0**, under MIT.

The Pico port adapts AP setup, USB CDC serial, the wireless-chip LED, client
listing and TCP half-close handling. It also adds Pico build/setup guidance,
a hello payload, and host sender regression tests and timeout fixes.

## Connectivity-check responses

The original bridge attributes its Nintendo connectivity-check responses to
[90DNS by Thesola10](https://github.com/Thesola10/90dns), identified upstream
as **GPL-2.0-or-later**, via
[fernando-granco/switch2-homebrew](https://github.com/fernando-granco/switch2-homebrew),
identified upstream as **MIT**. These original attribution comments are
preserved in both sketches. These links returned 404 when checked on
2026-11-12; this notice records the provenance stated by the original bridge,
not an independent verification of those unavailable repositories.

The top-level MIT notice does not relicense third-party material. Any
GPL-covered material remains subject to GPL-2.0-or-later. A copy of GPL v2
is provided in [licenses/GPL-2.0.txt](licenses/GPL-2.0.txt).

## CivSwitch

[CivSwitch by Gezine](https://github.com/Gezine/CivSwitch) provides the
Remote JS Loader used on the console. The small hello test uses its documented
`await log(...)` interface, as shown in its
[hello-world example](https://github.com/Gezine/CivSwitch/blob/main/payloads/helloworld.js).
The loader itself is not bundled here.

## Build dependencies

The firmware is built with
[Earle Philhower's Arduino-Pico](https://github.com/earlephilhower/arduino-pico)
**6.3.2**, including its WiFi, DNS, WebServer, Pico SDK, lwIP and CYW43 components.
Those dependencies retain their respective upstream licences and notices;
the project's MIT licence does not replace them. The TCP adapter uses the
core's internal `ClientContext` API. Dependency source and licence notices
are available in the pinned Arduino-Pico source distribution and its submodules.

The host sender uses [pyserial](https://github.com/pyserial/pyserial), installed
separately with `pip`; its code is not vendored here.

## Local experimental FTP-over-USB extension

This package extends favas0/CivSwitch-Pico2W-SerialBridge revision
`0d1e167cfed96b5a4884c413e06e0718f769ae7d` with `SerialTcpBridge.h`,
`ftp_usb.py`, FTP/serial regression tests, launch/build scripts, and documentation.
The new extension code is distributed under the repository's MIT terms.
Original notices and connectivity-check provenance are retained. This is not an
upstream release and has not been tested on physical Pico/Switch hardware here.

The unmodified pyserial **3.5** Python wheel is included under `vendor/` for
offline installation. Its BSD licence and additional notices are included separately in
`vendor/LICENSE-pyserial.txt`, copied from the upstream v3.5 source. The wheel was downloaded
from PyPI and verified against the release metadata's SHA-256 digest.
