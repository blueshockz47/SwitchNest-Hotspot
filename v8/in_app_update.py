"""Download and install a published SwitchNest release without opening a browser.

Only SHA-256-verified GitHub release assets are accepted; never run an installer
script from an archive. The existing unprivileged v8 installer handles rollback.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

from v8 import updates

MAX_BYTES = 100 * 1024 * 1024

def _json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SwitchNest-Updater", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=25) as response:
        return json.load(response)

def latest_stable():
    data = _json("https://api.github.com/repos/" + updates.REPO + "/releases/latest")
    tag = data.get("tag_name", "")
    if updates.version_key(tag) <= updates.version_key(updates.VERSION):
        raise RuntimeError("No newer stable release available")
    assets = data.get("assets", [])
    matches = [a for a in assets if a.get("name", "").endswith(".zip") and a.get("name", "").startswith("SwitchNest-Hotspot-Linux-")]
    matches = [a for a in matches if a.get("name") == "SwitchNest-Hotspot-Linux-" + tag + ".zip"]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one Linux release ZIP asset")
    asset = matches[0]
    digest = asset.get("digest", "")
    if not digest.startswith("sha256:") or len(digest) != 71 or any(c not in "0123456789abcdefABCDEF" for c in digest[7:]):
        raise RuntimeError("Release asset lacks a verifiable SHA-256 digest")
    url = asset.get("browser_download_url", "")
    if not url.startswith("https://github.com/" + updates.REPO + "/releases/download/"):
        raise RuntimeError("Untrusted release asset URL")
    return tag, url, digest[7:]

def install_latest():
    if os.geteuid() == 0:
        raise RuntimeError("Updater must run without sudo")
    print("Checking latest stable release...", flush=True)
    tag, url, digest = latest_stable()
    print("Downloading " + tag + "...", flush=True)
    with tempfile.TemporaryDirectory(prefix="switchnest-update-") as temp:
        folder = Path(temp)
        archive = folder / "update.zip"
        req = urllib.request.Request(url, headers={"User-Agent": "SwitchNest-Updater"})
        h = hashlib.sha256()
        total = 0
        with urllib.request.urlopen(req, timeout=40) as response, archive.open("wb") as dest:
            header = response.headers.get("Content-Length")
            expected_bytes = int(header) if header and header.isdecimal() else None
            if expected_bytes is not None and expected_bytes > MAX_BYTES:
                raise RuntimeError("Update exceeds size limit")
            print("SWITCHNEST_PROGRESS:" + json.dumps({"stage": "download", "bytes": 0, "total": expected_bytes}), flush=True)
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_BYTES:
                    raise RuntimeError("Update exceeds size limit")
                if total // (5 * 1024 * 1024) != (total - len(chunk)) // (5 * 1024 * 1024):
                    print(f"Downloaded {total / (1024 * 1024):.1f} MiB", flush=True)
                print("SWITCHNEST_PROGRESS:" + json.dumps({"stage": "download", "bytes": total, "total": expected_bytes}), flush=True)
                h.update(chunk)
                dest.write(chunk)
        print("SWITCHNEST_PROGRESS:" + json.dumps({"stage": "verify"}), flush=True)
        print("Verifying SHA-256 checksum...", flush=True)
        if h.hexdigest() != digest:
            raise RuntimeError("Update checksum mismatch")
        print("SWITCHNEST_PROGRESS:" + json.dumps({"stage": "extract"}), flush=True)
        print("Checksum verified. Extracting release...", flush=True)
        target = folder / "source"
        target.mkdir()
        with zipfile.ZipFile(archive) as z:
            names = z.infolist()
            if len(names) > 1000:
                raise RuntimeError("Too many archive entries")
            if sum(entry.file_size for entry in names) > MAX_BYTES * 3:
                raise RuntimeError("Uncompressed archive exceeds size limit")
            for entry in names:
                p = Path(entry.filename)
                if p.is_absolute() or ".." in p.parts or not p.parts or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise RuntimeError("Unsafe ZIP entry")
                if entry.file_size > MAX_BYTES:
                    raise RuntimeError("Oversized ZIP entry")
                if entry.is_dir():
                    continue
                if p.name in ("install.py", "control_center.py") and len(p.parts) < 3:
                    raise RuntimeError("Unexpected archive layout")
            z.extractall(target)
        roots = [p for p in target.iterdir() if p.is_dir()]
        if len(roots) != 1 or not (roots[0] / "v8" / "install.py").is_file():
            raise RuntimeError("Unexpected release structure")
        expected = roots[0] / "v8" / "install.py"
        if ("VERSION = \"" + tag.removeprefix("v") + "\"") not in expected.read_text():
            raise RuntimeError("Release version does not match its tag")
        # Run the installer only after the verified release is fully extracted.
        print("SWITCHNEST_PROGRESS:" + json.dumps({"stage": "install"}), flush=True)
        print("Installing " + tag + " (this can take several minutes)...", flush=True)
        subprocess.run([sys.executable, "-m", "v8.install", "install"], cwd=roots[0], check=True, env={**os.environ, "PYTHONPATH": str(roots[0])})
    return "Installed " + tag + ". Close and reopen SwitchNest to use the update."

if __name__ == "__main__":
    try:
        print(install_latest(), flush=True)
    except Exception as exc:
        print("Update failed: " + str(exc), file=sys.stderr, flush=True)
        sys.exit(1)
