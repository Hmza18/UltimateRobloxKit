"""urk.py setup/check/upgrade/uninstall, add_module lifecycle, project checks and the dashboard."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from _util import ROOT


def urk(*args, check=True):
    r = subprocess.run([sys.executable, str(ROOT / "urk.py"), *map(str, args)], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise AssertionError(f"urk {' '.join(map(str, args))} failed:\n{r.stdout}\n{r.stderr}")
    return r


def files(root: Path):
    return sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())


class UrkCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.game = Path(self.tmp.name) / "Game"
        urk("new", "starter-game", "Game", self.game)

    def tearDown(self):
        self.tmp.cleanup()

    def test_setup_dry_run_changes_nothing(self):
        before = files(self.game)
        urk("setup", "--project", self.game, "--dry-run", "--with-mcp")
        self.assertEqual(files(self.game), before)

    def test_setup_check_upgrade_uninstall(self):
        urk("setup", "--project", self.game, "--profile", "ui", "--with-mcp")
        self.assertTrue((self.game / ".claude/ultimate-roblox-kit.json").exists())
        self.assertTrue((self.game / "src/shared/Urk/UI").is_dir() or not (ROOT / "library/src/UI").exists())
        self.assertTrue((self.game / "src/shared/Urk/Icons/Icons.luau").exists())
        r = urk("check", self.game)
        self.assertNotIn("ERROR", r.stdout)
        urk("upgrade", "--project", self.game)
        urk("uninstall", "--project", self.game)
        self.assertFalse((self.game / ".claude/ultimate-roblox-kit.json").exists())
        self.assertFalse((self.game / ".mcp.json").exists(), "kit-created .mcp.json removed when empty")

    def test_check_reports_broken_config(self):
        urk("setup", "--project", self.game, "--profile", "design", "--no-library")
        (self.game / ".mcp.json").write_text("{ not json")
        r = urk("check", self.game, check=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("invalid JSON", r.stdout)

    def test_icons_search(self):
        r = urk("icons", "search", "coin")
        self.assertIn("coin", r.stdout)


class AddModuleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.game = Path(self.tmp.name) / "Game"
        urk("new", "starter-game", "Game", self.game)
        self.dest = self.game / "src/shared/Urk"

    def tearDown(self):
        self.tmp.cleanup()

    def test_dependencies_tests_and_require_rewrite(self):
        urk("add", "Icons", "--project", self.game)
        self.assertTrue((self.dest / "Icons/IconData.luau").exists(), "required file pulled in")
        spec = (self.game / "tests/urk/icons_catalog.spec.luau").read_text()
        self.assertIn('require("../../src/shared/Urk/Icons/IconCatalog")', spec)
        self.assertTrue((self.game / "tests/urk/run.luau").exists())
        lock = json.loads((self.dest / "urk-modules.json").read_text())
        self.assertEqual(lock["modules"], ["Icons"])

    def test_every_module_installs_with_resolvable_requires(self):
        mods = [ln.split()[0] for ln in urk("add", "--list").stdout.splitlines() if ln.strip() and not ln.startswith("$")]
        self.assertTrue({"Util", "Icons"} <= set(mods))
        urk("add", *mods, "--project", self.game)
        lock = json.loads((self.dest / "urk-modules.json").read_text())
        self.assertEqual(sorted(lock["modules"]), sorted(mods))

    def test_edits_are_kept_and_foreign_files_protected(self):
        urk("add", "Icons", "--project", self.game)
        edited = self.dest / "Icons/Icons.luau"
        edited.write_text(edited.read_text() + "\n-- mine\n")
        r = urk("add", "--update", "--project", self.game)
        self.assertIn("kept", r.stdout)
        self.assertIn("-- mine", edited.read_text())
        r = urk("add", "--remove", "Icons", "--project", self.game)
        self.assertTrue(edited.exists(), "edited file survives removal")
        self.assertFalse((self.dest / "Icons/IconData.luau").exists())
        other = Path(self.tmp.name) / "Other"
        urk("new", "starter-game", "Other", other)
        (other / "src/shared/Urk/Icons").mkdir(parents=True)
        (other / "src/shared/Urk/Icons/Icons.luau").write_text("-- someone else's file")
        r = urk("add", "Icons", "--project", other, check=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual((other / "src/shared/Urk/Icons/Icons.luau").read_text(), "-- someone else's file")

    def test_dry_run(self):
        before = files(self.game)
        urk("add", "Icons", "--project", self.game, "--dry-run")
        self.assertEqual(files(self.game), before)


class DashboardTests(unittest.TestCase):
    def test_dashboard_is_self_contained_and_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "index.html"
            r = subprocess.run([sys.executable, str(ROOT / "scripts/dashboard/build_dashboard.py"), "--out", str(out)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            page = out.read_text()
            self.assertNotIn("__URK_DATA__", page)
            self.assertNotIn("<script src", page, "no external scripts")
            self.assertNotIn("<link", page, "no external stylesheets")
            start = page.index("const D = ") + len("const D = ")
            data = json.JSONDecoder().raw_decode(page[start:])[0]
            self.assertEqual(len(data["skills"]), len(list((ROOT / "skills").glob("*/*/SKILL.md"))))
            self.assertGreaterEqual(len(data["icons"]["icons"]), 80)
            self.assertTrue(all(i["png"] for i in data["icons"]["icons"]))
            self.assertTrue(data["workflows"])


class SharedModuleSyncTests(unittest.TestCase):
    def test_template_and_library_utilities_match(self):
        pairs = [("templates/starter-game/src/shared/Signal.luau", "library/src/Util/Signal.luau"),
                 ("templates/starter-game/src/shared/Trove.luau", "library/src/Util/Trove.luau"),
                 ("templates/starter-game/src/shared/Logic/RateLimiter.luau", "library/src/Util/RateLimiter.luau"),
                 ("templates/starter-game/src/shared/Logic/Validate.luau", "library/src/Util/Validate.luau")]
        for a, b in pairs:
            with self.subTest(file=a):
                self.assertEqual((ROOT / a).read_text(), (ROOT / b).read_text(),
                                 "copies diverged: change both, they are deliberately identical")


if __name__ == "__main__":
    unittest.main()
