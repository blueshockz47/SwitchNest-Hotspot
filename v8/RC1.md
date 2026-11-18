# SwitchNest v8.0-RC.1

Install on SteamOS Desktop Mode using `bash install-switchnest-v8.sh` from a trusted extracted checkout, without sudo. Close the existing application first. Internet and at least 2 GiB free space are required. The installer runs Python compilation, FTP and installer regression tests, and Qt import checks before activation. It does not install the v7.1 hotspot backend. Existing hotspot, firewall, DNS and settings remain unchanged.

Launch from KDE or `~/.local/share/switchnest/launch`. Check installed versions with `cd ~/.local/share/switchnest/current && python3 -m v8.install status`; use `rollback` instead of `status` to switch to the previous managed release. Rollback source: milestone/v8.0-beta.2.

## Release gates

- Clean install and update on SteamOS; verify old launcher resolves current release.
- Rollback after two managed installs and confirm preferences survive.
- Run `python3 -m unittest -v v8.test_ftp_tree v8.test_install` and inspect CI.
- Confirm actual Qt window, small-screen controls, hotspot on/off and local FTP PASV connection.
- Verify uploads/downloads, conflicts, nested deletion, cancel/retry, bookmarks and large-file metrics using disposable data.
- Verify network isolation independently; diagnostics are not proof of isolation.

## Known limitations

FTP is unencrypted. Size verification is not a checksum. Transfer retry restarts unfinished entries; byte-offset resume is not supported. Remote free capacity unavailable. Transfer estimates may include skipped files. Hard-link-based no-clobber downloads may fail on exFAT. Cancellation does not undo deletion or remove remote partial files. Automatic online updates are not implemented. No public release or hardware certification yet.
