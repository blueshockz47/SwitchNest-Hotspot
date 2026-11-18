# SwitchNest v8.0 — development milestone 1

The stable v7.1 installers remain unchanged. This milestone is an unprivileged prototype, not a deployable internet mode.

Offline is the default. Filtered Internet is experimental and not yet implemented. DNS filtering cannot guarantee protection against direct IP connections, alternative resolvers, updates or account enforcement.

## Implementation roadmap

- Integrate mode transitions with the existing manager lifecycle lock and retain the offline guard throughout transitions until verified. Restore offline on failure, reboot or incomplete transition.
- Implement locally administered DNS policy and isolated namespace tests with synthetic domains. Review upstream 90DNS licensing before importing source or data.
- Verify IPv4/IPv6 forwarding policy, resolver health, rollback and service failure handling, for both host dnsmasq and Podman.
- Introduce KDE QML controls using a narrow privileged helper. Display verified effective state, not the requested state.
- Preserve SSID, connection UUID, configuration paths, service identifiers and widget ID. Test streaming, FTP, suspend and Wi-Fi restoration before release.

Run model tests with `python3 -m unittest discover -s v8/tests -v`. The model has no network side effects and its inputs are hypothetical evidence, not live diagnostics.
