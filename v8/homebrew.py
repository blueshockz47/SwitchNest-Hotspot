"""Switch 2 homebrew discovery and conservative FTP installer (unprivileged).

GitHub search results are untrusted. Only explicitly curated repository IDs,
NRO release assets with GitHub SHA-256 digests, and /switch/ destinations
qualify for unattended installation. All other packages require confirmation.
"""
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.parse
import urllib.request

API = "https://api.github.com"
MAX_BYTES = 100 * 1024 * 1024
# Repository IDs are curated here, not inferred from keywords or project names.
# Empty until maintainers review release packaging, provenance and compatibility.
VERIFIED_REPOSITORIES = frozenset()
SYSTEM_EXTENSIONS = (".kip", ".kips", ".nsp", ".bin", ".sys", ".ovl")
USER_AGENT = "SwitchNest-Homebrew/8.1.0"

def request_json(path, opener=urllib.request.urlopen):
    if not path.startswith("/") or path.startswith("//"):
        raise ValueError("Invalid API path")
    req = urllib.request.Request(API + path, headers={
        "Accept": "application/vnd.github+json", "User-Agent": USER_AGENT})
    with opener(req, timeout=15) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024:
        raise ValueError("GitHub response too large")
    return json.loads(data)

def discover(query, fetch=request_json):
    query = query.strip()[:90]
    if not query:
        return []
    data = fetch("/search/repositories?" + urllib.parse.urlencode({
        "q": query, "per_page": 25}))
    result = []
    for item in data.get("items", []):
        name = item.get("full_name", "")
        if (re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", name)
                and not item.get("archived") and not item.get("disabled")):
            result.append({"repo": name, "description": str(item.get("description") or "")[:160],
                           "url": "https://github.com/" + name,
                           "verified": item.get("id") in VERIFIED_REPOSITORIES})
    return result

def release_assets(repo, fetch=request_json):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid repository")
    release = fetch("/repos/" + repo + "/releases/latest")
    items = []
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        if (not re.fullmatch(r"[A-Za-z0-9_.() -]+", name)
                or not url.startswith("https://github.com/" + repo + "/releases/download/")
                or not name.lower().endswith((".nro", ".zip", ".ovl", ".kip", ".bin"))):
            continue
        digest = asset.get("digest") or ""
        size = asset.get("size", 0)
        if not isinstance(size, int) or size <= 0 or size > MAX_BYTES:
            continue
        items.append({"name": name, "url": url, "size": size,
                      "digest": digest if re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest) else "",
                      "system": not name.lower().endswith(".nro")})
    return {"version": str(release.get("tag_name") or "")[:60], "assets": items}

def automatic_allowed(repo_id, asset, destination):
    return (repo_id in VERIFIED_REPOSITORIES
            and asset["name"].lower().endswith(".nro")
            and re.fullmatch(r"sha256:[a-fA-F0-9]{64}", asset.get("digest", "")) is not None
            and destination == "/switch/" + asset["name"])

def validate_destination(name, destination):
    if not re.fullmatch(r"[A-Za-z0-9_.() -]+", name):
        raise ValueError("Invalid asset name")
    if destination != "/switch/" + name or not name.lower().endswith(".nro"):
        raise ValueError("Only single-file NRO installs in /switch/ are supported")
    return destination

def download_asset(asset, directory, opener=urllib.request.urlopen):
    if not asset["url"].startswith("https://github.com/"):
        raise ValueError("Untrusted download host")
    expected = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", expected):
        raise ValueError("Verified SHA-256 digest required")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix=".switchnest-homebrew-", dir=directory)
    digest = hashlib.sha256()
    total = 0
    try:
        with os.fdopen(fd, "wb") as out:
            req = urllib.request.Request(asset["url"], headers={"User-Agent": USER_AGENT})
            with opener(req, timeout=30) as response:
                final_url = urllib.parse.urlsplit(response.geturl())
                if final_url.scheme != "https" or final_url.hostname not in ("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"):
                    raise ValueError("Untrusted download redirect")
                while True:
                    block = response.read(65536)
                    if not block:
                        break
                    total += len(block)
                    if total > MAX_BYTES or total > asset["size"]:
                        raise ValueError("Download exceeds declared size")
                    digest.update(block)
                    out.write(block)
        if total != asset["size"] or digest.hexdigest() != expected.split(":")[1].lower():
            raise ValueError("Download integrity verification failed")
        return Path(path)
    except BaseException:
        Path(path).unlink(missing_ok=True)
        raise

def install_nro(asset, destination, host, port, *, confirmed=False, repo_id=None,
                fetcher=download_asset, tree_factory=None):
    """Upload verified NRO; reject overwrite. No root or networking changes."""
    validate_destination(asset["name"], destination)
    if not (confirmed or automatic_allowed(repo_id, asset, destination)):
        raise PermissionError("Installation confirmation required")
    address = ipaddress.IPv4Address(host)
    if address not in ipaddress.IPv4Network("10.42.60.0/24") or int(address) & 255 in (0, 1, 255):
        raise ValueError("Invalid FTP endpoint")
    if not 1 <= int(port) <= 65535:
        raise ValueError("Invalid FTP port")
    from v8.ftp_tree import Tree
    factory = tree_factory or Tree
    with tempfile.TemporaryDirectory(prefix="switchnest-homebrew-") as temp:
        path = fetcher(asset, temp)
        target = Path(temp) / asset["name"]
        os.replace(path, target)
        tree = factory(str(address), int(port), "skip", lambda: False, lambda *_: None)
        existing = tree.entries("/switch/")
        if asset["name"] in existing:
            raise FileExistsError("Existing homebrew file; backup or remove it manually")
        tree.upload(target, "/switch/")
        if tree.sizes("/switch/").get(asset["name"]) != asset["size"]:
            raise OSError("Remote file verification failed")
    return "Installed and verified: " + destination
