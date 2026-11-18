import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 850
    height: 600
    minimumWidth: 600
    minimumHeight: 420
    title: "SwitchNest Control Center"
    property var report: ({})
    property bool busy: false
    property string notice: "Waiting for diagnostics"
    Connections {
        target: controller
        function onRefreshed(raw) {
            try { root.report = JSON.parse(raw); root.notice = "Diagnostics refreshed" }
            catch (e) { root.notice = "Invalid diagnostics response" }
        }
        function onMessage(message) { root.notice = message }
        function onBusyChanged(value) { root.busy = value }
    }
    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20
        ColumnLayout {
            Layout.preferredWidth: 170
            Layout.fillHeight: true
            Label { text: "SwitchNest"; font.pixelSize: 24; font.bold: true }
            Label { text: "8.0-alpha.1" }
            Button { text: "Overview"; Layout.fillWidth: true; onClicked: pages.currentIndex = 0 }
            Button { text: "Diagnostics"; Layout.fillWidth: true; onClicked: pages.currentIndex = 1 }
            Item { Layout.fillHeight: true }
            Label { text: "Developer preview" }
        }
        StackLayout {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                Label { text: "Hotspot overview"; font.pixelSize: 24; font.bold: true }
                GroupBox {
                    title: "Hotspot controls"
                    Layout.fillWidth: true
                    ColumnLayout {
                        anchors.fill: parent
                        Label { text: "Installed v7.1 backend" }
                        RowLayout {
                            Button { text: "Hotspot ON"; enabled: !root.busy; onClicked: controller.action("on") }
                            Button { text: "Hotspot OFF"; enabled: !root.busy; onClicked: controller.action("off") }
                        }
                        Label { text: "DNS service: " + (root.report.dns_service ? root.report.dns_service.output : "Unknown"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
                GroupBox {
                    title: "Network profiles"
                    Layout.fillWidth: true
                    ColumnLayout {
                        anchors.fill: parent
                        Label { text: "Offline backend • isolation not verified"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Button { text: "Filtered Internet — not implemented"; enabled: false }
                    }
                }
                Label { text: root.notice; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Button { text: "Refresh status"; enabled: !root.busy; onClicked: controller.refresh() }
                Item { Layout.fillHeight: true }
            }
            ColumnLayout {
                Label { text: "Network diagnostics"; font.pixelSize: 24 }
                Button { text: "Refresh"; enabled: !root.busy; onClicked: controller.refresh() }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea { readOnly: true; text: JSON.stringify(root.report, null, 2); wrapMode: TextEdit.Wrap }
                }
            }
        }
    }
}
