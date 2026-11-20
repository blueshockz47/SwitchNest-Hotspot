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
        with target.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() == asset["digest"][7:].lower():
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

def install_zip(path, plan, host, port, *, confirmed=False, tree_factory=None,
                progress=None, cancelled=None):
    """Resume safely: compare remote bytes against archive SHA-256 before skipping.

    Incomplete/unverified remote files are never overwritten. The user must
    remove those files manually before retrying; this avoids destructive FTP
    operations. Files completed during earlier attempts are verified by
    downloading them and comparing SHA-256 against the ZIP entry.
    """
    if not confirmed:
        raise PermissionError("Explicit install confirmation required")
    current = inspect_zip(path)
    if current != plan:
        raise ValueError("ZIP content changed since preview")
    from v8.ftp_tree import Tree
    factory = tree_factory or Tree
    stop = cancelled or (lambda: False)
    tree = factory(host, port, "skip", stop, lambda *_: None)
    entries_cache = {}
    sizes_cache = {}
    def check():
        if stop():
            raise InterruptedError("Installation cancelled; completed files can be resumed")
    def listing(directory):
        if directory not in entries_cache:
            entries_cache[directory] = tree.entries(directory)
        return entries_cache[directory]
    def sizes(directory):
        if directory not in sizes_cache:
            sizes_cache[directory] = tree.sizes(directory)
        return sizes_cache[directory]
    def emit(done, index, name, state):
        if progress:
            progress(done, current["bytes"], index, current["count"], name, state)
    done = 0
    emit(0, 0, "", "Preparing")
    with zipfile.ZipFile(path) as z, tempfile.TemporaryDirectory(prefix="switchnest-zip-") as td:
        root = Path(td)
        for index, item in enumerate(current["files"], 1):
            check()
            parts = item["path"].split("/")
            name = parts[-1]
            directory = "/"
            for part in parts[:-1]:
                check()
                existing = listing(directory)
                if part in existing:
                    if not existing[part]:
                        raise FileExistsError("Directory conflicts with file: " + directory + part)
                else:
                    tree.run(directory, ["--quote", "MKD " + directory + part,
                                         "--output", os.devnull])
                    existing[part] = True
                directory += part + "/"
            check()
            expected = item["size"]
            dest = root / name
            # Extract only the current member to avoid requiring 1.3 GiB
            # of temporary space and to make cancellation responsive.
            h = hashlib.sha256()
            with z.open(item["path"]) as src, dest.open("wb") as out:
                written = 0
                while True:
                    check()
                    chunk = src.read(256 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > expected:
                        raise ValueError("ZIP member expanded beyond declared size")
                    out.write(chunk)
                    h.update(chunk)
            if written != expected:
                raise ValueError("ZIP member size mismatch")
            existing = listing(directory)
            if name in existing:
                if existing[name]:
                    raise FileExistsError("File conflicts with directory: " + directory + name)
                if sizes(directory).get(name) != expected:
                    raise FileExistsError("Incomplete remote file: " + directory + name +
                                          ". Remove it using FTP File Manager to resume.")
                # Verify actual remote bytes, not just the size. Existing
                # user data with the same name must never be trusted.
                remote = root / ("remote-" + str(index))
                tree.run(directory + name, ["--output", str(remote)], size=expected)
                remote_hash = hashlib.sha256()
                with remote.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(256 * 1024), b""):
                        check()
                        remote_hash.update(chunk)
                remote.unlink()
                if remote_hash.digest() != h.digest():
                    raise FileExistsError("Different remote file: " + directory + name +
                                          ". Back it up or remove it manually.")
                state = "Verified existing file"
            else:
                emit(done, index, item["path"], "Uploading")
                # Upload directly with existing curl/PASV transport. The
                # remote size is checked by Tree.upload. An interrupted
                # partial file is preserved for manual inspection/removal.
                if progress:
                    tree.expected_total = expected
                    tree.finished_bytes = 0
                    tree.metric = lambda transferred, _total, _speed: emit(
                        done + min(expected, transferred), index, item["path"], "Uploading")
                tree.upload(dest, directory)
                tree.metric = lambda *_: None
                existing[name] = False
                sizes_cache.pop(directory, None)
                state = "Uploaded and size-verified"
            done += expected
            emit(done, index, item["path"], state)
            dest.unlink()
    return "Completed " + str(current["count"]) + " files (verified or uploaded)"
