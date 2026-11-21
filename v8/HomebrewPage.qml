import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: home
    property var ftpState: ftpBrowser ? JSON.parse(ftpBrowser.state) : ({host: "", port: "", status: "Initializing FTP...", busy: false, connected: false})
    property var results: []
    property var curatedResults: []
    property string catalogQuery: ""
    property string catalogCategory: "All"
    property string releaseQuery: ""
    property string releaseSource: "All"
    property var releaseRows: {
        let rows = monitorGithub.concat(monitorReddit).concat(monitorCatalog)
        return rows.filter(function(item) {
            if (releaseSource !== "All" && item.source !== releaseSource) return false
            let haystack = [item.name || "", item.title || "", item.repo || "", item.version || ""].join(" ").toLowerCase()
            return haystack.indexOf(releaseQuery.toLowerCase()) !== -1
        })
    }
    function updateCatalog() {
        let rows = curatedResults.slice()
        let seen = ({})
        for (let row of rows) if (row.repo) seen[row.repo.toLowerCase()] = true
        for (let item of monitorCatalog) {
            if (!item.repo || seen[item.repo.toLowerCase()]) continue
            seen[item.repo.toLowerCase()] = true
            rows.push({name: item.name, category: item.category || "Other", repo: item.repo,
                       manual: true, community: true, source: item.sources.join(" + "),
                       warning: "Unverified community listing. Only GitHub release NROs with SHA-256 digests can be installed after explicit confirmation; ZIPs are download-only."})
        }
        let q = catalogQuery.toLowerCase().trim()
        results = rows.filter(function(item) {
            if (catalogCategory !== "All" && item.category !== catalogCategory) return false
            return !q || [item.name, item.repo, item.category, item.source || ""].join(" ").toLowerCase().indexOf(q) !== -1
        })
        statusText = results.length + " projects shown (curated + community, deduplicated). Community release assets require SHA-256 verification and confirmation."
    }
    property var assets: []
    property string selectedRepo: ""
    property bool selectedManual: false
    property string selectedWarning: ""
    property string selectedAsset: ""
    property string downloadedDirectory: ""
    property bool working: false
    property string readyZip: ""
    property string previewText: ""
    property real transferPercent: 0
    property bool transferActive: false
    property bool transferComplete: false
    property string transferStatus: ""
    property bool installingZip: false
    property string statusText: "Loading the curated Switch 2 homebrew catalog..."
    property var monitorGithub: []
    property var monitorReddit: []
    property var monitorCatalog: []
    property var monitorDirectory: ({url: "https://switch2homebrew.com/", automated: false})
    property var monitorKnownVersions: ({})
    property bool monitorInitialized: false
    property bool monitorVisible: false
    property string monitorStatus: "Checking latest Switch 2 releases..."
    // 6-hour refresh; network work runs on a Python background thread.
    Timer {
        id: homebrewRefreshTimer
        interval: 21600000
        running: true
        repeat: true
        onTriggered: controller.homebrew_monitor_refresh()
    }
    Dialog {
        id: homebrewUpdateNotice
        title: "New Switch 2 homebrew releases"
        standardButtons: Dialog.Ok
        anchors.centerIn: parent
        Label { text: "New releases detected. Open Latest Releases to review them."; wrapMode: Text.Wrap; width: 300 }
    }
    Connections {
        target: controller
        function onHomebrewMonitorResult(raw) {
            try {
                let data = JSON.parse(raw)
                if (data.kind !== "monitor") {
                    home.monitorStatus = data.message || "Homebrew refresh failed"
                    return
                }
                let changed = false
                let next = ({})
                for (let item of data.github) {
                    next[item.repo] = item.version
                    if (home.monitorInitialized && home.monitorKnownVersions[item.repo] !== undefined &&
                        home.monitorKnownVersions[item.repo] !== item.version)
                        changed = true
                }
                home.monitorKnownVersions = next
                home.monitorInitialized = true
                home.monitorGithub = data.github
                home.monitorReddit = data.reddit
                home.monitorCatalog = data.catalog || []
                home.updateCatalog()
                if (data.directory && data.directory.url === "https://switch2homebrew.com/" && data.directory.automated === false)
                    home.monitorDirectory = data.directory
                home.monitorStatus = data.github.length + " GitHub releases • " +
                    data.reddit.length + " unverified Reddit discoveries • " +
                    home.monitorCatalog.length + " community catalog projects" +
                    (data.warnings.length ? " • " + data.warnings.join("; ") : "")
                if (changed) homebrewUpdateNotice.open()
            } catch (e) {
                home.monitorStatus = "Invalid discovery response"
            }
        }
    }
    property string activeCategory: "All"
    property string action: ""
    property string actionRepo: ""
    property string actionName: ""
    property var choices: []
    function selectApp(item) {
        selectedRepo = item.repo
        selectedManual = item.manual
        selectedWarning = "⚠ " + item.warning
        selectedAsset = ""
    }
    function requestRelease(actionName) {
        if (!actionRepo || working) return
        action = actionName
        statusText = "Checking releases for " + actionName + "..."
        controller.homebrew_releases(actionRepo)
    }
    function useAsset(asset) {
        selectedRepo = actionRepo
        selectedAsset = asset.name
        if (action === "download" || action === "zip") downloadOnlyDialog.open()
        else if (action === "install") {
            if (ftpState.connected && !ftpState.busy) installDialog.open()
            else statusText = "Connect to your Switch 2 FTP server above, then retry Download & Install. Only verified single-file NRO packages can be uploaded to /switch/."
        }
    }
    spacing: 4
    Component.onCompleted: { controller.homebrew_search("", "All"); controller.homebrew_monitor_refresh() }
    Connections {
        target: ftpBrowser
        function onChanged() { home.ftpState = JSON.parse(ftpBrowser.state) }
    }
    Connections {
        target: controller
        function onHomebrewBusy(value) { home.working = value; if (!value) { home.installingZip = false; home.transferActive = false } }
        function onHomebrewProgress(raw) {
            let p = JSON.parse(raw)
            if (p.total > 0) home.transferPercent = Math.min(99, Math.round(p.done * 100 / p.total))
            home.transferActive = true
            home.transferComplete = false
            home.transferStatus = (p.index ? p.index + "/" + p.count + " — " : "") + (p.status || "") + (p.name ? ": " + p.name : "")
        }
        function onHomebrewResult(raw) {
            try {
                let data = JSON.parse(raw)
                if (data.kind === "search") { home.curatedResults = data.items; home.assets = []; home.readyZip = ""; home.activeCategory = data.category || "All"; home.updateCatalog() }
                else if (data.kind === "assets") {
                    if (data.repo !== home.actionRepo || !home.action) return
                    home.choices = data.assets.filter(function(asset) {
                        let name = asset.name.toLowerCase()
                        return !!asset.digest && (home.action === "install" ? name.endsWith(".nro") : (name.endsWith(".nro") || name.endsWith(".zip")))
                    })
                    if (home.choices.length === 1) {
                        home.useAsset(home.choices[0])
                        home.action = ""
                    } else if (home.choices.length > 1) assetPicker.open()
                    else { home.statusText = "No SHA-256 verified " + (home.action === "zip" ? "official ZIP" : "compatible release asset") + " for " + home.actionName + ". No unverified downloads offered."; home.action = "" }
                }
                else if (data.kind === "download_only_ready") {
                    home.transferPercent = 100
                    home.transferComplete = true
                    home.downloadedDirectory = data.directory
                    home.statusText = data.message + " Saved: " + data.path
                    controller.homebrew_open_download_directory(data.directory)
                }
                else if (data.kind === "zip_ready") {
                    home.readyZip = data.name
                    home.previewText = data.count + " files (" + Math.round(data.bytes / 1048576) + " MiB extracted)\\n" + data.sample.join("\\n")
                    home.statusText = "Download verified. Review files before installing."
                    home.statusText = "ZIP downloaded. Manual installation required."
                }
                else if (data.kind === "installed") {
                    home.transferPercent = 100
                    home.transferComplete = true
                    home.statusText = data.message
                }
                else {
                    home.statusText = data.message || "Unknown result"
                    if (data.kind === "error") {
                        home.transferActive = false
                        if (home.transferStatus.length > 0) home.transferStatus = "Failed: " + home.statusText
                    }
                }
            } catch (e) { home.statusText = "Invalid homebrew response" }
        }
    }
    Label { text: "Switch 2 Homebrew Manager"; font.pixelSize: 22; font.bold: true }
    Label { text: "Verified NRO → FTP install  •  ZIP → manual download"; font.pixelSize: 11; color: "#aab7c6"; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Switch 2 FTP"; font.bold: true }
        TextField { id: ftpHost; text: home.ftpState.host; placeholderText: "Switch 2 IP"; Layout.fillWidth: true; enabled: !home.ftpState.busy && !home.working }
        TextField { id: ftpPort; text: home.ftpState.port; placeholderText: "Port"; Layout.preferredWidth: 80; enabled: !home.ftpState.busy && !home.working }
        Button { text: "Connect"; enabled: !home.ftpState.busy && !home.working; onClicked: ftpBrowser.connect_to(ftpHost.text, ftpPort.text) }
        Button { text: "Disconnect"; enabled: home.ftpState.connected && !home.ftpState.busy && !home.working; onClicked: ftpBrowser.disconnect() }
    }
    Label { text: (home.ftpState.busy ? "Connecting / FTP operation in progress" : home.ftpState.connected ? "Connected to " + home.ftpState.host + ":" + home.ftpState.port : "Not connected") + " — " + home.ftpState.status; color: home.ftpState.connected ? "#22c55e" : "#ef4444"; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Live Homebrew Updates"; font.bold: true; color: "#52e0ae" }
        Label { text: home.monitorStatus; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11 }
        Button { text: "Check Now"; onClicked: controller.homebrew_monitor_refresh() }
    }
    RowLayout {
        TextField { id: searchBox; placeholderText: "Search Switch 2 homebrew"; Layout.fillWidth: true; onAccepted: { home.catalogQuery = text; home.updateCatalog() } }
        ComboBox {
            id: categoryBox
            model: ["All", "Tools", "Games", "Streaming", "Emulation", "Fun", "Media", "Other"]
            onActivated: function(index) {
                home.catalogCategory = categoryBox.model[index]
                home.updateCatalog()
            }
        }
        Button { text: "Search"; enabled: !home.working; onClicked: { home.catalogQuery = searchBox.text; home.updateCatalog() } }
        Button { text: "Show all"; enabled: !home.working; onClicked: { searchBox.text = ""; categoryBox.currentIndex = 0; home.catalogQuery = ""; home.catalogCategory = "All"; home.updateCatalog() } }
    }
    Label { text: home.statusText; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Label { text: home.selectedWarning; visible: home.selectedWarning.length > 0; color: "#f59e0b"; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }

    Label { text: "Three-column app catalog • Right-click an app for download options"; font.pixelSize: 11; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        GridView {
            id: projectList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / 3
            cellHeight: 64
            model: home.results
            delegate: ItemDelegate {
                id: projectCard
                required property var modelData
                width: projectList.cellWidth - 6
                height: projectList.cellHeight - 4
                padding: 6
                highlighted: home.selectedRepo !== "" && modelData.repo === home.selectedRepo
                background: Rectangle {
                    radius: 7
                    color: projectCard.highlighted ? "#193d43" : projectCard.hovered ? "#252f3b" : "#1a222c"
                    border.width: projectCard.highlighted ? 2 : 1
                    border.color: projectCard.highlighted ? "#52e0ae" : "#33404d"
                }
                contentItem: RowLayout {
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        radius: 7
                        color: modelData.category === "Emulation" ? "#233b62" : modelData.category === "Games" ? "#513451" : modelData.category === "Streaming" ? "#284c4b" : modelData.category === "Tools" ? "#554329" : "#353b50"
                        Label {
                            anchors.centerIn: parent
                            text: modelData.category === "Emulation" ? "🎮" : modelData.category === "Games" ? "🕹️" : modelData.category === "Streaming" ? "📺" : modelData.category === "Tools" ? "🛠️" : modelData.category === "Media" ? "🎵" : "✨"
                            font.pixelSize: 24
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label {
                            text: modelData.name
                            font.pixelSize: 15
                            font.bold: true
                            color: "#f2f6fa"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            text: modelData.category + "  •  " + (modelData.community ? modelData.source + " • UNVERIFIED" : (modelData.repo ? "GitHub" : "Manual"))
                            font.pixelSize: 11
                            color: "#aab7c6"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
                onClicked: {
                    home.selectApp(modelData)
                    home.statusText = modelData.community ? "Community listing: review GitHub, then choose a verified release asset; installs require confirmation." : "Right-click " + modelData.name + " for actions."
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: function(mouse) {
                        home.selectApp(projectCard.modelData)
                        home.actionRepo = projectCard.modelData.repo
                        home.actionName = projectCard.modelData.name
                        contextMenu.popup()
                    }
                }
                Menu {
                    id: contextMenu
                    width: Math.max(280, implicitWidth)
                    MenuItem {
                        text: "Download Only"
                        width: contextMenu.width
                        enabled: !!home.actionRepo && !home.working
                        onTriggered: home.requestRelease("download")
                    }
                    MenuItem {
                        text: "Download && Install"
                        width: contextMenu.width
                        enabled: !!home.actionRepo && !projectCard.modelData.community && !home.working
                        onTriggered: home.requestRelease("install")
                    }
                    MenuSeparator {}
                    MenuItem {
                        text: home.actionRepo ? "View GitHub Repository" : "View Homebrew Project Directory"
                        width: contextMenu.width
                        onTriggered: Qt.openUrlExternally(home.actionRepo
                            ? "https://github.com/" + home.actionRepo
                            : "https://ouncebrew.github.io/hblist/")
                    }
                }
            }
        }
    }
    RowLayout {
        visible: home.downloadedDirectory.length > 0
        Label { text: "Downloaded ZIP — manual installation required"; color: "#f59e0b" }
        Button { text: "Open download folder"; onClicked: controller.homebrew_open_download_directory(home.downloadedDirectory) }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        visible: home.transferActive || home.transferComplete || home.transferStatus.length > 0
        Label {
            text: home.transferComplete ? "Transfer complete" : home.transferActive ? "Homebrew transfer in progress" : "Last homebrew transfer"
            font.bold: true
        }
        ProgressBar {
            Layout.fillWidth: true
            from: 0
            to: 100
            value: home.transferPercent
        }
        Label {
            text: home.transferPercent + "% complete · " + (100 - home.transferPercent) + "% remaining"
            font.bold: true
            Layout.fillWidth: true
        }
        Label {
            text: home.transferStatus
            wrapMode: Text.WrapAnywhere
            Layout.fillWidth: true
            color: "#aab7c6"
        }
    }
    Dialog {
        id: assetPicker
        title: "Choose verified release asset"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Cancel
        ColumnLayout {
            Label { text: home.actionName; Layout.preferredWidth: 400 }
            ListView {
                Layout.preferredWidth: 400
                Layout.preferredHeight: 240
                clip: true
                model: home.choices
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.name
                    onClicked: {
                        assetPicker.close()
                        home.useAsset(modelData)
                        home.action = ""
                    }
                }
            }
        }
        onRejected: home.action = ""
    }
    Dialog {
        id: downloadOnlyDialog
        title: "Download only — manual installation"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Yes | Dialog.No
        ColumnLayout {
            Label { text: "Download " + home.selectedAsset + " to SteamOS and open its folder?"; wrapMode: Text.Wrap; Layout.preferredWidth: 380 }
            Label { text: "ZIP download only: no extraction or FTP upload. Follow the project’s manual installation instructions. SHA-256 verification is required."; color: "#f59e0b"; wrapMode: Text.Wrap; Layout.preferredWidth: 380 }
        }
        onAccepted: {
            home.transferPercent = 0
            home.transferStatus = "Preparing download: " + home.selectedAsset
            home.transferActive = true
            home.transferComplete = false
            controller.homebrew_download_only(home.selectedRepo, home.selectedAsset)
        }
    }
    Dialog {
        id: installDialog
        title: "Confirm homebrew installation"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            Label { text: "Upload " + home.selectedAsset + " to /switch/ over your existing FTP connection?"; wrapMode: Text.Wrap; Layout.preferredWidth: 330 }
            Label { text: "The existing file will not be overwritten. FTP is unencrypted. Install only software you trust."; wrapMode: Text.Wrap; Layout.preferredWidth: 330 }
        }
        onAccepted: {
            home.transferPercent = 0
            home.transferStatus = "Preparing download and installation: " + home.selectedAsset
            home.transferActive = true
            home.transferComplete = false
            controller.homebrew_install(home.selectedRepo, JSON.stringify({name: home.selectedAsset}), true)
        }
    }

}