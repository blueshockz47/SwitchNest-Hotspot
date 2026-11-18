# Troubleshooting

Start with menu Option 4. Reproduce the failure once and collect only the relevant output. Review logs before sharing: connection names, client addresses, MAC addresses and HTTP Host headers can identify devices or networks.

## Services and local checks

```bash
sudo systemctl status steamdeck-switch2-hotspot.service steamdeck-switch2-dnsmasq.service steamdeck-switch2-http.service --no-pager
sudo journalctl -u steamdeck-switch2-hotspot.service -u steamdeck-switch2-dnsmasq.service -u steamdeck-switch2-http.service -n 60 --no-pager
ip -4 address show
sudo ss -lntup
sudo python3 /etc/steamdeck-switch2/connectivity.py --bind 10.42.60.1 --check
sudo nft list table inet steamdeck_switch2_offline
```

The local HTTP self-check connects directly to the Deck's IP, so it does not depend on public DNS. A passing local check does not prove client reachability or forwarding isolation; also test from the Switch.

## Missing dnsmasq

The installer uses Podman when host dnsmasq is missing. Keep home Wi-Fi online during its first image build. Dedicated storage is under the desktop user's `/home/.../steamdeck-switch2-podman`; it does not change global Podman storage. Do not try to launch arbitrary old `civswitch-dhcp` containers as a substitute for this installer's services.

## Port 80 or DNS port conflict

Inspect listeners before changing anything:

```bash
sudo ss -lntup 'sport = :53'
sudo ss -ltnp 'sport = :80'
```

Stop only a conflicting server you recognize, such as a manually started Python HTTP server. The installer does not terminate unrelated DNS services for you.

## Widget not visible or toggle fails

The supported add-on is `install-switchnest-plasma67-panel-toggle.sh`. The earlier script that tried to find `Toolbar.qml` is not included. Plasma 6.7 packages the built-in network applet differently, and this add-on creates its own widget.

Run the add-on installer from the normal desktop user's session with sudo, add its named widget, and sign out/in if it is not listed. Check manager Option 4 and the service journal if clicking fails. For a password-only v7.1 upgrade, the installed manager path and UUID stay compatible with the widget.

## Sunshine unreachable

```bash
sudo ss -lntup | grep -E '47984|47989|47990|48010'
curl --connect-timeout 5 http://10.42.60.1:47989/serverinfo
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=steamdeck-switch2 --list-ports
```

If the local request returns XML but Moonlight cannot connect, verify the Switch address/DNS and the hotspot zone's streaming rules. TCP 47990 is the management UI; RTSP uses TCP 48010. See [streaming setup](SUNSHINE.md).

## Home Wi-Fi did not reconnect

Choose the home network in SteamOS network settings. Restoration is best effort and uses the previously saved connection UUID. Do not delete all NetworkManager profiles or flush nftables to recover Wi-Fi.

## Password fails

Try forgetting the saved Switch network and reconnecting. WPA2 must still be verified on the target hardware. To return to the previous open behavior, run Option 5 and choose OPEN, understanding that nearby devices can then connect without a password.

Do not share `settings.sh`, NetworkManager connection files, password backups, DHCP leases or complete journals without reviewing them. No password is needed in an issue report.
