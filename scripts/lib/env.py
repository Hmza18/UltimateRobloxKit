"""Shared helpers: kit paths and tool discovery. Stdlib only, Python 3.9+."""
from __future__ import annotations

import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

KIT_ROOT = Path(__file__).resolve().parents[2]


def find_blender():
    """$BLENDER, then PATH, then the standard macOS, Windows and Linux install locations."""
    candidates = [os.environ.get("BLENDER"), shutil.which("blender"), "/Applications/Blender.app/Contents/MacOS/Blender"]
    if sys.platform.startswith("win"):
        candidates += sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender*\blender.exe"), reverse=True)
    candidates += ["/usr/bin/blender", "/snap/bin/blender"]
    for c in candidates:
        if c and Path(c).is_file():
            return c
    return None


def tool_version(cmd, args=("--version",), timeout=20):
    """Return the first output line of `cmd --version`, or None if the tool is missing or fails."""
    path = shutil.which(cmd) if not Path(cmd).is_file() else cmd
    if not path:
        return None
    try:
        out = subprocess.run([path, *args], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = (out.stdout or out.stderr).strip().splitlines()
    return text[0] if text else ""
