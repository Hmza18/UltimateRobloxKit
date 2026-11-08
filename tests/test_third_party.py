"""third_party.py pins commits, refuses non-copy repositories and never overwrites skills.
Uses a throwaway local git repository, so it runs offline."""
import contextlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from _util import ROOT

_spec = importlib.util.spec_from_file_location("third_party", ROOT / "scripts/install/third_party.py")
tp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tp)


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.email=t@example.com", "-c", "user.name=t", *args], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout.strip()


class ThirdPartyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.src = base / "upstream"
        (self.src / "skills/demo").mkdir(parents=True)
        (self.src / "skills/demo/SKILL.md").write_text("---\nname: demo\ndescription: x\n---\n")
        (self.src / "LICENSE").write_text("MIT License")
        git(self.src, "init", "-q")
        git(self.src, "add", ".")
        git(self.src, "commit", "-qm", "v1")
        self.sha = git(self.src, "rev-parse", "HEAD")
        (self.src / "skills/demo/SKILL.md").write_text("changed later")
        git(self.src, "commit", "-qam", "v2")
        self.repo = {"id": "demo", "url": str(self.src), "commit": self.sha, "license": "MIT", "license_file": "LICENSE",
                     "policy": "copy", "skills_dir": "skills", "skills": ["demo"]}
        self.base = base

    def tearDown(self):
        self.tmp.cleanup()

    def test_fetch_checks_out_pinned_commit_and_installs_with_license(self):
        clone = tp.fetch(self.repo, self.base / "cache")
        target = self.base / "proj"
        with contextlib.redirect_stdout(io.StringIO()):
            tp.install(self.repo, clone, target, None, dry=False)
        skill = target / ".claude/skills/demo"
        self.assertIn("name: demo", (skill / "SKILL.md").read_text())  # v1, not "changed later"
        self.assertEqual((skill / "UPSTREAM_LICENSE").read_text(), "MIT License")
        self.assertIn(self.sha, (skill / "UPSTREAM_SOURCE").read_text())

    def test_short_sha_refused(self):
        with self.assertRaises(SystemExit):
            tp.fetch({**self.repo, "commit": self.sha[:7]}, self.base / "cache")

    def test_existing_skill_not_overwritten(self):
        clone = tp.fetch(self.repo, self.base / "cache")
        target = self.base / "proj"
        (target / ".claude/skills/demo").mkdir(parents=True)
        (target / ".claude/skills/demo/SKILL.md").write_text("mine")
        with contextlib.redirect_stdout(io.StringIO()):
            tp.install(self.repo, clone, target, None, dry=False)
        self.assertEqual((target / ".claude/skills/demo/SKILL.md").read_text(), "mine")

    def test_unreviewed_skill_refused(self):
        clone = tp.fetch(self.repo, self.base / "cache")
        with self.assertRaises(SystemExit):
            tp.install(self.repo, clone, self.base / "proj", ["other"], dry=True)

    def test_link_only_repositories_cannot_be_installed(self):
        link_only = [r for r in json.loads((ROOT / "third_party/manifest.json").read_text())["repositories"] if r["policy"] == "link"]
        self.assertTrue(link_only)
        with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()):
            tp.main(["install", link_only[0]["id"], "--target", str(self.base / "proj")])


if __name__ == "__main__":
    unittest.main()
