#!/usr/bin/env python3
"""Build the local developer dashboard: dashboard/index.html, one self-contained file (no server,
no network, no external scripts). Open it in a browser, or run `python3 urk.py dashboard --open`.

  python3 scripts/dashboard/build_dashboard.py [--project ~/games/MyGame] [--out dashboard/index.html]

Tabs: Skills (search, filter, dependencies, route a task), Workflows, Library (modules and READMEs),
Icons (search, tint, light/dark, copy Luau), Templates (command builder), Install (command builder for
setup/install/add), Environment (doctor + project check captured at build time; rebuild to refresh),
Project (memory, game plan, check, generator command), UI Playground (every built-in screen with its
preview thumbnail and commands), Assets (registry summary, licences, duplicates, pack previews), Agents
(each agent's role and skills), Tests (routing eval with held-out sets, economy example, kit audit).
Data comes from the same files the CLI uses, so the dashboard never disagrees with the tools.
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import re
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


def screens():
    out = []
    for f in sorted((ROOT / "library/src/UI/Spec/Screens").glob("*.json")):
        spec = json.loads(f.read_text())

        def count(node):
            if isinstance(node, dict):
                return (1 if "type" in node else 0) + sum(count(v) for v in node.values())
            if isinstance(node, list):
                return sum(count(v) for v in node)
            return 0
        out.append({"name": f.stem, "kind": spec.get("kind", "?"), "description": spec.get("description", ""), "elements": count(spec)})
    return out


def thumb(path: Path, width: int = 360) -> str | None:
    """Small base64 JPEG/PNG preview so the single-file dashboard stays light. Needs Pillow."""
    try:
        from PIL import Image
    except ImportError:
        return None
    import io
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((width, width))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=78)
    return base64.b64encode(buf.getvalue()).decode()


def ui_playground():
    out = []
    for s in screens():
        img = ROOT / "docs/images/ui" / f"{s['name']}.png"
        out.append({**s, "thumb": thumb(img) if img.exists() else None})
    return out


def agents():
    out = []
    for f in sorted((ROOT / ".claude/agents").glob("*.md")):
        text = f.read_text(encoding="utf-8")
        desc = next((ln.split(":", 1)[1].strip() for ln in text.splitlines() if ln.startswith("description:")), "")
        body = text.split("---", 2)[-1]
        skills = sorted(set(re.findall(r"`([a-z0-9-]+)`", body)) & {p.parent.name for p in (ROOT / "skills").glob("*/*/SKILL.md")})
        out.append({"name": f.stem, "description": desc, "skills": skills})
    return out


def asset_library():
    sys.path.insert(0, str(ROOT / "tools" / "assets"))
    import registry  # noqa: E402
    reg = registry.scan([ROOT / "assets", ROOT / "examples"])
    kinds, licences = {}, {}
    for e in reg["assets"]:
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
        key = (e["licence"] or "none found").split(" (")[0]
        licences[key] = licences.get(key, 0) + 1
    d = registry.dupes(reg, 2)
    packs = []
    for prev in sorted((ROOT / "assets").glob("**/preview*.png")):
        packs.append({"path": prev.relative_to(ROOT).as_posix(), "thumb": thumb(prev, 420)})
    return {"count": reg["count"], "kinds": kinds, "licences": licences, "identical": len(d["exact"]),
            "similar": len(d["similar"]), "packs": packs}


def tests_centre():
    sys.path.insert(0, str(ROOT / "scripts" / "automation"))
    import skills as skills_cli  # noqa: E402
    data = json.loads((ROOT / "catalog/route_eval.json").read_text())
    routing = {k: {kk: v[kk] for kk in ("cases", "accuracy", "meanSkillsLoaded", "meanTokensLoaded")}
               for k, v in (("tuned", skills_cli.evaluate(data["cases"])), ("heldout", skills_cli.evaluate(data.get("heldout", []))),
                            ("heldout2", skills_cli.evaluate(data.get("heldout2", []))))}
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        econ_out, audit_out = Path(tmp) / "economy.json", Path(tmp) / "audit.json"
        subprocess.run([sys.executable, str(ROOT / "tools/economy/economy_sim.py"), str(ROOT / "tools/economy/examples/pet-sim.json"),
                        "--players", "10", "--json", str(econ_out)], capture_output=True, timeout=300)
        subprocess.run([sys.executable, str(ROOT / "scripts/validate/audit.py"), "--kit", "--json", str(audit_out)],
                       capture_output=True, timeout=300)
        economy = json.loads(econ_out.read_text()) if econ_out.exists() else None
        audit = json.loads(audit_out.read_text()) if audit_out.exists() else None
    return {"routing": routing, "economy": economy, "audit": audit["counts"] if audit else None,
            "specs": len(list((ROOT / "library/tests").glob("*.spec.luau"))), "pyTests": len(list((ROOT / "tests").glob("test_*.py")))}


def project_centre(project: Path | None):
    if not project:
        return None
    mem = subprocess.run([sys.executable, str(ROOT / "scripts/automation/memory.py"), "context", "--project", str(project)],
                         capture_output=True, text=True).stdout
    plan = project / "GAME_PLAN.md"
    return {"memory": mem, "plan": plan.read_text(encoding="utf-8") if plan.exists() else None}


def capture(args):
    try:
        out = subprocess.run([sys.executable, *args], capture_output=True, text=True, timeout=120)
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
        "screens": screens(),
        "icons": icons(),
        "agents": sorted(p.stem for p in (ROOT / ".claude/agents").glob("*.md")),
        "commands": sorted(p.stem for p in (ROOT / ".claude/commands").glob("*.md")),
        "doctor": capture([str(ROOT / "scripts/install/doctor.py"), "--json"] + (["--project", str(a.project)] if a.project else [])),
        "check": capture([str(ROOT / "scripts/validate/check_project.py"), str(a.project), "--json"]) if a.project else None,
        "project": str(a.project) if a.project else None,
        "projectCentre": project_centre(a.project),
        "playground": ui_playground(),
        "assetLibrary": asset_library(),
        "agentsInfo": agents(),
        "tests": tests_centre(),
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
