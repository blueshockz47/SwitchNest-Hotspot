import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    property var dataState: JSON.parse(ftpBrowser.state)
    property var localSelected: []
    property var remoteSelected: []
    property var uploadName: []
    property int sortMode: 0
    function toggle(items, name) { return items.indexOf(name) < 0 ? items.concat([name]) : items.filter(x => x !== name) }
    function sorted(rows) { return rows.slice().sort((a,b) => a.directory !== b.directory ? (a.directory ? -1 : 1) : sortMode === 1 ? (b.size || 0)-(a.size || 0) || a.name.localeCompare(b.name) : a.name.localeCompare(b.name)) }
    function sizeText(n) { return n === null || n === undefined ? "" : n >= 1048576 ? (n/1048576).toFixed(1)+" MiB" : n >= 1024 ? (n/1024).toFixed(1)+" KiB" : n+" B" }
    Connections {
        target: ftpBrowser
        function onChanged() { page.dataState = JSON.parse(ftpBrowser.state) }
    }
    RowLayout {
        TextField { id: host; text: page.dataState.host; Layout.fillWidth: true; enabled: !page.dataState.busy }
        TextField { id: port; text: page.dataState.port; Layout.preferredWidth: 85; enabled: !page.dataState.busy }
        Button { text: "Connect"; enabled: !page.dataState.busy; onClicked: { page.remoteSelected=[]; ftpBrowser.connect_to(host.text, port.text) } }
    }
    RowLayout { Label { text: "Local FTP • PASV"; color: "#98a5b5" } Item { Layout.fillWidth: true } ComboBox { model: ["Name", "Size"]; onCurrentIndexChanged: page.sortMode=currentIndex; enabled: !page.dataState.busy } }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Label { text: "Local files"; font.bold: true }
            Label { text: page.dataState.local; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Button { text: "Up"; enabled: !page.dataState.busy; onClicked: { page.localSelected=[]; ftpBrowser.local_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.localRows)
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.directory ? "📁 " : "▧ ") + modelData.name + (modelData.directory ? "" : "  ·  " + page.sizeText(modelData.size))
                    font.pixelSize: 13
                    implicitHeight: 34
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + "  " + (modelData.date || "")
                    highlighted: page.localSelected.indexOf(modelData.name) >= 0
                    enabled: !page.dataState.busy
                    onClicked: { if (modelData.directory) { page.localSelected=[]; ftpBrowser.local_open(modelData.name) } else page.localSelected=page.toggle(page.localSelected, modelData.name) }
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
            Button { text: "Up"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.remoteSelected=[]; ftpBrowser.remote_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.remoteRows)
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.directory ? "📁 " : "▧ ") + modelData.name + (modelData.directory ? "" : "  ·  " + page.sizeText(modelData.size))
                    font.pixelSize: 13
                    implicitHeight: 34
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + "  " + (modelData.date || "")
                    highlighted: page.remoteSelected.indexOf(modelData.name) >= 0
                    enabled: !page.dataState.busy
                    onClicked: { if (modelData.directory) { page.remoteSelected=[]; ftpBrowser.remote_open(modelData.name) } else page.remoteSelected=page.toggle(page.remoteSelected, modelData.name) }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
    RowLayout {
        Button { text: "Upload (" + page.localSelected.length + ")"; enabled: !page.dataState.busy && page.dataState.connected && page.localSelected.length > 0; onClicked: { page.uploadName=page.localSelected; confirm.open() } }
        Button { text: "Download (" + page.remoteSelected.length + ")"; enabled: !page.dataState.busy && page.dataState.connected && page.remoteSelected.length > 0; onClicked: ftpBrowser.batch("download", JSON.stringify(page.remoteSelected)) }
        Button { text: "Reload"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.localSelected=[]; page.remoteSelected=[]; ftpBrowser.refresh() } }
        Button { text: "Cancel"; enabled: page.dataState.busy; onClicked: ftpBrowser.cancel() }
    }
    ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: page.dataState.total > 0 && page.dataState.busy && page.dataState.current !== "" ? Math.min(100, (page.dataState.completed + page.dataState.progress/100)*100/page.dataState.total) : page.dataState.progress }
    Label { text: page.dataState.status + (page.dataState.total > 0 ? " · " + page.dataState.completed + "/" + page.dataState.total + " files · " + page.dataState.current : ""); wrapMode: Text.Wrap; Layout.fillWidth: true; maximumLineCount: 4 }
    Dialog {
        id: confirm
        title: "Confirm upload"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Upload " + page.uploadName.length + " selected file(s)? Existing remote file may be replaced. Cancelled uploads may leave a partial file."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: ftpBrowser.batch("upload", JSON.stringify(page.uploadName))
    }
}
