#!/usr/bin/env python3
"""Project memory: decisions, conventions and notes that every agent session should know.

  python3 scripts/automation/memory.py add decision "Coins never drop on death" --project ~/games/MyGame
  python3 scripts/automation/memory.py add convention "Remotes live in ReplicatedStorage.Remotes" --project .
  python3 scripts/automation/memory.py list [--kind decision] --project .
  python3 scripts/automation/memory.py search coins --project .
  python3 scripts/automation/memory.py context --project .     # short digest to paste into a new session
  python3 scripts/automation/memory.py forget 3 --project .

Stored as plain Markdown in <project>/.urk/memory/<kind>s.md, one dated bullet per entry, so people can
read and edit it and git can review it. The kit's agents read `context` at the start of a task (see the
kit-conventions skill). Never store secrets, tokens or personal data here. Standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

KINDS = ("decision", "convention", "note", "todo")
SECRETISH = re.compile(r"(ROBLOSECURITY|_\|WARNING|sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|password\s*[:=])", re.I)
LINE = re.compile(r"^- \[(\d{4}-\d{2}-\d{2})\] (.*)$")


def folder(project: Path) -> Path:
    return project / ".urk" / "memory"


def entries(project: Path, kind: str | None = None) -> list[dict]:
    out = []
    for k in KINDS:
        if kind and k != kind:
            continue
        f = folder(project) / f"{k}s.md"
        if not f.exists():
            continue
        for line in f.read_text().splitlines():
            m = LINE.match(line)
            if m:
                out.append({"kind": k, "date": m.group(1), "text": m.group(2)})
    for i, e in enumerate(out, 1):
        e["id"] = i
    return out


def write_all(project: Path, items: list[dict]) -> None:
    folder(project).mkdir(parents=True, exist_ok=True)
    for k in KINDS:
        rows = [e for e in items if e["kind"] == k]
        f = folder(project) / f"{k}s.md"
        if not rows:
            if f.exists():
                f.unlink()
            continue
        title = {"decision": "Decisions", "convention": "Conventions", "note": "Notes", "todo": "To do"}[k]
        f.write_text(f"# {title}\n\n" + "\n".join(f"- [{e['date']}] {e['text']}" for e in rows) + "\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["add", "list", "search", "context", "forget"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--project", type=Path, default=Path("."))
    ap.add_argument("--kind", choices=KINDS)
    a = ap.parse_args(argv)
    project = a.project.expanduser().resolve()
    if a.cmd == "add":
        if len(a.args) < 2 or a.args[0] not in KINDS:
            ap.error(f"usage: add <{'|'.join(KINDS)}> \"text\"")
        text = " ".join(a.args[1:]).replace("\n", " ").strip()
        if SECRETISH.search(text):
            sys.exit("refused: that looks like a secret. Keep credentials out of project memory.")
        items = entries(project)
        items.append({"kind": a.args[0], "date": dt.date.today().isoformat(), "text": text})
        write_all(project, items)
        print(f"remembered {a.args[0]}: {text}")
    elif a.cmd in ("list", "search"):
        q = " ".join(a.args).lower()
        for e in entries(project, a.kind):
            if a.cmd == "list" or q in e["text"].lower():
                print(f"{e['id']:3} {e['kind']:10} {e['date']}  {e['text']}")
    elif a.cmd == "context":
        items = entries(project)
        if not items:
            print("No project memory yet. Add with: urk.py memory add decision \"...\"")
            return 0
        print(f"Project memory for {project.name} ({len(items)} entries):")
        for k in KINDS:
            rows = [e for e in items if e["kind"] == k][-15:]
            if rows:
                print(f"{k}s:")
                for e in rows:
                    print(f"  - {e['text']}")
    elif a.cmd == "forget":
        if not a.args or not a.args[0].isdigit():
            ap.error("usage: forget <id> (see list)")
        items = entries(project)
        keep = [e for e in items if e["id"] != int(a.args[0])]
        if len(keep) == len(items):
            sys.exit("no entry with that id")
        write_all(project, keep)
        print("forgotten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
