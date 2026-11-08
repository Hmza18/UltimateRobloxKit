"""Shared test helpers: kit paths on sys.path."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for p in (ROOT / "scripts", ROOT / "tools"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))
