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
    property string transferSide: "local"
    property var transferNames: []
    property string activeSide: "local"
    property string entryName: ""
    property string operation: ""
    property string opSide: ""
    property string opName: ""
    property var clipboard: []
    property string clipSide: ""
    property string clipPath: ""
    property string clipHost: ""
    function copyFiles() {
        clipboard = (activeSide === "local" ? localSelected : remoteSelected).slice()
        clipSide = activeSide
        clipPath = activeSide === "local" ? dataState.local : dataState.remote
        clipHost = dataState.host + ":" + dataState.port
    }
    function transfer(side, names) {
        if (dataState.busy || !dataState.connected || !names.length) return
        transferSide=side; transferNames=names.slice(); conflictDialog.open()
    }
    function pasteFiles() {
        if (clipSide === activeSide || clipPath !== (clipSide === "local" ? dataState.local : dataState.remote) || clipHost !== dataState.host + ":" + dataState.port) return
        transfer(clipSide, clipboard)
    }
    function editEntry(action) {
        opSide=activeSide; opName=entryName; operation=action
        newName.text= action === "rename" ? entryName : ""
        editDialog.open()
    }
    Shortcut { sequence: StandardKey.Copy; enabled: page.visible && !page.dataState.busy && !host.activeFocus && !port.activeFocus && !search.activeFocus && !editDialog.visible && !conflictDialog.visible; onActivated: page.copyFiles() }
    Shortcut { sequence: StandardKey.Paste; enabled: page.visible && !page.dataState.busy && !host.activeFocus && !port.activeFocus && !search.activeFocus && !editDialog.visible && !conflictDialog.visible; onActivated: page.pasteFiles() }
    function toggle(items, name) { return items.indexOf(name) < 0 ? items.concat([name]) : items.filter(x => x !== name) }
    function sorted(rows) { return rows.filter(x => x.name.toLowerCase().includes(search.text.toLowerCase())).sort((a,b) => a.directory !== b.directory ? (a.directory ? -1 : 1) : sortMode === 1 ? (b.size || 0)-(a.size || 0) || a.name.localeCompare(b.name) : a.name.localeCompare(b.name)) }
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
    TextField { id: search; placeholderText: "Filter files and folders"; Layout.fillWidth: true }
    RowLayout { Label { text: "Local FTP • PASV"; color: "#98a5b5" } Item { Layout.fillWidth: true } ComboBox { model: ["Name", "Size"]; onCurrentIndexChanged: page.sortMode=currentIndex; enabled: !page.dataState.busy } }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Label { text: "Local · " + page.sizeText(page.dataState.localFree) + " free"; font.bold: true }
            Label { text: page.dataState.local; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Button { text: "Up"; enabled: !page.dataState.busy; onClicked: { page.activeSide="local"; page.entryName=""; page.localSelected=[]; ftpBrowser.local_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.localRows)
                DropArea {
                    anchors.fill: parent
                    keys: ["remote"]
                    onDropped: drop => {
                        if (drop.source && drop.source.fileName) {
                            page.transfer("remote", [drop.source.fileName])
                            drop.acceptProposedAction()
                        }
                    }
                }
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
                    property string fileName: modelData.name
                    onClicked: {
                        page.activeSide="local"; page.entryName=modelData.name
                        if (modelData.directory) { page.localSelected=[]; ftpBrowser.local_open(modelData.name); page.entryName="" }
                        else page.localSelected=page.toggle(page.localSelected, modelData.name)
                    }
                    onPressAndHold: { page.activeSide="local"; page.entryName=modelData.name; entryMenu.popup() }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { page.activeSide="local"; page.entryName=modelData.name; entryMenu.popup() }
                    }
                    Drag.active: dragHandler.active || dragFinishing
                    property bool dragFinishing: false
                    Drag.keys: ["local"]
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    DragHandler {
                        id: dragHandler
                        enabled: !modelData.directory && !page.dataState.busy
                        target: null
                        onActiveChanged: {
                            if (active) parent.dragFinishing = true
                            else { parent.Drag.drop(); parent.dragFinishing = false }
                        }
                        onCentroidChanged: if (active) {
                            parent.Drag.hotSpot.x = centroid.position.x
                            parent.Drag.hotSpot.y = centroid.position.y
                        }
                    }
                    Menu {
                        id: entryMenu
                        MenuItem { text: "Upload file / folder"; onTriggered: page.transfer("local",[page.entryName]) }
                        MenuItem { text: "Rename"; onTriggered: page.editEntry("rename") }
                        MenuItem { text: "Delete"; onTriggered: page.editEntry("delete") }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Label { text: "Remote · capacity unavailable"; font.bold: true }
            Label { text: page.dataState.remote; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Button { text: "Up"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.activeSide="remote"; page.entryName=""; page.remoteSelected=[]; ftpBrowser.remote_open("..") } }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.remoteRows)
                DropArea {
                    anchors.fill: parent
                    keys: ["local"]
                    onDropped: drop => {
                        if (drop.source && drop.source.fileName) {
                            page.transfer("local", [drop.source.fileName])
                            drop.acceptProposedAction()
                        }
                    }
                }
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
                    property string fileName: modelData.name
                    onClicked: {
                        page.activeSide="remote"; page.entryName=modelData.name
                        if (modelData.directory) { page.remoteSelected=[]; ftpBrowser.remote_open(modelData.name); page.entryName="" }
                        else page.remoteSelected=page.toggle(page.remoteSelected, modelData.name)
                    }
                    onPressAndHold: { page.activeSide="remote"; page.entryName=modelData.name; entryMenu.popup() }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { page.activeSide="remote"; page.entryName=modelData.name; entryMenu.popup() }
                    }
                    Drag.active: dragHandler.active || dragFinishing
                    property bool dragFinishing: false
                    Drag.keys: ["remote"]
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    DragHandler {
                        id: dragHandler
                        enabled: !modelData.directory && !page.dataState.busy
                        target: null
                        onActiveChanged: {
                            if (active) parent.dragFinishing = true
                            else { parent.Drag.drop(); parent.dragFinishing = false }
                        }
                        onCentroidChanged: if (active) {
                            parent.Drag.hotSpot.x = centroid.position.x
                            parent.Drag.hotSpot.y = centroid.position.y
                        }
                    }
                    Menu {
                        id: entryMenu
                        MenuItem { text: "Download file / folder"; onTriggered: page.transfer("remote",[page.entryName]) }
                        MenuItem { text: "Rename"; onTriggered: page.editEntry("rename") }
                        MenuItem { text: "Delete"; onTriggered: page.editEntry("delete") }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
    RowLayout {
        Button { text: "Upload (" + page.localSelected.length + ")"; enabled: !page.dataState.busy && page.dataState.connected && page.localSelected.length > 0; onClicked: page.transfer("local",page.localSelected) }
        Button { text: "Download (" + page.remoteSelected.length + ")"; enabled: !page.dataState.busy && page.dataState.connected && page.remoteSelected.length > 0; onClicked: page.transfer("remote",page.remoteSelected) }
        Button { text: "Reload"; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.localSelected=[]; page.remoteSelected=[]; ftpBrowser.refresh() } }
        Button { text: "Cancel"; enabled: page.dataState.busy; onClicked: ftpBrowser.cancel() }
    }
    RowLayout {
        Button { text: "Copy"; enabled: !page.dataState.busy; onClicked: page.copyFiles() }
        Button { text: "Paste"; enabled: !page.dataState.busy && page.clipboard.length > 0 && page.clipSide !== page.activeSide; onClicked: page.pasteFiles() }
        Button { text: "+ Folder"; enabled: !page.dataState.busy && (page.activeSide === "local" || page.dataState.connected); onClicked: page.editEntry("mkdir") }
        Button { text: "History"; onClicked: historyDialog.open() }
        Label { text: page.activeSide; color: "#52e0ae" }
    }
    Label { visible: page.dataState.busy && page.dataState.transferSize > 0; text: page.sizeText(page.dataState.bytesDone) + " / " + page.sizeText(page.dataState.transferSize) + " · " + page.sizeText(page.dataState.speed) + "/s" + (page.dataState.speed > 0 ? " · ETA " + Math.ceil((page.dataState.transferSize-page.dataState.bytesDone)/page.dataState.speed) + " s" : ""); Layout.fillWidth: true }
    ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: page.dataState.total > 0 && page.dataState.busy && page.dataState.current !== "" ? Math.min(100, (page.dataState.completed + page.dataState.progress/100)*100/page.dataState.total) : page.dataState.progress }
    Label { text: page.dataState.status + (page.dataState.total > 0 ? " · " + page.dataState.completed + "/" + page.dataState.total + " files · " + page.dataState.current : ""); wrapMode: Text.Wrap; Layout.fillWidth: true; maximumLineCount: 4 }
    Dialog {
        id: editDialog
        modal: true
        title: page.operation + " · " + page.opSide
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            Label { text: page.operation === "delete" ? "Permanently delete " + page.opName + "? Only empty folders can be deleted." : "Enter new name"; wrapMode: Text.Wrap; Layout.preferredWidth: 280 }
            TextField { id: newName; visible: page.operation !== "delete"; Layout.fillWidth: true }
        }
        onAccepted: { ftpBrowser.manage(page.opSide, page.operation, page.opName, newName.text); page.entryName=""; page.localSelected=[]; page.remoteSelected=[] }
    }
    Dialog {
        id: historyDialog
        title: "Transfer history (saved)"
        modal: true
        standardButtons: Dialog.Close
        ScrollView {
            width: 320; height: 240
            TextArea { readOnly: true; wrapMode: TextEdit.Wrap; text: page.dataState.history.map(x => x.result + " · " + x.direction + " · " + x.name + " · " + x.date).join("\n") || "No transfers yet" }
        }
    }
    Dialog {
        id: conflictDialog
        title: "Transfer options"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            Label { text: (page.transferSide === "local" ? "Upload " : "Download ") + page.transferNames.length + " selected entries (including subfolders)."; wrapMode: Text.Wrap; Layout.preferredWidth: 300 }
            ComboBox { id: policy; model: ["Skip existing", "Keep both (rename)", "Replace existing"] }
            Label { text: "Replace may overwrite files. Interrupted uploads may leave partial files."; wrapMode: Text.Wrap; Layout.preferredWidth: 300 }
        }
        onOpened: policy.currentIndex=0
        onAccepted: ftpBrowser.tree_batch(page.transferSide === "local" ? "upload" : "download",JSON.stringify(page.transferNames),["skip","rename","replace"][policy.currentIndex])
    }
    Dialog {
        id: confirm
        title: "Confirm upload"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Upload " + page.uploadName.length + " selected file(s)? Existing remote file may be replaced. Cancelled uploads may leave a partial file."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: ftpBrowser.batch("upload", JSON.stringify(page.uploadName))
    }
}
