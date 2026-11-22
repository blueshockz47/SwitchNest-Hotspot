import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ColumnLayout {
    id: page
    FolderDialog {
        id: localFolderDialog
        title: "Choose PC folder or mounted removable drive"
        onAccepted: { page.clearSelection(); ftpBrowser.open_local_folder(selectedFolder) }
    }
    Dialog {
        id: removableDialog
        title: "Mounted removable drives"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 480
        standardButtons: Dialog.Ok | Dialog.Cancel
        property var drives: []
        onOpened: drives = ftpBrowser.removable_mounts()
        onAccepted: {
            if (drives.length > 0 && drivePicker.currentIndex >= 0) {
                page.clearSelection()
                ftpBrowser.open_removable_mount(drives[drivePicker.currentIndex].path)
            }
        }
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                text: removableDialog.drives.length
                      ? "Select a mounted USB drive or SD card:"
                      : "No mounted removable drives found. Mount the device in SteamOS Dolphin first, then reopen this dialog."
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            ComboBox {
                id: drivePicker
                Layout.fillWidth: true
                enabled: removableDialog.drives.length > 0
                model: removableDialog.drives.map(function(d) { return d.name + "  (" + d.path + ")" })
            }
        }
    }
    property var dataState: ftpBrowser ? JSON.parse(ftpBrowser.state) : ({host: "", port: "", localRows: [], remoteRows: [], status: "Initializing FTP...", busy: false, connected: false, history: [], bookmarks: [], local: "", remote: "/", localFree: 0})
    property var localSelected: []
    property var remoteSelected: []
    property var uploadName: []
    property int sortMode: 0
    property bool showHidden: true
    property var deleteNames: []
    property string deleteSide: "local"
    property string deletePath: ""
    property bool selectionMode: false
    property bool showActivity: false
    property bool queueExpanded: false
    property string notification: ""
    property string lastStatus: ""
    property int fileFontSize: 17
    property bool showDetails: true
    property color paneColor: "#202938"
    property color paneBorder: "#33465c"
    property bool dragInProgress: false
    property string dropTarget: ""
    property string dropFolder: ""
    property string transferFolder: ""
    function targetAt(point) {
        if (!dataState.connected || dataState.busy) return ""
        let local = localList.mapToItem(page, 0, 0)
        let remote = remoteList.mapToItem(page, 0, 0)
        if (dragGhost.dragSide === "remote" && point.x >= local.x && point.x < local.x + localList.width && point.y >= local.y && point.y < local.y + localList.height) return "local"
        if (dragGhost.dragSide === "local" && point.x >= remote.x && point.x < remote.x + remoteList.width && point.y >= remote.y && point.y < remote.y + remoteList.height) return "remote"
        return ""
    }
    function beginDrag(side, name, directory, source, point) {
        if (dataState.busy || !dataState.connected) return
        dragGhost.fileName = name
        dragGhost.dragSide = side
        dragGhost.isDirectory = directory
        dragInProgress = true
        updateDrag(source, point)
    }
    function updateDrag(source, point) {
        if (!dragInProgress) return
        // Two distinct coordinate systems: hit-test in page space, draw in overlay space.
        // Overlay.overlay is attached to the window and is offset from this page.
        let pagePoint = source.mapToItem(page, point.x, point.y)
        let overlayPoint = source.mapToItem(dragOverlay, point.x, point.y)
        dragGhost.x = overlayPoint.x - dragGhost.width / 2
        dragGhost.y = overlayPoint.y - dragGhost.height / 2
        dropTarget = targetAt(pagePoint)
        dropFolder = ""
        if (dropTarget) {
            let list = dropTarget === "local" ? localList : remoteList
            // Hit-test the actual delegate rectangles rather than ListView
            // indices: indexAt coordinates can disagree with the viewport.
            // Use the actual delegate at the pointer, not the row index from
            // an unfiltered model. This remains correct after sorting/scrolling.
            let inList = list.mapFromItem(page, pagePoint.x, pagePoint.y)
            let delegate = list.itemAt(inList.x, inList.y + list.contentY)
            if (delegate && delegate.isFolder && delegate.fileName) {
                let bounds = delegate.mapToItem(page, 0, 0)
                if (pagePoint.x >= bounds.x && pagePoint.x < bounds.x + delegate.width &&
                    pagePoint.y >= bounds.y && pagePoint.y < bounds.y + delegate.height)
                    dropFolder = delegate.fileName
            }
        }
    }
    function finishDrag(source, point) {
        if (!dragInProgress) return
        // Explicit hit testing avoids unreliable Qt Quick drag-source delivery
        // across two clipped ListViews. Only cross-panel drops transfer.
        updateDrag(source, point)
        let target = dropTarget
        let side = dragGhost.dragSide
        let name = dragGhost.fileName
        let folder = dropFolder
        dragInProgress = false
        dropTarget = ""
        dropFolder = ""
        if (target && target !== side) {
            let selected = side === "local" ? localSelected : remoteSelected
            let names = selected.indexOf(name) >= 0 ? selected.slice() : [name]
            transferFolder = folder
            transfer(side, names)
        }
    }
    function clearSelection() { localSelected=[]; remoteSelected=[]; entryName="" }
    function selectRange(side, name, modifiers) {
        let selected = side === "local" ? localSelected : remoteSelected
        let rows = sorted(side === "local" ? dataState.localRows : dataState.remoteRows, side)
        let names = rows.map(x => x.name)
        let target = names.indexOf(name)
        if (target < 0) return
        let anchor = names.indexOf(entryName)
        let result
        if ((modifiers & Qt.ShiftModifier) && anchor >= 0) {
            let range = names.slice(Math.min(anchor,target),Math.max(anchor,target)+1)
            result = (modifiers & Qt.ControlModifier) ? Array.from(new Set(selected.concat(range))) : range
        } else if ((modifiers & Qt.ControlModifier) || selectionMode) {
            result = toggle(selected,name)
        } else {
            result = [name]
        }
        // Selection belongs to the active pane only; changing panes clears stale highlights.
        if (side === "local") { localSelected=result; remoteSelected=[] }
        else { remoteSelected=result; localSelected=[] }
        activeSide=side
        entryName=name
    }
    function selectAll() { if (activeSide==="local") localSelected=sorted(dataState.localRows, "local").map(x=>x.name); else remoteSelected=sorted(dataState.remoteRows, "remote").map(x=>x.name) }
    function deleteSelected() { deleteSide=activeSide; deletePath=activeSide==="local"?dataState.local:dataState.remote; deleteNames=(activeSide==="local"?localSelected:remoteSelected).slice(); if(deleteNames.length) batchDelete.open() }
    function navigate(action) { clearSelection(); ftpBrowser.navigate(activeSide,action) }
    function switchBookmarks() {
        return (dataState.bookmarks || []).map((item,index) => ({item:item,index:index})).filter(x => x.item.side === "remote" && x.item.host === dataState.host && String(x.item.port) === String(dataState.port))
    }
    function remoteSegments() {
        let segments = (dataState.remote || "/").split("/").filter(x => x.length)
        let result = [{name:"Root",path:"/"}]
        let path = "/"
        for (let segment of segments) {
            path += segment + "/"
            result.push({name:segment,path:path})
        }
        return result
    }
    function openDirectory(side, name) {
        clearSelection()
        activeSide=side
        if (side === "local") ftpBrowser.local_open(name)
        else ftpBrowser.remote_open(name)
    }
    Shortcut { sequence: "Ctrl+A"; enabled: page.visible && !page.dataState.busy && !localSearch.activeFocus && !remoteSearch.activeFocus && !host.activeFocus && !port.activeFocus && !editDialog.visible && !conflictDialog.visible && !batchDelete.visible; onActivated: page.selectAll() }
    Shortcut { sequence: "F5"; enabled: page.visible && !page.dataState.busy && page.dataState.connected; onActivated: { page.clearSelection(); ftpBrowser.refresh() } }
    property string transferSide: "local"
    property var transferNames: []
    property string activeSide: "local"
    property string entryName: ""
    property string operation: ""
    property string opSide: ""
    property string opName: ""
    property bool opDirectory: false
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
    function droppedFiles(side, name) {
        if (!name || dataState.busy || !dataState.connected) return
        // Use the same conflict-confirmation workflow as the Upload/Download buttons.
        transferFolder = ""
        transfer(side, [name])
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
        opDirectory=(opSide==="local" ? dataState.localRows : dataState.remoteRows).some(x=>x.name===opName && x.directory)
        newName.text= action === "rename" ? entryName : ""
        editDialog.open()
    }
    Shortcut { sequences: [StandardKey.Copy]; enabled: page.visible && !page.dataState.busy && !host.activeFocus && !port.activeFocus && !localSearch.activeFocus && !remoteSearch.activeFocus && !editDialog.visible && !conflictDialog.visible; onActivated: page.copyFiles() }
    Shortcut { sequences: [StandardKey.Paste]; enabled: page.visible && !page.dataState.busy && !host.activeFocus && !port.activeFocus && !localSearch.activeFocus && !remoteSearch.activeFocus && !editDialog.visible && !conflictDialog.visible; onActivated: page.pasteFiles() }
    function toggle(items, name) { return items.indexOf(name) < 0 ? items.concat([name]) : items.filter(x => x !== name) }
    function sorted(rows, side) { let query = (side === "remote" ? remoteSearch.text : localSearch.text).toLowerCase(); return rows.filter(x => (showHidden || !x.name.startsWith(".")) && x.name.toLowerCase().includes(query)).sort((a,b) => a.directory !== b.directory ? (a.directory ? -1 : 1) : sortMode === 1 ? (b.size || 0)-(a.size || 0) || a.name.localeCompare(b.name) : a.name.localeCompare(b.name)) }
    function typeText(row) { if (row.directory) return "Folder"; let name = row.name || ""; let dot = name.lastIndexOf("."); return dot > 0 ? name.slice(dot + 1).toUpperCase() : "File" }
    function fileLabel(row) { return (row.directory ? "📁 " : "▧ ") + row.name + (showDetails ? "    ·    " + typeText(row) + (row.directory ? "" : "    ·    " + sizeText(row.size)) + (row.date ? "    ·    " + row.date : "") : (row.directory ? "" : "  ·  " + sizeText(row.size))) }
    function sizeText(n) { return n === null || n === undefined ? "" : n >= 1073741824 ? (n/1073741824).toFixed(2)+" GiB" : n >= 1048576 ? (n/1048576).toFixed(1)+" MiB" : n >= 1024 ? (n/1024).toFixed(1)+" KiB" : n+" B" }
    Connections {
        target: ftpBrowser
        function onChanged() {
            page.dataState = JSON.parse(ftpBrowser.state)
            let next = page.dataState.status || ""
            if (next !== page.lastStatus) {
                page.lastStatus = next
                page.notification = next
            }
        }
    }
    Label { text: "FTP File Manager"; font.pixelSize: 20; font.bold: true; color: "#eef5ff" }
    Label { text: "Manage files on your Switch 2 without leaving SwitchNest"; font.pixelSize: 12; color: "#9cb3cd" }
    RowLayout {
        Label { text: "Host"; color: "#a9bfd7" }
        TextField { id: host; text: page.dataState.host; Layout.fillWidth: true; enabled: !page.dataState.busy && !page.dataState.connected; placeholderText: "Switch 2 FTP address" }
        Label { text: "Port"; color: "#a9bfd7" }
        TextField { id: port; text: page.dataState.port; Layout.preferredWidth: 85; enabled: !page.dataState.busy && !page.dataState.connected }
        Label { text: page.dataState.connected ? "● CONNECTED" : (page.dataState.busy ? "● CONNECTING…" : "● DISCONNECTED"); color: page.dataState.connected ? "#43f5b0" : (page.dataState.busy ? "#f4bd53" : "#ff454f"); font.bold: true; font.pixelSize: 14 }
        Button { text: page.dataState.discoveryBusy ? "Searching..." : "Find Switch 2 IP"; enabled: !page.dataState.discoveryBusy && !page.dataState.busy && !page.dataState.connected; onClicked: ftpBrowser.find_switch_ip() }
        Button { text: page.dataState.busy ? "Working..." : page.dataState.connected ? "Disconnect" : "Connect"; enabled: !page.dataState.busy; onClicked: { page.remoteSelected=[]; if (page.dataState.connected) ftpBrowser.disconnect(); else ftpBrowser.connect_to(host.text, port.text) } }
    }
    Label { text: page.dataState.discoveryStatus || ""; visible: text.length > 0; color: "#8cb9c9"; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Label { text: (page.dataState.connected ? "Connected to " + page.dataState.host + ":" + page.dataState.port : page.dataState.busy ? "FTP operation in progress" : "Not connected") + " — " + page.dataState.status; color: !page.dataState.connected && (String(page.dataState.status || "").toLowerCase().indexOf("connection refused") >= 0 || String(page.dataState.status || "").toLowerCase().indexOf("could not connect to server") >= 0) ? "#ff454f" : page.dataState.connected ? "#52e0ae" : "#9cb3cd"; font.bold: !page.dataState.connected && String(page.dataState.status || "").toLowerCase().indexOf("connection refused") >= 0; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        CheckBox { text: "Select"; checked: page.selectionMode; onToggled: { page.selectionMode=checked; page.clearSelection() } }
        CheckBox { text: "Hidden"; checked: page.showHidden; onToggled: { page.showHidden=checked; page.clearSelection() } }
    }
    RowLayout { Label { text: "FILE VIEW  •  Local FTP / PASV"; color: "#98a5b5" } Item { Layout.fillWidth: true } CheckBox { text: "Details"; checked: page.showDetails; onToggled: page.showDetails = checked } ComboBox { model: ["Name", "Size"]; onCurrentIndexChanged: page.sortMode=currentIndex; enabled: !page.dataState.busy } }
    SplitView {
        id: fileSplit
        orientation: Qt.Horizontal
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            SplitView.preferredWidth: fileSplit.width / 2
            SplitView.minimumWidth: 220
            spacing: 4
            Label { text: "THIS PC  /  FILE EXPLORER"; color: "#40c9b7"; font.bold: true; font.pixelSize: 13 }

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 0
                    color: "#202938"
                    border.color: "#8190a4"
                    Label { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: Text.AlignVCenter; text: page.dataState.local; elide: Text.ElideMiddle; ToolTip.visible: pathHover.hovered; ToolTip.text: page.dataState.local }
                    HoverHandler { id: pathHover }
                }
                Label { text: page.localSelected.length + " selected"; visible: page.localSelected.length > 0; color: "#8cb9c9" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                Button { text: "◀ Back"; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.navigate("local", "back") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Forward ▶"; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.navigate("local", "forward") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Up"; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.local_open("..") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Downloads"; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.open_local_shortcut("Downloads") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Browse..."; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { localFolderDialog.open() } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Desktop"; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.open_local_shortcut("Desktop") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Removable..."; Layout.fillWidth: true; enabled: !page.dataState.busy; onClicked: { removableDialog.open() } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 38; color: "#263449"; RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8; Label { text: "Name"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 14 } Label { text: "Size"; Layout.preferredWidth: 90; font.bold: true; font.pixelSize: 14 } Label { text: "Type"; Layout.preferredWidth: 85; font.bold: true; font.pixelSize: 14 } Label { text: "Modified"; Layout.preferredWidth: 112; font.bold: true; font.pixelSize: 14 } } }
            RowLayout { Layout.fillWidth: true; TextField { id: localSearch; Layout.fillWidth: true; placeholderText: "Filter PC filenames · Ctrl+F to search"; onTextChanged: page.clearSelection() } Button { text: "Clear"; onClicked: localSearch.clear() } }
            ListView {
                id: localList
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.localRows, "local")
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    contentItem: RowLayout {
                        spacing: 8
                        CheckBox {
                            Layout.preferredWidth: 28
                            checked: page.localSelected.indexOf(modelData.name) >= 0
                            enabled: !page.dataState.busy
                            onClicked: page.selectRange("local", modelData.name, Qt.ControlModifier)
                            ToolTip.visible: hovered
                            ToolTip.text: "Select " + modelData.name
                        }
                        Label {
                            text: (modelData.directory ? "📁  " : "▧  ") + modelData.name
                            Layout.fillWidth: true
                            font.pixelSize: page.fileFontSize
                            color: "#e4edf8"
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Label { text: modelData.directory ? "—" : page.sizeText(modelData.size); Layout.preferredWidth: 90; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                        Label { text: page.typeText(modelData); Layout.preferredWidth: 85; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                        Label { text: modelData.date || ""; Layout.preferredWidth: 112; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                    }
                    implicitHeight: 44
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + "  " + (modelData.date || "")
                    background: Rectangle {
                        color: parent.highlighted ? "#28516a" : parent.hovered ? "#26374d" : "#1d293a"
                        radius: 3
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    highlighted: page.localSelected.indexOf(modelData.name) >= 0 || (modelData.directory && page.dropTarget === "local" && page.dropFolder === modelData.name)
                    enabled: !page.dataState.busy
                    property string fileName: modelData.name
                    property bool isFolder: modelData.directory
                    onClicked: {
                        if (modelData.directory && !page.selectionMode && !(Qt.application.keyboardModifiers & (Qt.ControlModifier | Qt.ShiftModifier))) page.openDirectory("local",modelData.name)
                        else page.selectRange("local",modelData.name,Qt.application.keyboardModifiers)
                    }
                    onPressAndHold: { page.activeSide="local"; page.entryName=modelData.name; entryMenu.popup() }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { page.activeSide="local"; page.entryName=modelData.name; entryMenu.popup() }
                    }
                    DragHandler {
                        id: dragHandler
                        enabled: !page.dataState.busy && page.dataState.connected
                        target: null
                        onActiveChanged: {
                            if (active) page.beginDrag("local", modelData.name, modelData.directory, parent, centroid.position)
                            else page.finishDrag(parent, centroid.position)
                        }
                        onCentroidChanged: if (active) page.updateDrag(parent, centroid.position)
                    }
                    Menu {
                        id: entryMenu
                        MenuItem { text: "Upload file / folder"; onTriggered: page.transfer("local",[page.entryName]) }
                        MenuItem { text: "Properties"; onTriggered: { ftpBrowser.properties(page.activeSide,page.entryName); propertiesDialog.open() } }
                        MenuItem { text: "Rename"; onTriggered: page.editEntry("rename") }
                        MenuItem {
                            text: (page.activeSide === "local" ? page.localSelected : page.remoteSelected).indexOf(page.entryName) >= 0 && (page.activeSide === "local" ? page.localSelected : page.remoteSelected).length > 1 ? "Delete selected (" + (page.activeSide === "local" ? page.localSelected : page.remoteSelected).length + ")" : "Delete"
                            onTriggered: {
                                let selected = page.activeSide === "local" ? page.localSelected : page.remoteSelected
                                if (selected.indexOf(page.entryName) >= 0 && selected.length > 1)
                                    page.deleteSelected()
                                else
                                    page.editEntry("delete")
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
            RowLayout { Layout.fillWidth: true; Button { text: "Upload to Switch 2  →"; enabled: page.dataState.connected && !page.dataState.busy && page.localSelected.length > 0; onClicked: page.transfer("local", page.localSelected) } Button { text: "Refresh PC"; enabled: !page.dataState.busy; onClicked: ftpBrowser.refresh() } Item { Layout.fillWidth: true } Label { text: page.dataState.localRows.length + " items · " + page.localSelected.length + " selected"; color: "#9fb2c9" } }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            SplitView.preferredWidth: fileSplit.width / 2
            SplitView.minimumWidth: 220
            spacing: 4
            Label { text: "NINTENDO SWITCH 2  /  FTP"; color: "#40c9b7"; font.bold: true; font.pixelSize: 13 }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 34; color: "#202938"; border.color: "#8190a4"; Label { anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: Text.AlignVCenter; text: page.dataState.remote || "/"; color: "#e4edf8"; elide: Text.ElideMiddle } }
            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                Button { text: "◀ Back"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.navigate("remote", "back") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Forward ▶"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.navigate("remote", "forward") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Home"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.open_remote_path("/") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Up"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.remote_open("..") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "Refresh"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.refresh() } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
                Button { text: "/switch"; Layout.fillWidth: true; enabled: !page.dataState.busy && page.dataState.connected; onClicked: { page.clearSelection(); ftpBrowser.open_remote_path("/switch/") } background: Rectangle { color: parent.down ? "#314761" : parent.hovered ? "#30445d" : "#263449"; border.color: "#1e2a3b"; border.width: 1 } }
            }
                Menu {
                    id: switchQuickMenu
                    MenuItem { text: "Favorites"; enabled: false }
                    Repeater {
                        model: page.switchBookmarks()
                        delegate: MenuItem {
                            required property var modelData
                            text: "★ " + modelData.item.path
                            enabled: !page.dataState.busy && page.dataState.connected
                            onTriggered: { page.clearSelection(); ftpBrowser.open_bookmark(modelData.index) }
                        }
                    }
                    MenuSeparator {}
                    MenuItem { text: "Recent folders"; enabled: false }
                    Repeater {
                        model: page.dataState.remoteRecent || []
                        delegate: MenuItem {
                            required property string modelData
                            text: "◷ " + modelData
                            enabled: !page.dataState.busy && page.dataState.connected
                            onTriggered: { page.clearSelection(); ftpBrowser.open_remote_path(modelData) }
                        }
                    }
                }
                Menu {
                    id: switchActionsMenu
                    MenuItem {
                        text: "Pin current folder"
                        enabled: !page.dataState.busy && page.dataState.connected
                        onTriggered: ftpBrowser.bookmark("remote")
                    }
                    MenuItem {
                        text: "Copy current path"
                        enabled: page.dataState.connected
                        onTriggered: ftpBrowser.copy_remote_path()
                    }
                }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 38; color: "#263449"; RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8; Label { text: "Name"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 14 } Label { text: "Size"; Layout.preferredWidth: 90; font.bold: true; font.pixelSize: 14 } Label { text: "Type"; Layout.preferredWidth: 85; font.bold: true; font.pixelSize: 14 } Label { text: "Modified"; Layout.preferredWidth: 112; font.bold: true; font.pixelSize: 14 } } }
            RowLayout { Layout.fillWidth: true; TextField { id: remoteSearch; Layout.fillWidth: true; placeholderText: "Filter Switch filenames"; onTextChanged: page.clearSelection() } Button { text: "Clear"; onClicked: remoteSearch.clear() } }
            ListView {
                id: remoteList
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: page.sorted(page.dataState.remoteRows, "remote")
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    contentItem: RowLayout {
                        spacing: 8
                        CheckBox {
                            Layout.preferredWidth: 28
                            checked: page.remoteSelected.indexOf(modelData.name) >= 0
                            enabled: !page.dataState.busy
                            onClicked: page.selectRange("remote", modelData.name, Qt.ControlModifier)
                            ToolTip.visible: hovered
                            ToolTip.text: "Select " + modelData.name
                        }
                        Label {
                            text: (modelData.directory ? "📁  " : "▧  ") + modelData.name
                            Layout.fillWidth: true
                            font.pixelSize: page.fileFontSize
                            color: "#e4edf8"
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Label { text: modelData.directory ? "—" : page.sizeText(modelData.size); Layout.preferredWidth: 90; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                        Label { text: page.typeText(modelData); Layout.preferredWidth: 85; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                        Label { text: modelData.date || ""; Layout.preferredWidth: 112; font.pixelSize: 14; color: "#b6c8dd"; elide: Text.ElideRight }
                    }
                    implicitHeight: 44
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.name + "  " + (modelData.date || "")
                    background: Rectangle {
                        color: parent.highlighted ? "#28516a" : parent.hovered ? "#26374d" : "#1d293a"
                        radius: 3
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    highlighted: page.remoteSelected.indexOf(modelData.name) >= 0 || (modelData.directory && page.dropTarget === "remote" && page.dropFolder === modelData.name)
                    enabled: !page.dataState.busy
                    property string fileName: modelData.name
                    property bool isFolder: modelData.directory
                    onClicked: {
                        if (modelData.directory && !page.selectionMode && !(Qt.application.keyboardModifiers & (Qt.ControlModifier | Qt.ShiftModifier))) page.openDirectory("remote",modelData.name)
                        else page.selectRange("remote",modelData.name,Qt.application.keyboardModifiers)
                    }
                    onPressAndHold: { page.activeSide="remote"; page.entryName=modelData.name; entryMenu.popup() }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { page.activeSide="remote"; page.entryName=modelData.name; entryMenu.popup() }
                    }
                    DragHandler {
                        id: dragHandler
                        enabled: !page.dataState.busy && page.dataState.connected
                        target: null
                        onActiveChanged: {
                            if (active) page.beginDrag("remote", modelData.name, modelData.directory, parent, centroid.position)
                            else page.finishDrag(parent, centroid.position)
                        }
                        onCentroidChanged: if (active) page.updateDrag(parent, centroid.position)
                    }
                    Menu {
                        id: entryMenu
                        MenuItem { text: "Download file / folder"; onTriggered: page.transfer("remote",[page.entryName]) }
                        MenuItem { text: "Properties"; onTriggered: { ftpBrowser.properties(page.activeSide,page.entryName); propertiesDialog.open() } }
                        MenuItem { text: "Rename"; onTriggered: page.editEntry("rename") }
                        MenuItem {
                            text: (page.activeSide === "local" ? page.localSelected : page.remoteSelected).indexOf(page.entryName) >= 0 && (page.activeSide === "local" ? page.localSelected : page.remoteSelected).length > 1 ? "Delete selected (" + (page.activeSide === "local" ? page.localSelected : page.remoteSelected).length + ")" : "Delete"
                            onTriggered: {
                                let selected = page.activeSide === "local" ? page.localSelected : page.remoteSelected
                                if (selected.indexOf(page.entryName) >= 0 && selected.length > 1)
                                    page.deleteSelected()
                                else
                                    page.editEntry("delete")
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
            RowLayout { Layout.fillWidth: true; Button { text: "←  Download to PC"; enabled: page.dataState.connected && !page.dataState.busy && page.remoteSelected.length > 0; onClicked: page.transfer("remote", page.remoteSelected) } Button { text: "New folder"; enabled: page.dataState.connected && !page.dataState.busy; onClicked: { page.activeSide = "remote"; page.editEntry("mkdir") } } Item { Layout.fillWidth: true } Label { text: page.dataState.remoteRows.length + " items · " + page.remoteSelected.length + " selected"; color: "#9fb2c9" } }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Label {
            text: page.dragInProgress
                ? (page.dropTarget ? "Copy " + dragGhost.fileName + " → " + (page.dropTarget === "remote" ? "Switch 2" : "SteamOS") + (page.dropFolder ? " / " + page.dropFolder : " / current folder") + " · Release to confirm" : "Move over the opposite panel to choose a destination")
                : "Drag files onto a folder to copy inside it; drop on empty space for the current directory."
            color: page.dropTarget ? "#52e0ae" : "#8cb9c9"
            font.pixelSize: 13
            font.bold: page.dragInProgress
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Label { text: "COPY ONLY · Originals kept"; color: "#8cb9c9"; font.pixelSize: 12 }
    }
    // Phase 3a: Dolphin-inspired compact action toolbar; existing backend calls are unchanged.
    ToolBar {
        Layout.fillWidth: true
        RowLayout {
            anchors.fill: parent
            spacing: 4
            ToolButton {
                text: "↑ Upload (" + page.localSelected.length + ")"
                enabled: !page.dataState.busy && page.dataState.connected && page.localSelected.length > 0
                onClicked: page.transfer("local",page.localSelected)
                ToolTip.visible: hovered; ToolTip.text: "Copy selected SteamOS files to Switch 2"
            }
            ToolButton {
                text: "↓ Download (" + page.remoteSelected.length + ")"
                enabled: !page.dataState.busy && page.dataState.connected && page.remoteSelected.length > 0
                onClicked: page.transfer("remote",page.remoteSelected)
                ToolTip.visible: hovered; ToolTip.text: "Copy selected Switch 2 files to SteamOS"
            }
            ToolSeparator {}
            ToolButton {
                text: "⟳"
                enabled: !page.dataState.busy && page.dataState.connected
                onClicked: { page.localSelected=[]; page.remoteSelected=[]; ftpBrowser.refresh() }
                ToolTip.visible: hovered; ToolTip.text: "Refresh both panels (F5)"
            }
            ToolButton {
                text: "+ Folder"
                enabled: !page.dataState.busy && (page.activeSide === "local" || page.dataState.connected)
                onClicked: page.editEntry("mkdir")
            }
            ToolButton {
                text: "Delete"
                enabled: !page.dataState.busy && (page.activeSide==="local"?page.localSelected.length:page.remoteSelected.length)>0
                onClicked: page.deleteSelected()
                ToolTip.visible: hovered; ToolTip.text: "Permanently delete selected entries after confirmation"
            }
            Item { Layout.fillWidth: true }
            Label {
                text: (page.activeSide === "local" ? "SteamOS" : "Switch 2") + " · " + (page.activeSide === "local" ? page.localSelected.length : page.remoteSelected.length) + " selected"
                elide: Text.ElideRight
                Layout.maximumWidth: 150
                color: "#8cb9c9"
            }
            ToolButton {
                text: "Cancel"
                visible: page.dataState.busy
                enabled: page.dataState.busy
                onClicked: ftpBrowser.cancel()
            }
            ToolButton {
                text: page.queueExpanded ? "Hide queue" : "Show queue"
                onClicked: page.queueExpanded = !page.queueExpanded
            }
            ToolButton {
                text: "More ▾"
                onClicked: ftpActions.popup()
                Menu {
                    id: ftpActions
                    MenuItem { text: "Copy"; enabled: !page.dataState.busy; onTriggered: page.copyFiles() }
                    MenuItem { text: "Paste"; enabled: !page.dataState.busy && page.clipboard.length > 0 && page.clipSide !== page.activeSide; onTriggered: page.pasteFiles() }
                    MenuSeparator {}
                    MenuItem { text: "Select all"; enabled: !page.dataState.busy; onTriggered: page.selectAll() }
                    MenuItem { text: "Clear selection"; onTriggered: page.clearSelection() }
                    MenuSeparator {}
                    MenuItem { text: "Transfer queue"; onTriggered: queueDialog.open() }
                    MenuItem { text: "Transfer history"; onTriggered: historyDialog.open() }
                    MenuItem { text: "Retry remaining entries"; enabled: !page.dataState.busy && page.dataState.retryAvailable; onTriggered: retryDialog.open() }
                }
            }
        }
    }
    RowLayout {
        visible: page.dataState.busy
        Label { text: "Transfer " + Math.round(page.dataState.progress || 0) + "%"; font.pixelSize: 14; font.bold: true }
        Label { text: page.dataState.current || ""; elide: Text.ElideMiddle; Layout.maximumWidth: 240 }
        Label { text: page.dataState.pending && page.dataState.pending.length ? page.dataState.pending.length + " pending" : ""; color: "#8cb9c9" }
        Item { Layout.fillWidth: true }
        Button { text: "View Queue"; onClicked: queueDialog.open() }
    }
    Label { visible: page.dataState.busy && page.dataState.transferSize > 0; text: page.sizeText(page.dataState.bytesDone) + " / " + page.sizeText(page.dataState.transferSize) + " · " + page.sizeText(page.dataState.speed) + "/s" + (page.dataState.speed > 0 ? " · ETA " + Math.max(0,Math.ceil((page.dataState.transferSize-page.dataState.bytesDone)/page.dataState.speed)) + " s" : ""); Layout.fillWidth: true }
    ProgressBar { indeterminate: page.dataState.busy && page.dataState.transferSize === 0 && page.dataState.total === 0; Layout.fillWidth: true; from: 0; to: 100; value: page.dataState.total > 0 && page.dataState.busy && page.dataState.current !== "" ? Math.min(100, (page.dataState.completed + page.dataState.progress/100)*100/page.dataState.total) : page.dataState.progress }
    Label { text: page.dataState.status + (page.dataState.total > 0 ? " · " + page.dataState.completed + "/" + page.dataState.total + " files · " + page.dataState.current : page.dataState.completed > 0 ? " · " + page.dataState.completed + " entries" : ""); wrapMode: Text.Wrap; Layout.fillWidth: true; maximumLineCount: 4 }
    Frame {
        Layout.fillWidth: true
        Layout.preferredHeight: page.queueExpanded ? 165 : 0
        visible: page.queueExpanded
        ColumnLayout {
            anchors.fill: parent
            RowLayout {
                Label { text: "Transfer queue"; font.bold: true }
                Item { Layout.fillWidth: true }
                Label { text: "Completed: " + ((page.dataState.queueSummary || {}).completed || 0) + " · Waiting: " + ((page.dataState.queueSummary || {}).waiting || 0) }
                ToolButton { text: "Details"; onClicked: queueDialog.open() }
            }
            ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: page.dataState.progress || 0 }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: page.dataState.transferItems || []
                delegate: Label {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.status + "  ·  " + modelData.name
                    elide: Text.ElideMiddle
                }
            }
        }
    }
    Label {
        visible: page.notification.length > 0
        text: page.notification
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: "#8cb9c9"
        font.pixelSize: 12
    }
    Dialog {
        id: retryDialog
        title: "Retry remaining entries"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Restart unfinished entries. Replace existing files, including partial files?"; wrapMode: Text.Wrap; width: 300 }
        onAccepted: ftpBrowser.retry_failed("replace")
    }
    Dialog {
        id: batchDelete
        title: "Permanent deletion"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Delete "+page.deleteNames.length+" selected entries and ALL their contents from "+page.deletePath+"? This cannot be undone."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: { if (page.deletePath === (page.deleteSide==="local"?page.dataState.local:page.dataState.remote)) ftpBrowser.delete_batch(page.deleteSide,JSON.stringify(page.deleteNames),true); page.clearSelection() }
    }
    Dialog {
        id: queueDialog
        title: "Transfer queue"
        modal: true
        standardButtons: Dialog.Close
        ColumnLayout {
            Label { text: page.dataState.status; wrapMode: Text.Wrap; Layout.preferredWidth: 300 }
            Label { text: "Transfer entries: " + (page.dataState.transferItems || []).length }
            Label { text: "Waiting: " + ((page.dataState.queueSummary || {}).waiting || 0) + "  ·  Active: " + ((page.dataState.queueSummary || {}).active || 0) + "  ·  Completed: " + ((page.dataState.queueSummary || {}).completed || 0); color: "#8cb9c9" }
            Label { text: "Overall transfer progress: " + Math.round(page.dataState.progress || 0) + "%"; color: "#8cb9c9" }
            ProgressBar { Layout.preferredWidth: 370; from: 0; to: 100; value: page.dataState.progress || 0 }
            Label { text: "Queue statuses track top-level entries. Folder byte totals are reported for the overall batch."; wrapMode: Text.Wrap; Layout.preferredWidth: 370; color: "#8cb9c9" }
            ScrollView {
                Layout.preferredWidth: 390
                Layout.preferredHeight: 230
                ColumnLayout {
                    width: 370
                    Repeater {
                        model: page.dataState.transferItems || []
                        delegate: RowLayout {
                            required property var modelData
                            width: 360
                            Label { text: modelData.status === "Completed" ? "✓" : modelData.status === "Active" ? "●" : "○"; color: modelData.status === "Completed" ? "#52e0ae" : "#98a5b5" }
                            Label { text: modelData.name; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            Label { text: modelData.status; color: "#8cb9c9" }
                        }
                    }
                }
            }
            Button { text: "Cancel transfer"; enabled: page.dataState.busy; onClicked: ftpBrowser.cancel() }
        }
    }
    Dialog {
        id: bookmarkDialog
        title: "Saved directories"
        modal: true
        standardButtons: Dialog.Close
        ColumnLayout {
            ComboBox { id: saved; model: page.dataState.bookmarks.map(x=>x.side+": "+x.path); Layout.preferredWidth: 300 }
            Button { text: "Open"; enabled: saved.currentIndex>=0 && !page.dataState.busy; onClicked: { page.clearSelection(); ftpBrowser.open_bookmark(saved.currentIndex); bookmarkDialog.close() } }
        }
    }
    Dialog {
        id: propertiesDialog
        title: "Properties"
        modal: true
        standardButtons: Dialog.Close
        Label { text: page.dataState.details; width: 300; wrapMode: Text.Wrap }
    }
    Dialog {
        id: editDialog
        modal: true
        title: page.operation + " · " + page.opSide
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            Label { text: page.operation === "delete" ? "Permanently delete " + page.opName + (page.opDirectory ? " and ALL files and subfolders inside? This cannot be undone." : "? This cannot be undone.") : "Enter new name"; wrapMode: Text.Wrap; Layout.preferredWidth: 280 }
            TextField { id: newName; visible: page.operation !== "delete"; Layout.fillWidth: true }
        }
        onAccepted: { if (page.operation==="delete") ftpBrowser.delete_batch(page.opSide,JSON.stringify([page.opName]),true); else ftpBrowser.manage(page.opSide, page.operation, page.opName, newName.text); page.entryName=""; page.localSelected=[]; page.remoteSelected=[] }
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
            Label { text: (page.transferSide === "local" ? "Upload " : "Download ") + page.transferNames.length + " selected entries into " + (page.transferFolder || "current folder") + "."; wrapMode: Text.Wrap; Layout.preferredWidth: 300 }
            ComboBox { id: policy; model: ["Skip existing", "Keep both (rename)", "Replace existing"] }
            Label { text: "Replace may overwrite files. Interrupted uploads may leave partial files."; wrapMode: Text.Wrap; Layout.preferredWidth: 300 }
        }
        onOpened: policy.currentIndex=0
        onRejected: page.transferFolder = ""
        onAccepted: {
            let direction = page.transferSide === "local" ? "upload" : "download"
            if (page.transferFolder)
                ftpBrowser.tree_batch_into(direction,JSON.stringify(page.transferNames),["skip","rename","replace"][policy.currentIndex],page.transferFolder)
            else
                ftpBrowser.tree_batch(direction,JSON.stringify(page.transferNames),["skip","rename","replace"][policy.currentIndex])
            page.transferFolder = ""
        }
    }
    Dialog {
        id: confirm
        title: "Confirm upload"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: "Upload " + page.uploadName.length + " selected file(s)? Existing remote file may be replaced. Cancelled uploads may leave a partial file."; wrapMode: Text.Wrap; width: 300 }
        onAccepted: ftpBrowser.batch("upload", JSON.stringify(page.uploadName))
    }
    // This overlay is outside the clipped file lists.
    Item {
        id: dragOverlay
        parent: Overlay.overlay
        anchors.fill: parent
        z: 1000
        visible: page.dragInProgress
        enabled: false
        Rectangle {
            id: dragGhost
            property string fileName: ""
            property string dragSide: "local"
            property bool isDirectory: false
            width: Math.min(310, Math.max(155, ghostLabel.implicitWidth + 34))
            height: 46
            radius: 9
            color: "#243e55"
            border.color: "#52e0ae"
            border.width: 2
            opacity: page.dragInProgress ? 0.95 : 0
            scale: page.dragInProgress ? 1.04 : 0.92
            Behavior on opacity { NumberAnimation { duration: 110 } }
            Behavior on scale { NumberAnimation { duration: 110 } }
            Label {
                id: ghostLabel
                anchors.centerIn: parent
                width: Math.min(280, implicitWidth)
                elide: Text.ElideRight
                text: (dragGhost.isDirectory ? "📁 " : "▧ ") + dragGhost.fileName
                color: "white"
                font.pixelSize: 15
                font.bold: true
            }
        }
    }

}
