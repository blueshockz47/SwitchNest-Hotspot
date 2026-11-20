import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    // Defer the window-state request until the native window is mapped by KDE/KWin.
    Timer {
        id: startupMaximize
        interval: 250
        repeat: false
        onTriggered: {
            if (root.updatePrefs.fullscreen_on_start)
                root.showMaximized()
        }
    }
    Component.onCompleted: {
        if (root.updatePrefs.fullscreen_on_start)
            startupMaximize.start()
    }
    width: 960
    height: 620
    minimumWidth: 620
    minimumHeight: 480
    title: "SwitchNest Control Center"
    Material.theme: Material.Dark
    Material.accent: Material.Teal
    color: "#11151c"
    property var report: ({})
    property bool busy: false
    property bool updateBusy: false
    property string updateStatus: "Checking for published GitHub releases..."
    property string notice: "Waiting for diagnostics"
    property string activityLog: "Waiting for activity...\n"
    property bool updateInProgress: false
    property string availableVersion: ""
    property var updatePrefs: controller ? JSON.parse(controller.updatePreferences) : ({fullscreen_on_start: false})
    property var wifiInfo: ({})
    property string wifiName: ""
    property string wifiPassword: ""
    property int wifiChannel: 1
    property string presetName: ""
    property var wifiPresetMap: ({})
    property var wifiEventsList: []
    property var wifiHealthInfo: ({state: "unknown", issues: []})
    property string wifiRestartMessage: ""
    property var selfTestInfo: ({checks: [], state: "not run"})
    property string wifiFeedback: "Select Check Compatibility to inspect the existing hotspot profile."
    property string updateStage: "idle"
    property real downloadPercent: -1
    property real downloadedMB: 0
    property real totalMB: 0
    property var clients: root.hotspot.clients || []
    property var hotspot: report.hotspot || ({state: "unknown"})
    property string http: report.http_service ? report.http_service.output : "Unknown"
    property string dns: report.dns_service ? report.dns_service.output : "Unknown"
    property color muted: "#98a5b5"
    property color accent: "#52e0ae"
    Connections {
        target: controller
        function onRefreshed(raw) {
            try { root.report = JSON.parse(raw) }
            catch (e) { root.notice = "Invalid diagnostics response" }
        }
        function onMessage(message) { root.notice = message; root.activityLog += message + "\n" }
        function onUpdateLog(chunk) { root.activityLog += chunk }
        function onWifiStatus(raw) {
            try {
                root.wifiInfo = JSON.parse(raw)
                if (root.wifiInfo.ssid) root.wifiName = root.wifiInfo.ssid
                if (root.wifiInfo.channel) root.wifiChannel = Number(root.wifiInfo.channel)
                root.wifiFeedback = root.wifiInfo.error || "Profile information loaded. Verify the adapter before applying."
            } catch (e) { root.wifiFeedback = "Unable to read Wi-Fi profile" }
        }
        function onWifiRestartSuggested() { wifiRestartDialog.open() }
        function onWifiRestartProgress(message) { root.wifiRestartMessage = message; root.activityLog += message + "\\n" }
        function onWifiPresets(raw) {
            try { root.wifiPresetMap = JSON.parse(raw) } catch(e) { root.wifiPresetMap = ({}) }
        }
        function onNetworkEvents(raw) {
            try { root.wifiEventsList = JSON.parse(raw) } catch(e) { root.wifiEventsList = [] }
        }
        function onSelfTestResult(raw) {
            try { root.selfTestInfo = JSON.parse(raw) }
            catch(e) { root.selfTestInfo = ({checks: [], state: "unavailable"}) }
        }
        function onWifiHealth(raw) {
            try { root.wifiHealthInfo = JSON.parse(raw) } catch(e) { root.wifiHealthInfo = ({state: "unknown", issues: []}) }
        }
        function onWifiResult(raw) {
            try {
                var result = JSON.parse(raw)
                root.wifiPassword = ""
                root.wifiFeedback = result.message || result.error || "Unknown result"
                Qt.callLater(function() { controller.wifi_status(); controller.wifi_events() })
            } catch (e) { root.wifiFeedback = "Invalid Wi-Fi response" }
        }
        function onPreferencesChanged() { root.updatePrefs = JSON.parse(controller.updatePreferences) }
        function onRollbackCompleted() { restartDialog.open() }
        function onUpdateProgress(raw) {
            try {
                var p = JSON.parse(raw)
                root.updateStage = p.stage || "unknown"
                if (p.stage === "download") {
                    root.downloadedMB = (p.bytes || 0) / 1048576
                    root.totalMB = p.total ? p.total / 1048576 : 0
                    root.downloadPercent = p.total ? Math.min(100, 100 * p.bytes / p.total) : -1
                }
            } catch (e) { root.activityLog += "Progress report unavailable\\n" }
        }
        function onUpdateAvailable(version) { root.availableVersion = version; updateAvailableDialog.open() }
        function onUpdateInstalled(version) { root.updateInProgress = false; restartDialog.open() }
        function onBusyChanged(value) { root.busy = value; if (!value && root.updateInProgress && root.updateStage !== "idle") root.updateInProgress = false }
        function onUpdateBusy(value) { root.updateBusy = value }
        function onUpdateResult(value) { root.updateStatus = value }
    }
    Dialog {
        id: updateAvailableDialog
        title: "SwitchNest update available"
        modal: true
        anchors.centerIn: parent
        width: Math.min(470, root.width - 50)
        implicitHeight: 230
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            spacing: 12
            Label {
                text: "A new SwitchNest version (" + root.availableVersion + ") is available. Would you like to install it now?"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Later"; onClicked: updateAvailableDialog.close() }
                Button { text: "View on GitHub"; onClicked: { controller.download_update(); updateAvailableDialog.close() } }
                Button {
                    text: "Download & Install"
                    highlighted: true
                    enabled: !root.busy && !root.updateBusy
                    onClicked: {
                        updateAvailableDialog.close()
                        pages.currentIndex = 6
                        root.activityLog = "Preparing update...\n"
                        root.updateInProgress = true
                        root.updateStage = "download"
                        controller.install_update()
                    }
                }
            }
        }
    }
    Dialog {
        id: restartDialog
        title: "Restart SwitchNest"
        modal: true
        anchors.centerIn: parent
        width: Math.min(460, root.width - 50)
        implicitHeight: 190
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            spacing: 14
            Label {
                text: "The version change completed successfully. Restart SwitchNest to use the selected version."
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Later"; onClicked: restartDialog.close() }
                Button { text: "Restart SwitchNest"; highlighted: true; onClicked: controller.restart_after_update() }
            }
        }
    }
    Dialog {
        id: wifiRestartDialog
        title: "Wi-Fi settings saved — restart hotspot?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(480, root.width - 40)
        implicitHeight: 230
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            Label { text: "The saved SSID or Wi-Fi settings will take effect when the hotspot is restarted. This disconnects your Switch 2. SwitchNest will use the existing v7.1 OFF/ON helper and verify the result. If the restart fails, it will attempt one recovery using the previous profile."; Layout.fillWidth: true; wrapMode: Text.Wrap }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Later"; onClicked: wifiRestartDialog.close() }
                Button { text: "Restart Hotspot"; highlighted: true; onClicked: { wifiRestartDialog.close(); controller.wifi_restart() } }
            }
        }
    }
    Dialog {
        id: wifiConfirmDialog
        title: "Apply Wi-Fi changes?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(470, root.width - 40)
        implicitHeight: 210
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            Label { text: "The Wi-Fi name, password or channel may change. Existing clients may disconnect when the hotspot is restarted using its normal controls. A backup will be saved before applying."; Layout.fillWidth: true; wrapMode: Text.Wrap }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Cancel"; onClicked: wifiConfirmDialog.close() }
                Button { text: "Apply Profile"; highlighted: true; onClicked: { wifiConfirmDialog.close(); controller.wifi_apply(root.wifiName, root.wifiPassword, root.wifiChannel) } }
            }
        }
    }
    Dialog {
        id: wifiRestoreDialog
        title: "Restore previous Wi-Fi settings?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, root.width - 40)
        implicitHeight: 190
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            Label { text: "Restore the backed-up Wi-Fi name, channel and WPA2 password. Restart the hotspot afterward."; Layout.fillWidth: true; wrapMode: Text.Wrap }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Cancel"; onClicked: wifiRestoreDialog.close() }
                Button { text: "Restore"; highlighted: true; onClicked: { wifiRestoreDialog.close(); controller.wifi_restore() } }
            }
        }
    }
    Dialog {
        id: rollbackDialog
        title: "Restore previous version?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, root.width - 50)
        implicitHeight: 200
        standardButtons: Dialog.NoButton
        ColumnLayout {
            width: parent.width
            Label { text: "SwitchNest will restore the previous installed version. Restart is required."; wrapMode: Text.Wrap; Layout.fillWidth: true }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button { text: "Cancel"; onClicked: rollbackDialog.close() }
                Button { text: "Restore Previous Version"; highlighted: true; onClicked: { rollbackDialog.close(); controller.rollback_update() } }
            }
        }
    }
    component Panel: Rectangle {
        color: "#1b222d"
        radius: 14
        border.color: "#303b49"
        Layout.fillWidth: true
    }
    component NavButton: Button {
        required property int page
        Layout.fillWidth: true
        flat: pages.currentIndex !== page
        highlighted: pages.currentIndex === page
        onClicked: pages.currentIndex = page
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            color: "#161c25"
            Layout.preferredWidth: root.width < 800 ? 145 : 190
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                Label { text: "◉  SwitchNest"; font.pixelSize: root.width < 800 ? 17 : 23; font.bold: true; color: root.accent }
                Label { text: "CONTROL CENTER"; font.pixelSize: 11; color: root.muted }
                Item { Layout.preferredHeight: 20 }
                NavButton { text: "Overview"; page: 0 }
                NavButton { text: "Network"; page: 1 }
                NavButton { text: "Streaming"; page: 2 }
                NavButton { text: "Files"; page: 3 }
                NavButton { text: "Diagnostics"; page: 4 }
                NavButton { text: "Settings"; page: 5 }
                NavButton { text: root.updateStatus.startsWith("Update available") ? "Updates •" : "Updates"; page: 6 }
                Item { Layout.fillHeight: true }
                Label { text: "v" + controller.version; color: root.accent }
                Label { text: "Linux stable"; color: root.muted; font.pixelSize: 12 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.width < 800 ? 12 : 22
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Label { text: ["Overview","Network","Streaming","Files","Diagnostics","Settings","Updates"][pages.currentIndex]; font.pixelSize: 28; font.bold: true }
                Item { Layout.fillWidth: true }
                Button { text: "Refresh"; enabled: !root.busy; onClicked: controller.refresh() }
            }
            StackLayout {
                id: pages
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollView {
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        spacing: 8
                        Panel {
                            implicitHeight: hotspotLayout.implicitHeight + 32
                            ColumnLayout {
                                id: hotspotLayout
                                anchors.fill: parent
                                anchors.margins: 16
                                Label { text: "OFFLINE HOTSPOT"; color: root.muted; font.pixelSize: 12 }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: root.hotspot.state === "on" ? "Hotspot Active" : root.hotspot.state === "off" ? "Hotspot Inactive" : "Status unknown"; font.pixelSize: root.width < 800 ? 18 : 25; font.bold: true; color: root.hotspot.state === "on" ? root.accent : root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                    Button { text: root.hotspot.state === "on" ? "Turn OFF" : "Turn ON"; highlighted: root.hotspot.state !== "on"; enabled: !root.busy && (root.hotspot.state === "on" || root.hotspot.state === "off"); onClicked: controller.action(root.hotspot.state === "on" ? "off" : "on") }
                                    BusyIndicator { running: root.busy; visible: running; implicitWidth: 30; implicitHeight: 30 }
                                }
                                Label { text: "v7.1 backend"; color: root.muted }
                                Label { text: "Gateway: " + (root.hotspot.ip || "Unavailable"); color: root.muted }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Panel {
                                implicitHeight: 76
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14
                                    Label { text: "DNS SERVICE"; color: root.muted; font.pixelSize: 12 }
                                    Label { text: root.dns; color: root.dns === "active" ? root.accent : root.muted; font.pixelSize: 18; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            Panel {
                                implicitHeight: 76
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14
                                    Label { text: "ISOLATION"; color: root.muted; font.pixelSize: 12 }
                                    Label { text: "Unverified"; font.pixelSize: 18; color: "#f2bf69" }
                                }
                            }
                        }
                        Panel {
                            implicitHeight: networkInfo.implicitHeight + 28
                            ColumnLayout {
                                id: networkInfo
                                anchors.fill: parent; anchors.margins: 14
                                Label { text: "Network information"; font.bold: true }
                                Label { text: "SSID: " + (root.hotspot.ssid || "Unavailable"); Layout.fillWidth: true; wrapMode: Text.Wrap }
                                Label { text: "Host IPv4: " + (root.hotspot.ip || "Unavailable"); Layout.fillWidth: true; wrapMode: Text.Wrap }
                                Label { text: "Security: " + (root.hotspot.security || "Unavailable"); Layout.fillWidth: true; wrapMode: Text.Wrap }
                                Label { text: "HTTP service: " + root.http; color: root.http === "active" ? root.accent : root.muted }
                                Label { text: "DNS: " + root.dns; color: root.dns === "active" ? root.accent : root.muted }
                                Label { text: "Connection health: " + (root.hotspot.state === "on" && root.dns === "active" ? "Hotspot and DNS active (isolation unverified)" : "Requires attention"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                            }
                        }
                        Panel {
                            implicitHeight: clientsInfo.implicitHeight + 28
                            ColumnLayout {
                                id: clientsInfo
                                anchors.fill: parent; anchors.margins: 14
                                Label { text: "Connected Wi-Fi stations"; font.bold: true }
                                Label { text: Array.isArray(root.hotspot.stations) ? String(root.hotspot.stations.length) + " associated stations" : "Station count unavailable"; color: root.accent }
                                Repeater {
                                    model: root.clients
                                    delegate: Label {
                                        required property var modelData
                                        text: modelData.mac + "  •  " + (modelData.ip || "IP unavailable") + "  •  " + modelData.status + (modelData.signal !== undefined ? "  •  " + modelData.signal + " dBm" : "") + (modelData.connected_seconds !== undefined ? "  •  " + modelData.connected_seconds + "s" : "") + (modelData.rx_bytes !== undefined ? "  •  RX " + modelData.rx_bytes + " B" : "") + (modelData.tx_bytes !== undefined ? "  •  TX " + modelData.tx_bytes + " B" : "")
                                        color: root.muted
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                                Button { text: "Refresh clients"; enabled: !root.busy; onClicked: controller.refresh() }
                            }
                        }
                        Panel {
                            implicitHeight: 90
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 14
                                Label { text: "Network profiles"; font.bold: true }
                                Label { text: "Offline backend available • Filtered Internet pending"; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            }
                        }
                    }
                }
                ColumnLayout {
                    Label { text: "Network profiles"; font.pixelSize: 22 }
                    Label { text: "Offline uses the installed v7.1 backend. Isolation is not independently verified."; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Button { text: "Filtered Internet — unavailable"; enabled: false }
                    Label { text: "Active connections"; font.bold: true }
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        TextArea { readOnly: true; text: root.report.active_connections ? root.report.active_connections.output : "Waiting for diagnostics"; wrapMode: TextEdit.Wrap }
                    }
                }
                ColumnLayout {
                    Label { text: "Sunshine / Moonlight"; font.pixelSize: 22 }
                    Label { text: !root.report.sunshine_installed ? "Checking installation" : !root.report.sunshine_installed.ok ? "Flatpak installation unavailable" : root.report.sunshine_processes && root.report.sunshine_processes.ok ? (root.report.sunshine_processes.output.indexOf("dev.lizardbyte.app.Sunshine") >= 0 ? "Sunshine running" : "Sunshine stopped") : "Process state unavailable"; color: root.accent; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    RowLayout {
                        Button { text: "Start"; enabled: !root.busy; onClicked: controller.sunshine("start") }
                        Button { text: "Stop"; enabled: !root.busy; onClicked: controller.sunshine("stop") }
                    }
                    Button { text: "Open Sunshine web UI"; onClicked: controller.sunshine_web() }
                    Label { text: "Stopping Sunshine disconnects existing streams."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
                ColumnLayout {
                    TabBar {
                        id: fileTabs
                        Layout.fillWidth: true
                        TabButton {
                            text: "FTP File Manager"
                            contentItem: Label {
                                text: "FTP File Manager"
                                color: "#22c55e"
                                font.bold: true
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        TabButton {
                            text: "Homebrew Manager"
                            contentItem: Item {
                                implicitWidth: homebrewTitle.implicitWidth
                                implicitHeight: homebrewTitle.implicitHeight
                                Row {
                                    id: homebrewTitle
                                    anchors.centerIn: parent
                                    spacing: 0
                                    Label { text: "Home"; color: "#ef4444"; font.bold: true; font.pixelSize: 16 }
                                    Label { text: "brew"; color: "#3b82f6"; font.bold: true; font.pixelSize: 16 }
                                    Label { text: " Manager"; color: "#facc15"; font.bold: true; font.pixelSize: 16 }
                                }
                            }
                        }
                    }
                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: fileTabs.currentIndex
                        FtpPage {}
                        HomebrewPage {}
                    }
                }
                ColumnLayout {
                    RowLayout {
                        Label { text: "Live diagnostics (10-second refresh)"; font.pixelSize: 20 }
                        Item { Layout.fillWidth: true }
                        Button { text: "Copy Diagnostics"; onClicked: controller.copy_diagnostics() }
                    }
                    RowLayout {
                        Label { text: "Hotspot: " + root.hotspot.state; color: root.accent }
                        Label { text: "DNS: " + root.dns; color: root.accent }
                        Label { text: "Clients: " + root.clients.length; color: root.accent }
                    }
                    Label { text: "Health: " + root.wifiHealthInfo.state; color: root.wifiHealthInfo.state === "healthy" ? root.accent : "#f2bf69" }
                    Label { text: root.wifiHealthInfo.issues.join("; ") || "No service alerts (isolation remains unverified)"; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Button { text: "Refresh Health"; enabled: !root.busy; onClicked: controller.refresh() }
                    Label { text: "Isolation: unverified; active services do not prove traffic is blocked."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        TextArea { readOnly: true; text: JSON.stringify(root.report, null, 2); wrapMode: TextEdit.Wrap; selectByMouse: true }
                    }
                }
                ScrollView {
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        Label { text: "Settings"; font.pixelSize: 22 }
                    CheckBox {
                        id: launchAtLogin
                        text: "Start SwitchNest on desktop login"
                        checked: controller ? controller.startOnLogin : false
                        onToggled: controller.set_autostart(checked)
                        Connections {
                            target: controller
                            function onAutostartChanged() { launchAtLogin.checked = controller.startOnLogin }
                        }
                    }
                    Label { text: "Launches the app in Desktop Mode, not the hotspot. Gaming Mode is not supported."; wrapMode: Text.Wrap; Layout.fillWidth: true; color: root.muted }
                    CheckBox { text: "Launch SwitchNest maximized"; checked: root.updatePrefs.fullscreen_on_start; onToggled: controller.set_update_preference("fullscreen_on_start", checked) }
                    Label { text: "Applies on next launch. The title bar, minimize, restore, and close controls remain available."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Wi-Fi configuration (existing NetworkManager AP profile)"; font.bold: true }
                    Label { text: "Current SSID: " + (root.hotspot.ssid || "Unavailable"); color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    TextField { placeholderText: "Wi-Fi name (SSID)"; text: root.wifiName; onTextEdited: root.wifiName = text; Layout.fillWidth: true; maximumLength: 32 }
                    TextField { placeholderText: "New WPA2 password (leave blank to keep current)"; text: root.wifiPassword; echoMode: TextInput.Password; onTextEdited: root.wifiPassword = text; Layout.fillWidth: true }
                    Label { text: "2.4 GHz Wi-Fi channel"; color: root.muted }
                    ComboBox {
                        id: wifiChannelChoice
                        model: ["Channel 1", "Channel 6", "Channel 11"]
                        currentIndex: root.wifiChannel === 6 ? 1 : root.wifiChannel === 11 ? 2 : 0
                        onActivated: root.wifiChannel = [1, 6, 11][currentIndex]
                    }
                    Label { text: root.wifiFeedback; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Label { text: "Adapter AP support: " + (root.wifiInfo.adapter ? String(root.wifiInfo.adapter.ap_supported) : "Not checked") + " | Supported channels reported: " + (root.wifiInfo.adapter ? root.wifiInfo.adapter.channels.join(", ") : "Unknown"); Layout.fillWidth: true; wrapMode: Text.Wrap; color: root.muted }
                    RowLayout {
                        Button { text: "Check Compatibility"; enabled: !root.busy; onClicked: controller.wifi_status() }
                        Button { text: "Apply Wi-Fi Settings"; highlighted: true; enabled: !root.busy && root.wifiName.length > 0; onClicked: wifiConfirmDialog.open() }
                    }
                    Button { text: "Restore Previous Wi-Fi Settings"; enabled: !root.busy && root.wifiInfo.backup === true; onClicked: wifiRestoreDialog.open() }
                    Label { text: "Only Wi-Fi profile fields are changed. IP, DHCP, DNS, firewall, FTP and the existing hotspot ON/OFF backend are untouched. NetworkManager authorization is required. Restart the hotspot with its existing controls after changes."; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Label { text: "Hotspot restart and recovery"; font.bold: true }
                    Label { text: root.wifiRestartMessage || "After changing SSID, restart the hotspot to activate it."; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    RowLayout {
                        Button { text: "Restart Hotspot"; enabled: !root.busy; onClicked: wifiRestartDialog.open() }
                        Button { text: "Restart SwitchNest"; enabled: !root.busy; onClicked: controller.restart_control_center() }
                    }
                    Label { text: "Wi-Fi presets (SSID + channel only; no passwords)"; font.bold: true }
                    TextField { placeholderText: "Preset name"; text: root.presetName; onTextEdited: root.presetName = text; Layout.fillWidth: true }
                    RowLayout {
                        Button { text: "Save Preset"; onClicked: controller.wifi_save_preset(root.presetName, root.wifiName, root.wifiChannel) }
                        Button { text: "Refresh Presets"; onClicked: controller.wifi_presets() }
                    }
                    ComboBox {
                        id: presetChoice
                        Layout.fillWidth: true
                        model: Object.keys(root.wifiPresetMap)
                        onActivated: controller.wifi_select_preset(currentText)
                    }
                    Label { text: "v8.0.9 Stability & Recovery"; font.bold: true }
                    Label { text: "Recovery: one attempt after a failed confirmed restart; 120-second cooldown. Client disconnects do not trigger recovery."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    RowLayout {
                        Button { text: "Run Self-Test"; enabled: !root.busy; onClicked: controller.run_self_test() }
                        Button { text: "Export Redacted Report"; enabled: !root.busy; onClicked: controller.export_diagnostics() }
                    }
                    Label { text: "Self-test: " + root.selfTestInfo.state; color: root.accent }
                    Repeater {
                        model: root.selfTestInfo.checks || []
                        delegate: Label {
                            required property var modelData
                            text: modelData.label + ": " + modelData.result + (modelData.reason ? " — " + modelData.reason : "")
                            color: root.muted
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                    RowLayout {
                        Button { text: "Verify App"; enabled: !root.busy; onClicked: controller.verify_application() }
                        Button { text: "Repair App Launcher"; enabled: !root.busy; onClicked: controller.repair_application() }
                    }
                    Label { text: "Self-test is read-only and cannot certify isolation or FTP reachability. Repair changes only the SwitchNest launcher."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Network event history (most recent 100 events)"; font.bold: true }
                    Button { text: "Refresh Events"; onClicked: controller.wifi_events() }
                    Repeater {
                        model: root.wifiEventsList.slice(-12).reverse()
                        delegate: Label {
                            required property var modelData
                            text: modelData.time + "  " + modelData.event + "  " + modelData.detail
                            color: root.muted
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                    Label { text: "Advanced v7.1 manager (legacy)"; color: root.muted }
                    Button { text: "Change Wi-Fi password"; enabled: !root.busy; onClicked: controller.wifi_settings() }
                    Label { text: "Use the legacy manager only when the profile editor is unavailable."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Refresh interval: 10 seconds"; color: root.muted }
                    Label { text: "Update notifications"; font.bold: true }
                    CheckBox { text: "Check for updates at startup"; checked: root.updatePrefs.check_at_startup; onToggled: controller.set_update_preference("check_at_startup", checked) }
                    CheckBox { text: "Show update available popup"; checked: root.updatePrefs.show_update_popup; onToggled: controller.set_update_preference("show_update_popup", checked) }
                    CheckBox { text: "Stable releases only for startup checks"; checked: root.updatePrefs.stable_only; onToggled: controller.set_update_preference("stable_only", checked) }
                    Item { Layout.fillHeight: true }
                    }
                }
                ColumnLayout {
                    Label { text: "Software updates"; font.pixelSize: 22 }
                    Label { text: "Installed: v" + controller.version; color: root.accent }
                    ComboBox { id: channel; model: ["Stable", "Development"]; enabled: !root.updateBusy }
                    Label { text: root.updateStatus; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Button { text: root.updateBusy ? "Checking..." : "Check for Updates"; enabled: !root.updateBusy; onClicked: controller.check_updates(channel.currentIndex===0?"stable":"development") }
                    Button { text: "Download & Install Update"; highlighted: true; visible: root.updateStatus.startsWith("Update available: ") && channel.currentIndex === 0; enabled: !root.updateBusy && !root.busy; onClicked: { root.activityLog = "Preparing update...\n"; root.updateInProgress = true; root.updateStage = "download"; controller.install_update() } }
                    Button { text: "View Update on GitHub"; visible: root.updateStatus.startsWith("Update available: "); onClicked: controller.download_update() }
                    Label { text: "Stage: " + root.updateStage; color: root.muted }
                    ProgressBar { Layout.fillWidth: true; visible: root.updateInProgress && root.updateStage === "download"; from: 0; to: 100; value: root.downloadPercent < 0 ? 0 : root.downloadPercent; indeterminate: root.downloadPercent < 0 }
                    Label { visible: root.updateInProgress && root.updateStage === "download"; text: root.downloadedMB.toFixed(1) + " MB" + (root.totalMB > 0 ? " / " + root.totalMB.toFixed(1) + " MB (" + root.downloadPercent.toFixed(0) + "%)" : " downloaded"); color: root.muted }
                    Button { text: "Restore Previous Version"; enabled: !root.busy && !root.updateBusy && controller && controller.rollbackAvailable; onClicked: rollbackDialog.open() }
                    Button { text: "Open GitHub releases"; onClicked: controller.open_updates(false) }
                    Button { text: "Open development downloads"; onClicked: controller.open_updates(true) }
                    Label { text: "Private repository: sign in using GitHub CLI for automatic lookup, or use your browser. Download & Install uses a GitHub release ZIP with a published SHA-256 digest. It installs without sudo and keeps the previous version for rollback. Restart SwitchNest after installation."; wrapMode: Text.Wrap; Layout.fillWidth: true; color: root.muted }
                    Item { Layout.fillHeight: true }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 190
                color: "#1b222d"
                radius: 8
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    TextArea { text: root.activityLog; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: root.muted; font.pixelSize: 13 }
                }
            }
        }
    }
}
