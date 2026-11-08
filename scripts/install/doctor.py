#!/usr/bin/env python3
"""Environment diagnostics for Roblox + Blender + AI-agent development. Reads only; installs nothing.

  python3 scripts/install/doctor.py                 # machine
  python3 scripts/install/doctor.py --project .     # plus a Rojo project's pins and config
  python3 scripts/install/doctor.py --json

Status per item: ok, missing, mismatch (installed version differs from the project's rokit.toml pin),
or info. Environment variables are reported as set / not set; values are never printed.
Exit code 0 unless --strict and a required item is missing.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.env import find_blender, tool_version  # noqa: E402

TOOLS = {"rokit": "rojo-rbx/rokit", "rojo": "rojo-rbx/rojo", "wally": "UpliftGames/wally", "selene": "Kampfkarren/selene",
         "stylua": "JohnnyMorganz/StyLua", "lune": "lune-org/lune", "luau-lsp": "JohnnyMorganz/luau-lsp"}
REQUIRED_FOR_CODE = {"rokit", "rojo", "selene", "stylua"}
ENV_VARS = ["ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID", "BLENDER"]


def pins(project: Path):
    path = project / "rokit.toml"
    if not path.exists():
        return {}
    found = {}
    for line in path.read_text().splitlines():
        m = re.match(r'\s*([\w-]+)\s*=\s*"([^"@]+)@([^"]+)"', line)
        if m:
            found[m.group(1)] = m.group(3).lstrip("v")
    return found


def studio_paths():
    if sys.platform == "darwin":
        # Check the executable, not the bundle folder: an interrupted install leaves an empty .app.
        exe = Path("/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio")
        return [exe] if exe.is_file() else []
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("LOCALAPPDATA", "")) / "Roblox" / "Versions"
        return sorted(base.glob("*/RobloxStudioBeta.exe")) if base.exists() else []
    return []


def check(project: Path | None):
    items = []

    def add(name, status, detail="", fix=""):
        items.append({"item": name, "status": status, "detail": detail, "fix": fix})

    add("os", "info", f"{platform.system()} {platform.release()} {platform.machine()}")
    add("python", "ok" if sys.version_info >= (3, 9) else "mismatch", sys.version.split()[0], "Python 3.9+ is required")
    add("git", "ok" if shutil.which("git") else "missing", tool_version("git") or "", "Install git")
    project_pins = pins(project) if project else {}
    for tool, repo in TOOLS.items():
        version = tool_version(tool)
        if version is None:
            add(tool, "missing", "", f"rokit add {repo} (or `rokit install` in a project that pins it)" if tool != "rokit" else
                "Install Rokit from github.com/rojo-rbx/rokit/releases, then `rokit self-install`")
            continue
        pin = project_pins.get(tool)
        num = re.search(r"\d+\.\d+\.\d+", version)
        if pin and num and num.group(0) != pin:
            add(tool, "mismatch", f"{version} (project pins {pin})", "run `rokit install` in the project")
        else:
            add(tool, "ok", version)
    blender = find_blender()
    add("blender", "ok" if blender else "missing", (tool_version(blender) or "") if blender else "",
        "Install Blender 4.2+ from blender.org or set BLENDER=/path/to/blender")
    studio = studio_paths()
    add("roblox-studio", "ok" if studio else "missing", str(studio[0]) if studio else "",
        "Install from create.roblox.com (the user signs in; agents never do)")
    for name in ("claude", "uvx"):
        add(name, "ok" if shutil.which(name) else "missing", "", "optional")
    for var in ENV_VARS:
        add(f"env:{var}", "info", "set" if os.environ.get(var) else "not set")
    if project:
        mcp = project / ".mcp.json"
        if mcp.exists():
            try:
                servers = sorted(json.loads(mcp.read_text()).get("mcpServers", {}))
                add(".mcp.json", "ok", ", ".join(servers) or "no servers")
            except json.JSONDecodeError as exc:
                add(".mcp.json", "mismatch", f"invalid JSON: {exc}")
        else:
            add(".mcp.json", "info", "absent", "see integrations/mcp/mcp.example.json")
        proj = project / "default.project.json"
        add("default.project.json", "ok" if proj.exists() else "missing", "", "templates/starter-game has one")
        add("rokit.toml", "ok" if project_pins else "missing", ", ".join(f"{k}@{v}" for k, v in project_pins.items()))
        manifest = project / ".claude" / "ultimate-roblox-kit.json"
        if manifest.exists():
            m = json.loads(manifest.read_text())
            add("kit-install", "ok", f"version {m.get('version')}, {len(m.get('skills', []))} skills")
        else:
            add("kit-install", "info", "not installed in this project", "python3 scripts/install/install.py --target <project>")
    return items


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true", help="exit 1 if a tool needed for Luau work is missing")
    a = ap.parse_args(argv)
    items = check(a.project.resolve() if a.project else None)
    if a.json:
        print(json.dumps(items, indent=1))
    else:
        for i in items:
            line = f"{i['status']:9} {i['item']:22} {i['detail']}"
            print(line + (f"\n          -> {i['fix']}" if i["status"] in ("missing", "mismatch") and i["fix"] else ""))
    missing = [i["item"] for i in items if i["status"] == "missing" and i["item"] in REQUIRED_FOR_CODE]
    return 1 if a.strict and missing else 0


if __name__ == "__main__":
    sys.exit(main())
