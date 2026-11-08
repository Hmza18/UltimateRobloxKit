"""Security, licensing and code hygiene across the repository."""
import json
import py_compile
import re
import unittest

from _util import ROOT

SKIP = {".git", "build", "dist", "__pycache__", ".claude/skills"}
SECRET_PATTERNS = {
    "GitHub token": re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}"),
    "AWS key": re.compile(r"AKIA[0-9A-Z]{16}"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "Roblox cookie": re.compile(r"_\|WARNING:-DO-NOT-SHARE-THIS"),
    "Slack token": re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    "Anthropic or OpenAI key": re.compile(r"sk-(?:ant-)?[A-Za-z0-9_-]{32,}"),
    "assigned API key": re.compile(r"(?i)(?:api[_-]?key|secret|token)\s*[:=]\s*['\"][A-Za-z0-9+/_-]{24,}['\"]"),
}
PIPE_TO_SHELL = re.compile(r"(curl|wget|iwr|Invoke-WebRequest)[^\n|]*\|\s*(sudo\s+)?(sh|bash|zsh|iex|Invoke-Expression)\b")


def repo_files():
    for p in sorted(ROOT.rglob("*")):
        rel = p.relative_to(ROOT).as_posix()
        if p.is_file() and not any(rel == s or rel.startswith(s + "/") or f"/{s}/" in f"/{rel}" for s in SKIP):
            yield p, rel


class HygieneTests(unittest.TestCase):
    def test_no_secrets(self):
        hits = []
        for p, rel in repo_files():
            if p.suffix in (".png", ".jpg", ".blend", ".fbx", ".glb", ".zip"):
                continue
            text = p.read_text(encoding="utf-8", errors="ignore")
            for label, pat in SECRET_PATTERNS.items():
                if pat.search(text) and rel != "tests/test_repo_hygiene.py":
                    hits.append(f"{rel}: {label}")
        self.assertEqual(hits, [])

    def test_no_pipe_to_shell_in_executable_code(self):
        hits = []
        for p, rel in repo_files():
            if p.suffix in (".sh", ".ps1", ".py", ".yml", ".yaml", ".toml", ".json") and rel != "tests/test_repo_hygiene.py":
                if PIPE_TO_SHELL.search(p.read_text(encoding="utf-8", errors="ignore")):
                    hits.append(rel)
        self.assertEqual(hits, [], "piping downloads into a shell is not allowed")

    def test_python_compiles(self):
        for p, rel in repo_files():
            if p.suffix == ".py":
                with self.subTest(file=rel):
                    py_compile.compile(str(p), doraise=True)

    def test_json_parses(self):
        for p, rel in repo_files():
            if p.suffix == ".json":
                with self.subTest(file=rel):
                    json.loads(p.read_text(encoding="utf-8"))

    def test_third_party_manifest(self):
        data = json.loads((ROOT / "third_party/manifest.json").read_text())
        sources = (ROOT / "SOURCES.md").read_text()
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text()
        for r in data["repositories"]:
            with self.subTest(repo=r["id"]):
                self.assertIn(r["policy"], ("copy", "link", "pip"))
                self.assertTrue(r["license"])
                self.assertIn(r["url"], sources, "every reviewed repository is listed in SOURCES.md")
                if r["policy"] in ("copy", "pip"):
                    self.assertRegex(r["commit"], r"^[0-9a-f]{40}$", "copy and pip need a full pinned SHA")
                    self.assertIn(r["url"], notices)
                if r["policy"] == "copy":
                    self.assertTrue(re.match(r"^(MIT|Apache-2\.0|BSD-[23]-Clause|MPL-2\.0|CC0-1\.0)$", r["license"]), r["license"])

    def test_bundled_fonts_and_assets_have_licenses(self):
        for font in ROOT.rglob("*.ttf"):
            with self.subTest(font=font.name):
                self.assertTrue(any(font.parent.glob("*OFL*")) or any(font.parent.glob("LICENSE*")))

    def test_shell_scripts_strict_mode(self):
        for p, rel in repo_files():
            if p.suffix == ".sh":
                with self.subTest(file=rel):
                    self.assertIn("set -euo pipefail", p.read_text())


if __name__ == "__main__":
    unittest.main()
