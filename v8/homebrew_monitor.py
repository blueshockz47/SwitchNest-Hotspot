"""Read-only release monitoring. Reddit discoveries never authorize downloads."""
import json
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from v8 import homebrew, catalog_sources

USER_AGENT = "SwitchNest-Homebrew-Monitor/8.1.6 (read-only)"
MAX_RESPONSE = 1024 * 1024
DIRECTORY_URL = "https://switch2homebrew.com/"
REDDIT_URL = "https://www.reddit.com/r/SwitchHacks/new.json?limit=25"
REDDIT_TERMS = ("switch 2", "switch2", "kaihen", "libounce", "ounce")

def reddit_discover(opener=urllib.request.urlopen):
    request = urllib.request.Request(REDDIT_URL, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with opener(request, timeout=12) as response:
        raw = response.read(MAX_RESPONSE + 1)
    if len(raw) > MAX_RESPONSE:
        raise ValueError("Reddit response too large")
    entries = json.loads(raw).get("data", {}).get("children", [])
    result = []
    for entry in entries[:25]:
        post = entry.get("data", {}) if isinstance(entry, dict) else {}
        title = post.get("title", "")
        permalink = post.get("permalink", "")
        if not isinstance(title, str) or not isinstance(permalink, str):
            continue
        if not any(term in title.casefold() for term in REDDIT_TERMS):
            continue
        if not re.fullmatch(r"/r/[A-Za-z0-9_]+/comments/[A-Za-z0-9]+/[^?#]*", permalink):
            continue
        result.append({"title": title[:140], "url": "https://www.reddit.com" + permalink,
                       "status": "Unverified community discovery", "source": "Reddit"})
    return result[:15]

def github_updates(fetch=None, repos=None, warnings=None):
    fetch = fetch or homebrew.request_json
    repos = repos if repos is not None else sorted(homebrew.SWITCH2_CANDIDATES)
    result = []
    failures = 0
    for repo in repos:
        if repo not in homebrew.SWITCH2_CANDIDATES:
            continue
        try:
            release = homebrew.release_assets(repo, fetch=fetch)
        except (ValueError, KeyError, OSError, TypeError, urllib.error.URLError) as exc:
            failures += 1
            continue
        if release["assets"]:
            result.append({"repo": repo, "version": release["version"],
                           "asset_count": len(release["assets"]),
                           "url": "https://github.com/" + repo + "/releases",
                           "source": "GitHub", "status": "Official repository release; assets require verification"})
    if warnings is not None and failures:
        warnings.append(f"GitHub discovery unavailable for {failures} curated repositories; results may be incomplete")
    return result

def refresh(fetch=None, reddit_fetch=reddit_discover, repos=None, catalog_fetch=None):
    warnings = []
    github = github_updates(fetch=fetch, repos=repos, warnings=warnings)
    try:
        reddit = reddit_fetch()
    except (ValueError, OSError, TypeError, KeyError, json.JSONDecodeError) as exc:
        reddit = []
        warnings.append("Reddit discovery unavailable: " + type(exc).__name__)
    try:
        catalog, catalog_warnings = catalog_sources.discover(
            fetch=catalog_fetch or catalog_sources.get_text)
        warnings.extend(catalog_warnings)
    except (ValueError, OSError, TypeError, UnicodeError) as exc:
        catalog = []
        warnings.append("Catalog discovery unavailable: " + type(exc).__name__)
    # Directory-only source: no verified feed/API or parser contract yet.
    # Never treat its listings as confirmed releases or installable assets.
    directory = {"source": "Switch2Homebrew", "url": DIRECTORY_URL,
                 "status": "Community directory — unverified; open in browser",
                 "automated": False}
    return {"kind": "monitor", "github": github, "reddit": reddit, "catalog": catalog, "directory": directory,
            "warnings": warnings, "checked_at": datetime.now(timezone.utc).isoformat()}
