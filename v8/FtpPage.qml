import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    property var dataState: JSON.parse(ftpBrowser.state)
    property string localSelected: ""
    property string remoteSelected: ""
    property string uploadName: ""
    Connections {
        target: ftpBrowser
        function onChanged() { page.dataState = JSON.parse(ftpBrowser.state) }
    }
    RowLayout {
        TextField { id: host; text: page.dataState.host; Layout.fillWidth: true; enabled: !page.dataState.busy }
        TextField { id: port; text: page.dataState.port; Layout.preferredWidth: 85; enabled: !page.dataState.busy }
        Button { text: "Connect"; enabled: !page.dataState.busy; onClicked: { page.remoteSelected=""; ftpBrowser.connect_to(host.text, port.text) } }
    }
    Label { text: "Local FTP • PASV • Unencrypted"; color: "#98a5b5" }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Label { text: "Local files"; font.bold: true }
            Label { text: page.dataState.local; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Button { text: "Up"; enabled: !page.dataState.busy; onClicked: { page.localSelected=""; ftpBrowser.local_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.dataState.localRows
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.directory ? "▸ " : "  ") + modelData.name
                    highlighted: page.localSelected === modelData.name
                    enabled: !page.dataState.busy
                    onClicked: { if (modelData.directory) { page.localSelected=""; ftpBrowser.local_open(modelData.name) } else page.localSelected=modelData.name }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Label { text: "Remote files"; font.bold: true }
            Label { text: page.dataState.remote; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Button { text: "Up"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.remoteSelected=""; ftpBrowser.remote_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.dataState.remoteRows
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.directory ? "▸ " : "  ") + modelData.name
                    highlighted: page.remoteSelected === modelData.name
                    enabled: !page.dataState.busy
                    onClicked: { if (modelData.directory) { page.remoteSelected=""; ftpBrowser.remote_open(modelData.name) } else page.remoteSelected=modelData.name }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
    RowLayout {
        Button { text: "Upload"; enabled: !page.dataState.busy && page.dataState.connected && page.localSelected !== ""; onClicked: { page.uploadName=page.localSelected; confirm.open() } }
        Button { text: "Download"; enabled: !page.dataState.busy && page.dataState.connected && page.remoteSelected !== ""; onClicked: ftpBrowser.download(page.remoteSelected) }
        Button { text: "Reload"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.localSelected=""; page.remoteSelected=""; ftpBrowser.refresh() } }
        Button { text: "Cancel"; enabled: page.dataState.busy; onClicked: ftpBrowser.cancel() }
    }
    ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: page.dataState.progress }
    Label { text: page.dataState.status; wrapMode: Text.Wrap; Layout.fillWidth: true; maximumLineCount: 4 }
    Dialog {
        id: confirm
        title: "Confirm upload"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Upload " + page.uploadName + "? Existing remote file may be replaced. Cancelled uploads may leave a partial file."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: ftpBrowser.upload(page.uploadName, true)
    }
}
