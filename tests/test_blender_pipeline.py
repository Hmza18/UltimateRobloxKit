"""End-to-end asset pipeline in real Blender. Skipped when Blender is not installed.
Set URK_SKIP_BLENDER=1 to skip explicitly (for example on slow CI runners)."""
import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from _util import ROOT
from lib.env import find_blender

BLENDER = None if os.environ.get("URK_SKIP_BLENDER") else find_blender()


@unittest.skipUnless(BLENDER, "Blender not found (set BLENDER=/path/to/blender)")
class BlenderPipelineTests(unittest.TestCase):
    def test_batch_build_export_reimport(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("asset_batch", ROOT / "scripts/export/asset_batch.py")
        ab = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ab)
        with tempfile.TemporaryDirectory() as tmp:
            batch = Path(tmp) / "spec.json"
            batch.write_text(json.dumps({"batch": "t", "assets": [
                {"name": "Crate", "generator": "crate", "size": [2, 2, 2]},
                {"name": "Bottle", "generator": "bottle", "size": [0.4, 0.4, 1.2], "layout": "guide"}]}))
            out = Path(tmp) / "out"
            with contextlib.redirect_stdout(io.StringIO()):
                code = ab.main([str(batch), "--out", str(out), "--no-renders", "--blender", BLENDER])
            self.assertEqual(code, 0)
            for name in ("Crate", "Bottle"):
                for ext in ("fbx", "obj", "mtl", "glb", "blend", "png"):
                    self.assertTrue((out / name / f"{name}.{ext}").exists(), f"{name}.{ext}")
                checks = {c["check"]: c["result"] for c in json.loads((out / name / "qa.json").read_text())}
                self.assertNotIn("FAIL", checks.values(), checks)
                self.assertEqual(checks["reimport_fbx"], "PASS")
                self.assertEqual(checks["roblox_studio_import"], "NEEDS MANUAL REVIEW")
            status = json.loads((out / "status.json").read_text())
            self.assertEqual({e["state"] for e in status["assets"].values()}, {"awaiting-approval"})

    def test_lod_and_collision_hull(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("asset_batch_lod", ROOT / "scripts/export/asset_batch.py")
        ab = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ab)
        with tempfile.TemporaryDirectory() as tmp:
            batch = Path(tmp) / "spec.json"
            batch.write_text(json.dumps({"batch": "t", "assets": [{"name": "Barrel", "generator": "barrel", "size": [1.6, 1.6, 2.2]}]}))
            out = Path(tmp) / "out"
            with contextlib.redirect_stdout(io.StringIO()):
                code = ab.main([str(batch), "--out", str(out), "--no-renders", "--lod", "--blender", BLENDER])
            self.assertEqual(code, 0)
            for suffix in ("_LOD1.fbx", "_LOD2.fbx", "_Collision.fbx", "_Collision.obj"):
                self.assertTrue((out / "Barrel" / f"Barrel{suffix}").exists(), suffix)
            lod = json.loads((out / "Barrel" / "lod.json").read_text())
            self.assertLess(lod["levels"][-1]["tris"], lod["levels"][0]["tris"])
            self.assertLessEqual(lod["hull"]["tris"], 256)
            checks = {c["check"]: c["result"] for c in json.loads((out / "Barrel" / "qa.json").read_text())}
            self.assertEqual(checks["collision_hull_encloses"], "PASS", checks)


if __name__ == "__main__":
    unittest.main()
