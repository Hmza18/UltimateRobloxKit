"""Screen specs: shared fixtures, every built-in screen, the token generator and the preview renderer."""
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from _util import ROOT

sys.path.insert(0, str(ROOT / "tools" / "ui"))
import spec_rules  # noqa: E402

FIX = ROOT / "tests" / "fixtures" / "ui-specs"
SCREENS = ROOT / "library" / "src" / "UI" / "Spec" / "Screens"


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / "ui" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SpecRuleTests(unittest.TestCase):
    def test_valid_fixtures(self):
        for f in sorted((FIX / "valid").glob("*.json")):
            with self.subTest(fixture=f.name):
                self.assertEqual(spec_rules.validate(json.loads(f.read_text())), [])

    def test_invalid_fixtures_report_expected_paths(self):
        expected = json.loads((FIX / "invalid" / "expected.json").read_text())
        self.assertGreaterEqual(len(expected), 15)
        for name, paths in expected.items():
            with self.subTest(fixture=name):
                errors = spec_rules.validate(json.loads((FIX / "invalid" / f"{name}.json").read_text()))
                got = {e["path"] for e in errors}
                for p in paths:
                    self.assertIn(p, got, f"{name}: {errors}")

    def test_builtin_screens_are_valid(self):
        screens = sorted(SCREENS.glob("*.json"))
        if not screens:
            self.skipTest("no built-in screens yet")
        self.assertGreaterEqual(len(screens), 16)
        for f in screens:
            with self.subTest(screen=f.name):
                self.assertEqual(spec_rules.validate(json.loads(f.read_text())), [])

    def test_specs_use_existing_icons(self):
        icons = {i["name"] for i in json.loads((ROOT / "assets/icons/urk/icons.json").read_text())["icons"]}
        files = list((FIX / "valid").glob("*.json")) + list(SCREENS.glob("*.json"))

        def walk(node, path):
            if isinstance(node, dict):
                for k, v in node.items():
                    if k in ("icon", "currency") and isinstance(v, str):
                        yield path + "." + k, v
                    yield from walk(v, f"{path}.{k}")
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    yield from walk(v, f"{path}[{i}]")

        for f in files:
            for where, name in walk(json.loads(f.read_text()), f.name):
                with self.subTest(where=where):
                    self.assertTrue(name in icons or f"{name}-color" in icons, f"unknown icon {name}")


class TokenTests(unittest.TestCase):
    def test_generated_luau_is_current(self):
        self.assertEqual(load_tool("build_tokens").main(["--check"]), 0)

    def test_every_style_resolves_required_keys(self):
        required = {"fonts", "text", "textStroke", "outline", "radius", "spacing", "palette", "surfaces", "buttons",
                    "badges", "rarity", "motion", "sizes", "pattern", "gloss", "shadow"}
        for name in spec_rules.STYLES:
            with self.subTest(style=name):
                style = spec_rules.resolved_style(name)
                self.assertTrue(required <= set(style), required - set(style))
                for kind, b in style["buttons"].items():
                    self.assertTrue(b.get("palette") in style["palette"] or b.get("surface") in style["surfaces"], kind)
                for kind, b in style["badges"].items():
                    self.assertIn(b["palette"], style["palette"], kind)

    def test_palette_text_is_readable_on_bottom_colour(self):
        """Card captions use white text with a dark outline; the outline makes contrast, so check the
        outline against the palette instead (WCAG 3:1 for large text)."""
        def lum(hexc):
            c = [int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)]
            c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        for name in spec_rules.STYLES:
            style = spec_rules.resolved_style(name)
            outline = style["textStroke"]["color"]
            for pal, sw in style["palette"].items():
                a, b = sorted((lum(outline), lum(sw["bottom"])), reverse=True)
                with self.subTest(style=name, palette=pal):
                    self.assertGreaterEqual((a + 0.05) / (b + 0.05), 3.0)


class PreviewTests(unittest.TestCase):
    def test_preview_renders_offline_and_refuses_invalid(self):
        preview = load_tool("preview_spec")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "shop.html"
            self.assertEqual(preview.main([str(FIX / "valid" / "pet-shop.json"), "-o", str(out)]), 0)
            page = out.read_text()
            self.assertIn("STARTER PACK", page)
            self.assertIn("data:image/png;base64", page)
            self.assertNotIn("<script src", page)
            self.assertNotIn("https://", page.split("<body>")[0], "no external fetches in <head>")
            with self.assertRaises(SystemExit):
                preview.render_spec(json.loads((FIX / "invalid" / "bad-palette.json").read_text()))


if __name__ == "__main__":
    unittest.main()
