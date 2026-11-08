#!/usr/bin/env python3
"""Deterministic skill router: task text -> workflow recipe + the few skills to load.

  python3 scripts/automation/route.py "Create 20 supermarket products"
  python3 scripts/automation/route.py --json "Build a Roblox simulator"

This mirrors what the roblox-kit-router skill tells Claude to do, so routing can be tested in CI.
Scoring: a trigger phrase found in the task scores 3 (multi-word phrases 4); a workflow whose
keywords match pulls in its whole skill list. Dependencies are added after ranking.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.env import KIT_ROOT  # noqa: E402
from lib.skills import discover, with_dependencies  # noqa: E402

MAX_SKILLS = 8
MAX_EXTRA = 3


def normalise(text: str) -> str:
    return " " + " ".join(stem(w) for w in re.findall(r"[a-z0-9]+", text.lower())) + " "


def stem(w: str) -> str:
    """Tiny suffix stripper applied to both tasks and triggers: exploiting/exploits -> exploit."""
    if len(w) > 5 and w.endswith("ing"):
        w = w[:-3]
    elif len(w) > 4 and w.endswith("ed"):
        w = w[:-2]
    elif len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
        w = w[:-1]
    return w


def has(text_n: str, phrase: str) -> bool:
    return normalise(phrase) in text_n


def route(task: str, skills=None, workflows=None):
    skills = skills or discover()
    if workflows is None:
        workflows = json.loads((KIT_ROOT / "catalog" / "workflows.json").read_text())["workflows"]
    t = normalise(task)
    matched = []
    for wf in workflows:
        score = sum(1 for k in wf["keywords"] if has(t, k))
        if score >= wf.get("min_matches", 1):
            matched.append((score, wf))
    matched.sort(key=lambda x: (-x[0], -x[1].get("priority", 1)))
    scores = {}
    for name, s in skills.items():
        sc = sum(4 if " " in trig.strip() else 3 for trig in s["triggers"] if has(t, trig))
        if sc:
            scores[name] = sc
    chosen = []
    for _, wf in matched[:2]:
        for n in wf["skills"]:
            if n in skills and n not in chosen:  # skip skills a selective install left out
                chosen.append(n)
    # Trigger matches name the specific feature (pets, quests, ...), so they are always worth a few
    # slots on top of the workflow's general list.
    extra = 0
    for n, _ in sorted(scores.items(), key=lambda kv: (-kv[1], kv[0])):
        if n not in chosen and (len(chosen) < MAX_SKILLS or extra < MAX_EXTRA):
            chosen.append(n)
            extra += 1
    if not chosen:
        chosen = ["roblox-kit-router"] if "roblox-kit-router" in skills else []
    full = with_dependencies(chosen, skills, depth=1)
    return {
        "task": task,
        "workflows": [wf["id"] for _, wf in matched[:2]],
        "primary": chosen,
        "load_order": full,
        "gates": [g for _, wf in matched[:2] for g in wf.get("gates", [])],
    }


def _workflow(wid):
    return next(w for w in json.loads((KIT_ROOT / "catalog" / "workflows.json").read_text())["workflows"] if w["id"] == wid)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", nargs="+")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    r = route(" ".join(a.task))
    if a.json:
        print(json.dumps(r, indent=1))
        return 0
    skills = discover()
    print(f"Task: {r['task']}")
    print(f"Workflows: {', '.join(r['workflows']) or 'none matched'}")
    print("Load these skills (in order):")
    for n in r["load_order"]:
        print(f"  - {n:34} {skills[n]['path']}/SKILL.md")
    missing = [n for wf in r["workflows"] for n in _workflow(wf)["skills"] if n not in skills]
    if missing:
        print(f"Not installed here (install them for full coverage): {', '.join(sorted(set(missing)))}")
    if r["gates"]:
        print("Validation gates:")
        for g in r["gates"]:
            print(f"  * {g}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
