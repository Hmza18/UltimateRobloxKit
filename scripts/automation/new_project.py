#!/usr/bin/env python3
"""Create a new Rojo game project from the kit's templates.

  python3 scripts/automation/new_project.py --list
  python3 scripts/automation/new_project.py --template simulator --name ClickQuest --out ~/games/ClickQuest

Copies templates/starter-game, then overlays the chosen template's files (an overlay's
overlay.json names its base), replacing __GAME_NAME__ in text files. Refuses to write into
an existing non-empty folder.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / "templates"
TEXT = {".luau", ".lua", ".json", ".toml", ".md", ".txt", ".yml", ".yaml", ".gitignore", ".luaurc"}


def templates():
    out = {}
    for d in sorted(p for p in TEMPLATES.iterdir() if p.is_dir()):
        meta = json.loads((d / "overlay.json").read_text()) if (d / "overlay.json").exists() else {"base": None}
        if (d / "default.project.json").exists() or meta.get("base"):
            out[d.name] = meta
    return out


def chain(name, all_t):
    order = []
    while name:
        if name in order:
            raise SystemExit(f"template base cycle at {name}")
        order.insert(0, name)
        name = all_t[name].get("base")
    return order


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--template", default="starter-game")
    ap.add_argument("--name")
    ap.add_argument("--out", type=Path)
    a = ap.parse_args(argv)
    all_t = templates()
    if a.list:
        for n, m in all_t.items():
            print(f"{n:14} {m.get('description', 'base project')}")
        return 0
    if a.template not in all_t:
        raise SystemExit(f"unknown template {a.template!r}; use --list")
    if not a.name or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,49}", a.name):
        raise SystemExit("--name must start with a letter and use letters, digits or _ (max 50)")
    out = (a.out or Path.cwd() / a.name).expanduser().resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit(f"{out} exists and is not empty; choose another --out")
    out.mkdir(parents=True, exist_ok=True)
    for layer in chain(a.template, all_t):
        src = TEMPLATES / layer
        for f in sorted(src.rglob("*")):
            rel = f.relative_to(src)
            if f.is_dir() or rel.as_posix() == "overlay.json" or "__pycache__" in rel.parts or f.name == ".DS_Store":
                continue
            dest = out / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            if f.suffix in TEXT or f.name in TEXT:
                dest.write_text(f.read_text(encoding="utf-8").replace("__GAME_NAME__", a.name), encoding="utf-8")
            else:
                shutil.copy2(f, dest)
    print(f"Created {a.template} project '{a.name}' in {out}")
    print("Next: cd into it, then `rokit install`, `rojo serve` (Studio: Rojo plugin > Connect), `lune run tests/run`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
