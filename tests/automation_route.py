"""Import shim: scripts/automation/route.py as a module for tests."""
import importlib.util

from _util import ROOT

_spec = importlib.util.spec_from_file_location("route", ROOT / "scripts/automation/route.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
route = _mod.route
