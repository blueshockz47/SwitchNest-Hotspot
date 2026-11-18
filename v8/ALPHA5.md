 # Alpha.5 FTP preview

Run the existing Control Center from the project root. Open Files, connect to the local FTP server, and select files to transfer. Default 10.42.60.99:1337. Uses curl traditional PASV and ignores the server-advertised PASV address. No firewall changes. Upload confirmation warns of replacement and partial files; downloads refuse existing destinations. Directory listings retry twice; transfers do not automatically retry. Test with disposable files first. Qt runtime and upload hardware tests pending. FTP is unencrypted.
