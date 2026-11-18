import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 960
    height: 620
    minimumWidth: 700
    minimumHeight: 480
    title: "SwitchNest Control Center"
    Material.theme: Material.Dark
    Material.accent: Material.Teal
    color: "#11151c"
    property var report: ({})
    property bool busy: false
    property string notice: "Waiting for diagnostics"
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
            Layout.preferredWidth: 190
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                Label { text: "◉  SwitchNest"; font.pixelSize: 23; font.bold: true; color: root.accent }
                Label { text: "CONTROL CENTER"; font.pixelSize: 11; color: root.muted }
                Item { Layout.preferredHeight: 20 }
                NavButton { text: "Overview"; page: 0 }
                NavButton { text: "Network"; page: 1 }
                NavButton { text: "Streaming"; page: 2 }
                NavButton { text: "Files"; page: 3 }
                NavButton { text: "Diagnostics"; page: 4 }
                NavButton { text: "Settings"; page: 5 }
                Item { Layout.fillHeight: true }
                Label { text: "v8.0-alpha.2"; color: root.accent }
                Label { text: "Developer preview"; color: root.muted; font.pixelSize: 12 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 22
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
                        spacing: 12
                        Panel {
                            implicitHeight: 174
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                Label { text: "OFFLINE HOTSPOT"; color: root.muted; font.pixelSize: 12 }
                                Label { text: "SwitchNest network"; font.pixelSize: 25; font.bold: true }
                                Label { text: "Powered by your existing v7.1 installation"; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                RowLayout {
                                    Button { text: "Turn ON"; highlighted: true; enabled: !root.busy; onClicked: controller.action("on") }
                                    Button { text: "Turn OFF"; enabled: !root.busy; onClicked: controller.action("off") }
                                    BusyIndicator { running: root.busy; visible: running; implicitWidth: 30; implicitHeight: 30 }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Panel {
                                implicitHeight: 100
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14
                                    Label { text: "DNS SERVICE"; color: root.muted; font.pixelSize: 12 }
                                    Label { text: root.dns; color: root.dns === "active" ? root.accent : root.muted; font.pixelSize: 18; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            Panel {
                                implicitHeight: 100
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14
                                    Label { text: "ISOLATION"; color: root.muted; font.pixelSize: 12 }
                                    Label { text: "Unverified"; font.pixelSize: 18; color: "#f2bf69" }
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
                    Label { text: "Streaming management is planned for a later build."; color: root.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
                ColumnLayout {
                    Label { text: "File transfers"; font.pixelSize: 22 }
                    Label { text: "Local FTP integration is planned."; color: root.muted }
                    Item { Layout.fillHeight: true }
                }
                ScrollView {
                    TextArea { readOnly: true; text: JSON.stringify(root.report, null, 2); wrapMode: TextEdit.Wrap }
                }
                ColumnLayout {
                    Label { text: "Settings"; font.pixelSize: 22 }
                    Label { text: "Existing v7.1 settings are unchanged."; color: root.muted }
                    Label { text: "Refresh interval: 10 seconds"; color: root.muted }
                    Item { Layout.fillHeight: true }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 58
                color: "#1b222d"
                radius: 8
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    TextArea { text: root.notice; readOnly: true; wrapMode: TextEdit.Wrap; color: root.muted; font.pixelSize: 12 }
                }
            }
        }
    }
}
