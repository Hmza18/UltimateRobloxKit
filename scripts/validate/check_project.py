#!/usr/bin/env python3
"""Validate a project's UltimateRobloxKit installation and configuration. Reads only.

  python3 scripts/validate/check_project.py ~/games/MyGame [--json]

Checks
- kit manifest present and parseable; installed files exist; which ones you edited (hash differs)
- every installed skill parses and its dependencies are installed
- .mcp.json and .claude/settings.json are valid JSON; MCP server commands exist on this machine
- Luau library lock (src/shared/Urk/urk-modules.json): files present, edited files listed
- Rojo project file valid and its $path entries exist; rokit.toml pins readable
Exit 1 if anything is an ERROR. Edited files are WARN (allowed, but updates will skip them).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.frontmatter import load  # noqa: E402


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def check(project: Path):
    out = []

    def add(level, item, detail=""):
        out.append({"level": level, "item": item, "detail": detail})

    claude = project / ".claude"
    manifest_path = claude / "ultimate-roblox-kit.json"
    if not manifest_path.exists():
        add("INFO", "kit", "not installed here (python3 urk.py setup --project <dir>)")
    else:
        try:
            manifest = json.loads(manifest_path.read_text())
        except json.JSONDecodeError as exc:
            add("ERROR", "manifest", f"invalid JSON: {exc}")
            manifest = None
        if manifest:
            add("OK", "kit", f"version {manifest.get('version')} ({manifest.get('commit', '?')[:7]}), {len(manifest['skills'])} skills")
            missing = [r for r in manifest["files"] if not (project / r).exists()]
            edited = [r for r, d in manifest["files"].items() if (project / r).exists() and sha(project / r) != d]
            add("ERROR" if missing else "OK", "kit files", f"{len(missing)} missing" + (f": {missing[:5]}" if missing else ""))
            if edited:
                add("WARN", "kit files edited", f"{len(edited)} (kept on update): {edited[:5]}")
            names = set()
            for skill in manifest["skills"]:
                path = claude / "skills" / skill / "SKILL.md"
                try:
                    meta, _ = load(path)
                    names.add(meta["name"])
                    for dep in (meta.get("metadata") or {}).get("depends", []) or []:
                        if dep not in manifest["skills"]:
                            add("ERROR", f"skill {skill}", f"depends on {dep}, which is not installed")
                except (OSError, ValueError, KeyError) as exc:
                    add("ERROR", f"skill {skill}", str(exc))
            add("OK", "skills parse", f"{len(names)} of {len(manifest['skills'])}")
    for rel in (".mcp.json", ".claude/settings.json", ".claude/settings.local.json"):
        p = project / rel
        if not p.exists():
            continue
        try:
            data = json.loads(p.read_text())
        except json.JSONDecodeError as exc:
            add("ERROR", rel, f"invalid JSON: {exc}")
            continue
        add("OK", rel, "valid JSON")
        if rel == ".mcp.json":
            for name, server in (data.get("mcpServers") or {}).items():
                cmd = server.get("command", "")
                found = shutil.which(cmd) or Path(cmd).exists() or (project / cmd).exists()
                add("OK" if found else "WARN", f"mcp {name}", f"command {cmd!r}" + ("" if found else " not found on this machine"))
    lock = project / "src/shared/Urk/urk-modules.json"
    if lock.exists():
        data = json.loads(lock.read_text())
        base = lock.parent
        files = {r: d for r, d in data["files"].items() if not r.startswith("tests/")}
        missing = [r for r in files if not (base / r).exists()]
        edited = [r for r, d in files.items() if (base / r).exists() and sha(base / r) != d]
        add("ERROR" if missing else "OK", "library modules", f"{', '.join(data['modules'])}; {len(missing)} missing")
        if edited:
            add("WARN", "library files edited", str(edited[:5]))
    proj = project / "default.project.json"
    if proj.exists():
        try:
            tree = json.loads(proj.read_text())

            def paths(node, acc):
                if isinstance(node, dict):
                    if "$path" in node:
                        acc.append(node["$path"])
                    for k, v in node.items():
                        if not k.startswith("$"):
                            paths(v, acc)
                return acc

            bad = [p for p in paths(tree.get("tree", {}), []) if not (project / p).exists()]
            add("ERROR" if bad else "OK", "default.project.json", f"missing paths: {bad}" if bad else "all $path entries exist")
        except json.JSONDecodeError as exc:
            add("ERROR", "default.project.json", f"invalid JSON: {exc}")
    rokit = project / "rokit.toml"
    if rokit.exists():
        pins = [ln.split("=")[0].strip() for ln in rokit.read_text().splitlines() if "@" in ln and "=" in ln]
        add("OK", "rokit.toml", ", ".join(pins))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", type=Path, nargs="?", default=Path.cwd())
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    items = check(a.project.expanduser().resolve())
    if a.json:
        print(json.dumps(items, indent=1))
    else:
        for i in items:
            print(f"{i['level']:5} {i['item']:24} {i['detail']}")
    return 1 if any(i["level"] == "ERROR" for i in items) else 0


if __name__ == "__main__":
    sys.exit(main())
