#!/usr/bin/env python3
"""Skills: list, search and show the kit's skills, and evaluate how well the router picks them.

  python3 scripts/automation/skills.py list [--category ui]
  python3 scripts/automation/skills.py search pets eggs
  python3 scripts/automation/skills.py show roblox-shop-builder
  python3 scripts/automation/skills.py eval [--min 0.9] [--json report.json]

`eval` runs every case in catalog/route_eval.json through the router (scripts/automation/route.py) and
reports accuracy (cases where every expected skill is among the primary skills), mean skills loaded and
mean tokens loaded per task (SKILL.md bytes / 4, an estimate), so routing and token efficiency can be
tracked in CI. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))
from lib.env import KIT_ROOT  # noqa: E402
from lib.skills import discover  # noqa: E402
from route import route  # noqa: E402


def tokens(path: Path) -> int:
    return round(path.stat().st_size / 4) if path.exists() else 0


def evaluate(cases: list[dict]) -> dict:
    skills = discover()
    rows = []
    for case in cases:
        r = route(case["task"], skills)
        missing = [s for s in case["expect"] if s not in r["primary"]]
        cost = sum(tokens(KIT_ROOT / skills[n]["path"] / "SKILL.md") for n in r["load_order"] if n in skills)
        rows.append({"task": case["task"], "ok": not missing, "missing": missing, "primary": r["primary"],
                     "loaded": len(r["load_order"]), "tokens": cost})
    n = len(rows) or 1
    return {"cases": len(rows), "accuracy": round(sum(r["ok"] for r in rows) / n, 3),
            "meanSkillsLoaded": round(sum(r["loaded"] for r in rows) / n, 2),
            "meanTokensLoaded": round(sum(r["tokens"] for r in rows) / n), "rows": rows}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["list", "search", "show", "eval"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--category")
    ap.add_argument("--min", type=float, help="eval: exit 1 below this accuracy")
    ap.add_argument("--json", type=Path)
    a = ap.parse_args(argv)
    skills = discover()
    if a.cmd == "list":
        for name, s in sorted(skills.items(), key=lambda kv: (kv[1]["category"], kv[0])):
            if not a.category or s["category"] == a.category:
                print(f"{s['category']:13} {name:34} {s['description'][:70]}")
        return 0
    if a.cmd == "search":
        q = [w.lower() for w in a.args]
        hits = []
        for name, s in skills.items():
            hay = " ".join([name, s["description"], " ".join(s["triggers"])]).lower()
            score = sum(hay.count(w) for w in q)
            if score:
                hits.append((score, name, s))
        for score, name, s in sorted(hits, key=lambda h: (-h[0], h[1]))[:15]:
            print(f"{score:3} {name:34} {s['description'][:80]}")
        return 0
    if a.cmd == "show":
        if not a.args or a.args[0] not in skills:
            sys.exit("usage: show <skill-name> (see list)")
        s = skills[a.args[0]]
        path = KIT_ROOT / s["path"] / "SKILL.md"
        print(f"{a.args[0]} ({s['category']}), ~{tokens(path)} tokens, depends on: {', '.join(s.get('depends', [])) or 'none'}")
        print(f"triggers: {', '.join(s['triggers'])}\n{path}")
        return 0
    data = json.loads((KIT_ROOT / "catalog" / "route_eval.json").read_text())
    rep = {"tuned": evaluate(data["cases"]), "heldout": evaluate(data.get("heldout", [])),
           "heldout2": evaluate(data.get("heldout2", []))}
    for label, part in rep.items():
        for r in part["rows"]:
            if not r["ok"]:
                print(f"MISS ({label})  {r['task']}\n      missing {', '.join(r['missing'])}; got {', '.join(r['primary'])}")
    for label, part in rep.items():
        print(f"{label:8} routing accuracy {part['accuracy'] * 100:5.1f}% on {part['cases']:2} cases; "
              f"mean {part['meanSkillsLoaded']} skills, ~{part['meanTokensLoaded']} tokens loaded per task")
    if a.json:
        a.json.write_text(json.dumps(rep, indent=1) + "\n")
    return 1 if a.min is not None and rep["tuned"]["accuracy"] < a.min else 0


if __name__ == "__main__":
    sys.exit(main())
