"""Unprivileged, bounded cache for read-only GitHub release metadata.

Cached metadata is never trusted for installation; installers re-fetch upstream.
"""
import json
import os
import re
import time
from pathlib import Path

CACHE_FILE = Path.home() / ".cache" / "switchnest" / "homebrew" / "releases.json"
TTL_SECONDS = 24 * 3600
COOLDOWN_SECONDS = 3600
MAX_CACHE_BYTES = 1024 * 1024
REPO_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")


def _read(path=CACHE_FILE):
    try:
        if path.stat().st_size > MAX_CACHE_BYTES:
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError, TypeError, UnicodeError):
        return {}


def _write(data, path=CACHE_FILE):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    try:
        with temp.open("w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False)
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _valid_release(data):
    if not isinstance(data, dict) or not isinstance(data.get("version"), str):
        return False
    assets = data.get("assets")
    if not isinstance(assets, list) or len(assets) > 100:
        return False
    return all(isinstance(a, dict) and isinstance(a.get("name"), str)
               and isinstance(a.get("url"), str) and isinstance(a.get("size"), int)
               and isinstance(a.get("digest"), str) for a in assets)


def get(repo, now=None, path=CACHE_FILE):
    if not isinstance(repo, str) or not REPO_PATTERN.fullmatch(repo):
        return None
    now = time.time() if now is None else now
    entry = _read(path).get("releases", {}).get(repo)
    if not isinstance(entry, dict) or not _valid_release(entry.get("data")):
        return None
    timestamp = entry.get("checked_at")
    if not isinstance(timestamp, (int, float)) or timestamp > now + 60:
        return None
    return {"data": entry["data"], "stale": now - timestamp >= TTL_SECONDS}


def put(repo, release, now=None, path=CACHE_FILE):
    if not REPO_PATTERN.fullmatch(repo) or not _valid_release(release):
        return
    now = time.time() if now is None else now
    state = _read(path)
    releases = state.get("releases", {})
    if not isinstance(releases, dict):
        releases = {}
    releases = {key: value for key, value in releases.items()
                if isinstance(value, dict) and isinstance(value.get("checked_at"), (int, float))
                and now - value["checked_at"] < 7 * TTL_SECONDS}
    releases[repo] = {"checked_at": now, "data": release}
    state["releases"] = releases
    _write(state, path)


def cooldown_remaining(now=None, path=CACHE_FILE):
    now = time.time() if now is None else now
    until = _read(path).get("rate_limit_until", 0)
    return max(0, int(until - now)) if isinstance(until, (int, float)) else 0


def mark_limited(now=None, path=CACHE_FILE):
    now = time.time() if now is None else now
    state = _read(path)
    state["rate_limit_until"] = now + COOLDOWN_SECONDS
    _write(state, path)
