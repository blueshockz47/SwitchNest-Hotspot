# Sunshine and Moonlight over the offline hotspot

Sunshine must already be installed and configured on the Steam Deck. Moonlight must already work on your Switch 2 environment. Neither application nor console firmware is bundled here.

## Allow local streaming

The installer permits DNS, DHCP and HTTP when firewalld is active. It does **not** add Sunshine streaming ports on a fresh installation. Existing permanent Sunshine rules are preserved by a password-only Option 5 upgrade.

With firewalld running and the `steamdeck-switch2` zone already created, apply default Sunshine streaming rules:

```bash
for port in 47984 47989 48010; do
  sudo firewall-cmd --zone=steamdeck-switch2 --add-port="${port}/tcp"
  sudo firewall-cmd --permanent --zone=steamdeck-switch2 --add-port="${port}/tcp"
done
for port in 47998-48000 48002; do
  sudo firewall-cmd --zone=steamdeck-switch2 --add-port="${port}/udp"
  sudo firewall-cmd --permanent --zone=steamdeck-switch2 --add-port="${port}/udp"
done
sudo firewall-cmd --zone=steamdeck-switch2 --list-ports
```

These commands apply runtime rules and save permanent rules, without a reload. Port 48002 is Sunshine's documented unused microphone port; it is included for parity with the previously working setup. For a custom Sunshine base port, adapt the ports to its configuration.

TCP 47990 is Sunshine's web management UI, not RTSP. The streaming rules above leave that management port out. Pair from the Steam Deck browser at `https://localhost:47990` rather than exposing it to the hotspot. Existing rules from a previous setup may already allow it; review those separately if needed.

The rules permit connections to services on the Steam Deck; they do not remove the hotspot's forwarding block. Do not disable the firewall or enable internet sharing to make streaming work.

## Pair

1. Start Sunshine and turn the hotspot ON.
2. Connect the Switch to `SteamDeck-Switch2`.
3. In Moonlight, add PC `10.42.60.1` manually.
4. Enter Moonlight's pairing PIN in Sunshine's local management UI on the Steam Deck.
5. Start a stream.

If the controller appears to Steam as a virtual Xbox controller, Steam Input's Desktop Layout can map its right stick to Joystick Mouse and triggers to mouse clicks. Controller behavior and button names depend on the Moonlight build and Steam mode. The hold-Plus mouse shortcut was not working in the user's KaiHEN Moonlight build; host-side Steam Input was used successfully.

For reachability issues, see [troubleshooting](TROUBLESHOOTING.md).

Reference: [Sunshine's configuration documentation](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html).
