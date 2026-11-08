"""Every game template composes into a valid Rojo project. Static Luau checks run everywhere;
Lune tests run when `lune` is on PATH (CI installs it; see .github/workflows/ci.yml)."""
import contextlib
import importlib.util
import io
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _util import ROOT

_spec = importlib.util.spec_from_file_location("new_project", ROOT / "scripts/automation/new_project.py")
np = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(np)

DEPRECATED = re.compile(r"(?<![\w.:])(wait|spawn|delay)\(")
PINS = {"rojo": "7.7.1", "wally": "0.3.2", "selene": "0.32.0", "stylua": "2.6.0", "lune": "0.11.1", "luau-lsp": "1.70.1"}


def project_paths(node, out):
    if isinstance(node, dict):
        if "$path" in node:
            out.append(node["$path"])
        for k, v in node.items():
            if not k.startswith("$"):
                project_paths(v, out)
    return out


class TemplateTests(unittest.TestCase):
    def compose(self, template, tmp):
        out = Path(tmp) / template
        with contextlib.redirect_stdout(io.StringIO()):
            np.main(["--template", template, "--name", "TestGame", "--out", str(out)])
        return out

    def test_templates_listed(self):
        names = set(np.templates())
        self.assertTrue({"starter-game", "simulator", "tycoon", "obby", "ui"} <= names, names)

    def test_each_template(self):
        for template in sorted(np.templates()):
            with self.subTest(template=template), tempfile.TemporaryDirectory() as tmp:
                out = self.compose(template, tmp)
                project = json.loads((out / "default.project.json").read_text())
                self.assertEqual(project["name"], "TestGame")
                for p in project_paths(project["tree"], []):
                    self.assertTrue((out / p).exists(), f"{p} in default.project.json does not exist")
                pins = (out / "rokit.toml").read_text()
                for tool, version in PINS.items():
                    self.assertRegex(pins, rf'{re.escape(tool)}\s*=\s*"[^"@]+@v?{re.escape(version)}"')
                luau = sorted(out.rglob("*.luau"))
                self.assertTrue(luau)
                for f in luau:
                    text = f.read_text()
                    rel = f.relative_to(out).as_posix()
                    self.assertNotIn("__GAME_NAME__", text, rel)
                    if rel.startswith("src/"):
                        self.assertTrue(text.lstrip().startswith("--!strict"), f"{rel} should start with --!strict")
                    code = "\n".join(line.split("--")[0] for line in text.splitlines())
                    self.assertIsNone(DEPRECATED.search(code), f"{rel} uses a deprecated global (use task.*)")
                self.assertTrue(list((out / "tests").glob("*.spec.luau")), "template has Lune specs")

    def test_refuses_non_empty_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "x").write_text("keep")
            with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()):
                np.main(["--template", "starter-game", "--name", "A", "--out", tmp])

    @unittest.skipUnless(shutil.which("lune"), "lune not installed")
    def test_lune_specs_pass(self):
        for template in sorted(np.templates()):
            with self.subTest(template=template), tempfile.TemporaryDirectory() as tmp:
                out = self.compose(template, tmp)
                r = subprocess.run(["lune", "run", "tests/run"], cwd=out, capture_output=True, text=True, timeout=120)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
