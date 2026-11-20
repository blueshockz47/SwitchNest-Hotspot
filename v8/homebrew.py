"""Switch 2 homebrew discovery and conservative FTP installer (unprivileged).

GitHub search results are untrusted. Only explicitly curated repository IDs,
NRO release assets with GitHub SHA-256 digests, and /switch/ destinations
qualify for unattended installation. All other packages require confirmation.
"""
import hashlib
import urllib.error
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

# Explicit Switch 2 / kaiHEN candidate catalog. A catalog entry does not
# verify its binaries or authorize automatic installation.
# Names/categories from the community Switch 2 homebrew list. Catalog membership
# is NOT a compatibility audit or permission to install arbitrary release assets.
# Projects without an individually reviewed GitHub repository remain browse-only.
CATALOG = (
    ("RetroArch", "Emulation", "NerdsMcGee/retroarch-s2"),
    ("SW2NES", "Emulation", "Rodpad/SW2NES"),
    ("SW2SNES", "Emulation", "Rodpad/SW2SNES"),
    ("SW2PS2", "Emulation", "Rodpad/SW2PS2"),
    ("Toronja (3DS)", "Emulation", "Olmectron/toronja"),
    ("OunceShell", "Tools", None),
    ("90DNS Tester", "Tools", "souldbminerr/90DNS-Tester"),
    ("Force Internal Speaker", "Tools", "souldbminerr/switch_internal_speakers_nro"),
    ("FTPD Plugin", "Tools", "NerdsMcGee/kaihen-ftpd-plugin"),
    ("Checkpoint", "Tools", "wowilookgood/Checkpoint"),
    ("PKSM", "Tools", "wowilookgood/PKSM"),
    ("NXGallery", "Tools", "wowilookgood/NXGallery"),
    ("Donkey Kong Country 2", "Games", "souldbminerr/DKC2Recomp-NX"),
    ("Donkey Kong Country 3", "Games", "souldbminerr/DKC3Recomp-NX"),
    ("xStarbound", "Games", "Sergaliciousnes/xStarbound-Switch2"),
    ("Super Mario 64 EX", "Games", "NerdsMcGee/sm64ex-alo-s2"),
    ("Sonic 3 AIR", "Games", "NerdsMcGee/sonic3air-s2"),
    ("Sonic Robo Blast 2", "Games", "misshexa66/SRB2-Ounce"),
    ("Dr. Robotnik's Ring Racers", "Games", "misshexa66/RingRacers-Ounce"),
    ("UnleashedRecomp", "Games", "Lightmaxifrvr/UnleashedRecomp-NX2"),
    ("pokeplatinum", "Games", "cybervisi0n/pokeplatinum"),
    ("Dusklight", "Games", "wowilookgood/dusklight"),
    ("Nic Cage Eats Stuff", "Games", "PennyLoafer5/nces-switch2"),
    ("Angry Birds Reloaded", "Games", "githubuser77777/abreloaded_nx2"),
    ("OpenRCT2", "Games", "souldbminerr/OpenRCT2-Switch"),
    ("Chiaki-ng/Akira", "Streaming", "chiaki-ng/akira-ounce"),
    ("Moonlight", "Streaming", None),
    ("Donut", "Fun", "Rix565/ouncedonut"),
    ("Bad Apple!", "Fun", "souldbminerr/bad-apple-switch"),
    ("KaiTube", "Streaming", "Sank-kab/KaiTube"),
    ("Super Smash Bros. Melee", "Games", "Prlxd/melee-switch2-port"),
    ("KaiPlayer", "Media", "mizuiroame/kaiplayer"),
)
CATALOG_SOURCE = "https://ouncebrew.github.io/hblist/"
SWITCH2_CANDIDATES = frozenset(repo for _, _, repo in CATALOG if repo)

# Conservative installation guidance; catalog membership never implies a safe install.
# Download-only entries require checking the project's own installation guide.
MANUAL_INSTALL_NAMES = frozenset({
    "FTPD Plugin", "Force Internal Speaker", "PKSM", "Checkpoint",
    "SW2NES", "SW2SNES", "SW2PS2", "Toronja (3DS)",
    "Super Smash Bros. Melee", "UnleashedRecomp", "Sonic 3 AIR",
    "Sonic Robo Blast 2", "Dr. Robotnik's Ring Racers", "OpenRCT2",
    "xStarbound", "pokeplatinum", "Chiaki-ng/Akira", "Moonlight",
})

def catalog_search(query="", category="All"):
    query = query.strip()[:90].casefold()
    if category not in {"All", "Tools", "Games", "Streaming", "Emulation", "Fun", "Media"}:
        raise ValueError("Invalid homebrew category")
    rows = []
    for name, kind, repo in CATALOG:
        if category != "All" and kind != category:
            continue
        if query and not (query in name.casefold() or query in kind.casefold()
                          or (repo and query in repo.casefold())):
            continue
        if name == "RetroArch":
            mode = "ZIP installation (review required)"
            warning = "Review the verified ZIP contents and destinations before FTP installation."
        elif name in MANUAL_INSTALL_NAMES:
            mode = "Download only / manual installation"
            warning = "Manual installation or additional files/setup may be required. Follow the project's Switch 2 instructions; do not upload blindly to /switch/."
        elif repo:
            mode = "Release browser / conditional installation"
            warning = "Only verified .nro or compatible ZIP release assets can use the installer. Other assets are download-only or unsupported."
        else:
            mode = "Browse only / manual download"
            warning = "No reviewed release source is configured. Consult the linked community catalog and project documentation for download and manual installation."
        rows.append({"name": name, "category": kind, "repo": repo or "",
                     "status": mode, "warning": warning,
                     "manual": name in MANUAL_INSTALL_NAMES or not repo,
                     "source": CATALOG_SOURCE})
    return rows

# Discovery limit for displaying release packages (no downloads implied).
MAX_LISTING_BYTES = 2 * 1024 * 1024 * 1024

def discover(query, fetch=request_json):
    query = query.strip()[:90].casefold()
    if not query:
        return []
    result = []
    for repo in sorted(SWITCH2_CANDIDATES):
        if query not in repo.casefold():
            continue
        item = fetch("/repos/" + repo)
        name = item.get("full_name", "")
        if (name.casefold() != repo.casefold()
                or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", name)
                or item.get("archived") or item.get("disabled")):
            continue
        result.append({"repo": name,
                       "description": str(item.get("description") or "")[:160],
                       "url": "https://github.com/" + name,
                       "verified": item.get("id") in VERIFIED_REPOSITORIES})
    return result

def release_assets(repo, fetch=request_json):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid repository")
    try:
        release = fetch("/repos/" + repo + "/releases/latest")
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        releases = fetch("/repos/" + repo + "/releases?per_page=20")
        if not isinstance(releases, list):
            raise ValueError("Unexpected GitHub releases response") from exc
        release = next((entry for entry in releases
                        if isinstance(entry, dict) and not entry.get("draft")
                        and entry.get("assets")), None)
        if release is None:
            raise ValueError("No published GitHub release assets found for " + repo) from exc
    items = []
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        if (not re.fullmatch(r"[A-Za-z0-9_.() -]+", name)
                or not url.startswith("https://github.com/" + repo + "/releases/download/")
                or not name.lower().endswith((".nro", ".zip", ".ovl", ".kip", ".bin", ".txt"))):
            continue
        digest = asset.get("digest") or ""
        size = asset.get("size", 0)
        if not isinstance(size, int) or size <= 0 or size > MAX_LISTING_BYTES:
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
