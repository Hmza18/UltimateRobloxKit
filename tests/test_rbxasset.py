"""The Blender-free asset kit: every generator closed and outward, atlas and texture valid."""
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from _util import ROOT  # noqa: F401
from rbxasset.atlas import pack, pack_guide, to_texture_uv
from rbxasset.generators import REGISTRY, build
from rbxasset.grid import layer_fits
from rbxasset.layout import make_layout
from rbxasset.meshkit import validate


class GeneratorTests(unittest.TestCase):
    def test_every_generator_closed_outward_and_fitted(self):
        for name in sorted(REGISTRY):
            for size in ([1.0, 1.0, 1.0], [2.5, 0.8, 3.2]):
                with self.subTest(generator=name, size=size):
                    mesh = build({"generator": name, "size": size})
                    v = validate(mesh)
                    self.assertTrue(v["closed"], v)
                    self.assertTrue(v["outward"], v)
                    self.assertEqual(v["degenerate_faces"], 0)
                    self.assertLessEqual(v["tris"], 1000)
                    (x0, y0, z0), (x1, y1, z1) = mesh.bounds()
                    for got, want in zip((x1 - x0, y1 - y0, z1 - z0), size):
                        self.assertAlmostEqual(got, want, places=5)
                    self.assertAlmostEqual(z0, 0.0, places=6)
                    self.assertAlmostEqual((x0 + x1) / 2, 0.0, places=6)

    def test_unknown_generator(self):
        with self.assertRaises(KeyError):
            build({"generator": "nope", "size": [1, 1, 1]})

    def test_atlas_inside_texture(self):
        mesh = build({"generator": "barrel", "size": [1.6, 1.6, 2.2]})
        for packer in (pack, pack_guide):
            rects = packer(mesh.panels, 1024)
            for name, r in rects.items():
                fw, fh = (r["h"], r["w"]) if r.get("rot") else (r["w"], r["h"])
                with self.subTest(packer=packer.__name__, panel=name):
                    self.assertGreaterEqual(r["x"], 0)
                    self.assertGreaterEqual(r["y"], 0)
                    self.assertLessEqual(r["x"] + fw, 1024)
                    self.assertLessEqual(r["y"] + fh, 1024)
                    for corner in ((0, 0), (1, 1)):
                        u, v = to_texture_uv(corner, r)
                        self.assertTrue(0 <= u <= 1 and 0 <= v <= 1)

    def test_grid(self):
        self.assertTrue(layer_fits({"width": 0.8, "depth": 0.4, "pitch": [0.9, 0.4625]}, {}))
        self.assertFalse(layer_fits({"width": 1.0, "depth": 0.4, "pitch": [0.9, 0.4625]}, {}))


class LayoutTests(unittest.TestCase):
    def test_layout_and_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            layout = make_layout({"name": "Crate", "generator": "crate", "size": [2, 2, 2], "colors": {"wood": "#D08A3E"}}, tmp)
            data = json.loads((Path(tmp) / "layout.json").read_text())
            self.assertEqual(data["object_name"], "SM_Crate")
            self.assertEqual(len(data["faces"]), len(layout["faces"]))
            png = (Path(tmp) / "Crate.png").read_bytes()
            self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
            w, h = struct.unpack(">II", png[16:24])
            self.assertEqual((w, h), (1024, 1024))
            # IDAT decompresses to height rows of 1 filter byte + width * 4 bytes.
            idat = png[png.index(b"IDAT") + 4:png.index(b"IEND") - 8]
            self.assertEqual(len(zlib.decompress(idat)), 1024 * (1 + 1024 * 4))

    def test_bad_name_rejected(self):
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(ValueError):
            make_layout({"name": "../evil", "generator": "crate", "size": [1, 1, 1]}, tmp)


if __name__ == "__main__":
    unittest.main()
