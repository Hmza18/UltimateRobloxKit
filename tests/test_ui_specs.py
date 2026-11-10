"""Screen specs: shared fixtures, every built-in screen, the token generator and the preview renderer."""
import importlib.util
import json
import re
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
                    if spec_rules.ispackicon(name):
                        continue  # "pack:name" icons live in a game's own imported pack
                    self.assertTrue(name in icons or f"{name}-color" in icons, f"unknown icon {name}")


class MotionAndIconTests(unittest.TestCase):
    """`motion` ids mirror library/src/Visuals/UI/UIPresets.luau; pack icons are checked by shape."""

    def test_motion_list_holds_every_required_luau_preset(self):
        source = (ROOT / "library" / "src" / "Visuals" / "UI" / "UIPresets.luau").read_text()
        block = re.search(r"UIPresets\.REQUIRED = table\.freeze\(\{(.*?)\n\}\)", source, re.S)
        self.assertIsNotNone(block, "UIPresets.REQUIRED not found")
        required = set(re.findall(r'"([A-Za-z0-9]+)"', block.group(1)))
        self.assertGreaterEqual(len(required), 60)
        self.assertEqual(required - set(spec_rules.MOTION_PRESETS), set())
        # Every mirrored id is registered somewhere in the Luau file (the Lune parity spec checks equality).
        for name in spec_rules.MOTION_PRESETS:
            with self.subTest(preset=name):
                self.assertIn(f'"{name}"', source)
        self.assertEqual(len(spec_rules.MOTION_PRESETS), len(set(spec_rules.MOTION_PRESETS)))

    def test_motion_field(self):
        def issues(motion):
            spec = {"spec": 1, "id": "M", "kind": "window", "window": {"title": "M"},
                    "body": [{"type": "divider", "motion": motion}]}
            return {e["path"] for e in spec_rules.validate(spec)}
        self.assertEqual(issues("PopIn"), set())
        self.assertEqual(issues({"preset": "BouncyPress", "delay": 0.5}), set())
        self.assertEqual(issues("popIn"), {"body[1].motion"})
        self.assertEqual(issues({"delay": 1}), {"body[1].motion.preset"})
        self.assertEqual(issues({"preset": "PopIn", "delay": 6}), {"body[1].motion.delay"})

    def test_pack_icon_names(self):
        for name in ("mypack:sword", "ui-pack-2:iron-sword", "a:b"):
            self.assertTrue(spec_rules.ispackicon(name) and spec_rules.isicon(name), name)
        for name in ("MyPack:sword", "mypack:Sword", "mypack:", ":sword", "a:b:c", "a--b:c", "a:b-", "-a:b", "sword", None):
            self.assertFalse(spec_rules.ispackicon(name), name)

    def test_tracked_specs_name_no_real_pack(self):
        """Fixtures and built-in screens only use the placeholder pack id."""
        for f in list((FIX / "valid").glob("*.json")) + list(SCREENS.glob("*.json")):
            for pack in re.findall(r'"([a-z0-9-]+):[a-z0-9-]+"', f.read_text()):
                self.assertEqual(pack, "mypack", f.name)


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

    def test_preview_renders_every_style_and_animated_component(self):
        preview = load_tool("preview_spec")
        spec = json.loads((FIX / "valid" / "animated-components.json").read_text())
        for name in sorted(spec_rules.STYLES):
            with self.subTest(style=name):
                style = spec_rules.resolved_style(name)
                page = preview.render_spec({**spec, "style": name})
                self.assertNotIn('class="missing"', page, "every element type has a renderer and every icon resolves")
                for text in ("CLAIM REWARD", "Ember Fox", "EGG COLLECTOR", "Builderman", "QUEST COMPLETE", "REBIRTH?"):
                    self.assertIn(text, page)
                self.assertIn('title="motion: SlideInDown"', page)
                self.assertIn("pack icon mypack:iron-sword", page)
                # Text on a surface takes that surface's text colour (dark styles have light text).
                self.assertIn(f"--wt:{style['surfaces']['window']['text']}", page)
                self.assertIn(f"--it:{style['surfaces']['inset']['text']}", page)
                self.assertNotIn("PET WORLD", page, "hidden elements are not drawn")

    def test_preview_has_no_hard_coded_dark_ink(self):
        """Dark styles must not get dark text on dark surfaces: ink comes from the style's surfaces."""
        preview = load_tool("preview_spec")
        sheet = preview.css(spec_rules.resolved_style("scifi"))
        text_rules = re.findall(r"[;{]color:(#[0-9A-Fa-f]{3,8})", sheet)
        # Allowed fixed colours: white outlined text, the medal ink, the page note (on its own white pill)
        # and the gold of earned stars. Everything else must come from the style.
        fixed = [c for c in text_rules if c.lower() not in ("#fff", "#ffffff", "#1b1530", "#22324a", "#ffc83d")]
        self.assertEqual(fixed, [])
        # #1B1530 is only allowed on the fixed-colour medals.
        self.assertEqual(sheet.count("#1B1530"), 1)
        for surface in ("window", "inset", "dark"):
            self.assertIn(spec_rules.resolved_style("scifi")["surfaces"][surface]["text"], sheet)

    def test_preview_all_builtin_screens_in_a_dark_style(self):
        preview = load_tool("preview_spec")
        for f in sorted(SCREENS.glob("*.json")):
            with self.subTest(screen=f.name):
                page = preview.render_spec({**json.loads(f.read_text()), "style": "scifi"})
                self.assertNotIn('class="missing"', page)


if __name__ == "__main__":
    unittest.main()
