# Beta.1

Rollback: milestone/v8.0-alpha.10. Hotspot engine unchanged. Select mode permits tapping folders for selection instead of navigation. Batch deletion captures side and path; single-file deletion uses the same confirmed worker. Search clears selection. Saved FTP endpoints are validated before LIST. Listing and metadata operations reset stale transfer metrics.

Run `python3 -m unittest -v v8.test_ftp_tree` from the repository root. CI also compiles Python source. Tests use temporary files and mocked FTP commands; no real console is contacted. Verify actual console FTP and QML on SteamOS before release. Byte-offset resume remains pending; size verification is not checksum verification. Cancellation is not rollback. Test the complete alpha.10 feature set and offline hotspot on/off. Do not mark beta stable until validation passes.
