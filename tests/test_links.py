"""Every relative Markdown link in the repository resolves to a file or folder."""
import re
import unittest
from pathlib import Path

from _util import ROOT

LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)|!\[[^\]]*\]\(([^)\s]+)\)")
SKIP_DIRS = {".git", "node_modules", "build", "dist", ".claude/skills"}


class LinkTests(unittest.TestCase):
    def test_relative_links(self):
        missing = []
        for md in sorted(ROOT.rglob("*.md")):
            rel = md.relative_to(ROOT).as_posix()
            if any(rel.startswith(d + "/") or f"/{d}/" in rel for d in SKIP_DIRS):
                continue
            text = re.sub(r"```.*?```", "", md.read_text(encoding="utf-8"), flags=re.S)
            for m in LINK.finditer(text):
                target = (m.group(1) or m.group(2)).split("#")[0]
                if not target or re.match(r"^[a-z]+:", target) or target.startswith("#"):
                    continue
                if not (md.parent / target).resolve().exists():
                    missing.append(f"{rel} -> {target}")
        self.assertEqual(missing, [], "broken links:\n" + "\n".join(missing))


if __name__ == "__main__":
    unittest.main()
