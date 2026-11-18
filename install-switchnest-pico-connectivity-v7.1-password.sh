#!/usr/bin/env bash
# SwitchNest Hotspot installer + ON/OFF manager, v7.1 (optional WPA2-Personal).
# OPEN mode allows nearby devices to join without authentication; WPA2 is recommended.
# This installer blocks IP forwarding but does not isolate connected devices from the host.
# Host dependencies: nmcli, nft, systemd, flock, ss, python3, and dnsmasq or Podman.
# Does not install host packages or change SteamOS read-only settings.
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CON='SteamDeck-Switch2'
AP_IP='10.42.60.1'
CONF='/etc/steamdeck-switch2'
STATE='/var/lib/steamdeck-switch2'
LEASE_DIR='/var/lib/steamdeck-switch2-dhcp'
RUNNER="$CONF/manager.sh"
CONFIG="$CONF/settings.sh"
UNIT='steamdeck-switch2-hotspot.service'
DNS_UNIT='steamdeck-switch2-dnsmasq.service'
HTTP_UNIT='steamdeck-switch2-http.service'
TABLE='steamdeck_switch2_offline'
ZONE='steamdeck-switch2'
CONTAINER='steamdeck-switch2-dns'
IMAGE='localhost/steamdeck-switch2-dnsmasq:v1'
PODMAN_HOME='' # Set during install and persisted for systemd services
log(){ printf '\n%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ask(){ local answer; read -r -p "$1 [y/N]: " answer || return 1; [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; }
installed(){ [[ -f "$CONFIG" && -f "$RUNNER" ]]; }
load_config(){
  installed || fail 'Choose 1 to install the offline hotspot first.'
  # Root-owned configuration written by this installer, never downloaded code.
  source "$CONFIG"
}
active(){ nmcli -t -f UUID connection show --active | grep -Fxq "$AP_UUID"; }

# Security is stored only in the NetworkManager profile, not settings.sh.
# Do not print PSKs or place them in command history / temporary files.
wifi_security_mode(){
  local key
  key=$(nmcli -g 802-11-wireless-security.key-mgmt connection show uuid "$1" 2>/dev/null || true)
  case "$key" in
    ''|--) printf 'open\n';;
    wpa-psk) printf 'wpa2\n';;
    *) printf 'unsupported\n';;
  esac
}
choose_wifi_security(){
  # Globals are consumed by install_hotspot/change_wifi_security only.
  local choice password confirm attempt
  WIFI_SECURITY_CHOICE=''; WIFI_SECURITY_PSK=''
  printf '\nWi-Fi security for %s:\n' "$CON"
  printf '  1) WPA2-Personal (password, recommended)\n'
  printf '  2) OPEN (no password; anyone nearby may connect)\n'
  printf '  3) Cancel\n'
  read -r -p 'Choose [1-3, default 1]: ' choice || return 1
  case "${choice:-1}" in
    1)
      for attempt in 1 2 3; do
        password=''; confirm=''
        read -r -s -p 'Enter Wi-Fi password (8-63 printable ASCII characters): ' password || { printf '\n'; return 1; }
        printf '\n'
        if (( ${#password} < 8 || ${#password} > 63 )) || [[ "$password" == *[![:print:]]* ]]; then
          log 'Invalid password: use 8-63 printable ASCII characters.'
          continue
        fi
        read -r -s -p 'Confirm Wi-Fi password: ' confirm || { printf '\n'; return 1; }
        printf '\n'
        if [[ "$password" != "$confirm" ]]; then
          log 'Passwords did not match.'
          continue
        fi
        WIFI_SECURITY_CHOICE=wpa2
        WIFI_SECURITY_PSK=$password
        password=''; confirm=''
        return 0
      done
      log 'Password entry cancelled after 3 unsuccessful attempts.'
      return 1
      ;;
    2)
      log 'OPEN selected: the Wi-Fi network will have NO password.'
      WIFI_SECURITY_CHOICE=open
      return 0
      ;;
    3) return 1;;
    *) log 'Invalid security selection.'; return 1;;
  esac
}
apply_wifi_security(){
  local uuid=$1 mode=$2 password=${3:-}
  case "$mode" in
    wpa2)
      # RSN limits the hotspot to WPA2 (not legacy WPA1).
      # Password is briefly present in nmcli's process arguments. NetworkManager
      # persists it in its protected system connection, never in our config.
      nmcli connection modify uuid "$uuid" \
        802-11-wireless-security.key-mgmt wpa-psk \
        802-11-wireless-security.proto rsn \
        802-11-wireless-security.psk "$password" \
        802-11-wireless-security.psk-flags 0 >/dev/null 2>&1
      ;;
    open)
      # Remove the entire security setting; key-mgmt=none is not an OPEN AP.
      if [[ $(wifi_security_mode "$uuid") != open ]]; then
        nmcli connection modify uuid "$uuid" remove 802-11-wireless-security >/dev/null 2>&1
      fi
      ;;
    *) return 1;;
  esac
}
change_wifi_security(){
  local old_mode old_psk='' new_mode new_psk was_on=0
  load_config
  old_mode=$(wifi_security_mode "$AP_UUID")
  [[ "$old_mode" != unsupported ]] || { log 'Unsupported existing security mode; refusing to modify this profile.'; return 0; }
  log "Current hotspot security: $([[ "$old_mode" == wpa2 ]] && printf 'WPA2-Personal' || printf 'OPEN')"
  choose_wifi_security || { log 'Security unchanged.'; return 0; }
  new_mode=$WIFI_SECURITY_CHOICE
  new_psk=$WIFI_SECURITY_PSK
  WIFI_SECURITY_PSK=''
  if [[ "$new_mode" == open && "$old_mode" == open ]]; then
    log 'Hotspot is already OPEN; no changes made.'
    return 0
  fi
  if [[ "$new_mode" == open ]]; then
    ask 'Remove Wi-Fi password and allow nearby devices to join?' || return 0
  fi
  ask 'Apply Wi-Fi security change? Connected devices will disconnect.' || return 0
  if [[ "$old_mode" == wpa2 ]]; then
    old_psk=$(nmcli --show-secrets -g 802-11-wireless-security.psk connection show uuid "$AP_UUID" 2>/dev/null || true)
    if [[ -z "$old_psk" || "$old_psk" == -- ]]; then
      log 'Cannot retrieve the previous WPA2 password for rollback. No changes made.'
      return 0
    fi
  fi
  if active || systemctl is-active --quiet "$UNIT"; then was_on=1; fi
  if systemctl is-active --quiet "$UNIT"; then
    systemctl stop "$UNIT" || { log 'Could not stop hotspot service; security unchanged.'; return 0; }
  fi
  if active; then
    stop_runtime || { log 'Could not stop hotspot; security unchanged.'; return 0; }
  fi
  if ! apply_wifi_security "$AP_UUID" "$new_mode" "$new_psk" || \
     [[ $(wifi_security_mode "$AP_UUID") != "$new_mode" ]]; then
    log 'Security update failed. Restoring the previous security setting.'
    apply_wifi_security "$AP_UUID" "$old_mode" "$old_psk" || log 'WARNING: rollback failed; inspect the NetworkManager profile.'
    if ((was_on)); then turn_on --confirmed; fi
    return 0
  fi
  new_psk=''
  # Update the installed manager so the existing KDE taskbar widget keeps using
  # the same stable path and UUID, with correct OPEN/WPA2 status messages.
  if [[ $(readlink -f "${BASH_SOURCE[0]}") != "$RUNNER" ]]; then
    local manager_backup
    if manager_backup=$(mktemp "$CONF/manager-before-password.XXXXXX.sh"); then
      if cp -p "$RUNNER" "$manager_backup"; then
        log "Previous manager backed up to: $manager_backup"
      else
        rm -f "$manager_backup"
        log 'WARNING: could not back up previous manager.'
      fi
    else
      log 'WARNING: could not create a manager backup.'
    fi
    install -m 700 "${BASH_SOURCE[0]}" "$RUNNER" || log 'WARNING: manager update failed; hotspot profile was updated.'
  fi
  if ((was_on)); then
    log 'Restarting hotspot with the new Wi-Fi security...'
    turn_on --confirmed
    if ! active || ! systemctl is-active --quiet "$UNIT"; then
      log 'Hotspot could not start with the new security. Attempting rollback.'
      systemctl stop "$UNIT" || true
      if ! stop_runtime; then
        log 'WARNING: cleanup failed; forwarding guard retained. Check status before retrying.'
        return 0
      fi
      if ! apply_wifi_security "$AP_UUID" "$old_mode" "$old_psk"; then
        log 'WARNING: could not restore previous security. Hotspot remains OFF.'
        return 0
      fi
      old_psk=''
      turn_on --confirmed
      if active && systemctl is-active --quiet "$UNIT"; then
        log 'Previous Wi-Fi security restored and hotspot restarted.'
      else
        log 'Previous Wi-Fi security restored, but the hotspot did not restart. Check status.'
      fi
      return 0
    fi
  fi
  old_psk=''
  if [[ "$new_mode" == wpa2 ]]; then
    log 'WPA2-Personal enabled. Reconnect Switch 2 with your new Wi-Fi password.'
  else
    log 'Hotspot is now OPEN. Reconnect Switch 2; no Wi-Fi password is required.'
  fi
  log 'SSID, IP, DHCP/DNS, HTTP, firewall rules and connection UUID were preserved.'
}

podman_local(){
  [[ -n "${PODMAN_HOME:-}" ]] || fail 'Dedicated Podman storage path is not configured.'
  "$PODMAN_BIN" --root "$PODMAN_HOME/storage" --runroot /run/steamdeck-switch2-podman \
    --storage-driver=vfs "$@"
}
choose_podman_home(){
  # SteamOS has a very small /var partition. Store all container layers on /home.
  # Do not change global Podman configuration or other projects' storage.
  local target_user="${SUDO_USER:-deck}" user_home free_kib
  [[ "$target_user" != root ]] || target_user=deck
  user_home=$(getent passwd "$target_user" | cut -d: -f6)
  [[ -n "$user_home" && -d "$user_home" ]] || fail "Cannot locate home directory for $target_user."
  [[ "$user_home" == /home/* ]] || fail "Refusing non-/home container storage path: $user_home"
  PODMAN_HOME="$user_home/steamdeck-switch2-podman"
  mkdir -p "$PODMAN_HOME/storage"
  chmod 700 "$PODMAN_HOME" "$PODMAN_HOME/storage"
  free_kib=$(df -Pk "$PODMAN_HOME" | awk 'END {print $4}')
  [[ "$free_kib" =~ ^[0-9]+$ ]] || fail 'Cannot check available /home space.'
  (( free_kib >= 2097152 )) || fail 'Need at least 2 GiB free on /home to build the container.'
  log "Dedicated Podman storage: $PODMAN_HOME/storage"
  log 'This leaves your existing /var/lib/containers/storage untouched.'
}
prepare_backend(){
  BACKEND=host; DNS_BIN=''; PODMAN_BIN=''; IMAGE_ID=''; PODMAN_HOME=''
  if command -v dnsmasq >/dev/null; then
    DNS_BIN=$(command -v dnsmasq)
    id -u nobody >/dev/null 2>&1 || fail 'The nobody account is required for host dnsmasq.'
    return 0
  fi
  command -v podman >/dev/null || fail 'Neither dnsmasq nor Podman is installed.'
  BACKEND=podman
  PODMAN_BIN=$(command -v podman)
  log 'Host dnsmasq is missing. Using dnsmasq inside Podman.'
  choose_podman_home
  mkdir -p "$STATE"; chmod 700 "$STATE"
  if ! podman_local image exists "$IMAGE"; then
    log 'One-time internet download: official Debian image and dnsmasq from Debian repositories.'
    log 'This happens before activating the hotspot. Later starts use only the local image.'
    ask 'Download and build the local dnsmasq container now?' || fail 'Download declined; no Wi-Fi changes made.'
    local builddir
    builddir=$(mktemp -d "$PODMAN_HOME/build.XXXXXX")
    cat > "$builddir/Containerfile" <<'BUILD'
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends dnsmasq-base && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["/usr/sbin/dnsmasq"]
BUILD
    if ! podman_local build --network=host --tag "$IMAGE" --file "$builddir/Containerfile" "$builddir"; then
      rm -rf "$builddir"
      fail 'Container build failed; Wi-Fi was not changed. Keep home Wi-Fi online and retry option 1.'
    fi
    rm -rf "$builddir"
  fi
  IMAGE_ID=$(podman_local image inspect --format '{{.Id}}' "$IMAGE")
  [[ "$IMAGE_ID" =~ ^(sha256:)?[0-9a-f]{64}$ ]] || fail 'Could not identify the locally built image.'
  podman_local run --rm --pull=never --network=none "$IMAGE_ID" --version
}
dns_cleanup(){
  load_config
  if [[ ${BACKEND:-host} == podman ]]; then
    if podman_local container exists "$CONTAINER"; then podman_local rm -f "$CONTAINER"; fi
  fi
}
dns_run(){
  load_config
  if [[ ${BACKEND:-host} == podman ]]; then
    exec "$PODMAN_BIN" --root "$PODMAN_HOME/storage" --runroot /run/steamdeck-switch2-podman \
      --storage-driver=vfs run --rm --name "$CONTAINER" --pull=never \
      --network=host --user=0 --cap-add=NET_ADMIN --cap-add=NET_RAW \
      --security-opt=label=disable --sdnotify=ignore \
      --volume "$CONF/dnsmasq.conf:/etc/dnsmasq.conf:ro" \
      --volume "$LEASE_DIR:$LEASE_DIR:rw" \
      "$IMAGE_ID" --no-daemon --conf-file=/etc/dnsmasq.conf
  else
    exec "$DNS_BIN" --no-daemon --conf-file="$CONF/dnsmasq.conf"
  fi
}
wait_dns(){
  local attempt
  for attempt in {1..15}; do
    if systemctl is-active --quiet "$DNS_UNIT" && \
       ss -H -4 -lun 'sport = :53' | awk -v ip="$AP_IP:53" '$4==ip {found=1} END{exit !found}'; then
      return 0
    fi
    sleep 1
  done
  log 'DNS did not become ready at the hotspot IP within 15 seconds.'
  return 1
}

portal_source(){
  cat <<'PORTAL_PY'
#!/usr/bin/env python3
"""Offline connectivity-check responder matching the working Pico 2 W bridge.

Port of the handleHttp behavior in favas0/CivSwitch-Pico2W-SerialBridge,
revision 0d1e167cfed96b5a4884c413e06e0718f769ae7d. Upstream retains MIT
notices and credits 90DNS (GPL-2.0-or-later) via switch2-homebrew.
See the accompanying connectivity-notices and licence copies.
This is a fixed response service, not a web proxy or internet gateway.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LEGACY_HOST = "conntest.nintendowifi.net"
MODERN_HOSTS = frozenset({
    "ctest.cdn.nintendo.net",
    "ctest.p01.ctest.srv.nintendo.net",
    "ctest-dl-lp1.cdn.nintendo.net",
    "ctest-ul-lp1.cdn.nintendo.net",
    "api.p01.lp1.ctest.srv.nintendo.net",
    "api-ipv6.p01.lp1.ctest.srv.nintendo.net",
})
LEGACY_BODY = (b"<html><head><title>HTML Page</title></head>"
               b"<body>This is test.html page</body></html>")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SteamDeckOffline/1.0"
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(3)

    def respond(self, head=False):
        # Permit the optional standard HTTP port and case-insensitive hostnames.
        host = self.headers.get("Host", "").strip().lower()
        if host.endswith(":80"):
            host = host[:-3]
        if host == LEGACY_HOST:
            status, content_type, body = 200, "text/html", LEGACY_BODY
        elif host in MODERN_HOSTS:
            status, content_type, body = 200, "text/plain", b"ok"
        else:
            status, content_type, body = 404, "text/plain", b""
        self.send_response(status)
        if status == 200:
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Organization", "Nintendo")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        if not head:
            self.wfile.write(body)

    def do_GET(self):
        self.respond()

    def do_HEAD(self):
        self.respond(head=True)

    def do_POST(self):
        self.respond()

    def log_request(self, code="-", size="-"):
        # No URL paths, authentication headers or bodies are logged.
        print(f"connectivity peer={self.client_address[0]} "
              f"host={self.headers.get('Host', '')!r} status={code}", flush=True)

    def log_message(self, *args):
        pass


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8
    allow_reuse_address = True


def check(bind, port):
    """Connect directly to the AP, so these tests never query external DNS."""
    from http.client import HTTPConnection
    for host in (LEGACY_HOST, *sorted(MODERN_HOSTS)):
        conn = HTTPConnection(bind, port, timeout=3)
        try:
            conn.request("GET", "/", headers={"Host": host})
            reply = conn.getresponse()
            body = reply.read()
            expected = LEGACY_BODY if host == LEGACY_HOST else b"ok"
            if (reply.status != 200 or body != expected or
                    reply.getheader("X-Organization") != "Nintendo" or
                    reply.getheader("Cache-Control") != "no-store"):
                raise RuntimeError(f"Unexpected local response for {host}: HTTP {reply.status}")
            print(f"PASS {host}", flush=True)
        finally:
            conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="10.42.60.1")
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check(args.bind, args.port)
        return
    with Server((args.bind, args.port), Handler) as server:
        print(f"Offline Pico-compatible HTTP listening on {args.bind}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
PORTAL_PY
}
write_portal_files(){
  mkdir -p "$CONF/licenses"
  portal_source > "$CONF/connectivity.py"
  chmod 600 "$CONF/connectivity.py"
  cat > "$CONF/connectivity-notices.md" <<'PORTAL_NOTICES'
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
PORTAL_NOTICES
  cat > "$CONF/licenses/pico-MIT.txt" <<'PORTAL_MIT'
MIT License

Copyright (c) 2026 Jack Spence
Copyright (c) 2026 favas0 (Pico 2 W port and additions)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
PORTAL_MIT
  cat > "$CONF/licenses/GPL-2.0.txt" <<'PORTAL_GPL'
                    GNU GENERAL PUBLIC LICENSE
                       Version 2, June 1991

 Copyright (C) 1989, 1991 Free Software Foundation, Inc.,
 <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The licenses for most software are designed to take away your
freedom to share and change it.  By contrast, the GNU General Public
License is intended to guarantee your freedom to share and change free
software--to make sure the software is free for all its users.  This
General Public License applies to most of the Free Software
Foundation's software and to any other program whose authors commit to
using it.  (Some other Free Software Foundation software is covered by
the GNU Lesser General Public License instead.)  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
this service if you wish), that you receive source code or can get it
if you want it, that you can change the software or use pieces of it
in new free programs; and that you know you can do these things.

  To protect your rights, we need to make restrictions that forbid
anyone to deny you these rights or to ask you to surrender the rights.
These restrictions translate to certain responsibilities for you if you
distribute copies of the software, or if you modify it.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must give the recipients all the rights that
you have.  You must make sure that they, too, receive or can get the
source code.  And you must show them these terms so they know their
rights.

  We protect your rights with two steps: (1) copyright the software, and
(2) offer you this license which gives you legal permission to copy,
distribute and/or modify the software.

  Also, for each author's protection and ours, we want to make certain
that everyone understands that there is no warranty for this free
software.  If the software is modified by someone else and passed on, we
want its recipients to know that what they have is not the original, so
that any problems introduced by others will not reflect on the original
authors' reputations.

  Finally, any free program is threatened constantly by software
patents.  We wish to avoid the danger that redistributors of a free
program will individually obtain patent licenses, in effect making the
program proprietary.  To prevent this, we have made it clear that any
patent must be licensed for everyone's free use or not licensed at all.

  The precise terms and conditions for copying, distribution and
modification follow.

                    GNU GENERAL PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. This License applies to any program or other work which contains
a notice placed by the copyright holder saying it may be distributed
under the terms of this General Public License.  The "Program", below,
refers to any such program or work, and a "work based on the Program"
means either the Program or any derivative work under copyright law:
that is to say, a work containing the Program or a portion of it,
either verbatim or with modifications and/or translated into another
language.  (Hereinafter, translation is included without limitation in
the term "modification".)  Each licensee is addressed as "you".

Activities other than copying, distribution and modification are not
covered by this License; they are outside its scope.  The act of
running the Program is not restricted, and the output from the Program
is covered only if its contents constitute a work based on the
Program (independent of having been made by running the Program).
Whether that is true depends on what the Program does.

  1. You may copy and distribute verbatim copies of the Program's
source code as you receive it, in any medium, provided that you
conspicuously and appropriately publish on each copy an appropriate
copyright notice and disclaimer of warranty; keep intact all the
notices that refer to this License and to the absence of any warranty;
and give any other recipients of the Program a copy of this License
along with the Program.

You may charge a fee for the physical act of transferring a copy, and
you may at your option offer warranty protection in exchange for a fee.

  2. You may modify your copy or copies of the Program or any portion
of it, thus forming a work based on the Program, and copy and
distribute such modifications or work under the terms of Section 1
above, provided that you also meet all of these conditions:

    a) You must cause the modified files to carry prominent notices
    stating that you changed the files and the date of any change.

    b) You must cause any work that you distribute or publish, that in
    whole or in part contains or is derived from the Program or any
    part thereof, to be licensed as a whole at no charge to all third
    parties under the terms of this License.

    c) If the modified program normally reads commands interactively
    when run, you must cause it, when started running for such
    interactive use in the most ordinary way, to print or display an
    announcement including an appropriate copyright notice and a
    notice that there is no warranty (or else, saying that you provide
    a warranty) and that users may redistribute the program under
    these conditions, and telling the user how to view a copy of this
    License.  (Exception: if the Program itself is interactive but
    does not normally print such an announcement, your work based on
    the Program is not required to print an announcement.)

These requirements apply to the modified work as a whole.  If
identifiable sections of that work are not derived from the Program,
and can be reasonably considered independent and separate works in
themselves, then this License, and its terms, do not apply to those
sections when you distribute them as separate works.  But when you
distribute the same sections as part of a whole which is a work based
on the Program, the distribution of the whole must be on the terms of
this License, whose permissions for other licensees extend to the
entire whole, and thus to each and every part regardless of who wrote it.

Thus, it is not the intent of this section to claim rights or contest
your rights to work written entirely by you; rather, the intent is to
exercise the right to control the distribution of derivative or
collective works based on the Program.

In addition, mere aggregation of another work not based on the Program
with the Program (or with a work based on the Program) on a volume of
a storage or distribution medium does not bring the other work under
the scope of this License.

  3. You may copy and distribute the Program (or a work based on it,
under Section 2) in object code or executable form under the terms of
Sections 1 and 2 above provided that you also do one of the following:

    a) Accompany it with the complete corresponding machine-readable
    source code, which must be distributed under the terms of Sections
    1 and 2 above on a medium customarily used for software interchange; or,

    b) Accompany it with a written offer, valid for at least three
    years, to give any third party, for a charge no more than your
    cost of physically performing source distribution, a complete
    machine-readable copy of the corresponding source code, to be
    distributed under the terms of Sections 1 and 2 above on a medium
    customarily used for software interchange; or,

    c) Accompany it with the information you received as to the offer
    to distribute corresponding source code.  (This alternative is
    allowed only for noncommercial distribution and only if you
    received the program in object code or executable form with such
    an offer, in accord with Subsection b above.)

The source code for a work means the preferred form of the work for
making modifications to it.  For an executable work, complete source
code means all the source code for all modules it contains, plus any
associated interface definition files, plus the scripts used to
control compilation and installation of the executable.  However, as a
special exception, the source code distributed need not include
anything that is normally distributed (in either source or binary
form) with the major components (compiler, kernel, and so on) of the
operating system on which the executable runs, unless that component
itself accompanies the executable.

If distribution of executable or object code is made by offering
access to copy from a designated place, then offering equivalent
access to copy the source code from the same place counts as
distribution of the source code, even though third parties are not
compelled to copy the source along with the object code.

  4. You may not copy, modify, sublicense, or distribute the Program
except as expressly provided under this License.  Any attempt
otherwise to copy, modify, sublicense or distribute the Program is
void, and will automatically terminate your rights under this License.
However, parties who have received copies, or rights, from you under
this License will not have their licenses terminated so long as such
parties remain in full compliance.

  5. You are not required to accept this License, since you have not
signed it.  However, nothing else grants you permission to modify or
distribute the Program or its derivative works.  These actions are
prohibited by law if you do not accept this License.  Therefore, by
modifying or distributing the Program (or any work based on the
Program), you indicate your acceptance of this License to do so, and
all its terms and conditions for copying, distributing or modifying
the Program or works based on it.

  6. Each time you redistribute the Program (or any work based on the
Program), the recipient automatically receives a license from the
original licensor to copy, distribute or modify the Program subject to
these terms and conditions.  You may not impose any further
restrictions on the recipients' exercise of the rights granted herein.
You are not responsible for enforcing compliance by third parties to
this License.

  7. If, as a consequence of a court judgment or allegation of patent
infringement or for any other reason (not limited to patent issues),
conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot
distribute so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you
may not distribute the Program at all.  For example, if a patent
license would not permit royalty-free redistribution of the Program by
all those who receive copies directly or indirectly through you, then
the only way you could satisfy both it and this License would be to
refrain entirely from distribution of the Program.

If any portion of this section is held invalid or unenforceable under
any particular circumstance, the balance of the section is intended to
apply and the section as a whole is intended to apply in other
circumstances.

It is not the purpose of this section to induce you to infringe any
patents or other property right claims or to contest validity of any
such claims; this section has the sole purpose of protecting the
integrity of the free software distribution system, which is
implemented by public license practices.  Many people have made
generous contributions to the wide range of software distributed
through that system in reliance on consistent application of that
system; it is up to the author/donor to decide if he or she is willing
to distribute software through any other system and a licensee cannot
impose that choice.

This section is intended to make thoroughly clear what is believed to
be a consequence of the rest of this License.

  8. If the distribution and/or use of the Program is restricted in
certain countries either by patents or by copyrighted interfaces, the
original copyright holder who places the Program under this License
may add an explicit geographical distribution limitation excluding
those countries, so that distribution is permitted only in or among
countries not thus excluded.  In such case, this License incorporates
the limitation as if written in the body of this License.

  9. The Free Software Foundation may publish revised and/or new versions
of the General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

Each version is given a distinguishing version number.  If the Program
specifies a version number of this License which applies to it and "any
later version", you have the option of following the terms and conditions
either of that version or of any later version published by the Free
Software Foundation.  If the Program does not specify a version number of
this License, you may choose any version ever published by the Free Software
Foundation.

  10. If you wish to incorporate parts of the Program into other free
programs whose distribution conditions are different, write to the author
to ask for permission.  For software which is copyrighted by the Free
Software Foundation, write to the Free Software Foundation; we sometimes
make exceptions for this.  Our decision will be guided by the two goals
of preserving the free status of all derivatives of our free software and
of promoting the sharing and reuse of software generally.

                            NO WARRANTY

  11. BECAUSE THE PROGRAM IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW.  EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED
OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE ENTIRE RISK AS
TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.  SHOULD THE
PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING,
REPAIR OR CORRECTION.

  12. IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES,
INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING
OUT OF THE USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED
TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY
YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER
PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
convey the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

If the program is interactive, make it output a short notice like this
when it starts in an interactive mode:

    Gnomovision version 69, Copyright (C) year name of author
    Gnomovision comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, the commands you use may
be called something other than `show w' and `show c'; they could even be
mouse-clicks or menu items--whatever suits your program.

You should also get your employer (if you work as a programmer) or your
school, if any, to sign a "copyright disclaimer" for the program, if
necessary.  Here is a sample; alter the names:

  Yoyodyne, Inc., hereby disclaims all copyright interest in the program
  `Gnomovision' (which makes passes at compilers) written by James Hacker.

  <signature of Moe Ghoul>, 1 April 1989
  Moe Ghoul, President of Vice

This General Public License does not permit incorporating your program into
proprietary programs.  If your program is a subroutine library, you may
consider it more useful to permit linking proprietary applications with the
library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.
PORTAL_GPL
}
fix_dns_config(){
  # Modify only this hotspot's private DNS config. Keep DHCP/interface/leases.
  python3 - "$CONF/dnsmasq.conf" "$AP_IP" <<'DNS_PATCH'
from pathlib import Path
import sys
path = Path(sys.argv[1])
remove = {'server', 'servers-file', 'resolv-file', 'no-resolv', 'no-poll',
          'address', 'local', 'no-hosts'}
lines = [line for line in path.read_text().splitlines()
         if line.strip().split('=', 1)[0] not in remove]
lines += ['no-resolv', 'no-poll', 'no-hosts', 'address=/#/' + sys.argv[2], 'local=/#/']
path.write_text('\n'.join(lines) + '\n')
DNS_PATCH
}
check_http_port(){
  if systemctl is-active --quiet "$HTTP_UNIT"; then return 0; fi
  if ss -H -4 -ltn 'sport = :80' | awk -v ip="$AP_IP:80" \
      '$4==ip || $4=="0.0.0.0:80" || $4=="*:80" {found=1} END{exit !found}'; then
    fail 'Port 80 is already in use. If your manual Python HTTP server is open, stop it with Ctrl+C, then retry. Inspect: sudo ss -ltnp "sport = :80"'
  fi
}
wait_http(){
  local attempt
  for attempt in {1..10}; do
    if systemctl is-active --quiet "$HTTP_UNIT" && \
       ss -H -4 -ltn 'sport = :80' | awk -v ip="$AP_IP:80" '$4==ip {found=1} END{exit !found}'; then
      python3 "$CONF/connectivity.py" --bind "$AP_IP" --check
      return $?
    fi
    sleep 1
  done
  log 'Local HTTP connectivity responder did not become ready.'
  return 1
}
validate_dns_config(){
  if [[ "$BACKEND" == podman ]]; then
    podman_local run --rm --pull=never --network=none --security-opt=label=disable \
      --volume "$CONF/dnsmasq.conf:/etc/dnsmasq.conf:ro" \
      "$IMAGE_ID" --test --conf-file=/etc/dnsmasq.conf
  else
    "$DNS_BIN" --test --conf-file="$CONF/dnsmasq.conf"
  fi
}
write_service_files(){
  cat > "/etc/systemd/system/$DNS_UNIT" <<SERVICE
[Unit]
Description=Local DHCP and DNS for SwitchNest Hotspot
After=NetworkManager.service
PartOf=$UNIT
[Service]
Type=simple
ExecStartPre=/usr/bin/bash $RUNNER --internal-dns-cleanup
ExecStart=/usr/bin/bash $RUNNER --internal-dns
ExecStopPost=/usr/bin/bash $RUNNER --internal-dns-cleanup
Restart=on-failure
RestartSec=3
SERVICE
  cat > "/etc/systemd/system/$UNIT" <<SERVICE
[Unit]
Description=SwitchNest Hotspot
Wants=NetworkManager.service
After=NetworkManager.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash $RUNNER --internal-start
ExecStop=/usr/bin/bash $RUNNER --internal-stop
TimeoutStartSec=120
TimeoutStopSec=60
[Install]
WantedBy=multi-user.target
SERVICE
  cat > "/etc/systemd/system/$HTTP_UNIT" <<SERVICE
[Unit]
Description=Offline Pico-compatible Nintendo connectivity checks
After=NetworkManager.service
PartOf=$UNIT
[Service]
Type=simple
ExecStart=$(command -v python3) $CONF/connectivity.py --bind $AP_IP --port 80
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_UNIX
SERVICE
}
update_existing_hotspot(){
  local cmd was_on=0
  load_config
  for cmd in nmcli nft systemctl flock ss python3; do
    command -v "$cmd" >/dev/null || fail "Missing required command: $cmd"
  done
  [[ -f "$CONF/dnsmasq.conf" ]] || fail 'Hotspot DNS config missing; use option 1.'
  check_http_port
  log 'Existing Wi-Fi security will be preserved. Choose menu option 5 to change its password.'
  log 'If firewalld is active, this adds HTTP to the hotspot zone and reloads its permanent rules.'
  log 'Save unrelated runtime-only firewall rules before continuing.'
  ask 'Update this hotspot, including Pico DNS/HTTP, while keeping its profile and container?' || return 0
  if active; then was_on=1; fi
  # Save current owned configuration before editing; never touch other DNS setups.
  local backup
  backup=$(mktemp -d "$CONF/before-connectivity.XXXXXX")
  cp -p "$CONFIG" "$CONF/dnsmasq.conf" "$RUNNER" "$backup/"
  if systemctl cat "$UNIT" >/dev/null 2>&1; then
    systemctl stop "$UNIT" || fail 'Could not stop the previous hotspot manager.'
  fi
  stop_runtime || fail 'Could not stop the existing AP; no DNS changes applied.'
  fix_dns_config
  validate_dns_config
  write_portal_files
  configure_host_firewall
  if [[ $(readlink -f "${BASH_SOURCE[0]}") != "$RUNNER" ]]; then
    install -m 700 "${BASH_SOURCE[0]}" "$RUNNER"
  fi
  write_service_files
  systemctl daemon-reload
  log 'Pico-compatible local DNS and HTTP checks installed. Existing Wi-Fi profile/container retained.'
  log "Previous configuration backup: $backup"
  if ((was_on)); then
    turn_on --confirmed
  else
    log 'Hotspot remains OFF. Choose 2 to start it.'
  fi
}

configure_host_firewall(){
  # Give only the AP profile its own zone. Home Wi-Fi retains its previous zone.
  if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -Fxq "$ZONE"; then
      firewall-cmd --permanent --new-zone="$ZONE"
    fi
    firewall-cmd --permanent --zone="$ZONE" --add-service=dns
    firewall-cmd --permanent --zone="$ZONE" --add-service=dhcp
    firewall-cmd --permanent --zone="$ZONE" --add-service=http
    firewall-cmd --check-config
    # Required to load a newly defined zone; may discard unrelated runtime-only rules.
    firewall-cmd --reload
    nmcli connection modify "$CON" connection.zone "$ZONE"
  fi
}

remove_guard(){
  if nft list table inet "$TABLE" >/dev/null 2>&1; then nft delete table inet "$TABLE"; fi
}
apply_guard(){
  local rules
  rules=$(mktemp)
  if nft list table inet "$TABLE" >/dev/null 2>&1; then
    printf 'delete table inet %s\n' "$TABLE" > "$rules"
  fi
  cat >> "$rules" <<RULES
add table inet $TABLE
add chain inet $TABLE forward { type filter hook forward priority -100; policy accept; }
add rule inet $TABLE forward iifname "$IFACE" counter drop
add rule inet $TABLE forward oifname "$IFACE" counter drop
RULES
  # One atomic transaction; never flush or replace another firewall's rules.
  if ! nft -f "$rules"; then rm -f "$rules"; return 1; fi
  rm -f "$rules"
}
save_previous(){
  local uuid
  uuid=$(nmcli -g GENERAL.CON-UUID device show "$IFACE")
  if [[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ && "$uuid" != "$AP_UUID" ]]; then
    printf '%s\n' "$uuid" > "$STATE/previous-wifi-uuid"
    chmod 600 "$STATE/previous-wifi-uuid"
  fi
}
restore_previous(){
  local uuid
  if [[ -s "$STATE/previous-wifi-uuid" ]]; then
    uuid=$(cat "$STATE/previous-wifi-uuid")
    if [[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] && nmcli --wait 35 connection up uuid "$uuid"; then
      rm -f "$STATE/previous-wifi-uuid"
    else
      log 'Home Wi-Fi restore failed. Choose it in SteamOS network settings; the saved connection is retained.'
      return 1
    fi
  else
    log 'No previous Wi-Fi saved. Select your home Wi-Fi in SteamOS network settings.'
  fi
}
stop_runtime(){
  load_config
  if systemctl cat "$HTTP_UNIT" >/dev/null 2>&1; then
    systemctl stop "$HTTP_UNIT" || return 1
  fi
  systemctl stop "$DNS_UNIT" || return 1
  if active; then
    nmcli --wait 25 connection down uuid "$AP_UUID" || return 1
  fi
  # Keep the guard if disconnection failed; only remove it once the AP is down.
  if active; then log 'Hotspot still active; keeping the forwarding block.'; return 1; fi
  remove_guard
}
start_failed(){
  local code=$1
  trap - ERR INT TERM
  log 'Hotspot startup failed; stopping it and restoring the previous Wi-Fi.'
  if stop_runtime; then
    restore_previous || true
  else
    log 'Cleanup did not finish. Forwarding block retained. Use Hotspot OFF and check status.'
  fi
  exit "$code"
}
start_runtime(){
  load_config
  mkdir -p "$STATE"; chmod 700 "$STATE"
  save_previous
  # Fail closed: install isolation before bringing up the AP.
  apply_guard
  trap 'start_failed $?' ERR
  trap 'start_failed 130' INT
  trap 'start_failed 143' TERM
  nmcli --wait 35 connection up uuid "$AP_UUID"
  systemctl start "$HTTP_UNIT"
  wait_http
  systemctl start "$DNS_UNIT"
  wait_dns
  nft list table inet "$TABLE" >/dev/null
  trap - ERR INT TERM
}
install_or_update(){
  # Option 1 includes the complete Pico DNS/HTTP setup in both paths.
  # Preserve working installs; use the full installer for a new/partial setup.
  if installed && [[ -f "$CONF/dnsmasq.conf" ]]; then
    update_existing_hotspot
  else
    install_hotspot
  fi
}
install_hotspot(){
  local cmd dev choice uuid dns_user security
  log 'Install offline hotspot (optional WPA2 password; DHCP + DNS + forwarding block + ON/OFF).'
  log 'OPEN mode permits anyone within Wi-Fi range to connect; WPA2 is recommended.'
  log 'Requires nmcli, nft, systemctl, flock, ss, python3, plus host dnsmasq or Podman.'
  log 'Includes the working Pico DNS wildcard and local HTTP connectivity-check responses.'
  log 'When using Podman, all image layers are stored under /home, not the small SteamOS /var partition.'
  log 'If firewalld is running, setup adds a dedicated hotspot zone and reloads its permanent configuration.'
  log 'A firewalld reload discards unrelated runtime-only rules; save any such rules first.'
  for cmd in nmcli nft systemctl flock ss python3; do
    command -v "$cmd" >/dev/null || fail "Missing $cmd. Install it before running setup; no changes have been made."
  done
  check_http_port
  systemctl is-active --quiet NetworkManager.service || fail 'NetworkManager is not running.'
  local -a wifis
  mapfile -t wifis < <(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi" {print $1}')
  ((${#wifis[@]})) || fail 'No Wi-Fi interface found.'
  dev=${wifis[0]}
  if ((${#wifis[@]} > 1)); then
    printf 'Wi-Fi interfaces: %s\n' "${wifis[*]}"
    read -r -p "Choose Wi-Fi interface [$dev]: " choice
    dev=${choice:-$dev}
  fi
  [[ "$dev" =~ ^[a-zA-Z0-9_.:-]+$ ]] || fail 'Invalid interface name.'
  [[ $(nmcli -g GENERAL.TYPE device show "$dev") == wifi ]] || fail 'Not a Wi-Fi interface.'
  [[ $(nmcli -g WIFI-PROPERTIES.AP device show "$dev") == yes ]] || fail 'Adapter does not report AP support.'
  uuid=$(nmcli -g connection.uuid connection show "$CON" 2>/dev/null || true)
  if [[ -n "$uuid" ]]; then
    [[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || fail 'Several profiles may share the hotspot name; rename duplicates first.'
    ask "Replace the existing '$CON' profile and its offline services?" || return 0
  fi
  choose_wifi_security || { log 'Installation cancelled; no Wi-Fi changes made.'; return 0; }
  ask 'Apply the offline configuration? Updating an active hotspot disconnects its clients.' || return 0
  mkdir -p "$CONF" "$STATE"; chmod 700 "$CONF" "$STATE"
  prepare_backend
  # Stop our current/previous edition only. Never stop unrelated DNS services.
  # A prior installation might have systemd units but no manager.sh (as reported
  # by the user). A failing legacy ExecStop must not prevent recovery.
  if systemctl cat "$UNIT" >/dev/null 2>&1; then
    systemctl disable "$UNIT" || true
    systemctl stop "$UNIT" || log 'Previous hotspot stop reported an error; checking its actual state.'
    systemctl is-active --quiet "$UNIT" && fail 'Old hotspot service is still active; stop it before reinstalling.'
  fi
  if systemctl cat "$DNS_UNIT" >/dev/null 2>&1; then
    systemctl stop "$DNS_UNIT" || log 'Previous DHCP/DNS stop reported an error; checking its actual state.'
    systemctl is-active --quiet "$DNS_UNIT" && fail 'Old DHCP/DNS service is still active; stop it before reinstalling.'
  fi
  if [[ -n "$uuid" ]]; then
    if nmcli -t -f UUID connection show --active | grep -Fxq "$uuid"; then
      nmcli --wait 25 connection down uuid "$uuid"
    fi
  fi
  if systemctl cat steamdeck-switch2-firewall.service >/dev/null 2>&1; then
    systemctl disable --now steamdeck-switch2-firewall.service
    rm -f /etc/systemd/system/steamdeck-switch2-firewall.service
  fi
  remove_guard
  if [[ -n "$uuid" ]]; then nmcli connection delete uuid "$uuid"; fi
  nmcli connection add type wifi ifname "$dev" con-name "$CON" ssid "$CON" \
    802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 1 \
    ipv4.method manual ipv4.addresses "$AP_IP/24" ipv4.never-default yes \
    ipv4.ignore-auto-dns yes ipv6.method disabled connection.autoconnect no >/dev/null
  # New profiles begin OPEN. Add WPA2 only if selected by the user.
  # Delete/recreate above prevents inheriting any prior security setting.
  uuid=$(nmcli -g connection.uuid connection show "$CON")
  if [[ "$WIFI_SECURITY_CHOICE" == wpa2 ]]; then
    if ! apply_wifi_security "$uuid" wpa2 "$WIFI_SECURITY_PSK" || \
       [[ $(wifi_security_mode "$uuid") != wpa2 ]]; then
      nmcli connection delete uuid "$uuid" || true
      fail 'Could not configure WPA2. The new hotspot profile was removed.'
    fi
  else
    security=$(wifi_security_mode "$uuid")
    if [[ "$security" != open ]]; then
      nmcli connection delete uuid "$uuid" || true
      fail 'The new profile unexpectedly requires Wi-Fi authentication; aborted.'
    fi
  fi
  WIFI_SECURITY_PSK=''
  configure_host_firewall
  printf 'IFACE=%q\nAP_UUID=%q\nBACKEND=%q\nDNS_BIN=%q\nPODMAN_BIN=%q\nIMAGE_ID=%q\nPODMAN_HOME=%q\n' \
    "$dev" "$uuid" "$BACKEND" "$DNS_BIN" "$PODMAN_BIN" "$IMAGE_ID" "$PODMAN_HOME" > "$CONFIG"
  chmod 600 "$CONFIG"
  dns_user=nobody
  if [[ "$BACKEND" == podman ]]; then
    # Keep the container process root for host DHCP sockets; it is not privileged.
    # Bind mounts contain only this app's config and DHCP leases.
    dns_user=root
    install -d -m 700 "$LEASE_DIR"
  else
    install -d -o nobody -m 750 "$LEASE_DIR"
  fi
  cat > "$CONF/dnsmasq.conf" <<DNS
user=$dns_user
interface=$dev
except-interface=lo
bind-dynamic
listen-address=$AP_IP
port=53
no-resolv
no-poll
no-hosts
address=/#/$AP_IP
local=/#/
dhcp-range=10.42.60.20,10.42.60.100,255.255.255.0,12h
dhcp-option=option:router,$AP_IP
dhcp-option=option:dns-server,$AP_IP
dhcp-leasefile=$LEASE_DIR/dnsmasq.leases
log-dhcp
DNS
  validate_dns_config
  write_portal_files
  # Keep the installed manager independent of the downloaded file's location.
  if [[ $(readlink -f "${BASH_SOURCE[0]}") != "$RUNNER" ]]; then
    install -m 700 "${BASH_SOURCE[0]}" "$RUNNER"
  fi
  write_service_files
  systemctl daemon-reload
  if ask 'Automatically turn the offline hotspot ON after reboot?'; then
    systemctl enable "$UNIT"
  else
    systemctl disable "$UNIT"
  fi
  if [[ $(wifi_security_mode "$uuid") == wpa2 ]]; then
    log 'Installed WPA2-Personal hotspot (password protected). Choose 2 for ON or 3 for OFF.'
  else
    log 'Installed OPEN hotspot (NO PASSWORD). Choose 2 for ON or 3 for OFF.'
  fi
  log 'Reopen this menu with this downloaded script or: sudo bash /etc/steamdeck-switch2/manager.sh'
  if ask 'Turn the hotspot ON now?'; then turn_on --confirmed; fi
}
turn_on(){
  load_config
  log 'Hotspot ON usually disconnects home Wi-Fi on the same adapter.'
  if [[ ${1:-} != --confirmed ]]; then ask 'Turn Hotspot ON?' || return 0; fi
  if systemctl is-active --quiet "$UNIT"; then
    # Check actual state; also repair after an external/manual disconnection.
    if active && systemctl is-active --quiet "$DNS_UNIT" && systemctl is-active --quiet "$HTTP_UNIT" && nft list table inet "$TABLE" >/dev/null 2>&1; then
      log 'Hotspot is already ON.'; return 0
    fi
    systemctl stop "$UNIT"
  fi
  if ! systemctl start "$UNIT"; then
    journalctl -u "$UNIT" -u "$DNS_UNIT" -u "$HTTP_UNIT" -n 40 --no-pager
    log 'Could not start the hotspot. Use option 3 to restore home Wi-Fi if needed.'
    return 0
  fi
  if [[ $(wifi_security_mode "$AP_UUID") == wpa2 ]]; then
    log "WPA2-Personal hotspot ON: $CON (password protected). Host IP / DNS: $AP_IP."
  else
    log "OPEN hotspot ON: $CON (NO PASSWORD). Host IP / DNS: $AP_IP."
    log 'WARNING: anyone nearby can join. Switch it OFF when finished.'
  fi
  log 'Switch 2: automatic IP and DNS. Manual alternative: 10.42.60.2 / 255.255.255.0; gateway and DNS 10.42.60.1.'
  log 'Internet forwarding is blocked on this hotspot. Run your FTP server on Switch 2 for local transfers.'
  log 'Known Nintendo checks receive the same local HTTP responses as the Pico. This does not supply internet.'
  log 'If a firmware/client uses another check, inspect the HTTP service log; hardware verification is still required.' 
}
turn_off(){
  load_config
  ask 'Turn Hotspot OFF? This also disables its automatic startup.' || return 0
  systemctl disable "$UNIT"
  systemctl stop "$UNIT" || { log 'Stop failed. Check status; forwarding block is retained.'; return 0; }
  # Also handles an AP brought up outside the manager or a previous failed start.
  if ! stop_runtime; then log 'Cleanup failed. Check status before changing Wi-Fi.'; return 0; fi
  log 'Hotspot OFF. Local DHCP/DNS/HTTP stopped and hotspot forwarding rules removed.'
  if ask 'Reconnect to the previously active home Wi-Fi?'; then restore_previous || true; fi
}
status(){
  log 'Active connections:'
  nmcli -f NAME,TYPE,DEVICE connection show --active
  if ! installed; then log 'Offline hotspot is not installed by this version.'; return 0; fi
  load_config
  if active; then log 'Hotspot: ON'; else log 'Hotspot: OFF'; fi
  case $(wifi_security_mode "$AP_UUID") in
    wpa2) log 'Wi-Fi security: WPA2-Personal (password protected)';;
    open) log 'Wi-Fi security: OPEN (no password)';;
    *) log 'Wi-Fi security: unknown / unsupported';;
  esac
  printf 'DNS backend: %s\n' "${BACKEND:-host}"
  printf 'Manager: '; systemctl is-active "$UNIT" || true
  printf 'DHCP/DNS: '; systemctl is-active "$DNS_UNIT" || true
  printf 'Local HTTP: '; systemctl is-active "$HTTP_UNIT" || true
  printf 'After reboot: '; systemctl is-enabled "$UNIT" || true
  if nft list table inet "$TABLE"; then :; else log 'No hotspot forwarding block loaded (expected when OFF).'; fi
  log "Logs: sudo journalctl -u $DNS_UNIT -u $HTTP_UNIT -n 40 --no-pager"
  log "Local HTTP check: sudo python3 $CONF/connectivity.py --bind $AP_IP --check"
  log 'DNS (TCP/UDP 53), DHCP (UDP 67) and HTTP (TCP 80) are allowed in the dedicated zone when firewalld was active during setup.'
}
main(){
  [[ $EUID -eq 0 ]] || fail "Run: sudo bash ${BASH_SOURCE[0]}"
  case "${1:-}" in
    --internal-dns) dns_run; return;;
    --internal-dns-cleanup) dns_cleanup; return;;
    --internal-start|--internal-stop)
      exec 9>/run/lock/steamdeck-switch2-runtime.lock
      flock -w 45 9 || fail 'Another hotspot action is still running.'
      if [[ $1 == --internal-start ]]; then start_runtime; else stop_runtime; fi
      return;;
    '') ;;
    *) fail 'No arguments are required. Run the script to open its menu.';;
  esac
  umask 077
  command -v nmcli >/dev/null || fail 'NetworkManager/nmcli missing.'
  local choice
  while true; do
    cat <<'MENU'

SwitchNest Hotspot v7.1 (optional WPA2 password)
1) Install/update hotspot + Pico DNS/HTTP
2) Hotspot ON
3) Hotspot OFF + restore home Wi-Fi
4) Show status
5) Set/change Wi-Fi password (WPA2 or OPEN)
6) Exit
MENU
    read -r -p 'Choose [1-6]: ' choice || break
    case "$choice" in
      1) install_or_update;;
      2) turn_on;;
      3) turn_off;;
      4) status;;
      5) change_wifi_security;;
      6) break;;
      *) log 'Choose a number from 1 to 6.';;
    esac
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
