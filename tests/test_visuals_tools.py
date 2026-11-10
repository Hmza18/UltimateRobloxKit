"""Visual asset tooling: procedural VFX textures, the asset-id map, the preview sheet, and the
contrast rules of the game styles the ten visual themes use."""
import contextlib
import csv
import hashlib
import importlib.util
import io
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from _util import ROOT

VFX = ROOT / "assets" / "vfx"
THEME_STYLES = ["vibrant", "premium", "fantasy", "anime", "scifi", "cozy", "minimal", "arcade", "luxury", "adventure"]
# Enum.Font names (Roblox API). UI/Game/Kit resolves a style's font through Enum.Font first.
ENUM_FONTS = set("""AmaticSC Antique Arcade Arial ArialBold Arimo ArimoBold Bangers Bodoni BuilderSans BuilderSansBold
BuilderSansExtraBold BuilderSansMedium Cartoon Code Creepster DenkOne Fantasy Fondamento FredokaOne Garamond Gotham
GothamBlack GothamBold GothamMedium GrenzeGotisch Highway IndieFlower JosefinSans Jura Kalam Legacy LuckiestGuy
Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SciFi
SourceSans SourceSansBold SourceSansItalic SourceSansLight SourceSansSemibold SpecialElite TitilliumWeb Ubuntu""".split())


def load(name):
    spec = importlib.util.spec_from_file_location(f"vfx_{name}", ROOT / "tools" / "vfx" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


textures = load("textures")
assetmap = load("assetmap")
preview = load("preview")


def run(main, argv):
    """(exit code, stdout, stderr) of a tool's main(argv)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(argv)
    return code, out.getvalue(), err.getvalue()


def png_header(data: bytes):
    """(width, height, bit depth, colour type) parsed from IHDR, checking the signature and CRC."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "PNG signature"
    length, tag = struct.unpack(">I4s", data[8:16])
    assert tag == b"IHDR" and length == 13
    body = data[16:29]
    assert struct.unpack(">I", data[29:33])[0] == zlib.crc32(b"IHDR" + body) & 0xFFFFFFFF, "IHDR CRC"
    width, height, depth, color = struct.unpack(">IIBB", body[:10])
    return width, height, depth, color


def alpha_at(pixels: bytes, width: int, x: int, y: int) -> int:
    return pixels[(y * width + x) * 4 + 3]


def luminance(hex_color: str) -> float:
    c = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a: str, b: str) -> float:
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


class CommittedTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((VFX / "manifest.json").read_text())
        cls.items = cls.manifest["textures"] + cls.manifest["flipbooks"]

    def test_check_passes_on_committed_output(self):
        code, out, _ = run(textures.main, ["--check"])
        self.assertEqual(code, 0, out)

    def test_every_required_key_exists(self):
        keys = {i["key"] for i in self.items}
        for key in textures.REQUIRED_KEYS:
            self.assertIn(key, keys)
        for key in ("spark", "glow", "star", "ring", "smoke", "circle", "confetti", "coin", "gem", "heart", "leaf",
                    "drop", "shard", "bubble", "flare", "streak", "rays", "gradient_linear", "gradient_radial"):
            self.assertIn(key, keys, "VFX texture key")
        self.assertEqual(len(keys), len(self.items), "keys are unique")
        self.assertEqual(self.manifest["license"], "MIT")

    def test_files_are_valid_rgba_pngs_with_power_of_two_sizes(self):
        for item in self.items:
            with self.subTest(key=item["key"]):
                data = (VFX / item["file"]).read_bytes()
                width, height, depth, color = png_header(data)
                self.assertEqual((depth, color), (8, 6), "8-bit RGBA")
                self.assertEqual([width, height], item["size"])
                for side in (width, height):
                    self.assertTrue(side & (side - 1) == 0 and 8 <= side <= 1024, f"{side} is a power of two")
                self.assertEqual(data[-12:], b"\x00\x00\x00\x00IEND\xaeB`\x82", "ends with IEND")
                decoded_width, decoded_height, pixels = textures.decode_png(data)
                self.assertEqual(len(pixels), decoded_width * decoded_height * 4)
                self.assertTrue(any(pixels[i] for i in range(3, len(pixels), 4)), "not fully transparent")

    def test_manifest_matches_files_and_hashes(self):
        listed = {i["file"] for i in self.items}
        on_disk = {p.relative_to(VFX).as_posix() for d in ("textures", "flipbooks") for p in (VFX / d).glob("*.png")}
        self.assertEqual(listed, on_disk)
        for item in self.items:
            with self.subTest(key=item["key"]):
                data = (VFX / item["file"]).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), item["sha256"])
                self.assertEqual(len(data), item["bytes"])
                self.assertEqual(hashlib.sha256(textures.decode_png(data)[2]).hexdigest(), item["pixelSha256"])
                self.assertTrue(item["description"].strip())
                self.assertIn("assetId", item)
                self.assertTrue(item["assetId"] is None or isinstance(item["assetId"], int))

    def test_total_size_stays_small(self):
        total = sum(i["bytes"] for i in self.items)
        self.assertLess(total, 600 * 1024, f"{total} bytes of generated PNGs")

    def test_transparent_pixels_stay_white(self):
        """White RGB under zero alpha: filtering never drags a dark fringe into the edge."""
        for key in ("glow", "star", "ring", "heart"):
            _, _, pixels = textures.decode_png((VFX / "textures" / f"{key}.png").read_bytes())
            for i in range(0, len(pixels), 4):
                if pixels[i + 3] == 0:
                    self.assertEqual(pixels[i:i + 3], b"\xff\xff\xff", key)
                    break

    def test_glow_is_brightest_at_centre_and_transparent_at_corners(self):
        width, height, pixels = textures.decode_png((VFX / "textures" / "glow.png").read_bytes())
        centre = alpha_at(pixels, width, width // 2, height // 2)
        self.assertGreaterEqual(centre, 240)
        self.assertEqual(centre, max(pixels[i] for i in range(3, len(pixels), 4)), "the centre is the brightest pixel")
        for x, y in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
            self.assertEqual(alpha_at(pixels, width, x, y), 0, f"corner {x},{y}")
        ring = [alpha_at(pixels, width, width // 2 + d, height // 2) for d in range(0, width // 2, 8)]
        self.assertEqual(ring, sorted(ring, reverse=True), "alpha falls monotonically from the centre")

    def test_shapes_have_the_expected_coverage(self):
        def load_pixels(key):
            return textures.decode_png((VFX / "textures" / f"{key}.png").read_bytes())

        width, height, pixels = load_pixels("ring")
        self.assertEqual(alpha_at(pixels, width, width // 2, height // 2), 0, "a ring is hollow")
        self.assertGreater(alpha_at(pixels, width, int(width * (0.5 + 0.39)), height // 2), 200, "a ring has a band")

        width, height, pixels = load_pixels("circle")
        self.assertEqual(alpha_at(pixels, width, width // 2, height // 2), 255)
        self.assertEqual(alpha_at(pixels, width, 1, 1), 0)

        width, height, pixels = load_pixels("heart")
        self.assertEqual(alpha_at(pixels, width, width // 2, height // 2), 255)
        self.assertEqual(alpha_at(pixels, width, width // 2, 2), 0, "the notch between the lobes is empty")

        width, height, pixels = load_pixels("streak")
        row = height // 2
        self.assertGreater(alpha_at(pixels, width, int(width * 0.85), row), alpha_at(pixels, width, int(width * 0.2), row))

        width, height, pixels = load_pixels("gradient_linear")
        column = [alpha_at(pixels, width, width // 2, y) for y in range(height)]
        self.assertEqual(column, sorted(column, reverse=True))
        self.assertGreater(column[0], 250)
        self.assertLess(column[-1], 5)

    def test_flipbooks_match_particle_flipbook_layouts(self):
        self.assertEqual(textures.FLIPBOOK_LAYOUTS, {"Grid2x2": 2, "Grid4x4": 4, "Grid8x8": 8})
        self.assertGreaterEqual(len(self.manifest["flipbooks"]), 2)
        for item in self.manifest["flipbooks"]:
            with self.subTest(key=item["key"]):
                grid = textures.FLIPBOOK_LAYOUTS[item["layout"]]
                self.assertEqual(item["frames"], grid * grid)
                self.assertEqual(item["size"][0], item["size"][1], "flipbook sheets are square")
                self.assertEqual(item["frameSize"][0] * grid, item["size"][0])
                width, _, pixels = textures.decode_png((VFX / item["file"]).read_bytes())
                cell = item["frameSize"][0]
                for frame in range(item["frames"] - 1):  # the last frame of a fade may be empty
                    ox, oy = (frame % grid) * cell, (frame // grid) * cell
                    filled = any(alpha_at(pixels, width, ox + x, oy + y) for y in range(0, cell, 4) for x in range(0, cell, 4))
                    self.assertTrue(filled, f"frame {frame} has content")


class TextureGeneratorTests(unittest.TestCase):
    def test_rendering_is_deterministic(self):
        only = {"glow", "smoke", "star", "sparkle_twinkle"}
        first, second = textures.build(only), textures.build(only)
        self.assertEqual(set(first), {"textures/glow.png", "textures/smoke.png", "textures/star.png",
                                      "flipbooks/sparkle_twinkle.png"})
        for rel in first:
            self.assertEqual(first[rel][1], second[rel][1], rel)
            entry = first[rel][0]
            self.assertEqual(textures.encode_png(*entry["size"], first[rel][1]),
                             textures.encode_png(*entry["size"], second[rel][1]), rel)

    def test_two_full_writes_are_identical(self):
        results = textures.build({"ring", "confetti", "puff_dissolve"})
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            textures.write(Path(a), results)
            textures.write(Path(b), textures.build({"ring", "confetti", "puff_dissolve"}))
            files = sorted(p.relative_to(a).as_posix() for p in Path(a).rglob("*") if p.is_file())
            self.assertEqual(files, ["flipbooks/puff_dissolve.png", "manifest.json", "textures/confetti.png",
                                     "textures/ring.png"])
            for rel in files:
                self.assertEqual((Path(a) / rel).read_bytes(), (Path(b) / rel).read_bytes(), rel)

    def test_png_round_trip(self):
        pixels = bytes((x * 7 + y * 13 + c * 31) & 0xFF for y in range(8) for x in range(16) for c in range(4))
        data = textures.encode_png(16, 8, pixels)
        self.assertEqual(png_header(data), (16, 8, 8, 6))
        self.assertEqual(textures.decode_png(data), (16, 8, pixels))
        with self.assertRaises(ValueError):
            textures.decode_png(b"not a png")

    def test_sheet_packing_order(self):
        def solid(value):
            return bytes([255, 255, 255, value]) * 4  # 2 x 2 frame

        sheet = textures.pack_sheet([solid(10), solid(20), solid(30), solid(40)], 2, 2)
        self.assertEqual(len(sheet), 4 * 4 * 4)
        self.assertEqual(alpha_at(sheet, 4, 0, 0), 10)
        self.assertEqual(alpha_at(sheet, 4, 3, 0), 20, "second frame is top right")
        self.assertEqual(alpha_at(sheet, 4, 0, 3), 30, "third frame is bottom left")
        self.assertEqual(alpha_at(sheet, 4, 3, 3), 40)
        with self.assertRaises(ValueError):
            textures.pack_sheet([solid(1)], 2, 2)

    def test_check_detects_stale_missing_and_stray_files(self):
        results = textures.build({"circle", "gradient_linear"})
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            textures.write(out, results)
            problems = textures.check(out, results)
            self.assertTrue(all("required key" in p for p in problems), problems)  # a subset lacks the other keys

            target = out / "textures" / "circle.png"
            original = target.read_bytes()
            target.write_bytes(textures.encode_png(128, 128, bytes(128 * 128 * 4)))
            self.assertTrue(any("circle.png" in p for p in textures.check(out, results)))
            target.write_bytes(original)

            (out / "textures" / "stray.png").write_bytes(original)
            self.assertTrue(any("stray.png" in p for p in textures.check(out, results)))
            (out / "textures" / "stray.png").unlink()

            target.unlink()
            self.assertTrue(any("missing textures/circle.png" in p for p in textures.check(out, results)))

    def test_pixel_comparison_tolerates_one_step_only(self):
        self.assertTrue(textures.pixels_match(bytes([10, 20, 30, 40]), bytes([11, 19, 30, 40])))
        self.assertFalse(textures.pixels_match(bytes([10, 20, 30, 40]), bytes([12, 20, 30, 40])))
        self.assertFalse(textures.pixels_match(bytes([10, 20]), bytes([10])))

    def test_rebuild_keeps_asset_ids(self):
        results = textures.build({"circle"})
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            textures.write(out, results)
            manifest = json.loads((out / "manifest.json").read_text())
            manifest["textures"][0]["assetId"] = 424242
            (out / "manifest.json").write_text(json.dumps(manifest))
            textures.write(out, results)
            self.assertEqual(json.loads((out / "manifest.json").read_text())["textures"][0]["assetId"], 424242)

    def test_cli_list_and_bad_arguments(self):
        code, out, _ = run(textures.main, ["--list"])
        self.assertEqual(code, 0)
        self.assertIn("glow", out)
        self.assertIn("Grid4x4", out)
        code, _, err = run(textures.main, ["--only", "doesNotExist"])
        self.assertEqual(code, 2)
        self.assertIn("doesNotExist", err)


class AssetMapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.manifest = self.dir / "manifest.json"
        data = json.loads((VFX / "manifest.json").read_text())
        for item in data["textures"] + data["flipbooks"]:
            item["assetId"] = None
        self.manifest.write_text(json.dumps(data, indent=2) + "\n")

    def tool(self, *argv):
        return run(assetmap.main, ["--manifest", str(self.manifest), *map(str, argv)])

    def ids(self):
        data = json.loads(self.manifest.read_text())
        return {i["key"]: i["assetId"] for i in data["textures"] + data["flipbooks"]}

    def test_template_lists_every_key(self):
        code, out, _ = self.tool("template")
        self.assertEqual(code, 0)
        rows = list(csv.DictReader(io.StringIO(out)))
        self.assertEqual([r["key"] for r in rows], list(self.ids()))
        self.assertTrue(all(r["assetId"] == "" for r in rows))
        code, out, _ = self.tool("template", "--format", "json")
        self.assertEqual(json.loads(out), {key: None for key in self.ids()})

    def test_csv_round_trip(self):
        path = self.dir / "ids.csv"
        self.assertEqual(self.tool("template", "--out", path)[0], 0)
        rows = list(csv.reader(path.read_text().splitlines()))
        filled = {"glow": "1234567890", "spark": "rbxassetid://1234567891",
                  "sparkle_twinkle": "https://create.roblox.com/store/asset/1234567892/Twinkle"}
        for row in rows[1:]:
            row[2] = filled.get(row[0], "")
        path.write_text("\n".join(",".join(r) for r in rows) + "\n")

        code, out, err = self.tool("apply", path)
        self.assertEqual(code, 0, err)
        ids = self.ids()
        self.assertEqual((ids["glow"], ids["spark"], ids["sparkle_twinkle"]), (1234567890, 1234567891, 1234567892))
        self.assertIsNone(ids["ring"], "blank cells leave a key alone")
        self.assertIn("3/25" if len(ids) == 25 else f"3/{len(ids)}", err)
        self.assertIn('glow = "rbxassetid://1234567890",', out)
        self.assertIn('spark = "rbxassetid://1234567891",', out)
        self.assertIn("Enum.ParticleFlipbookLayout.Grid4x4", out)
        self.assertNotIn("ring =", out, "unmapped keys are left out of the Luau map")
        self.assertTrue(out.startswith("--!strict\n"))
        self.assertTrue(out.rstrip().endswith("} :: { [string]: string }"))

        code, out, _ = self.tool("template")
        self.assertIn("glow,textures/glow.png,1234567890", out, "the template is pre-filled with known ids")
        code, out, _ = self.tool("status")
        self.assertEqual(code, 0)
        self.assertIn(f"3/{len(ids)}", out)
        self.assertEqual(self.tool("status", "--require-all")[0], 1)

    def test_json_map_out_file_dry_run_and_clear(self):
        path = self.dir / "ids.json"
        path.write_text(json.dumps({"coin": 77, "gem": "78"}))
        luau = self.dir / "out" / "VfxTextures.luau"
        code, out, _ = self.tool("apply", path, "--out", luau, "--dry-run")
        self.assertEqual((code, out), (0, ""))
        self.assertIn('coin = "rbxassetid://77",', luau.read_text())
        self.assertIsNone(self.ids()["coin"], "a dry run leaves the manifest alone")

        self.assertEqual(self.tool("apply", path)[0], 0)
        self.assertEqual((self.ids()["coin"], self.ids()["gem"]), (77, 78))
        path.write_text(json.dumps({"coin": None}))
        self.assertEqual(self.tool("apply", path)[0], 0)
        self.assertIsNone(self.ids()["coin"], "null clears an id")
        self.assertEqual(self.ids()["gem"], 78)
        code, out, _ = self.tool("luau")
        self.assertIn('gem = "rbxassetid://78",', out)
        self.assertNotIn("coin =", out)

    def test_bad_ids_are_rejected_and_nothing_is_written(self):
        before = self.manifest.read_text()
        cases = {
            "letters": ({"glow": "abc"}, "not an asset id"),
            "zero": ({"glow": 0}, "greater than 0"),
            "negative": ({"glow": -5}, "greater than 0"),
            "fraction": ({"glow": 1.5}, "whole number"),
            "boolean": ({"glow": True}, "boolean"),
            "huge": ({"glow": 2 ** 60}, "too large"),
            "unknown key": ({"notATexture": 5}, "unknown texture key"),
            "duplicate id": ({"glow": 9, "spark": 9}, "already used"),
            "mixed": ({"glow": 5, "spark": "12x"}, "not an asset id"),
        }
        for label, (mapping, message) in cases.items():
            with self.subTest(case=label):
                path = self.dir / "bad.json"
                path.write_text(json.dumps(mapping))
                code, out, err = self.tool("apply", path)
                self.assertEqual(code, 1)
                self.assertEqual(out, "")
                self.assertIn(message, err)
                self.assertEqual(self.manifest.read_text(), before, "an invalid map changes nothing")

    def test_malformed_files(self):
        path = self.dir / "bad.csv"
        path.write_text("name,id\nglow,5\n")
        self.assertIn("header", self.tool("apply", path)[2])
        path.write_text("key,file,assetId\nglow,,5\nglow,,6\n")
        self.assertIn("twice", self.tool("apply", path)[2])
        bad_json = self.dir / "bad.json"
        bad_json.write_text("{ not json")
        self.assertEqual(self.tool("apply", bad_json)[0], 1)
        self.assertEqual(self.tool("apply", self.dir / "missing.csv")[0], 1)
        code, _, err = run(assetmap.main, ["--manifest", str(self.dir / "nope.json"), "status"])
        self.assertEqual(code, 1)
        self.assertIn("textures.py", err)

    def test_id_cannot_collide_with_an_existing_one(self):
        path = self.dir / "ids.json"
        path.write_text(json.dumps({"glow": 500}))
        self.assertEqual(self.tool("apply", path)[0], 0)
        path.write_text(json.dumps({"spark": 500}))
        code, _, err = self.tool("apply", path)
        self.assertEqual(code, 1)
        self.assertIn("already used by glow", err)

    def test_parse_id_forms(self):
        self.assertEqual(assetmap.parse_id("rbxassetid://42"), 42)
        self.assertEqual(assetmap.parse_id(" 42 "), 42)
        self.assertEqual(assetmap.parse_id(42.0), 42)
        self.assertEqual(assetmap.parse_id("https://www.roblox.com/library/42/Name"), 42)
        for bad in ("", "rbxassetid://", "rbxasset://textures/x.png", "42abc", None, [], "https://example.com/42"):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                assetmap.parse_id(bad)

    def test_committed_manifest_has_no_placeholder_ids(self):
        state = assetmap.status(json.loads((VFX / "manifest.json").read_text()))
        self.assertEqual(state["total"], state["mapped"] + len(state["missing"]))


class PreviewTests(unittest.TestCase):
    def test_contact_sheet_is_self_contained(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "sheet" / "preview.html"
            code, stdout, _ = run(preview.main, ["--out", str(out), "--tint", "#33CCFF"])
            self.assertEqual(code, 0, stdout)
            page = out.read_text()
        manifest = json.loads((VFX / "manifest.json").read_text())
        for item in manifest["textures"] + manifest["flipbooks"]:
            self.assertIn(f"<b>{item['key']}</b>", page)
        self.assertGreaterEqual(page.count("data:image/png;base64,"), len(manifest["textures"]) * 3)
        self.assertIn("#33CCFF", page)
        self.assertIn('class="sw dark"', page)
        self.assertIn('class="sw light"', page)
        for external in ("http://", "https://", "<link", "src=\"/"):
            self.assertNotIn(external, page, "no network references")

    def test_bad_arguments(self):
        self.assertEqual(run(preview.main, ["--tint", "red"])[0], 2)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(run(preview.main, ["--assets", tmp, "--out", str(Path(tmp) / "p.html")])[0], 1)


class ThemeStyleContrastTests(unittest.TestCase):
    """The ten visual themes are styles in design/tokens/styles.json; these are their readability rules."""

    @classmethod
    def setUpClass(cls):
        build_tokens = importlib.util.spec_from_file_location("build_tokens", ROOT / "tools/ui/build_tokens.py")
        mod = importlib.util.module_from_spec(build_tokens)
        build_tokens.loader.exec_module(mod)
        raw = json.loads((ROOT / "design/tokens/styles.json").read_text())["styles"]
        cls.raw = raw
        cls.styles = mod.resolve(raw)

    def test_the_ten_theme_styles_exist_and_are_complete(self):
        reference = self.styles["cartoon"]
        for name in THEME_STYLES:
            with self.subTest(style=name):
                self.assertIn(name, self.styles)
                style = self.styles[name]
                self.assertNotIn("extends", self.raw[name], "theme styles are complete, not variants of cartoon")
                self.assertEqual(set(style), set(reference), "same sections as cartoon")
                for section, value in reference.items():
                    if isinstance(value, dict) and section not in ("pattern",):
                        self.assertEqual(set(style[section]), set(value), f"{section} has the same keys as cartoon")
                self.assertTrue(style["description"].strip())

    def test_existing_styles_keep_their_values(self):
        cartoon = self.styles["cartoon"]
        self.assertEqual(cartoon["palette"]["purple"], {"top": "#B98CFF", "bottom": "#7A4DE8", "text": "#FFFFFF"})
        self.assertEqual(cartoon["outline"], {"color": "#1B1530", "thin": 2, "regular": 3, "thick": 4, "heavy": 6})
        self.assertEqual(self.styles["midnight"]["surfaces"]["window"]["top"], "#2B2F52")
        self.assertEqual(self.styles["pastel"]["palette"]["green"]["text"], "#2B2240")
        self.assertEqual(cartoon["rarity"]["mythic"], {"color": "#FF3B6B"})
        self.assertEqual(cartoon["rarity"]["secret"], {"color": "#FFFFFF", "rainbow": True})

    def test_surface_text_meets_wcag_aa(self):
        """Body text on every surface, at both ends of its gradient: at least 4.5:1."""
        for name, style in self.styles.items():
            for surface, swatch in style["surfaces"].items():
                for end in ("top", "bottom"):
                    with self.subTest(style=name, surface=surface, end=end):
                        self.assertGreaterEqual(contrast(swatch["text"], swatch[end]), 4.5)

    def test_palette_text_is_readable(self):
        """Button and card text: either the text colour itself reaches 4.5:1 on the swatch, or a text
        stroke of 2 px or more carries it and the stroke reaches 3:1 against the swatch."""
        for name in THEME_STYLES:
            style = self.styles[name]
            stroke = style["textStroke"]
            for palette, swatch in style["palette"].items():
                with self.subTest(style=name, palette=palette):
                    self.assertGreaterEqual(contrast(stroke["color"], swatch["bottom"]), 3.0)
                    own = min(contrast(swatch["text"], swatch["top"]), contrast(swatch["text"], swatch["bottom"]))
                    if stroke["thickness"] < 2:
                        self.assertGreaterEqual(own, 4.5, "thin strokes need readable text on their own")
                    else:
                        self.assertGreaterEqual(contrast(stroke["color"], swatch["text"]), 4.5,
                                                "the stroke separates the text from the fill")

    def test_fonts_are_shipped_by_roblox(self):
        for name in THEME_STYLES:
            for role, family in self.styles[name]["fonts"].items():
                with self.subTest(style=name, role=role):
                    self.assertIn(family, ENUM_FONTS)

    def test_styles_are_distinct_art_directions(self):
        seen = {}
        for name in THEME_STYLES:
            style = self.styles[name]
            signature = (style["surfaces"]["window"]["top"], style["outline"]["color"], style["fonts"]["title"],
                         style["radius"]["md"], style["pattern"]["kind"])
            for other, other_signature in seen.items():
                differing = sum(a != b for a, b in zip(signature, other_signature))
                self.assertGreaterEqual(differing, 3, f"{name} is too close to {other}")
            seen[name] = signature
            self.assertNotEqual(style["palette"], self.styles["cartoon"]["palette"], f"{name} has its own palette")

    def test_rarity_covers_mythic_and_secret(self):
        for name in THEME_STYLES:
            rarity = self.styles[name]["rarity"]
            self.assertEqual(list(rarity), ["common", "uncommon", "rare", "epic", "legendary", "mythic", "secret"])
            self.assertTrue(rarity["secret"].get("rainbow"))
            colors = [rarity[k]["color"] for k in list(rarity)[:6]]
            self.assertEqual(len(set(colors)), 6, f"{name} rarity colours are distinct")

    def test_theme_data_points_at_these_styles(self):
        text = (ROOT / "library/src/Visuals/Themes/ThemeData.luau").read_text()
        for name in THEME_STYLES:
            self.assertIn(f'style = "{name}"', text)


if __name__ == "__main__":
    unittest.main()
