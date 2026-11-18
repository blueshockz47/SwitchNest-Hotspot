#!/usr/bin/env bash
# SwitchNest Hotspot: Plasma 6.7 panel toggle add-on.
# Installs a SEPARATE panel widget; does not patch KDE's compiled network applet.
# Leaves the working v7 hotspot, DNS/HTTP services, and NetworkManager profile untouched.
# Install: sudo bash this-file.sh
# Remove:  sudo bash this-file.sh --remove
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

PLUGIN='local.steamdeck.switch2.offlinehotspot'
ROOT_HELPER='/etc/steamdeck-switch2-panel-toggle'
POLKIT_RULE='/etc/polkit-1/rules.d/49-steamdeck-switch2-panel-toggle.rules'
OWNER_FILE='/etc/steamdeck-switch2/panel-toggle-owner'

write_payloads() {
  local dir=$1
  mkdir -p "$dir/package/contents/ui"
  cat > "$dir/root-helper" <<'ROOT_HELPER_CODE'
#!/usr/bin/env bash
# Only the three fixed actions below are accepted, with no arbitrary commands.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
main() {
  [[ $EUID -eq 0 && $# -eq 1 ]] || exit 2
  local action=$1 trusted mode
  case "$action" in toggle|on|off) ;; *) exit 2;; esac
  for trusted in /etc/steamdeck-switch2 /etc/steamdeck-switch2/manager.sh /etc/steamdeck-switch2/settings.sh; do
    [[ -e "$trusted" && ! -L "$trusted" && $(stat -c %u "$trusted") == 0 ]] || {
      echo 'The v7 hotspot files are missing, symlinked, or not root-owned.' >&2; exit 1;
    }
    mode=$(stat -c %a "$trusted")
    (( (8#$mode & 0022) == 0 )) || { echo 'Hotspot files are writable by other users.' >&2; exit 1; }
  done
  # Source only the root-owned, verified installed v7 manager.
  source /etc/steamdeck-switch2/manager.sh
  load_config
  exec 8>/run/lock/steamdeck-switch2-panel-toggle.lock
  flock -w 3 8 || { echo 'Another hotspot action is running. Retry in a moment.' >&2; exit 1; }
  if [[ "$action" == toggle ]]; then
    if active || systemctl is-active --quiet "$UNIT"; then action=off; else action=on; fi
  fi
  if [[ "$action" == on ]]; then
    turn_on --confirmed
    if ! active || ! systemctl is-active --quiet "$UNIT" || \
       ! systemctl is-active --quiet "$DNS_UNIT" || \
       ! systemctl is-active --quiet "$HTTP_UNIT" || \
       ! nft list table inet "$TABLE" >/dev/null 2>&1; then
      echo 'Hotspot failed to start fully. Check sudo journalctl -u steamdeck-switch2-hotspot.service.' >&2
      exit 1
    fi
    echo 'TASKBAR_STATE=on'
  else
    # v7 Option 3 asks twice. The user's click authorizes both prompts.
    ask() { return 0; }
    turn_off
    if active || systemctl is-active --quiet "$UNIT" || \
       systemctl is-active --quiet "$DNS_UNIT" || \
       systemctl is-active --quiet "$HTTP_UNIT"; then
      echo 'Hotspot did not stop fully; check the systemd logs.' >&2; exit 1
    fi
    if nft list table inet "$TABLE" >/dev/null 2>&1; then
      echo 'The forwarding block is still active; inspect the hotspot service.' >&2; exit 1
    fi
    echo 'TASKBAR_STATE=off'
  fi
}
main "$@"
ROOT_HELPER_CODE

  cat > "$dir/launch.py" <<'LAUNCH_CODE'
#!/usr/bin/env python3
"""Click action: pkexec only the fixed, root-owned v7 hotspot helper."""
import shutil
import subprocess
import sys

HELPER = '/etc/steamdeck-switch2-panel-toggle'

def notify(message, error=False):
    binary = shutil.which('notify-send')
    if binary:
        subprocess.run([binary, '-a', 'SwitchNest Hotspot',
                        '-u', 'critical' if error else 'normal',
                        'SwitchNest Hotspot', message], check=False, timeout=10)

def main():
    if len(sys.argv) != 1:
        return 2
    if not shutil.which('pkexec'):
        notify('pkexec is unavailable.', True)
        print('pkexec is unavailable.', file=sys.stderr)
        return 1
    try:
        result = subprocess.run(['pkexec', HELPER, 'toggle'],
                                capture_output=True, text=True, timeout=210)
    except (OSError, subprocess.TimeoutExpired) as exc:
        notify(f'Hotspot action failed: {exc}', True)
        print(str(exc), file=sys.stderr)
        return 1
    if result.returncode:
        message = (result.stderr or result.stdout).strip().splitlines()
        message = message[-1][:250] if message else 'Hotspot action failed. Check service logs.'
        notify(message, True)
        print(message, file=sys.stderr)
        return result.returncode
    if 'TASKBAR_STATE=on' in result.stdout:
        notify('Offline hotspot ON (Pico DNS/HTTP enabled).')
        print('on')
    elif 'TASKBAR_STATE=off' in result.stdout:
        notify('Offline hotspot OFF. Home Wi-Fi restoration attempted.')
        print('off')
    else:
        notify('Hotspot returned an unexpected result.', True)
        print('Unexpected result from helper.', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
LAUNCH_CODE

  cat > "$dir/status.sh" <<'STATUS_CODE'
#!/usr/bin/env bash
# User-readable state, no privilege escalation and no network access.
set -euo pipefail
uuid=$(/usr/bin/nmcli -g connection.uuid connection show 'SteamDeck-Switch2' 2>/dev/null) || {
  echo unavailable; exit 0;
}
[[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || { echo unavailable; exit 0; }
if /usr/bin/nmcli -t -f UUID connection show --active 2>/dev/null | /usr/bin/grep -Fxq "$uuid"; then
  echo on
else
  echo off
fi
STATUS_CODE

  cat > "$dir/package/metadata.json" <<'META_CODE'
{
  "KPackageStructure": "Plasma/Applet",
  "X-Plasma-API-Minimum-Version": "6.0",
  "KPlugin": {
    "Id": "local.steamdeck.switch2.offlinehotspot",
    "Name": "SwitchNest Hotspot Toggle",
    "Description": "One-click v7 offline hotspot ON/OFF with home Wi-Fi restoration",
    "Icon": "network-wireless-hotspot",
    "Category": "System Information",
    "Version": "2.0",
    "License": "MIT"
  }
}
META_CODE

  cat > "$dir/package/contents/ui/main.qml" <<'QML_CODE'
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    property bool hotspotOn: false
    property bool statusKnown: false
    property bool statusBusy: false
    property bool pending: false
    property string lastError: ""
    readonly property string statusCommand: STATUS_COMMAND_PLACEHOLDER
    readonly property string actionCommand: ACTION_COMMAND_PLACEHOLDER

    Plasmoid.title: "SwitchNest Hotspot"
    Plasmoid.icon: "network-wireless-hotspot"
    preferredRepresentation: compactRepresentation
    toolTipMainText: "SwitchNest Hotspot"
    toolTipSubText: pending ? "Switching hotspot…" : lastError.length > 0 ? lastError
        : !statusKnown ? "Status unavailable (check v7 installation)"
        : hotspotOn ? "ON — click to turn OFF and restore home Wi-Fi"
        : "OFF — click to start offline hotspot"

    function refresh() {
        if (pending || statusBusy) return;
        statusBusy = true;
        executor.connectSource(statusCommand);
    }

    function toggle() {
        if (pending) return;
        pending = true;
        lastError = "";
        executor.connectSource(actionCommand);
    }

    Plasma5Support.DataSource {
        id: executor
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const output = String(data["stdout"] || "").trim();
            const error = String(data["stderr"] || "").trim();
            const code = Number(data["exit code"] || 0);
            if (source === root.statusCommand) {
                root.statusBusy = false;
                root.statusKnown = (output === "on" || output === "off");
                root.hotspotOn = (output === "on");
            } else if (source === root.actionCommand) {
                root.pending = false;
                if (code !== 0) root.lastError = error || "Hotspot toggle failed; see notification.";
                if (output === "on" || output === "off") {
                    root.hotspotOn = (output === "on");
                    root.statusKnown = true;
                }
                root.refresh();
            }
            disconnectSource(source);
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: 260
        Layout.preferredHeight: 120
        spacing: Kirigami.Units.smallSpacing
        Controls.Label {
            Layout.fillWidth: true
            text: root.pending ? "Switching…" : root.hotspotOn ? "Offline hotspot: ON" : "Offline hotspot: OFF"
            horizontalAlignment: Text.AlignHCenter
        }
        Controls.Button {
            Layout.alignment: Qt.AlignHCenter
            text: root.hotspotOn ? "Turn OFF + restore Wi-Fi" : "Turn ON"
            enabled: !root.pending
            onClicked: root.toggle()
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: root.lastError.length > 0
            text: root.lastError
            wrapMode: Text.WordWrap
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSizes.medium
        Layout.minimumHeight: Kirigami.Units.iconSizes.medium
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: 2
            source: root.hotspotOn ? "network-wireless-hotspot" : "network-wireless"
            opacity: root.pending ? 0.5 : 1.0
        }
        Rectangle {
            width: 7
            height: 7
            radius: 4
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: root.hotspotOn ? "#22b573" : "#888888"
            border.width: 1
            border.color: "#333333"
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }
}
QML_CODE
}

main() {
  [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0" >&2; exit 1; }
  local action=${1:-install} target_user=${SUDO_USER:-} target_home dir user_data plugin_path
  case "$action" in install|--remove) ;; *) echo "Usage: sudo bash $0 [--remove]" >&2; exit 2;; esac
  if [[ "$action" == --remove && -f "$OWNER_FILE" ]]; then target_user=$(cat "$OWNER_FILE"); fi
  [[ "$target_user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ && "$target_user" != root ]] || {
    echo 'Run with sudo from the normal desktop user (e.g. deck).' >&2; exit 1;
  }
  target_home=$(getent passwd "$target_user" | cut -d: -f6)
  [[ "$target_home" == /home/* && -d "$target_home" ]] || { echo 'Desktop user home not found.' >&2; exit 1; }
  user_data="$target_home/.local/share/steamdeck-switch2-panel-toggle"
  plugin_path="$target_home/.local/share/plasma/plasmoids/$PLUGIN"
  for command_name in runuser python3 nmcli systemctl flock pkexec kpackagetool6; do
    command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
  done
  if [[ "$action" == --remove ]]; then
    echo 'Remove the "SwitchNest Hotspot Toggle" widget from the panel first.'
    runuser -u "$target_user" -- kpackagetool6 --type Plasma/Applet --remove "$PLUGIN" || true
    rm -f -- "$ROOT_HELPER" "$POLKIT_RULE" "$OWNER_FILE"
    if [[ -f "$user_data/installed-marker" ]] && grep -Fxq 'steamdeck-switch2-plasma67-panel-toggle-v2' "$user_data/installed-marker"; then
      rm -f -- "$user_data/launch.py" "$user_data/status.sh" "$user_data/installed-marker"
      rmdir "$user_data" 2>/dev/null || true
    fi
    echo 'Panel add-on removed. The v7 hotspot remains installed and unchanged.'
    return
  fi
  [[ -d /etc/polkit-1/rules.d ]] || { echo 'Polkit rules directory missing.' >&2; exit 1; }
  for trusted in /etc/steamdeck-switch2 /etc/steamdeck-switch2/manager.sh /etc/steamdeck-switch2/settings.sh; do
    [[ -e "$trusted" && ! -L "$trusted" && $(stat -c %u "$trusted") == 0 ]] || {
      echo 'Install the working v7 hotspot first; root-owned manager/settings required.' >&2; exit 1;
    }
    mode=$(stat -c %a "$trusted")
    (( (8#$mode & 0022) == 0 )) || { echo 'Hotspot files must not be group/other writable.' >&2; exit 1; }
  done
  systemctl cat steamdeck-switch2-hotspot.service >/dev/null || { echo 'v7 hotspot service missing.' >&2; exit 1; }
  systemctl cat steamdeck-switch2-http.service >/dev/null || { echo 'v7 Pico HTTP service missing.' >&2; exit 1; }
  local uuid
  uuid=$(nmcli -g connection.uuid connection show 'SteamDeck-Switch2' 2>/dev/null || true)
  [[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || { echo 'Saved v7 hotspot profile not found.' >&2; exit 1; }
  dir=$(mktemp -d /tmp/steamdeck-panel-toggle.XXXXXX)
  trap 'rm -rf -- "$dir"' EXIT
  chmod 755 "$dir"
  write_payloads "$dir"
  chmod 755 "$dir/root-helper" "$dir/launch.py" "$dir/status.sh"
  chmod 755 "$dir/package" "$dir/package/contents" "$dir/package/contents/ui"
  chmod 644 "$dir/package/metadata.json" "$dir/package/contents/ui/main.qml"
  # Generate QML command literals using JSON escaping and POSIX shell quoting.
  python3 - "$dir/package/contents/ui/main.qml" "$user_data/status.sh" "$user_data/launch.py" <<'QML_PATHS'
from pathlib import Path
import json, shlex, sys
p = Path(sys.argv[1]); content = p.read_text()
status_cmd = shlex.quote(sys.argv[2])
action_cmd = '/usr/bin/python3 ' + shlex.quote(sys.argv[3])
content = content.replace('STATUS_COMMAND_PLACEHOLDER', json.dumps(status_cmd))
content = content.replace('ACTION_COMMAND_PLACEHOLDER', json.dumps(action_cmd))
p.write_text(content)
QML_PATHS
  python3 -m json.tool "$dir/package/metadata.json" >/dev/null
  python3 -m py_compile "$dir/launch.py"
  # Install the fixed root helper and the narrowly scoped policy authorization.
  install -m 755 "$dir/root-helper" "$ROOT_HELPER"
  python3 - "$target_user" "$POLKIT_RULE" "$ROOT_HELPER" <<'POLKIT_CODE'
from pathlib import Path
import json,sys
owner, path, helper = sys.argv[1:]
rule = '''// Allow only the active local desktop user to toggle this fixed v7 hotspot helper.
polkit.addRule(function(action, subject) {
    if (action.id === "org.freedesktop.policykit.exec" &&
        action.lookup("program") === HELPER &&
        action.lookup("user") === "root" &&
        subject.user === OWNER && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
'''.replace('OWNER', json.dumps(owner)).replace('HELPER',json.dumps(helper))
p = Path(path); p.write_text(rule); p.chmod(0o644)
POLKIT_CODE
  install -d -o "$target_user" -g "$(id -gn "$target_user")" -m 700 "$user_data"
  install -o "$target_user" -g "$(id -gn "$target_user")" -m 700 "$dir/launch.py" "$user_data/launch.py"
  install -o "$target_user" -g "$(id -gn "$target_user")" -m 700 "$dir/status.sh" "$user_data/status.sh"
  printf '%s\n' 'steamdeck-switch2-plasma67-panel-toggle-v2' > "$user_data/installed-marker"
  chown "$target_user:$(id -gn "$target_user")" "$user_data/installed-marker"
  printf '%s\n' "$target_user" > "$OWNER_FILE"
  chmod 600 "$OWNER_FILE"
  if [[ -d "$plugin_path" ]]; then
    runuser -u "$target_user" -- kpackagetool6 --type Plasma/Applet --upgrade "$dir/package"
  else
    runuser -u "$target_user" -- kpackagetool6 --type Plasma/Applet --install "$dir/package"
  fi
  echo
  echo 'Installed: SwitchNest Hotspot Toggle (Plasma 6.7 panel widget).'
  echo 'The original KDE Networks/Hotspot button was NOT modified.'
  echo 'Right-click the taskbar -> Enter Edit Mode -> Add Widgets.'
  echo 'Search for "SwitchNest Hotspot Toggle" and drag it onto the panel.'
  echo 'Click its icon: OFF -> v7 Option 2, ON -> v7 Option 3 (restore Wi-Fi).'
  echo 'If the widget is not listed, log out and back into Desktop Mode.'
  echo "To uninstall: sudo bash $0 --remove"
}
main "$@"
