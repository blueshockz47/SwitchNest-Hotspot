import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
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
    property string notice: "Waiting for diagnostics"
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
        function onMessage(message) { root.notice = message }
        function onBusyChanged(value) { root.busy = value }
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
                Item { Layout.fillHeight: true }
                Label { text: "v8.0-beta.2"; color: root.accent }
                Label { text: "Developer preview"; color: root.muted; font.pixelSize: 12 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.width < 800 ? 12 : 22
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Label { text: ["Overview","Network","Streaming","Files","Diagnostics","Settings"][pages.currentIndex]; font.pixelSize: 28; font.bold: true }
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
                            implicitHeight: 142
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                Label { text: "OFFLINE HOTSPOT"; color: root.muted; font.pixelSize: 12 }
                                Label { text: root.hotspot.state === "on" ? "Hotspot active" : root.hotspot.state === "off" ? "Hotspot off" : "Status unknown"; font.pixelSize: 25; font.bold: true; color: root.hotspot.state === "on" ? root.accent : root.muted }
                                Label { text: "v7.1 backend"; color: root.muted }
                                RowLayout {
                                    Button { text: root.hotspot.state === "on" ? "Turn OFF" : "Turn ON"; highlighted: root.hotspot.state !== "on"; enabled: !root.busy && (root.hotspot.state === "on" || root.hotspot.state === "off"); onClicked: controller.action(root.hotspot.state === "on" ? "off" : "on") }
                                    BusyIndicator { running: root.busy; visible: running; implicitWidth: 30; implicitHeight: 30 }
                                }
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
                                    model: root.hotspot.stations || []
                                    delegate: Label { required property string modelData; text: modelData; color: root.muted }
                                }
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
                FtpPage {}
                ScrollView {
                    TextArea { readOnly: true; text: JSON.stringify(root.report, null, 2); wrapMode: TextEdit.Wrap }
                }
                ColumnLayout {
                    Label { text: "Settings"; font.pixelSize: 22 }
                    Label { text: "Wi-Fi settings use the existing v7.1 manager."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Button { text: "Change Wi-Fi password"; enabled: !root.busy; onClicked: controller.wifi_settings() }
                    Label { text: "Select option 5 in Konsole. SSID changes are not supported in this preview."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Refresh interval: 10 seconds"; color: root.muted }
                    Item { Layout.fillHeight: true }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 65
                color: "#1b222d"
                radius: 8
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    TextArea { text: root.notice; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: root.muted; font.pixelSize: 13 }
                }
            }
        }
    }
}
