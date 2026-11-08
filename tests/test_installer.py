"""Installer behaviour on temporary projects: dry-run, install, conflicts, update, uninstall."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from _util import ROOT  # noqa: F401
import importlib.util

_spec = importlib.util.spec_from_file_location("install", ROOT / "scripts/install/install.py")
install = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(install)


def run(*args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = install.main(list(args))
    return code, out.getvalue()


def files(root: Path):
    return sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_dry_run_writes_nothing(self):
        code, out = run("--target", str(self.root), "--dry-run", "--with-mcp", "--with-claude-md")
        self.assertEqual(code, 0)
        self.assertIn("Would install", out)
        self.assertEqual(files(self.root), [])

    def test_full_install_and_uninstall_leaves_nothing(self):
        run("--target", str(self.root), "--with-mcp", "--with-claude-md")
        manifest = json.loads((self.root / ".claude/ultimate-roblox-kit.json").read_text())
        self.assertGreaterEqual(len(manifest["skills"]), 40)
        self.assertTrue((self.root / ".claude/skills/roblox-kit-router/SKILL.md").exists())
        self.assertTrue((self.root / ".claude/agents/urk-qa-reviewer.md").exists())
        self.assertTrue((self.root / ".claude/commands/urk-route.md").exists())
        self.assertTrue((self.root / ".claude/ultimate-roblox-kit/scripts/automation/route.py").exists())
        self.assertIn("blender", json.loads((self.root / ".mcp.json").read_text())["mcpServers"])
        run("--target", str(self.root), "--uninstall")
        self.assertEqual(files(self.root), [])

    def test_selective_install_pulls_dependencies(self):
        run("--target", str(self.root), "--skills", "roblox-networking", "--no-agents", "--no-commands")
        names = sorted(p.name for p in (self.root / ".claude/skills").iterdir())
        self.assertIn("roblox-networking", names)
        self.assertIn("roblox-kit-router", names)
        self.assertIn("kit-conventions", names)
        for dep in install.discover()["roblox-networking"]["depends"]:
            self.assertIn(dep, names)
        self.assertNotIn("roblox-audio", names)
        self.assertFalse((self.root / ".claude/agents").exists())

    def test_refuses_to_overwrite_user_file_without_force(self):
        own = self.root / ".claude/skills/roblox-networking/SKILL.md"
        own.parent.mkdir(parents=True)
        own.write_text("mine")
        with self.assertRaises(SystemExit):
            run("--target", str(self.root), "--skills", "roblox-networking")
        self.assertEqual(own.read_text(), "mine")
        self.assertFalse((self.root / ".claude/ultimate-roblox-kit.json").exists())
        run("--target", str(self.root), "--skills", "roblox-networking", "--force")
        self.assertNotEqual(own.read_text(), "mine")
        backups = list((self.root / ".claude/.urk-backup").rglob("SKILL.md"))
        self.assertEqual([b.read_text() for b in backups], ["mine"])

    def test_existing_install_requires_update_and_protects_edits(self):
        run("--target", str(self.root), "--skills", "roblox-audio")
        with self.assertRaises(SystemExit):
            run("--target", str(self.root), "--skills", "roblox-audio")
        edited = self.root / ".claude/skills/roblox-audio/SKILL.md"
        edited.write_text(edited.read_text() + "\nmy note\n")
        with self.assertRaises(SystemExit):
            run("--target", str(self.root), "--update", "--skills", "roblox-audio")
        self.assertIn("my note", edited.read_text())
        code, _ = run("--target", str(self.root), "--update", "--skills", "roblox-vfx")
        self.assertEqual(code, 0)
        self.assertTrue((self.root / ".claude/skills/roblox-vfx/SKILL.md").exists())

    def test_update_removes_deselected_unmodified_skills(self):
        run("--target", str(self.root), "--skills", "roblox-audio")
        run("--target", str(self.root), "--update", "--skills", "roblox-vfx")
        self.assertFalse((self.root / ".claude/skills/roblox-audio").exists() and any((self.root / ".claude/skills/roblox-audio").rglob("*.md")))

    def test_uninstall_keeps_edited_files_and_unrelated_content(self):
        (self.root / "CLAUDE.md").write_text("# My project\n")
        (self.root / ".mcp.json").write_text(json.dumps({"mcpServers": {"mine": {"command": "x"}}}))
        run("--target", str(self.root), "--skills", "roblox-audio", "--with-mcp", "--with-claude-md")
        self.assertIn("ULTIMATE-ROBLOX-KIT", (self.root / "CLAUDE.md").read_text())
        edited = self.root / ".claude/skills/roblox-audio/SKILL.md"
        edited.write_text("edited")
        run("--target", str(self.root), "--uninstall")
        self.assertEqual((self.root / "CLAUDE.md").read_text(), "# My project\n")
        self.assertEqual(json.loads((self.root / ".mcp.json").read_text()), {"mcpServers": {"mine": {"command": "x"}}})
        self.assertEqual(edited.read_text(), "edited")

    def test_version_pin(self):
        with self.assertRaises(SystemExit):
            run("--target", str(self.root), "--require-version", "99.0.0")
        code, _ = run("--target", str(self.root), "--require-version", install.kit_version(), "--dry-run")
        self.assertEqual(code, 0)

    def test_installed_router_works(self):
        import subprocess
        import sys
        run("--target", str(self.root), "--category", "modeling")
        out = subprocess.run([sys.executable, str(self.root / ".claude/ultimate-roblox-kit/scripts/automation/route.py"), "--json",
                              "Create 20 supermarket products"], capture_output=True, text=True, check=True)
        r = json.loads(out.stdout)
        self.assertIn("batch-asset-production", r["load_order"])
        # Running the script wrote __pycache__; uninstall must still leave nothing behind.
        run("--target", str(self.root), "--uninstall")
        self.assertEqual(files(self.root), [])


if __name__ == "__main__":
    unittest.main()
