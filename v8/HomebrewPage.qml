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
    property string statusText: "Search the curated Switch 2 homebrew catalog. Listings do not verify compatibility."
    spacing: 8
    Connections {
        target: controller
        function onHomebrewBusy(value) { home.working = value }
        function onHomebrewResult(raw) {
            try {
                let data = JSON.parse(raw)
                if (data.kind === "search") { home.results = data.items; home.assets = []; home.statusText = data.items.length + " Switch 2 candidate repositories found (not compatibility-verified)" }
                else if (data.kind === "assets") { home.selectedRepo = data.repo; home.assets = data.assets; home.statusText = "Release " + data.version + " — ZIP packages are listed but not installable yet" }
                else { home.statusText = data.message || "Unknown result" }
            } catch (e) { home.statusText = "Invalid homebrew response" }
        }
    }
    Label { text: "Switch 2 Homebrew Manager"; font.pixelSize: 22; font.bold: true }
    Label { text: "Only Switch 2 candidate projects are listed. NRO installation requires a GitHub SHA-256 digest and explicit confirmation. ZIPs and system packages are display-only."; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                    if (modelData.name.toLowerCase().endsWith(".nro") && modelData.digest)
                        installDialog.open()
                    else
                        home.statusText = "This package is display-only. ZIP installation is not supported; only verified individual NRO files can be installed."
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
}
