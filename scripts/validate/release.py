#!/usr/bin/env python3
"""Release gate for a Rojo game. It checks, writes notes and rollback info, and NEVER publishes.

  python3 scripts/validate/release.py check --project ~/games/MyGame
  python3 scripts/validate/release.py notes --project ~/games/MyGame --version 1.2.0

`check` runs, and reports PASS, FAIL or NEEDS MANUAL REVIEW for each:
  build      scripts/validate/build.py (lint, tests, rojo build)
  audit      scripts/validate/audit.py --strict (no HIGH security or licence finding)
  ids        no placeholder (0) game pass or developer product ids in GameConfig
  git        working tree committed, so the release maps to one commit
  odds       egg/loot odds shown to players (manual: Roblox requires it for paid random items)
  devices    tested on phone, tablet and console sizes (manual)
`notes` writes .urk/releases/<version>.md: commits since the last tag, the commit to roll back to, and
how to roll back in Studio (File > Version History) or by rebuilding that commit.

Publishing stays with the owner: open the place in Studio, review, and publish yourself. The kit never
uploads, publishes or changes a live place. Standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def git(project: Path, *args: str) -> str | None:
    try:
        return subprocess.run(["git", *args], cwd=project, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def check(project: Path) -> int:
    results = []
    code = subprocess.run([sys.executable, str(ROOT / "scripts/validate/build.py"), "--project", str(project)]).returncode
    results.append(("build", "PASS" if code == 0 else "FAIL", "lint, tests and rojo build"))
    code = subprocess.run([sys.executable, str(ROOT / "scripts/validate/audit.py"), "--project", str(project), "--strict"]).returncode
    results.append(("audit", "PASS" if code == 0 else "FAIL", "no HIGH security or licence finding"))
    cfg = project / "src" / "shared" / "GameConfig.luau"
    if cfg.exists():
        zeros = re.findall(r"name = \"([^\"]+)\", id = 0\b", cfg.read_text())
        results.append(("ids", "FAIL" if zeros else "PASS",
                        f"placeholder ids: {', '.join(zeros)}" if zeros else "game pass and product ids set"))
    else:
        results.append(("ids", "NEEDS MANUAL REVIEW", "no GameConfig.luau: check pass and product ids by hand"))
    status = git(project, "status", "--porcelain")
    if status is None:
        results.append(("git", "NEEDS MANUAL REVIEW", "not a git repository: record what you are releasing"))
    else:
        results.append(("git", "PASS" if status == "" else "FAIL", "clean" if status == "" else "uncommitted changes"))
    results.append(("odds", "NEEDS MANUAL REVIEW", "show the odds of every paid random item in game"))
    results.append(("devices", "NEEDS MANUAL REVIEW", "play on phone, tablet and console sizes in Studio's emulator"))
    print("\nRelease check")
    for name, state, note in results:
        print(f"  {state:20} {name:8} {note}")
    failed = any(state == "FAIL" for _, state, _ in results)
    print("\nNot ready: fix the FAIL items." if failed else
          "\nAutomated checks passed. Finish the manual items, then publish yourself from Studio. Nothing was published.")
    return 1 if failed else 0


def notes(project: Path, version: str) -> int:
    last_tag = git(project, "describe", "--tags", "--abbrev=0")
    head = git(project, "rev-parse", "--short", "HEAD") or "unknown"
    rng = f"{last_tag}..HEAD" if last_tag else "HEAD"
    log = git(project, "log", "--pretty=- %s (%h)", rng) or "- (no git history found)"
    out = project / ".urk" / "releases" / f"{version}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"# Release {version}\n\nDate: {dt.date.today().isoformat()}  \nCommit: {head}  \n"
                   f"Previous release: {last_tag or 'none'}\n\n## Changes\n\n{log}\n\n## Roll back\n\n"
                   f"1. In Studio: File > Version History, restore the version published before {version}, publish.\n"
                   f"2. Or rebuild the previous code: `git checkout {last_tag or '<previous commit>'}` then "
                   "`rojo build -o rollback.rbxl` and publish that place yourself.\n"
                   "3. Data: schema versions only move forward. If this release migrated data, the old server code must "
                   "refuse newer data (SaveDataLogic does), so check before rolling back across a migration.\n")
    print(f"wrote {out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["check", "notes"])
    ap.add_argument("--project", type=Path, required=True)
    ap.add_argument("--version", default=dt.date.today().strftime("%Y.%m.%d"))
    a = ap.parse_args(argv)
    project = a.project.expanduser().resolve()
    return check(project) if a.cmd == "check" else notes(project, a.version)


if __name__ == "__main__":
    sys.exit(main())
