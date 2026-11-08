"""License<N> delivery format (license-folder-delivery skill) and the supermarket reference set."""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from _util import ROOT
from rbxasset.generators import build
from rbxasset.meshkit import validate

_spec = importlib.util.spec_from_file_location("package_batch", ROOT / "scripts/export/package_batch.py")
pb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pb)


def fake_batch(out: Path, names, state="approved"):
    for n in names:
        d = out / n
        (d / "views").mkdir(parents=True)
        for ext in ("fbx", "obj", "mtl", "png", "blend"):
            (d / f"{n}.{ext}").write_bytes(f"{n}.{ext}".encode())
        (d / "views" / "hero.png").write_bytes(b"hero")
    (out / "status.json").write_text(json.dumps({"assets": {n: {"state": state} for n in names}}))


def run(*args):
    with contextlib.redirect_stdout(io.StringIO()):
        return pb.main(list(args))


class LicenseDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_layout_names_and_zip(self):
        fake_batch(self.base / "out", ["Crate", "Barrel"])
        self.assertEqual(run(str(self.base / "out"), "--license", "3", "--dest", str(self.base / "handoff")), 0)
        folder = self.base / "handoff/License3/Crate"
        self.assertEqual(sorted(p.name for p in folder.iterdir()),
                         ["Crate.blend", "Crate.mtl", "Crate.png", "Crate_FBX.fbx", "Crate_Image.png", "Crate_OBJ.obj"])
        with zipfile.ZipFile(self.base / "handoff/License3.zip") as z:
            names = z.namelist()
        self.assertEqual(len(names), 12)
        self.assertTrue(all(n.startswith("License3/") for n in names))

    def test_unapproved_refused(self):
        fake_batch(self.base / "out", ["Crate"], state="awaiting-approval")
        self.assertEqual(run(str(self.base / "out"), "--license", "1", "--dest", str(self.base / "handoff")), 1)
        self.assertFalse((self.base / "handoff/License1").exists())

    def test_previous_delivery_archived_not_overwritten(self):
        fake_batch(self.base / "out", ["Crate"])
        dest = self.base / "handoff"
        run(str(self.base / "out"), "--license", "1", "--dest", str(dest))
        (dest / "License1/Crate/Crate.png").write_bytes(b"old delivery")
        run(str(self.base / "out"), "--license", "1", "--dest", str(dest))
        archived = list((dest / "_previous").rglob("Crate.png"))
        self.assertEqual([p.read_bytes() for p in archived], [b"old delivery"])


class ReferenceSetTests(unittest.TestCase):
    def test_every_approved_reference_rebuilds_closed(self):
        data = json.loads((ROOT / "examples/supermarket-reference/products.json").read_text())
        specs = [s for group in data["licenses"].values() for s in group]
        self.assertEqual(len(specs), 51)
        for s in specs:
            with self.subTest(asset=s["name"]):
                v = validate(build(s))
                self.assertTrue(v["closed"] and v["outward"], v)
                self.assertLessEqual(v["tris"], s["max_tris"])

    def test_reference_table_matches_specs(self):
        table = (ROOT / "skills/modeling/license-folder-delivery/references/approved-products.md").read_text()
        data = json.loads((ROOT / "examples/supermarket-reference/products.json").read_text())
        for group in data["licenses"].values():
            for s in group:
                self.assertIn(f"`{s['name']}`", table)


if __name__ == "__main__":
    unittest.main()
