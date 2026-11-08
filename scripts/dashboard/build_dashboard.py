#!/usr/bin/env python3
"""Build the local developer dashboard: dashboard/index.html, one self-contained file (no server,
no network, no external scripts). Open it in a browser, or run `python3 urk.py dashboard --open`.

  python3 scripts/dashboard/build_dashboard.py [--project ~/games/MyGame] [--out dashboard/index.html]

Tabs: Skills (search, filter, dependencies, route a task), Workflows, Library (modules and READMEs),
Icons (search, tint, light/dark, copy Luau), Templates (command builder), Install (command builder for
setup/install/add), Environment (doctor + project check captured at build time; rebuild to refresh).
Data comes from the same files the CLI uses, so the dashboard never disagrees with the tools.
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from lib.skills import discover  # noqa: E402


def library_modules():
    src = ROOT / "library" / "src"
    mods = []
    for d in sorted(src.rglob("*")):
        if d.is_dir() and (d / "README.md").exists():
            rel = d.relative_to(src).as_posix()
            files = sorted(f.name for f in d.iterdir() if f.suffix == ".luau")
            tests = sorted(t.name for t in (ROOT / "library/tests").glob("*.spec.luau")
                           if any(f[:-5].lower().replace("logic", "") in t.name for f in files))
            mods.append({"name": rel, "files": files, "tests": tests, "readme": (d / "README.md").read_text(encoding="utf-8")})
    return mods


def templates():
    out = []
    for d in sorted((ROOT / "templates").iterdir()):
        if not d.is_dir():
            continue
        meta = json.loads((d / "overlay.json").read_text()) if (d / "overlay.json").exists() else {}
        readme = (d / "README.md").read_text(encoding="utf-8") if (d / "README.md").exists() else ""
        first = next((ln for ln in readme.splitlines() if ln.strip() and not ln.startswith("#")), "")
        out.append({"name": d.name, "base": meta.get("base"), "description": meta.get("description") or first,
                    "rojo": (d / "default.project.json").exists() or bool(meta.get("base"))})
    return out


def icons():
    cat = json.loads((ROOT / "assets/icons/urk/icons.json").read_text())
    for i in cat["icons"]:
        i["png"] = base64.b64encode((ROOT / "assets/icons/urk/png" / f"{i['name']}.png").read_bytes()).decode()
    return cat


def capture(args):
    try:
        out = subprocess.run([sys.executable, *args], capture_output=True, text=True, timeout=60)
        return json.loads(out.stdout)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path)
    ap.add_argument("--out", type=Path, default=ROOT / "dashboard" / "index.html")
    a = ap.parse_args(argv)
    skills = discover()
    data = {
        "version": (ROOT / "VERSION").read_text().strip(),
        "kitRoot": str(ROOT),
        "skills": [{k: s[k] for k in ("name", "category", "description", "triggers", "depends", "path")} for s in skills.values()],
        "workflows": json.loads((ROOT / "catalog/workflows.json").read_text())["workflows"],
        "library": library_modules(),
        "templates": templates(),
        "icons": icons(),
        "agents": sorted(p.stem for p in (ROOT / ".claude/agents").glob("*.md")),
        "commands": sorted(p.stem for p in (ROOT / ".claude/commands").glob("*.md")),
        "doctor": capture([str(ROOT / "scripts/install/doctor.py"), "--json"] + (["--project", str(a.project)] if a.project else [])),
        "check": capture([str(ROOT / "scripts/validate/check_project.py"), str(a.project), "--json"]) if a.project else None,
        "project": str(a.project) if a.project else None,
    }
    template = (Path(__file__).parent / "template.html").read_text(encoding="utf-8")
    page = template.replace("/*__URK_DATA__*/null", json.dumps(data).replace("</", "<\\/"))
    page = page.replace("__URK_VERSION__", html.escape(data["version"]))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(page, encoding="utf-8")
    print(f"dashboard: {a.out} ({len(page) // 1024} KB; {len(data['skills'])} skills, {len(data['library'])} library modules, "
          f"{len(data['icons']['icons'])} icons)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
