#!/usr/bin/env python3
"""Run every kit check: catalog freshness plus all unit tests (Blender test skips without Blender).

  python3 scripts/validate/run_all.py           # everything available on this machine
  URK_SKIP_BLENDER=1 python3 scripts/validate/run_all.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    steps = [
        ("catalog up to date", [sys.executable, str(ROOT / "scripts/automation/build_catalog.py"), "--check"], ROOT),
        ("unit tests", [sys.executable, "-m", "unittest", "discover", "-s", str(ROOT / "tests"), "-p", "test_*.py", "-v"], ROOT / "tests"),
    ]
    failed = []
    for label, cmd, cwd in steps:
        print(f"== {label}", flush=True)
        if subprocess.run(cmd, cwd=cwd).returncode != 0:
            failed.append(label)
    print("== result:", "FAIL (" + ", ".join(failed) + ")" if failed else "PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
