import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: home
    property var ftpState: ftpBrowser ? JSON.parse(ftpBrowser.state) : ({host: "", port: "", status: "Initializing FTP...", busy: false, connected: false})
    property var results: []
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
    property string transferStatus: ""
    property bool installingZip: false
    property string statusText: "Loading the curated Switch 2 homebrew catalog..."
    spacing: 8
    Component.onCompleted: controller.homebrew_search("", "All")
    Connections {
        target: ftpBrowser
        function onChanged() { home.ftpState = JSON.parse(ftpBrowser.state) }
    }
    Connections {
        target: controller
        function onHomebrewBusy(value) { home.working = value; if (!value) home.installingZip = false }
        function onHomebrewProgress(raw) {
            let p = JSON.parse(raw)
            if (p.total > 0) home.transferPercent = Math.min(100, Math.round(p.done * 100 / p.total))
            home.transferStatus = (p.index ? p.index + "/" + p.count + " — " : "") + (p.status || "") + (p.name ? ": " + p.name : "")
        }
        function onHomebrewResult(raw) {
            try {
                let data = JSON.parse(raw)
                if (data.kind === "search") { home.results = data.items; home.assets = []; home.readyZip = ""; home.statusText = data.items.length + " community-listed Switch 2 projects. Browse-only entries cannot be installed automatically." }
                else if (data.kind === "assets") { home.selectedRepo = data.repo; home.assets = data.assets; home.readyZip = ""; home.statusText = "Release " + data.version + " — verified NRO: install over FTP; verified ZIP: download only and open folder" }
                else if (data.kind === "download_only_ready") {
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
                else { home.statusText = data.message || "Unknown result" }
            } catch (e) { home.statusText = "Invalid homebrew response" }
        }
    }
    Label { text: "Switch 2 Homebrew Manager"; font.pixelSize: 22; font.bold: true }
    Label { text: "Only Switch 2 candidate projects are listed. NRO installation requires a GitHub SHA-256 digest and explicit confirmation. ZIPs are download-only and must be installed manually."; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
        TextField { id: searchBox; placeholderText: "Search Switch 2 homebrew"; Layout.fillWidth: true; onAccepted: controller.homebrew_search(text, categoryBox.currentText) }
        ComboBox { id: categoryBox; model: ["All", "Tools", "Games", "Streaming", "Emulation", "Fun", "Media"]; onActivated: controller.homebrew_search(searchBox.text, currentText) }
        Button { text: "Search"; enabled: !home.working; onClicked: controller.homebrew_search(searchBox.text, categoryBox.currentText) }
        Button { text: "Show all"; enabled: !home.working; onClicked: { searchBox.text = ""; categoryBox.currentIndex = 0; controller.homebrew_search("", "All") } }
    }
    Label { text: home.statusText; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Label { text: home.selectedWarning; visible: home.selectedWarning.length > 0; color: "#f59e0b"; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Label { text: "Catalog source: https://ouncebrew.github.io/hblist/ — listings are not security or compatibility verification."; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Switch 2 projects"; font.bold: true; Layout.fillWidth: true }
        Label { text: "Release assets"; font.bold: true; Layout.fillWidth: true }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: home.results
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData.name + " [" + modelData.category + "] — " + modelData.status
                onClicked: {
                    home.selectedManual = modelData.manual
                    home.selectedWarning = "⚠ " + modelData.warning
                    if (modelData.repo) { home.selectedRepo = modelData.repo; controller.homebrew_releases(modelData.repo) }
                    else { home.assets = []; home.statusText = modelData.name + " is browse-only. See the community Switch 2 Homebrew List for its official download link; no FTP installation is enabled." }
                }
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: home.assets
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData.name + (modelData.digest ? " (SHA-256)" : " (no digest)")
                onClicked: {
                    home.selectedAsset = modelData.name
                    if (!modelData.digest) {
                        home.statusText = "SHA-256 unavailable: automatic installation and download are disabled."
                    } else if (modelData.name.toLowerCase().endsWith(".nro")) {
                        if (!home.ftpState.connected)
                            home.statusText = "Connect to Switch 2 FTP before installing this NRO."
                        else
                            installDialog.open()
                    } else if (modelData.name.toLowerCase().endsWith(".zip")) {
                        downloadOnlyDialog.open()
                    } else {
                        home.statusText = "Unsupported asset format. Only verified NRO and ZIP packages are supported."
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
        visible: home.installingZip || home.transferStatus.length > 0
        Label { text: "Switch 2 ZIP FTP installation"; font.bold: true }
        ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: home.transferPercent }
        Label { text: home.transferPercent + "% — " + home.transferStatus; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
        Button {
            text: "Cancel installation"
            enabled: home.installingZip && home.working
            onClicked: controller.homebrew_cancel_install()
        }
        Label { text: "To resume, select the same ZIP and confirm installation again. Completed files are checked before skipping; incomplete files require manual cleanup."; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
        onAccepted: controller.homebrew_download_only(home.selectedRepo, home.selectedAsset)
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
        onAccepted: controller.homebrew_install(home.selectedRepo, JSON.stringify({name: home.selectedAsset}), true)
    }

}