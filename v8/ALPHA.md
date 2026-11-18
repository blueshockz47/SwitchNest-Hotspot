# 8.0-alpha.1 developer preview

This preview is not an installer and does not enable filtered internet. Keep v7.1 installed. The original installers remain unchanged.

From the repository root run:

    python3 -m unittest discover -s v8/tests -v
    python3 -m v8.diagnostics

The second command is read-only. It reports active connections, routes, DNS service status and visible firewall tables. Permission errors are reported as unavailable evidence. The reported network mode remains unverified; the inventory is not an isolation check.

Do not share diagnostic output publicly without reviewing its local network details.

Remaining work: general-purpose network policy backend, verified mode transitions, recovery, desktop controls and hardware testing. No console-specific domain blocklist is included.
