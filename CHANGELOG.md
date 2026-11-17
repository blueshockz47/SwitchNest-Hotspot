# Changelog

## v7.1 — private review snapshot, 2026-11-17

- Optional WPA2-Personal or OPEN Wi-Fi security at installation.
- Menu Option 5 changes security without reinstalling DNS/HTTP or changing the AP UUID.
- Hidden password confirmation, manager backup, restart of an active hotspot and rollback attempts on failure.
- Retains the working v7 DNS/HTTP responses and compatibility with the separate Plasma panel toggle.
- Adds repository documentation and local tests. Installer source files are unchanged from the supplied project artifacts.
- Password activation awaits Steam Deck hardware validation; no public release has been made.

## v7 — confirmed working baseline

- Combined installation of the offline hotspot and Pico-compatible local DNS/HTTP responses.
- ON/OFF management and previous Wi-Fi restoration.
- Dedicated Podman storage under `/home` when host dnsmasq is unavailable.
- User confirmed the open hotspot and separate Plasma 6.7.3 widget working.
- User confirmed Sunshine/Moonlight after separately adding the hotspot-zone streaming ports.
