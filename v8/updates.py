"""Read release metadata only; never execute downloaded content."""
import json
import re
import shutil
import subprocess
import urllib.request

VERSION="8.1.7"
REPO="blueshockz47/SwitchNest-Hotspot"
RELEASES="https://github.com/"+REPO+"/releases"
DEVELOPMENT="https://github.com/"+REPO+"/tree/development/v8.0"

def version_key(value):
    m=re.fullmatch(r"v?(\d+)\.(\d+)(?:\.(\d+))?(?:-(alpha|beta|rc)\.(\d+)|-stable-final)?",value,re.I)
    if not m: raise ValueError("Unsupported version")
    major,minor,patch,stage,number=m.groups()
    return int(major),int(minor),int(patch or 0),{"alpha":0,"beta":1,"rc":2,None:3}[stage.lower() if stage else None],int(number or 0)

def release_url(tag):
    """Construct a GitHub URL only from a validated release tag."""
    version_key(tag)
    return RELEASES + "/tag/" + tag

def check(channel):
    if channel not in ("stable","development"): raise ValueError("Invalid channel")
    endpoint="repos/"+REPO+"/releases?per_page=100"
    if shutil.which("gh"):
        result=subprocess.run(["gh","api",endpoint],capture_output=True,text=True,timeout=20)
        if result.returncode: raise RuntimeError("GitHub CLI lookup failed. Check gh auth login or open GitHub in your browser.")
        releases=json.loads(result.stdout)
    else:
        try:
            request=urllib.request.Request("https://api.github.com/"+endpoint,headers={"Accept":"application/vnd.github+json","User-Agent":"SwitchNest"})
            with urllib.request.urlopen(request,timeout=15) as response:
                releases=json.load(response)
        except OSError as exc:
            raise RuntimeError("Release lookup unavailable. Private repositories need authenticated GitHub CLI or browser access.") from exc
    candidates=[]
    for release in releases:
        if release.get("draft") or (channel=="stable" and release.get("prerelease")): continue
        tag=release.get("tag_name","")
        try: key=version_key(tag)
        except ValueError: continue
        if channel=="stable" and key[3]!=3: continue
        candidates.append((key,tag))
    if not candidates: return "No published releases found for this channel."
    key,tag=max(candidates)
    return ("Update available: "+tag if key>version_key(VERSION) else "No newer published release. Latest: "+tag)
