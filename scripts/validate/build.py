#!/usr/bin/env python3
"""Lint, test and build a Rojo game in one command, the same way the kit's CI does.

  python3 scripts/validate/build.py --project ~/games/MyGame
  python3 scripts/validate/build.py --project . --out build/game.rbxl --skip lint

Steps, each reported PASS, FAIL or MISSING TOOL (never silently skipped):
  lint    selene src (generates the roblox std first) and stylua --check src tests
  test    lune run tests/run, and lune run tests/urk/run tests/urk when the kit's specs are installed
  build   rojo build -o <out> (default build/<project>.rbxl)
Tools come from the project's rokit.toml (`rokit install`). Exit code 1 when any step fails.
Standard library only.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def step(name: str, cmd: list[str], cwd: Path) -> str:
    tool = shutil.which(cmd[0])
    if tool is None:
        print(f"MISSING TOOL  {name}: {cmd[0]} is not on PATH (run `rokit install` in the project)")
        return "MISSING TOOL"
    print(f"$ {' '.join(cmd)}", flush=True)
    code = subprocess.run([tool, *cmd[1:]], cwd=cwd).returncode
    result = "PASS" if code == 0 else "FAIL"
    print(f"{result:13} {name}")
    return result


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path, required=True)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--skip", action="append", default=[], choices=["lint", "test", "build"])
    a = ap.parse_args(argv)
    project = a.project.expanduser().resolve()
    if not (project / "default.project.json").exists():
        sys.exit(f"{project} has no default.project.json")
    results = {}
    if "lint" not in a.skip:
        if shutil.which("selene"):
            subprocess.run([shutil.which("selene"), "generate-roblox-std"], cwd=project, capture_output=True)
        results["selene"] = step("selene", ["selene", "src"], project)
        targets = ["src"] + (["tests"] if (project / "tests").exists() else [])
        results["stylua"] = step("stylua", ["stylua", "--check", *targets], project)
    if "test" not in a.skip:
        if (project / "tests" / "run.luau").exists():
            results["lune"] = step("lune", ["lune", "run", "tests/run"], project)
        if (project / "tests" / "urk" / "run.luau").exists():
            results["lune (kit specs)"] = step("lune (kit specs)", ["lune", "run", "tests/urk/run", "tests/urk"], project)
    if "build" not in a.skip:
        out = a.out or project / "build" / f"{project.name}.rbxl"
        out.parent.mkdir(parents=True, exist_ok=True)
        results["rojo"] = step("rojo build", ["rojo", "build", "-o", str(out)], project)
    print("\nSummary: " + ", ".join(f"{k} {v}" for k, v in results.items()))
    return 1 if any(v != "PASS" for v in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
