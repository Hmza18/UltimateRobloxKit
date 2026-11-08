#!/usr/bin/env python3
"""Add community Wally packages to a Rojo game made with the kit.

  python3 scripts/automation/packages.py --project ~/games/MyGame               # Fusion, Promise, ProfileStore
  python3 scripts/automation/packages.py --project ~/games/MyGame --only profilestore --no-install
  python3 scripts/automation/packages.py --list

What it does:
1. Writes or updates <project>/wally.toml with pinned versions (shared packages under [dependencies],
   ProfileStore under [server-dependencies], because it is a server-realm package).
2. Maps Packages -> ReplicatedStorage.Packages and ServerPackages -> ServerScriptService.ServerPackages
   in default.project.json (existing mappings are kept).
3. Runs `wally install` when Wally is on PATH (Rokit installs it from the template's rokit.toml).
   It never downloads or runs anything else.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Verified against the Wally index on 2026-11-08 (`wally install` resolved all three).
PACKAGES = {
    "fusion": {"alias": "Fusion", "spec": "elttob/fusion@0.3.0", "realm": "shared", "license": "MIT", "author": "Daniel P H Fox"},
    "promise": {"alias": "Promise", "spec": "evaera/promise@4.0.0", "realm": "shared", "license": "MIT", "author": "Eryn L. K."},
    "profilestore": {"alias": "ProfileStore", "spec": "lm-loleris/profilestore@1.0.3", "realm": "server",
                     "license": "Apache-2.0", "author": "loleris (MAD STUDIO)"},
}
SECTION = {"shared": "dependencies", "server": "server-dependencies"}


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", name.lower()).strip("-") or "game"


def update_manifest(text: str, chosen: list[str], game: str) -> str:
    if not text.strip():
        text = (f'[package]\nname = "you/{slug(game)}"\nversion = "0.1.0"\n'
                'registry = "https://github.com/UpliftGames/wally-index"\nrealm = "shared"\n')
    for key in chosen:
        pkg = PACKAGES[key]
        header = f"[{SECTION[pkg['realm']]}]"
        line = f'{pkg["alias"]} = "{pkg["spec"]}"'
        existing = re.search(rf'^{pkg["alias"]}\s*=.*$', text, flags=re.M)
        if existing:
            text = text[:existing.start()] + line + text[existing.end():]
        elif (m := re.search(rf"^{re.escape(header)}[ \t]*$", text, flags=re.M)):
            # Only a real section header at the start of a line, never the same words in a comment.
            text = text[:m.end()] + "\n" + line + text[m.end():]
        else:
            text = text.rstrip("\n") + f"\n\n{header}\n{line}\n"
    return text if text.endswith("\n") else text + "\n"


def update_project(project: dict, need_shared: bool, need_server: bool) -> dict:
    tree = project.setdefault("tree", {"$className": "DataModel"})
    if need_shared:
        rs = tree.setdefault("ReplicatedStorage", {"$className": "ReplicatedStorage"})
        rs.setdefault("Packages", {"$path": "Packages"})
    if need_server:
        sss = tree.setdefault("ServerScriptService", {"$className": "ServerScriptService"})
        sss.setdefault("ServerPackages", {"$path": "ServerPackages"})
    return project


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path)
    ap.add_argument("--only", help="comma-separated: " + ",".join(PACKAGES))
    ap.add_argument("--no-install", action="store_true", help="only write files")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    if a.list:
        for key, p in PACKAGES.items():
            print(f"{key:13} {p['spec']:32} {p['realm']:7} {p['license']:11} {p['author']}")
        return 0
    if not a.project:
        ap.error("--project is required")
    project = a.project.expanduser().resolve()
    project_file = project / "default.project.json"
    if not project_file.exists():
        sys.exit(f"{project_file} not found: run this on a Rojo project")
    chosen = [k.strip() for k in (a.only or ",".join(PACKAGES)).split(",") if k.strip()]
    unknown = [k for k in chosen if k not in PACKAGES]
    if unknown:
        sys.exit(f"unknown package(s): {', '.join(unknown)}; choose from {', '.join(PACKAGES)}")
    manifest = project / "wally.toml"
    new_manifest = update_manifest(manifest.read_text() if manifest.exists() else "", chosen, project.name)
    data = json.loads(project_file.read_text())
    realms = {PACKAGES[k]["realm"] for k in chosen}
    new_project = update_project(data, "shared" in realms, "server" in realms)
    if a.dry_run:
        print(new_manifest)
        print(json.dumps(new_project, indent=2))
        return 0
    manifest.write_text(new_manifest)
    project_file.write_text(json.dumps(new_project, indent=2) + "\n")
    gitignore = project / ".gitignore"
    lines = gitignore.read_text().splitlines() if gitignore.exists() else []
    for entry in ("Packages/", "ServerPackages/"):
        if entry not in lines:
            lines.append(entry)
    gitignore.write_text("\n".join(lines) + "\n")
    print(f"wrote {manifest} and updated {project_file.name}: {', '.join(PACKAGES[k]['spec'] for k in chosen)}")
    if a.no_install:
        return 0
    wally = shutil.which("wally")
    if not wally:
        print("Wally is not on PATH. Run `rokit install` (or install Wally 0.3.2), then `wally install` in the project.")
        return 0
    return subprocess.run([wally, "install"], cwd=project).returncode


if __name__ == "__main__":
    sys.exit(main())
