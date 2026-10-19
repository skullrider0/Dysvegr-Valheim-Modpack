#!/usr/bin/env python3
"""Dysvegr Thunderstore update scanner. Python standard library only.

Never installs files. 'check' prints a report; 'prepare' writes a proposed
server manifest for a separate, backed-up install. Invalid/partial scans
cannot produce an install manifest.
"""
import datetime
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / ".dysvegr-updates"
BASE = ROOT / "mods.tsv"
LOCAL = ROOT / "mods.local.tsv"
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
NAME = re.compile(r"^[A-Za-z0-9_-]+$")
BASE_URL = os.environ.get("THUNDERSTORE_BASE_URL", "https://thunderstore.io").rstrip("/")
BLOCKED = {"MSchmoecker-MultiUserChest", "cybrp-ItemDrawers"}

def version(v):
    if not isinstance(v, str) or not SEMVER.fullmatch(v):
        raise ValueError("Unrecognized version: " + repr(v))
    return tuple(map(int, v.split(".")))

def load_manifest(path):
    rows = []
    seen = set()
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            raise ValueError(f"{path}:{lineno}: expected three TAB-separated fields")
        package, ver, mode = fields
        if (not NAME.fullmatch(package) or package.count("-") < 1 or
                mode not in ("server", "client", "framework") or package in seen):
            raise ValueError(f"{path}:{lineno}: invalid row: {raw}")
        version(ver)
        seen.add(package)
        rows.append((package, ver, mode))
    if not rows:
        raise ValueError(f"{path} is empty")
    return rows

def effective_manifest():
    base = load_manifest(BASE)
    if not LOCAL.exists():
        return base
    local = {name: (v, mode) for name, v, mode in load_manifest(LOCAL)}
    # GitHub's manifest remains authoritative for package selection and
    # server/client role. Retain previously approved newer local versions.
    result = []
    for name, pinned, mode in base:
        local_row = local.get(name)
        if local_row and local_row[1] == mode and version(local_row[0]) > version(pinned):
            result.append((name, local_row[0], mode))
        else:
            result.append((name, pinned, mode))
    return result

def package_json(name):
    namespace, package = name.split("-", 1)
    paths = [
        f"/api/experimental/package/{namespace}/{package}/",
        f"/api/experimental/frontend/c/valheim/p/{namespace}/{package}/",
    ]
    errors = []
    for path in paths:
        url = BASE_URL + path
        for attempt in range(2):
            try:
                request = Request(url, headers={
                    "Accept": "application/json",
                    "User-Agent": "Dysvegr-Valheim-Modpack-update-check/1.0",
                })
                with urlopen(request, timeout=25) as resp:
                    if resp.status != 200:
                        raise ValueError(f"HTTP {resp.status}")
                    data = resp.read(4_000_001)
                    if len(data) > 4_000_000:
                        raise ValueError("Response exceeded safe limit")
                    return json.loads(data)
            except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as err:
                errors.append(f"{path}: {err}")
                if isinstance(err, HTTPError) and err.code not in (429, 500, 502, 503, 504):
                    break
                if attempt == 0:
                    time.sleep(1.2)
    raise RuntimeError(" | ".join(errors)[-850:])

def latest_version(info):
    if not isinstance(info, dict):
        raise ValueError("Unexpected API response (not an object)")
    pkg = info.get("package")
    if isinstance(pkg, dict):
        info = pkg
    if info.get("is_deprecated") or info.get("is_active") is False:
        raise ValueError("Package is deprecated or inactive")
    versions = []
    candidate = info.get("latest")
    if isinstance(candidate, dict):
        versions.append(candidate)
    if isinstance(info.get("latest_version"), dict):
        versions.append(info["latest_version"])
    value = info.get("versions")
    if isinstance(value, list):
        versions.extend(x for x in value if isinstance(x, dict))
    parsed = []
    for item in versions:
        if item.get("is_active") is False:
            continue
        ver = item.get("version_number") or item.get("version")
        if isinstance(ver, str) and SEMVER.fullmatch(ver):
            parsed.append((version(ver), ver, item))
    if not parsed:
        # Never guess a release from an unexpected/new API shape.
        raise ValueError("No active semantic versions found in API response")
    _, name, metadata = max(parsed, key=lambda record: record[0])
    return name, metadata

def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)

def serialize_manifest(rows):
    return "# package_id\tversion\tmode\n" + "".join(
        "\t".join(row) + "\n" for row in rows
    )

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode not in ("check", "prepare"):
        raise ValueError("Usage: python3 check-updates.py [check|prepare] [--all]")
    include_client = "--all" in sys.argv[2:] or mode == "check"
    installed = effective_manifest()
    changes = {}
    failures = []
    checked = 0
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = [f"Dysvegr Thunderstore version check -- {now}",
             "Server updates are never applied by scheduled checks.", ""]
    for package, old, role in installed:
        if role == "framework":
            continue  # ich777 updates the BepInEx framework separately
        if role == "client" and not include_client:
            continue
        checked += 1
        try:
            info = package_json(package)
            latest, metadata = latest_version(info)
            if version(latest) > version(old):
                changes[package] = (old, latest, role, metadata)
                lines.append(f"UPDATE [{role:6}] {package}   {old} -> {latest}")
            elif version(latest) < version(old):
                lines.append(f"WARNING [{role}] {package} installed {old} exceeds available {latest}")
            # Avoid spamming an enormous up-to-date mod list into the report.
        except Exception as exc:
            failures.append((package, str(exc)))
            lines.append(f"FAILED [{role:6}] {package}: {exc}")
        time.sleep(0.15)
    count_server = sum(1 for item in changes.values() if item[2] == "server")
    count_client = sum(1 for item in changes.values() if item[2] == "client")
    lines += ["", f"Checked {checked} packages; new: {count_server} server, {count_client} client; errors: {len(failures)}."]
    if not changes:
        lines.append("No newer versions detected among successfully checked packages.")
    if count_client:
        lines.append("Update client-only mods through Thunderstore/r2modman, not the dedicated server.")
    lines.append("Review compatibility and ensure players update matching multiplayer mods before applying server changes.")
    report = "\n".join(lines) + "\n"
    CACHE.mkdir(exist_ok=True)
    atomic_text(CACHE / "latest-report.txt", report)
    print(report)
    if failures:
        if mode == "prepare":
            (CACHE / "pending-mods.tsv").unlink(missing_ok=True)
        raise RuntimeError("Update scan incomplete; installation is blocked. See the failures above.")

    # Only 'prepare' writes an install candidate. A routine check can NEVER
    # create a pending install, even when new versions exist.
    if mode == "prepare":
        if not count_server:
            (CACHE / "pending-mods.tsv").unlink(missing_ok=True)
            print("No server mod updates to install.")
            return
        candidate = [(name, changes[name][1] if name in changes and role == "server" else old, role)
                     for name, old, role in installed]
        selected = {name: (v, role) for name, v, role in candidate}
        dependency_errors = []
        for package, (_, newver, role, metadata) in changes.items():
            if role != "server":
                continue
            deps = metadata.get("dependencies", [])
            if not isinstance(deps, list):
                dependency_errors.append(f"{package}: unrecognized dependencies structure")
                continue
            for dep in deps:
                if not isinstance(dep, str):
                    dependency_errors.append(f"{package}: unrecognized dependency {dep!r}")
                    continue
                match = re.fullmatch(r"(.+)-(\d+\.\d+\.\d+)", dep)
                if not match:
                    dependency_errors.append(f"{package}: unrecognized dependency {dep}")
                    continue
                depname, depver = match.groups()
                if depname in BLOCKED:
                    dependency_errors.append(f"{package}: update depends on excluded conflicting mod {depname}")
                elif depname not in selected:
                    dependency_errors.append(f"{package}: requires package not in curated modpack: {depname}")
                elif selected[depname][1] == "client":
                    dependency_errors.append(f"{package}: requires client-only package {depname}")
                elif version(selected[depname][0]) < version(depver):
                    dependency_errors.append(f"{package}: dependency {depname} needs {depver}, selected {selected[depname][0]}")
        if dependency_errors:
            (CACHE / "pending-mods.tsv").unlink(missing_ok=True)
            for error in dependency_errors:
                print("BLOCKED: " + error, file=sys.stderr)
            raise RuntimeError("Dependency changes need manual review; nothing will be installed.")
        atomic_text(CACHE / "pending-mods.tsv", serialize_manifest(candidate))
        atomic_text(CACHE / "current-mods.tsv", serialize_manifest(installed))
        print(f"Prepared {count_server} server updates for review. No installed files were changed.")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as err:
        print("ERROR: " + str(err), file=sys.stderr)
        sys.exit(1)
