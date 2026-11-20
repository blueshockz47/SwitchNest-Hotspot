import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: home
    property var results: []
    property var assets: []
    property string selectedRepo: ""
    property string selectedAsset: ""
    property bool working: false
    property string readyZip: ""
    property string previewText: ""
    property string statusText: "Search the curated Switch 2 homebrew catalog. Listings do not verify compatibility."
    spacing: 8
    Connections {
        target: controller
        function onHomebrewBusy(value) { home.working = value }
        function onHomebrewResult(raw) {
            try {
                let data = JSON.parse(raw)
                if (data.kind === "search") { home.results = data.items; home.assets = []; home.readyZip = ""; home.statusText = data.items.length + " Switch 2 candidate repositories found (not compatibility-verified)" }
                else if (data.kind === "assets") { home.selectedRepo = data.repo; home.assets = data.assets; home.readyZip = ""; home.statusText = "Release " + data.version + " — select a ZIP to download and preview" }
                else if (data.kind === "zip_ready") {
                    home.readyZip = data.name
                    home.previewText = data.count + " files (" + Math.round(data.bytes / 1048576) + " MiB extracted)\\n" + data.sample.join("\\n")
                    home.statusText = "Download verified. Review files before installing."
                    installZipDialog.open()
                }
                else { home.statusText = data.message || "Unknown result" }
            } catch (e) { home.statusText = "Invalid homebrew response" }
        }
    }
    Label { text: "Switch 2 Homebrew Manager"; font.pixelSize: 22; font.bold: true }
    Label { text: "Only Switch 2 candidate projects are listed. NRO installation requires a GitHub SHA-256 digest and explicit confirmation. ZIPs require a verified download followed by separate installation confirmation."; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        TextField { id: searchBox; placeholderText: "Search Switch 2 homebrew"; Layout.fillWidth: true; onAccepted: controller.homebrew_search(text) }
        Button { text: "Search"; enabled: !home.working; onClicked: controller.homebrew_search(searchBox.text) }
    }
    Label { text: home.statusText; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Repositories"; font.bold: true; Layout.fillWidth: true }
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
                text: modelData.repo
                onClicked: { home.selectedRepo = modelData.repo; controller.homebrew_releases(modelData.repo) }
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
                    if (modelData.name.toLowerCase().endsWith(".zip") && modelData.digest)
                        downloadZipDialog.open()
                    else if (modelData.name.toLowerCase().endsWith(".nro") && modelData.digest)
                        installDialog.open()
                    else
                        home.statusText = "Unsupported package. ZIP and NRO require a valid SHA-256; other assets are display-only."
                }
            }
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
        onAccepted: controller.homebrew_install(home.selectedRepo, JSON.stringify({name: home.selectedAsset}), true)
    }
    Dialog {
        id: downloadZipDialog
        title: "Download Switch 2 homebrew?"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Yes | Dialog.No
        ColumnLayout {
            Label { text: "Download " + home.selectedAsset + " to the SteamOS cache and verify SHA-256?"; wrapMode: Text.Wrap; Layout.preferredWidth: 380 }
            Label { text: "This does not install anything on the Switch 2. Large downloads may take several minutes."; wrapMode: Text.Wrap; Layout.preferredWidth: 380 }
        }
        onAccepted: controller.homebrew_download_zip(home.selectedRepo, home.selectedAsset)
    }
    Dialog {
        id: installZipDialog
        title: "Install downloaded ZIP to Switch 2?"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Yes | Dialog.No
        ColumnLayout {
            Label { text: "Download complete and SHA-256 verified. Install these files to the Switch 2 SD card via FTP?"; wrapMode: Text.Wrap; Layout.preferredWidth: 420 }
            ScrollView {
                Layout.preferredWidth: 420
                Layout.preferredHeight: 220
                TextArea { readOnly: true; text: home.previewText; wrapMode: Text.WrapAnywhere }
            }
            Label { text: "Preview shows up to 12 files. Existing remote files are not overwritten. FTP is unencrypted; interrupted transfers may leave partial files."; wrapMode: Text.Wrap; Layout.preferredWidth: 420 }
        }
        onAccepted: controller.homebrew_install_zip(home.selectedRepo, home.readyZip, true)
    }

}
