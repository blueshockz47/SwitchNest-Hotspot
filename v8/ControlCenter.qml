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
    width: 1440
    height: 900
    minimumWidth: 900
    minimumHeight: 620
    title: "SwitchNest Control Center"
    Material.theme: Material.Dark
    Material.accent: Material.Teal
    color: "#10151e"
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
    property color muted: "#a6b9cc"
    property color accent: "#40c9b7"
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
        color: "#1d293a"
        radius: 6
        border.color: "#304053"
        Layout.fillWidth: true
    }
    component NavButton: Button {
        id: navEntry
        required property int page
        property int fileTab: -1
        property string navIcon: ""
        property bool selected: pages.currentIndex === page && (fileTab < 0 || fileTabs.currentIndex === fileTab)
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        flat: true
        leftPadding: 0
        rightPadding: 0
        contentItem: RowLayout {
            spacing: 12
            anchors.leftMargin: 14
            Label {
                text: navEntry.navIcon
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: navEntry.selected ? "#40c9b7" : "#d5e1f0"
                font.pixelSize: 16
            }
            Label {
                text: navEntry.text
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
                color: navEntry.selected ? "#40c9b7" : "#d5e1f0"
                font.pixelSize: 14
                font.bold: navEntry.selected
                elide: Text.ElideRight
            }
        }
        background: Rectangle {
            radius: 3
            color: parent.selected ? "#23364d" : parent.hovered ? "#1d2b3e" : "transparent"
            Rectangle {
                visible: navEntry.selected
                width: 3
                height: parent.height
                anchors.left: parent.left
                color: "#40c9b7"
            }
        }
        onClicked: {
            if (fileTab >= 0) fileTabs.currentIndex = fileTab
            pages.currentIndex = page
        }
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            clip: true
            Layout.minimumWidth: 194
            Layout.maximumWidth: 194
            Layout.preferredWidth: 194
            Layout.fillHeight: true
            color: "#131c2a"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 8
                    Image {
                        source: "assets/switchnest-logo.svg"
                        sourceSize.width: 32
                        sourceSize.height: 32
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        fillMode: Image.PreserveAspectFit
                    }
                    Label { text: "SwitchNest"; font.pixelSize: 22; font.bold: true; color: root.accent }
                }
                Label { text: "LINUX CONTROL CENTER"; font.pixelSize: 10; font.bold: true; color: "#93aac5"; Layout.bottomMargin: 14 }
                NavButton { text: "Overview"; navIcon: "⌂"; page: 0 }
                NavButton { text: "Homebrew"; navIcon: "◆"; page: 3; fileTab: 1 }
                NavButton { text: "FTP Manager"; navIcon: "▣"; page: 3; fileTab: 0 }
                NavButton { text: "Streaming"; navIcon: "◈"; page: 2 }
                NavButton { text: "Network"; navIcon: "◉"; page: 1 }
                NavButton { text: "Diagnostics"; navIcon: "☷"; page: 4 }
                NavButton { text: "Settings"; navIcon: "⚙"; page: 5 }
                NavButton { text: "Updates"; navIcon: "↻"; page: 6 }
                Item { Layout.fillHeight: true }
                Label { text: "● SwitchNest Linux v" + controller.version; font.pixelSize: 11; color: root.accent; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    visible: false
                    width: 5; height: 31; radius: 3
                    color: pages.currentIndex === 0 ? "#5eead4" : pages.currentIndex === 1 ? "#60a5fa" :
                           pages.currentIndex === 2 ? "#c084fc" : pages.currentIndex === 3 ? "#fbbf24" :
                           pages.currentIndex === 4 ? "#fb7185" : pages.currentIndex === 5 ? "#34d399" : "#a78bfa"
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Label { text: pages.currentIndex === 3 ? (fileTabs.currentIndex === 0 ? "FTP Manager" : "Homebrew") : ["Overview","Network","Streaming","Files","Diagnostics","Settings","Updates"][pages.currentIndex]; font.pixelSize: 28; font.bold: true; color: "#edf6ff" }
                Item { Layout.fillWidth: true }
                Button { text: "⟳ Refresh"; enabled: !root.busy; onClicked: controller.refresh() }
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
                        spacing: 12
                        Label { text: "Network overview"; font.pixelSize: 20; font.bold: true; color: "#f0f5ff" }
                        Label { text: "Your local Switch 2 connection and SteamOS background services"; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: readFirstContent.implicitHeight + 32
                            radius: 10
                            color: "#1d293a"
                            border.color: "#43556a"
                            border.width: 1
                            ColumnLayout {
                                id: readFirstContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label { text: "◆"; font.pixelSize: 21; color: "#f2bf69" }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label { text: "Before You Connect"; font.pixelSize: 18; font.bold: true; color: "#edf6ff" }
                                        Label { text: "Follow these 5 quick steps before using SwitchNest."; font.pixelSize: 12; color: "#a6b9cc"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#43556a" }
                                Repeater {
                                    model: [
                                        {symbol: "✈", heading: "1. Airplane Mode", detail: "Turn on Airplane Mode on your Switch 2."},
                                        {symbol: "▣", heading: "2. Start Services", detail: "Start the SwitchNest hotspot and make sure DNS and HTTP both show Active."},
                                        {symbol: "▤", heading: "3. Test With Your Phone", detail: "Connect to SwitchNest Wi-Fi and confirm you're offline."},
                                        {symbol: "◈", heading: "4. Connect Your Switch 2", detail: "Enable Wi-Fi, connect to SwitchNest, and disable IPv6 in its network settings."},
                                        {symbol: "⚠", heading: "5. Use at Your Own Risk!", detail: "An offline phone test does not guarantee complete network isolation."}
                                    ]
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 12
                                        Rectangle {
                                            Layout.preferredWidth: 38
                                            Layout.preferredHeight: 38
                                            radius: 8
                                            color: "#253346"
                                            Label {
                                                anchors.centerIn: parent
                                                text: modelData.symbol
                                                font.pixelSize: 20
                                                color: modelData.heading.indexOf("5.") === 0 ? "#f2bf69" : "#edf6ff"
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label { text: modelData.heading; font.pixelSize: 13; font.bold: true; color: "#edf6ff"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                            Label { text: modelData.detail; font.pixelSize: 12; color: "#a6b9cc"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                        }
                                    }
                                }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.width < 1180 ? 2 : 4
                            columnSpacing: 8
                            rowSpacing: 8
                            Repeater {
                                model: [
                                    {heading: "HOTSPOT", value: root.hotspot.state === "on" ? "ACTIVE" : root.hotspot.state === "off" ? "INACTIVE" : "UNKNOWN", ok: root.hotspot.state === "on"},
                                    {heading: "DNS", value: String(root.dns).toUpperCase(), ok: root.dns === "active"},
                                    {heading: "HTTP", value: String(root.http).toUpperCase(), ok: root.http === "active"}
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 130
                                    Layout.preferredHeight: 82
                                    color: "#1d293a"
                                    radius: 4
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 8
                                        Label { text: modelData.heading; font.pixelSize: 11; font.bold: true; color: "#a6b9cc" }
                                        Label { text: modelData.value; font.pixelSize: 16; font.bold: true; color: modelData.ok ? "#43f5b0" : (String(modelData.value).toLowerCase() === "inactive" || String(modelData.value).toLowerCase() === "failed" ? "#ff454f" : "#f2bf69"); elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            spacing: 8
                            Button {
                                text: root.hotspot.state === "on" ? "Stop hotspot" : "Start hotspot"
                                highlighted: true
                                enabled: !root.busy && (root.hotspot.state === "on" || root.hotspot.state === "off")
                                onClicked: controller.action(root.hotspot.state === "on" ? "off" : "on")
                            }
                            Button { text: "Refresh"; enabled: !root.busy; onClicked: controller.refresh() }
                            BusyIndicator { running: root.busy; visible: running; implicitWidth: 28; implicitHeight: 28 }
                        }
                        Label { text: "Hotspot: " + (root.hotspot.ssid || "SSID unavailable") + "  ·  Gateway: " + (root.hotspot.ip || "Unavailable") + "  ·  Security: " + (root.hotspot.security || "Unknown"); color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        Label { text: "Connected devices"; font.pixelSize: 20; font.bold: true; color: "#f0f5ff"; Layout.topMargin: 8 }
                        Label { text: "Only associated Wi-Fi stations are listed; association does not prove FTP connectivity."; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: stationsColumn.implicitHeight + 16
                            color: "#1d293a"
                            radius: 4
                            ColumnLayout {
                                id: stationsColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 4
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    color: "#24364c"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        Label { text: "IP address"; Layout.fillWidth: true; Layout.preferredWidth: 1; font.bold: true; horizontalAlignment: Text.AlignLeft }
                                        Label { text: "MAC address"; Layout.fillWidth: true; Layout.preferredWidth: 1; font.bold: true; horizontalAlignment: Text.AlignLeft }
                                        Label { text: "Association"; Layout.fillWidth: true; Layout.preferredWidth: 1; font.bold: true; horizontalAlignment: Text.AlignLeft }
                                    }
                                }
                                Repeater {
                                    model: root.clients
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        color: index % 2 === 0 ? "#1d293a" : "#223248"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            Label { text: modelData.ip || "Unavailable"; Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft }
                                            Label { text: modelData.mac || "Unavailable"; Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft }
                                            Label { text: modelData.status || "Unknown"; Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft }
                                        }
                                    }
                                }
                                Label { visible: root.clients.length === 0; text: "No associated stations reported"; color: root.muted; Layout.margins: 12 }
                            }
                        }
                        Button { text: "Refresh devices"; enabled: !root.busy; onClicked: controller.refresh() }
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
                    Label { text: "Reminder: Sunshine and Moonlight are not included with SwitchNest. Install and configure them separately before using streaming. SwitchNest only provides controls for an existing Sunshine installation."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        visible: false
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
                        width: Math.min(parent.width, 960)
                        spacing: 14
                        Label { text: "Settings"; font.pixelSize: 22 }
                        Label { text: "Configure your hotspot, app preferences, and maintenance tools."; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    GroupBox {
                        title: "App preferences"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: 9
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
                        }
                    }
                    GroupBox {
                        title: "Hotspot Wi-Fi"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: 9
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: wifiStopWarning.implicitHeight + 24
                        radius: 6
                        color: root.hotspot.state === "on" ? "#422b20" : "#203344"
                        border.color: root.hotspot.state === "on" ? "#f59e0b" : "#436079"
                        Label {
                            id: wifiStopWarning
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            wrapMode: Text.Wrap
                            font.bold: true
                            color: root.hotspot.state === "on" ? "#fbbf24" : "#c8d7e7"
                            text: root.hotspot.state === "on"
                                  ? "⚠ Stop the hotspot before changing the Wi-Fi name (SSID), password, or channel. Apply is disabled while the hotspot is running."
                                  : "Before applying Wi-Fi changes, make sure the hotspot is stopped. Restart it after applying the new settings."
                        }
                    }
                    Label { text: "Current SSID: " + (root.hotspot.ssid || "Unavailable"); color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    TextField { placeholderText: "Wi-Fi name (SSID)"; text: root.wifiName; onTextEdited: root.wifiName = text; Layout.fillWidth: true; maximumLength: 32 }
                    TextField { placeholderText: "New WPA2 password (leave blank to keep current)"; text: root.wifiPassword; echoMode: TextInput.Password; onTextEdited: root.wifiPassword = text; Layout.fillWidth: true }
                    Label { text: "2.4 GHz Wi-Fi channel"; color: root.muted }
                    ComboBox {
                        id: wifiChannelChoice
                        Layout.preferredWidth: 190
                        implicitWidth: 190
                        model: ["Channel 1", "Channel 6", "Channel 11"]
                        currentIndex: root.wifiChannel === 6 ? 1 : root.wifiChannel === 11 ? 2 : 0
                        displayText: "Channel " + (root.wifiChannel === 6 || root.wifiChannel === 11 ? root.wifiChannel : 1)
                        onActivated: root.wifiChannel = [1, 6, 11][currentIndex]
                    }
                    Button { text: "Apply Wi-Fi Settings"; highlighted: true; enabled: !root.busy && root.hotspot.state === "off" && root.wifiName.length > 0; onClicked: wifiConfirmDialog.open() }
                    Label { text: root.wifiFeedback; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Label { text: "Adapter AP support: " + (root.wifiInfo.adapter ? String(root.wifiInfo.adapter.ap_supported) : "Not checked") + " | Supported channels reported: " + (root.wifiInfo.adapter ? root.wifiInfo.adapter.channels.join(", ") : "Unknown"); Layout.fillWidth: true; wrapMode: Text.Wrap; color: root.muted }
                    Button { text: "Check Compatibility"; enabled: !root.busy; onClicked: controller.wifi_status() }
                    Label { text: "Only Wi-Fi profile fields are changed. IP, DHCP, DNS, firewall, FTP and the existing hotspot ON/OFF backend are untouched. NetworkManager authorization is required. Restart the hotspot with its existing controls after changes."; color: root.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        }
                    }
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
                    GroupBox {
                        title: "Update preferences"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: 9
                            CheckBox { text: "Check for updates at startup"; checked: root.updatePrefs.check_at_startup; onToggled: controller.set_update_preference("check_at_startup", checked) }
                            CheckBox { text: "Show update available popup"; checked: root.updatePrefs.show_update_popup; onToggled: controller.set_update_preference("show_update_popup", checked) }
                            CheckBox { text: "Stable releases only for startup checks"; checked: root.updatePrefs.stable_only; onToggled: controller.set_update_preference("stable_only", checked) }
                        }
                    }
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
