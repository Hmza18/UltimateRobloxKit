"""URK Icons: catalog integrity, files, sprite-sheet geometry, Luau data in sync, and the importer."""
import importlib.util
import json
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from _util import ROOT

ICONS = ROOT / "assets/icons/urk"
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def png_size(path: Path):
    head = path.read_bytes()[:24]
    assert head[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", head[16:24])


HAS_PIL = importlib.util.find_spec("PIL") is not None


class IconCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cat = json.loads((ICONS / "icons.json").read_text())

    def test_metadata_and_license(self):
        self.assertEqual(self.cat["license"], "MIT")
        self.assertGreaterEqual(len(self.cat["icons"]), 250)
        styles = {i["style"] for i in self.cat["icons"]}
        self.assertEqual(styles, {"glyph", "color"})
        glyphs = {i["name"] for i in self.cat["icons"] if i["style"] == "glyph"}
        for g in glyphs:
            self.assertIn(f"{g}-color", {i["name"] for i in self.cat["icons"]}, "every glyph has an illustrated version")
        self.assertTrue((ROOT / "assets/icons/LICENSE.md").exists())

    def test_names_categories_tags(self):
        names = [i["name"] for i in self.cat["icons"]]
        self.assertEqual(len(names), len(set(names)))
        for i in self.cat["icons"]:
            with self.subTest(icon=i["name"]):
                self.assertRegex(i["name"], NAME)
                self.assertIn(i["category"], self.cat["categories"])
                self.assertGreaterEqual(len(i["tags"]), 1, "every icon is searchable by at least one tag")

    def test_files_and_geometry(self):
        for s in self.cat["sheets"]:
            self.assertEqual(png_size(ICONS / s["file"]), (1024, 1024))
        cells = set()
        for i in self.cat["icons"]:
            with self.subTest(icon=i["name"]):
                self.assertEqual(png_size(ICONS / "png" / f"{i['name']}.png"), (256, 256))
                self.assertTrue(0 <= i["x"] <= 1024 - i["w"] and 0 <= i["y"] <= 1024 - i["h"])
                self.assertEqual((i["x"] % 128, i["y"] % 128), (0, 0))
                key = (i["sheet"], i["x"], i["y"])
                self.assertNotIn(key, cells, "two icons share a cell")
                cells.add(key)
                self.assertLessEqual(i["sheet"], len(self.cat["sheets"]))

    def test_luau_data_matches_catalog(self):
        text = (ROOT / "library/src/Icons/IconData.luau").read_text()
        rows = re.findall(r'name = "([^"]+)", base = "[^"]+", style = "[^"]+", category = "([^"]+)".*?sheet = (\d+), x = (\d+), y = (\d+)', text)
        self.assertEqual([(r[0], r[1], int(r[2]), int(r[3]), int(r[4])) for r in rows],
                         [(i["name"], i["category"], i["sheet"], i["x"], i["y"]) for i in self.cat["icons"]])

    @unittest.skipUnless(HAS_PIL, "Pillow not installed")
    def test_build_is_reproducible(self):
        out = subprocess.run([sys.executable, str(ROOT / "tools/icons/build_icons.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    @unittest.skipUnless(HAS_PIL, "Pillow not installed")
    def test_style_validator(self):
        spec = importlib.util.spec_from_file_location("validate_icon", ROOT / "tools/icons/validate_icon.py")
        v = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(v)
        for i in self.cat["icons"]:
            with self.subTest(icon=i["name"]):
                r = v.check(ICONS / "png" / f"{i['name']}.png", glyph=i["style"] == "glyph")
                self.assertEqual([k for k, x in r.items() if not x["ok"]], [])
        from PIL import Image, ImageDraw
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.png"
            img = Image.new("RGBA", (256, 256), (240, 240, 240, 255))  # baked background
            ImageDraw.Draw(img).rectangle([10, 10, 90, 90], fill=(200, 200, 200, 255))  # off-centre, no outline
            img.save(bad)
            r = v.check(bad)
            failed = {k for k, x in r.items() if not x["ok"]}
            self.assertTrue({"transparent", "outline"} <= failed, failed)

    @unittest.skipUnless(HAS_PIL, "Pillow not installed")
    def test_importer_normalises_and_protects(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "pack" / "Weapons"
            src.mkdir(parents=True)
            for n in ("Sword_Icon 01.png", "BowIcon.png"):
                (src / n).write_bytes((ICONS / "png" / "sword.png").read_bytes())
            out = Path(tmp) / "out"
            cmd = [sys.executable, str(ROOT / "tools/icons/import_pack.py"), str(Path(tmp) / "pack"), "--pack", "demo",
                   "--source", "test", "--license-note", "test", "--out", str(out), "--luau", str(out / "Demo.luau")]
            r = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            cat = json.loads((out / "icons.json").read_text())
            self.assertEqual(sorted(i["name"] for i in cat["icons"]), ["bow-icon", "sword-icon-01"])
            self.assertEqual({i["category"] for i in cat["icons"]}, {"weapons"})
            self.assertIn("*", (out / ".gitignore").read_text())
            self.assertIn("Licence accepted", (out / "PROVENANCE.md").read_text())
            self.assertIn('pack = "demo"', (out / "Demo.luau").read_text())
            r2 = subprocess.run(cmd[:-6] + ["--pack", "other", "--source", "x", "--license-note", "x", "--out", str(out)],
                                capture_output=True, text=True)
            self.assertNotEqual(r2.returncode, 0, "a second pack must not overwrite the first")


if __name__ == "__main__":
    unittest.main()
