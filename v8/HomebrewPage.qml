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
                       warning: "Unverified community listing. GitHub release NROs can be installed after explicit confirmation, even without a publisher digest; ZIPs are download-only."})
        }
        let q = catalogQuery.toLowerCase().trim()
        let filtered = rows.filter(function(item) {
            if (catalogCategory !== "All" && item.category !== catalogCategory) return false
            return !q || [item.name, item.repo, item.category, item.source || ""].join(" ").toLowerCase().indexOf(q) !== -1
        })
        let order = ["Emulation", "Games", "Tools", "Streaming", "Media", "Fun", "Other"]
        filtered.sort(function(a, b) {
            let ai = order.indexOf(a.category), bi = order.indexOf(b.category)
            if (ai < 0) ai = order.length
            if (bi < 0) bi = order.length
            return ai - bi || (a.name || "").localeCompare(b.name || "", undefined, {sensitivity: "base"})
        })
        let counts = ({})
        for (let item of filtered) counts[item.category] = (counts[item.category] || 0) + 1
        let last = ""
        for (let item of filtered) {
            item.categoryStart = item.category !== last
            item.categoryCount = counts[item.category]
            last = item.category
        }
        results = filtered
        let groups = []
        for (let item of filtered) {
            if (!groups.length || groups[groups.length - 1].name !== item.category)
                groups.push({name: item.category, items: []})
            groups[groups.length - 1].items.push(item)
        }
        categoryGroups = groups
        statusText = results.length + " projects shown (curated + community, deduplicated). NRO installs require confirmation; publisher checksums may be unavailable."
    }
    property var categoryGroups: []
    function categoryColor(category) {
        return category === "Emulation" ? "#60a5fa" : category === "Games" ? "#f472b6" :
               category === "Tools" ? "#38bdf8" : category === "Streaming" ? "#2dd4bf" :
               category === "Media" ? "#fb7185" : category === "Fun" ? "#fb923c" : "#94a3b8"
    }
    function categoryIcon(category) {
        return category === "Emulation" ? "🎮" : category === "Games" ? "🕹️" :
               category === "Tools" ? "🛠️" : category === "Streaming" ? "📺" :
               category === "Media" ? "🎵" : "✨"
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
    property string monitorStatus: "Ready to check homebrew releases"
    property bool monitorChecking: false
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
                if (data.kind === "monitor_progress") {
                    home.monitorChecking = true
                    home.monitorStatus = data.message || "Checking homebrew releases..."
                    return
                }
                home.monitorChecking = false
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
                home.monitorChecking = false
                home.monitorStatus = "Invalid discovery response"
            }
        }
    }
    property string activeCategory: "All"
    property string action: ""
    property string actionRepo: ""
    property string actionName: ""
    property var choices: []
    property var installableRepos: ({})
    property var zipOnlyRepos: ({})
    property var checkedRepos: ({})
    property var staleRepos: ({})
    function restoreReleaseStatuses() {
        controller.homebrew_cached_releases()
    }
    property string probingRepo: ""
    function probeRelease(repo) {
        if (!repo || working) return
        probingRepo = repo
        action = "probe"
        statusText = "Checking GitHub release assets for " + repo + "..."
        controller.homebrew_releases(repo)
    }
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
            else statusText = "Connect to your Switch 2 FTP server above, then retry Download & Install. Only single-file GitHub release NRO packages can be uploaded to /switch/."
        }
    }
    spacing: 4
    Component.onCompleted: { home.restoreReleaseStatuses(); controller.homebrew_search("", "All"); Qt.callLater(function() { controller.homebrew_monitor_refresh(false) }) }
    onVisibleChanged: { if (visible) Qt.callLater(function() { controller.homebrew_monitor_refresh(false) }) }
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
                if (data.kind === "cached_releases") {
                    let available = Object.assign({}, home.installableRepos)
                    let zipped = Object.assign({}, home.zipOnlyRepos)
                    let checked = Object.assign({}, home.checkedRepos)
                    let stale = Object.assign({}, home.staleRepos)
                    for (let repo in data.releases) {
                        let info = data.releases[repo]
                        available[repo] = info.assets.some(function(a) { return a.name.toLowerCase().endsWith(".nro") })
                        zipped[repo] = !available[repo] && info.assets.some(function(a) { return a.name.toLowerCase().endsWith(".zip") })
                        checked[repo] = true
                        stale[repo] = !!info.stale
                    }
                    home.installableRepos = available
                    home.zipOnlyRepos = zipped
                    home.checkedRepos = checked
                    home.staleRepos = stale
                }
                else if (data.kind === "search") { home.curatedResults = data.items; home.assets = []; home.readyZip = ""; home.activeCategory = data.category || "All"; home.updateCatalog() }
                else if (data.kind === "assets") {
                    if (home.action === "probe" && data.repo === home.probingRepo) {
                        let eligible = data.assets.some(function(asset) { return asset.name.toLowerCase().endsWith(".nro") })
                        let next = Object.assign({}, home.installableRepos)
                        next[data.repo] = eligible
                        home.installableRepos = next
                        let checked = Object.assign({}, home.checkedRepos)
                        checked[data.repo] = true
                        home.checkedRepos = checked
                        let stale = Object.assign({}, home.staleRepos)
                        stale[data.repo] = !!data.stale
                        home.staleRepos = stale
                        let zipOnly = !eligible && data.assets.some(function(asset) { return asset.name.toLowerCase().endsWith(".zip") })
                        let zipState = Object.assign({}, home.zipOnlyRepos)
                        zipState[data.repo] = zipOnly
                        home.zipOnlyRepos = zipState
                        home.statusText = (data.stale ? "Cached release information (may be outdated). " : "") + (eligible ? "NRO release available for " + data.repo + ". Right-click again to install." : "No NRO release for " + data.repo + "; ZIP-only projects cannot be installed automatically.")
                        home.action = ""
                        home.probingRepo = ""
                        return
                    }
                    if (data.repo !== home.actionRepo || !home.action) return
                    home.choices = data.assets.filter(function(asset) {
                        let name = asset.name.toLowerCase()
                        return home.action === "install" ? name.endsWith(".nro") : (!!asset.digest && (name.endsWith(".nro") || name.endsWith(".zip")))
                    })
                    if (home.choices.length === 1) {
                        home.useAsset(home.choices[0])
                        home.action = ""
                    } else if (home.choices.length > 1) assetPicker.open()
                    else { home.statusText = "No compatible GitHub release asset for " + home.actionName + ". ZIP and download-only actions still require a GitHub SHA-256 digest."; home.action = "" }
                }
                else if (data.kind === "rate_limited") {
                    home.statusText = data.message || "GitHub API limit reached. Retry later."
                    home.action = ""
                    home.probingRepo = ""
                }
                else if (data.kind === "error" && home.action === "probe") {
                    home.statusText = "Release check failed: " + (data.message || "Unknown error")
                    home.action = ""
                    home.probingRepo = ""
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
    Label { text: "Homebrew Manager"; font.pixelSize: 22; font.bold: true; color: "#f0f5ff" }
    Label { text: "Discover Switch 2 homebrew, review release verification, and install supported NROs over FTP"; font.pixelSize: 12; color: "#aab7c6"; Layout.fillWidth: true; wrapMode: Text.Wrap }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "SWITCH 2 FTP"; font.bold: true; color: "#40c9b7"; font.pixelSize: 12 }
        TextField { id: ftpHost; text: home.ftpState.host; placeholderText: "Switch 2 IP"; Layout.fillWidth: true; enabled: !home.ftpState.busy && !home.working }
        TextField { id: ftpPort; text: home.ftpState.port; placeholderText: "Port"; Layout.preferredWidth: 80; enabled: !home.ftpState.busy && !home.working }
        Button { text: "Connect"; enabled: !home.ftpState.busy && !home.working; onClicked: ftpBrowser.connect_to(ftpHost.text, ftpPort.text) }
        Button { text: "Disconnect"; enabled: home.ftpState.connected && !home.ftpState.busy && !home.working; onClicked: ftpBrowser.disconnect() }
    }
    Label { text: (home.ftpState.busy ? "Connecting / FTP operation in progress" : home.ftpState.connected ? "Connected to " + home.ftpState.host + ":" + home.ftpState.port : "Not connected") + " — " + home.ftpState.status; color: home.ftpState.connected ? "#22c55e" : "#ef4444"; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "RELEASE MONITOR"; font.bold: true; color: "#40c9b7"; font.pixelSize: 12 }
        Label { text: home.monitorStatus; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 11 }
        Button { text: home.monitorChecking ? "Checking..." : "Check Now"; enabled: !home.monitorChecking; onClicked: controller.homebrew_monitor_refresh(true) }
    }
    ProgressBar {
        Layout.fillWidth: true
        visible: home.monitorChecking
        indeterminate: true
    }
    Label { text: "APP CATALOG"; font.bold: true; color: "#40c9b7"; font.pixelSize: 12; Layout.topMargin: 8 }
    RowLayout {
        TextField { id: searchBox; placeholderText: "Search apps, repositories, categories..."; Layout.fillWidth: true; onAccepted: { home.catalogQuery = text; home.updateCatalog() } }
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

    Label { text: home.results.length + " apps shown  •  Right-click an app to inspect download and install options"; font.pixelSize: 11; color: "#9fb2c9"; Layout.fillWidth: true }
    ScrollView {
        id: projectScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Column {
            width: projectScroll.availableWidth
            spacing: 14
            Repeater {
                model: home.categoryGroups
                delegate: Column {
                    id: categorySection
                    required property var modelData
                    width: parent.width
                    spacing: 8
                    Rectangle {
                        width: parent.width
                        height: 36
                        radius: 5
                        color: "#202e40"
                        border.color: home.categoryColor(categorySection.modelData.name)
                        border.width: 1
                        Rectangle {
                            width: 4
                            height: parent.height - 8
                            radius: 2
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: home.categoryColor(categorySection.modelData.name)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 17
                            anchors.rightMargin: 14
                            spacing: 10
                            Label { text: home.categoryIcon(categorySection.modelData.name); font.pixelSize: 17 }
                            Label {
                                text: categorySection.modelData.name
                                font.pixelSize: 15
                                font.bold: true
                                color: home.categoryColor(categorySection.modelData.name)
                            }
                            Rectangle {
                                Layout.preferredWidth: countLabel.implicitWidth + 18
                                Layout.preferredHeight: 24
                                radius: 12
                                color: "#33465e"
                                Label {
                                    id: countLabel
                                    anchors.centerIn: parent
                                    text: categorySection.modelData.items.length + " apps"
                                    font.pixelSize: 11
                                    color: "#f8fafc"
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: 8
                        rowSpacing: 5
                        Repeater {
                            model: categorySection.modelData.items
                            delegate: Loader {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: (categorySection.width - 16) / 3
                                Layout.preferredHeight: 62
                                sourceComponent: homebrewCard
                                onLoaded: item.modelData = modelData
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: homebrewCard
        ItemDelegate {
                id: projectCard
                property var modelData: ({})
                width: parent ? parent.width : 320
                height: 62
                padding: 5
                highlighted: home.selectedRepo !== "" && modelData.repo === home.selectedRepo
                background: Rectangle {
                    radius: 5
                    color: projectCard.highlighted ? "#1b4054" : projectCard.hovered ? "#293e55" : "#1d293a"
                    Behavior on color { ColorAnimation { duration: 160 } }
                    border.width: projectCard.highlighted ? 2 : 1
                    border.color: projectCard.highlighted ? "#5eead4" : projectCard.hovered ? home.categoryColor(modelData.category) : "#35465b"
                }
                contentItem: RowLayout {
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 5
                        color: "#24384e"
                        border.color: home.categoryColor(modelData.category)
                        border.width: 2
                        Label {
                            anchors.centerIn: parent
                            text: home.categoryIcon(modelData.category)
                            font.pixelSize: 22
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label {
                            text: modelData.name
                            font.pixelSize: 14
                            font.bold: true
                            color: "#f2f6fa"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: !!modelData.repo && home.checkedRepos[modelData.repo] !== true
                            text: "Release Not Checked"
                            font.pixelSize: 10
                            color: "#aab7c6"
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: !!modelData.repo && home.installableRepos[modelData.repo] === true
                            text: home.staleRepos[modelData.repo] ? "NRO Available — Cached Release" : "NRO Available — Download & Install"
                            font.pixelSize: 10
                            color: "#52e0ae"
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: !!modelData.repo && home.zipOnlyRepos[modelData.repo] === true
                            text: home.staleRepos[modelData.repo] ? "ZIP File — Manual Install (Cached)" : "ZIP File — Manual Install Required"
                            font.pixelSize: 10
                            font.bold: true
                            color: "#f59e0b"
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
                    home.statusText = modelData.community ? "Community listing: review the GitHub release; NRO installation requires confirmation." : "Right-click " + modelData.name + " for actions."
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: function(mouse) {
                        home.selectApp(projectCard.modelData)
                        home.actionRepo = projectCard.modelData.repo
                        home.actionName = projectCard.modelData.name
                        contextMenu.popup()
                        if (home.actionRepo && home.installableRepos[home.actionRepo] === undefined) home.probeRelease(home.actionRepo)
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
                        enabled: !!home.actionRepo && home.installableRepos[home.actionRepo] === true && !home.working
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
            Label { text: "UNVERIFIED NROs may lack a publisher checksum. A locally computed SHA-256 does not prove safety. The existing file will not be overwritten. FTP is unencrypted. Install only software you trust."; wrapMode: Text.Wrap; Layout.preferredWidth: 330 }
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