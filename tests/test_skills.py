"""Every skill: frontmatter, naming, metadata, dependencies, size, and resolvable references."""
import re
import unittest

from _util import ROOT
from lib.frontmatter import load
from lib.skills import discover

NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CATEGORIES = {"orchestration", "roblox", "toolchain", "blender", "modeling", "environments", "ui", "gameplay", "production", "visuals"}
KIT_PATH = re.compile(r"`(?:\$URK/)?((?:scripts|tools|templates|integrations|catalog|examples|docs/(?:workflows|architecture|references|getting-started|troubleshooting))/[^`\s*<>]+)`")


class SkillTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.skills = discover()
        cls.files = sorted((ROOT / "skills").glob("*/*/SKILL.md"))

    def test_found_skills(self):
        self.assertGreaterEqual(len(self.skills), 40)
        self.assertEqual(len(self.skills), len(self.files), "duplicate skill names")

    def test_frontmatter(self):
        for f in self.files:
            with self.subTest(skill=f.parent.name):
                meta, body = load(f)
                md = meta.get("metadata") or {}
                self.assertEqual(meta.get("name"), f.parent.name)
                self.assertRegex(meta["name"], NAME)
                self.assertTrue(80 <= len(meta.get("description", "")) <= 1024, "description length 80-1024")
                self.assertIn(md.get("category"), CATEGORIES)
                self.assertEqual(md.get("category"), f.parent.parent.name)
                self.assertIsInstance(md.get("triggers"), list)
                self.assertGreaterEqual(len(md["triggers"]), 3)
                self.assertTrue(all(t == t.lower() for t in md["triggers"]), "triggers are lowercase")
                self.assertIsInstance(md.get("depends", []), list)
                self.assertLessEqual(body.count("\n"), 260, "SKILL.md body over budget; move detail to references/")
                self.assertRegex(body, r"(?im)^#+ .*limitation", "needs a Limitations section")

    def test_dependencies_exist(self):
        for s in self.skills.values():
            for d in s["depends"]:
                with self.subTest(skill=s["name"], dep=d):
                    self.assertIn(d, self.skills)
                    self.assertNotEqual(d, s["name"])

    def test_kit_paths_exist(self):
        for f in self.files:
            text = f.read_text(encoding="utf-8")
            for m in KIT_PATH.finditer(text):
                path = m.group(1).split(" ")[0].rstrip(".,;:)")
                if any(ch in path for ch in "{}*") or "<" in path:
                    continue
                with self.subTest(skill=f.parent.name, path=path):
                    self.assertTrue((ROOT / path).exists(), f"{path} referenced but missing")

    def test_no_bare_wait(self):
        """Luau in skills uses task.wait, never the deprecated global wait()."""
        bad = re.compile(r"(?<![\w.:])wait\(")
        for f in sorted((ROOT / "skills").rglob("*")):
            if f.suffix in (".md", ".luau", ".lua") and f.is_file():
                for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                    if bad.search(line) and "deprecated" not in line.lower() and "not `wait" not in line and "never" not in line.lower():
                        with self.subTest(file=str(f.relative_to(ROOT)), line=n):
                            self.fail(line.strip())


if __name__ == "__main__":
    unittest.main()
