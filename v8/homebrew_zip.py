"""Explicit download -> review -> install workflow for Switch 2 ZIP releases.

No privileged operations. ZIPs remain local until the user confirms an
installation preview. No overwrites, links, or unsafe archive paths.
"""
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import zipfile

from v8 import homebrew

CACHE = Path.home() / ".cache" / "switchnest" / "homebrew"
MAX_ZIP_BYTES = 1024 * 1024 * 1024
MAX_EXPANDED_BYTES = 3 * 1024 * 1024 * 1024
MAX_FILES = 30000

def _asset_ok(asset):
    name = asset["name"]
    if not name.lower().endswith(".zip") or "/" in name or "\\" in name:
        raise ValueError("Only safe ZIP release packages are supported")
    if not 0 < asset["size"] <= MAX_ZIP_BYTES:
        raise ValueError("ZIP package exceeds 1 GiB download limit")
    if not homebrew.re.fullmatch(r"sha256:[a-fA-F0-9]{64}", asset.get("digest", "")):
        raise ValueError("GitHub SHA-256 required")

def download_zip(asset, cache=CACHE, opener=None, progress=None):
    """Download to a temporary file and atomically retain only verified data."""
    _asset_ok(asset)
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(cache, 0o700)
    target = cache / asset["digest"].split(":")[1].lower() / asset["name"]
    if target.is_file() and target.stat().st_size == asset["size"]:
        if hashlib.file_digest(target.open("rb"), "sha256").hexdigest() == asset["digest"][7:].lower():
            return target
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(prefix=".download-", dir=target.parent)
    os.close(fd)
    try:
        # download_asset validates HTTPS redirect host, byte size and SHA-256.
        # Its 100 MiB cap is for individual NROs; ZIP downloads use an explicit
        # bounded streaming implementation with the same host restrictions.
        import urllib.request
        import urllib.parse
        req = urllib.request.Request(asset["url"], headers={"User-Agent": homebrew.USER_AGENT})
        h = hashlib.sha256()
        total = 0
        with (opener or urllib.request.urlopen)(req, timeout=45) as response, open(tmp, "wb") as out:
            url = urllib.parse.urlsplit(response.geturl())
            if url.scheme != "https" or url.hostname not in (
                "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"):
                raise ValueError("Untrusted download redirect")
            while True:
                chunk = response.read(256 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > asset["size"] or total > MAX_ZIP_BYTES:
                    raise ValueError("Download exceeds declared size")
                out.write(chunk)
                h.update(chunk)
                if progress:
                    progress(total, asset["size"])
        if total != asset["size"] or h.hexdigest() != asset["digest"][7:].lower():
            raise ValueError("ZIP integrity verification failed")
        os.replace(tmp, target)
        return target
    finally:
        Path(tmp).unlink(missing_ok=True)

def inspect_zip(path):
    """Return a bounded, safe install plan without extracting anything."""
    path = Path(path)
    files = []
    total = 0
    seen = set()
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            raw = info.filename
            if "\\" in raw or raw.startswith("/") or "\x00" in raw:
                raise ValueError("Unsafe ZIP path")
            parts = PurePosixPath(raw).parts
            if not parts or any(p in ("", ".", "..") for p in raw.rstrip("/").split("/")):
                raise ValueError("Unsafe ZIP path")
            if len(parts) > 64 or any(ord(c) < 32 or ord(c) == 127 for c in raw):
                raise ValueError("Unsafe ZIP entry")
            mode = info.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError("ZIP links and special files are unsupported")
            if info.flag_bits & 0x1:
                raise ValueError("Encrypted ZIP unsupported")
            key = "/".join(parts).rstrip("/").casefold()
            if key in seen:
                raise ValueError("Duplicate ZIP path")
            seen.add(key)
            if info.is_dir():
                continue
            if info.file_size < 0 or info.file_size > MAX_EXPANDED_BYTES:
                raise ValueError("Oversized ZIP member")
            total += info.file_size
            files.append({"path": "/".join(parts), "size": info.file_size})
            if total > MAX_EXPANDED_BYTES or len(files) > MAX_FILES:
                raise ValueError("ZIP extraction limits exceeded")
    if not files:
        raise ValueError("Empty ZIP")
    return {"files": files, "count": len(files), "bytes": total,
            "sample": ["/" + f["path"] for f in files[:12]]}

def install_zip(path, plan, host, port, *, confirmed=False, tree_factory=None, progress=None):
    if not confirmed:
        raise PermissionError("Explicit install confirmation required")
    current = inspect_zip(path)
    if current != plan:
        raise ValueError("ZIP content changed since preview")
    from v8.ftp_tree import Tree
    factory = tree_factory or Tree
    tree = factory(host, port, "skip", lambda: False, lambda *_: None)
    # Preflight every remote destination, rejecting any file/folder conflict
    # before writing. This also avoids silently skipping existing files.
    dirs = {""}
    for item in current["files"]:
        parts = item["path"].split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]))
    for directory in sorted(dirs, key=lambda s: (s.count("/"), s)):
        if not directory:
            continue
        parent, name = directory.rsplit("/", 1) if "/" in directory else ("", directory)
        existing = tree.entries("/" + parent + "/" if parent else "/")
        if name in existing and not existing[name]:
            raise FileExistsError("Remote path conflicts with file: /" + directory)
    for item in current["files"]:
        parts = item["path"].split("/")
        parent = "/" + "/".join(parts[:-1]) + "/" if len(parts) > 1 else "/"
        try:
            existing = tree.entries(parent)
        except OSError:
            # Parent may not yet exist; checked when uploading.
            existing = {}
        if parts[-1] in existing:
            raise FileExistsError("Remote file exists: /" + item["path"])
    with tempfile.TemporaryDirectory(prefix="switchnest-zip-") as td:
        root = Path(td)
        with zipfile.ZipFile(path) as z:
            for item in current["files"]:
                dest = root.joinpath(*item["path"].split("/"))
                dest.parent.mkdir(parents=True, exist_ok=True)
                with z.open(item["path"]) as src, open(dest, "xb") as out:
                    shutil.copyfileobj(src, out, 256 * 1024)
                if dest.stat().st_size != item["size"]:
                    raise ValueError("Extracted file size mismatch")
        for child in sorted(root.iterdir()):
            tree.upload(child, "/")
        return "Uploaded " + str(current["count"]) + " files to Switch 2 (FTP size-verified)"
