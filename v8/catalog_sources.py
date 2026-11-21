"""Untrusted read-only community catalogs. No package downloads or installs."""
import csv
import io
import json
import re
import urllib.request
from urllib.parse import urlsplit

BREWSTORE = "https://raw.githubusercontent.com/HerXayah/brewstore-repo/main/packages.json"
IZ2S = "https://raw.githubusercontent.com/dadadush/switch2-homebrew-catalog/main/catalog/catalog.tsv"
MAX_BYTES = 512 * 1024
REPO = re.compile(r"^/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$")
MANIFEST = re.compile(r"^/HerXayah/brewstore-repo/main/packages/[A-Za-z0-9_.-]+/manifest\.json$")
AGENT = "SwitchNest-Homebrew-Catalog/8.1.6"


CATEGORY_MAP = {
    "tools": "Tools", "tool": "Tools", "utilities": "Tools", "utility": "Tools",
    "system": "Tools", "file managers": "Tools", "file manager": "Tools",
    "games": "Games", "game": "Games", "gaming": "Games",
    "emulators": "Emulation", "emulator": "Emulation", "emulation": "Emulation",
    "media": "Media", "music": "Media", "audio": "Media", "video": "Media",
    "streaming": "Streaming", "stream": "Streaming",
    "fun": "Fun", "entertainment": "Fun",
}
# Conservative title/repository hints used only when the source has no useful category.
HINTS = {
    "Emulation": ("cemu", "ppsspp", "retroarch", "snes", "nes", "gba", "mgba", "dolphin", "scummvm", "psp", "openrac", "nxengine"),
    "Streaming": ("moonlight", "chiaki", "stream", "sunshine", "strem"),
    "Media": ("youtube", "tube", "radio", "music", "video", "player", "torrent"),
    "Games": ("game vault", "donkey kong", "mario", "shipwright", "gravity rush", "starship", "pursuit", "openblops"),
    "Tools": ("ftp", "file manager", "browser", "chromium", "installer", "checkpoint", "shell", "90dns", "dns", "transfer", "dump", "patch", "brewstore", "switchfin", "sphaira", "pkforge", "blacklist", "nx2now"),
}

def normalize_category(category, name="", repo=""):
    """Classify for browsing only; never implies verification or install safety."""
    raw = str(category or "").strip().lower()
    haystack = (str(name) + " " + str(repo).split("/")[-1]).lower()
    # Explicit corrections take precedence over vague upstream Media/Other labels.
    if "moonlight" in haystack or "chiaki" in haystack or "strem" in haystack:
        return "Streaming"
    if "switch2now" in haystack or "switch2now" in haystack.replace("-", ""):
        return "Tools"
    if raw in CATEGORY_MAP:
        return CATEGORY_MAP[raw]
    if raw and raw not in ("other", "misc", "miscellaneous", "unknown", "uncategorized"):
        return "Other"
    haystack = (str(name) + " " + str(repo).split("/")[-1]).lower()
    for group, hints in HINTS.items():
        if any(hint in haystack for hint in hints):
            return group
    return "Other"

def get_text(url, opener=urllib.request.urlopen):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com":
        raise ValueError("Catalog host not allowed")
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with opener(request, timeout=10) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("Catalog response too large")
    return data.decode("utf-8")

def repo_from_url(url):
    if not isinstance(url, str):
        return ""
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "github.com" or not REPO.fullmatch(parsed.path):
        return ""
    return parsed.path.strip("/")

def iz2s_rows(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "IZSTORE2":
        raise ValueError("Unsupported i2zs catalog format")
    rows = []
    current = None
    for line in lines[1:]:
        parts = line.split("\t")
        if parts[0] == "app" and len(parts) >= 8:
            current = {"name": parts[4][:100], "category": parts[6][:40],
                       "version": parts[3][:50], "format": parts[2][:12],
                       "description": parts[7][:240], "repo": "",
                       "source": "i2zs", "status": "Unverified catalog listing"}
            rows.append(current)
        elif parts[0] == "repository" and len(parts) >= 2 and current:
            current["repo"] = repo_from_url(parts[1])
    for row in rows:
        row["category"] = normalize_category(row["category"], row["name"], row["repo"])
    return [r for r in rows if r["repo"]][:250]

def brewstore_rows(index_text, fetch=get_text):
    index = json.loads(index_text)
    if not isinstance(index, dict) or not isinstance(index.get("include"), list):
        raise ValueError("Unsupported BrewStore index")
    rows = []
    for url in index["include"][:100]:
        parsed = urlsplit(url) if isinstance(url, str) else None
        if not parsed or parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com" or not MANIFEST.fullmatch(parsed.path):
            continue
        try:
            data = json.loads(fetch(url))
            if not isinstance(data, dict):
                continue
            packages = data.get("packages", [])
            if not isinstance(packages, list):
                continue
            for package in packages[:10]:
                if not isinstance(package, dict):
                    continue
                repo = repo_from_url(package.get("url", ""))
                if not repo:
                    continue
                rows.append({"name": str(package.get("title") or package.get("name") or repo.split("/")[-1])[:100],
                             "category": normalize_category(package.get("category"), package.get("title") or package.get("name") or "", repo),
                             "version": str(package.get("version") or "")[:50],
                             "format": "unknown", "description": str(package.get("description") or "")[:240],
                             "repo": repo, "source": "BrewStore",
                             "status": "Unverified catalog listing"})
        except (ValueError, TypeError, OSError, UnicodeError, json.JSONDecodeError):
            continue
    return rows

def discover(fetch=get_text):
    warnings = []
    entries = []
    try:
        entries.extend(iz2s_rows(fetch(IZ2S)))
    except (ValueError, OSError, UnicodeError, TypeError) as exc:
        warnings.append("i2zs catalog unavailable: " + type(exc).__name__)
    try:
        entries.extend(brewstore_rows(fetch(BREWSTORE), fetch=fetch))
    except (ValueError, OSError, UnicodeError, TypeError) as exc:
        warnings.append("BrewStore catalog unavailable: " + type(exc).__name__)
    merged = {}
    for row in entries:
        key = row["repo"].casefold()
        if key not in merged:
            merged[key] = dict(row, sources=[row["source"]])
        else:
            if row["source"] not in merged[key]["sources"]:
                merged[key]["sources"].append(row["source"])
            if merged[key]["category"] == "Other" and row["category"] != "Other":
                merged[key]["category"] = row["category"]
    return list(merged.values()), warnings
