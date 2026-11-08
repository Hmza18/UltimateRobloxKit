"""Tests for the 0.4 tools: economy simulator, asset registry, visual UI scoring, game generator,
Wally overlay, audit, project memory, release gate and the routing evaluation. Standard library only;
tests that need Pillow skip without it."""
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from _util import ROOT


def load(rel: str, name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # dataclasses look their module up while the class is being built
    spec.loader.exec_module(mod)
    return mod


def quiet(fn, *args, **kwargs):
    with contextlib.redirect_stdout(io.StringIO()) as out:
        code = fn(*args, **kwargs)
    return code, out.getvalue()


try:
    import PIL  # noqa: F401
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


class EconomyTests(unittest.TestCase):
    def setUp(self):
        self.sim = load("tools/economy/economy_sim.py", "economy_sim")

    def test_curve_cost_matches_luau_formulas(self):
        # Same expectations as library/tests/sys_rebirth_upgrades.spec.luau ("curves cost what they say").
        self.assertEqual(self.sim.curve_cost({"kind": "linear", "base": 10, "step": 5}, 3), 20)
        self.assertEqual(self.sim.curve_cost({"kind": "exponential", "base": 100, "growth": 1.5}, 3), 225)
        self.assertEqual(self.sim.curve_cost({"kind": "table", "values": [1, 2]}, 9), 2)

    def test_example_is_balanced_and_broken_example_warns(self):
        good = json.loads((ROOT / "tools/economy/examples/pet-sim.json").read_text())
        rep = self.sim.report(good, good["session"]["hours"], 10, 7)
        self.assertEqual(rep["warnings"], [], rep["warnings"])
        broken = json.loads((ROOT / "tools/economy/examples/broken-wall.json").read_text())
        rep = self.sim.report(broken, broken["session"]["hours"], 5, 7)
        self.assertTrue(any(w.startswith("dead content") for w in rep["warnings"]), rep["warnings"])

    def test_deterministic_for_a_seed(self):
        cfg = json.loads((ROOT / "tools/economy/examples/pet-sim.json").read_text())
        self.assertEqual(self.sim.report(cfg, 0.3, 3, 11), self.sim.report(cfg, 0.3, 3, 11))

    def test_validation_errors(self):
        self.assertTrue(self.sim.validate({"income": {"base": 0}}))


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.reg = load("tools/assets/registry.py", "registry")

    def test_tags_split_names(self):
        tags = self.reg.tags_for(ROOT / "assets/icons/urk/png/coin-bronze.png", ROOT / "assets")
        self.assertIn("coin", tags)
        self.assertIn("bronze", tags)

    def test_scan_search_and_exact_dupes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "art"
            (root / "props").mkdir(parents=True)
            (root / "LICENSE.md").write_text("CC0 1.0")
            (root / "props" / "goldCoin.obj").write_text("v 0 0 0\n")
            (root / "props" / "gold_coin_copy.obj").write_text("v 0 0 0\n")
            (root / "props" / "tree.obj").write_text("v 1 0 0\n")
            reg = self.reg.scan([root])
            self.assertEqual(reg["count"], 3)
            self.assertTrue(all(e["licence"].startswith("CC0") for e in reg["assets"]))
            hits = self.reg.search(reg, "gold coin", None, 5)
            self.assertEqual({h["path"].split("/")[-1] for h in hits}, {"goldCoin.obj", "gold_coin_copy.obj"})
            self.assertEqual(len(self.reg.dupes(reg, 2)["exact"]), 1)

    @unittest.skipUnless(HAS_PIL, "Pillow not installed")
    def test_colour_variants_are_not_near_duplicates(self):
        from PIL import Image, ImageDraw
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for name, colour in (("red", (220, 40, 40, 255)), ("blue", (40, 80, 220, 255)), ("red2", (221, 41, 40, 255))):
                im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
                ImageDraw.Draw(im).ellipse((8, 8, 56, 56), fill=colour)
                p = Path(tmp) / f"{name}.png"
                im.save(p)
                paths.append(p)
            sig = {p.stem: self.reg.dhash(p) for p in paths}
            self.assertLessEqual(self.reg.hamming(sig["red"], sig["red2"]), 2)
            self.assertEqual(self.reg.hamming(sig["red"], sig["blue"]), 99)


@unittest.skipUnless(HAS_PIL, "Pillow not installed")
class VisualTests(unittest.TestCase):
    def setUp(self):
        self.vis = load("tools/ui/visual.py", "visual")

    def test_self_compare_is_perfect_and_unrelated_scores_lower(self):
        ref = ROOT / "docs/images/ui/PetSimShop.png"
        self.assertEqual(self.vis.compare(ref, ref)["total"], 100.0)
        other = self.vis.compare(ref, ROOT / "assets/icons/kenney-game/preview.png")
        self.assertLess(other["total"], 70)
        self.assertTrue(other["notes"])

    def test_extract_finds_the_cartoon_shop_palettes(self):
        hints = self.vis.extract(ROOT / "docs/images/ui/PetSimShop.png")
        self.assertEqual(hints["suggestion"]["style"], "cartoon")
        for palette in ("red", "teal", "purple"):
            self.assertIn(palette, hints["suggestion"]["palettes"])


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.gen = load("scripts/automation/generate_game.py", "generate_game")

    def test_parse_reads_genre_theme_and_counts(self):
        spec = self.gen.parse("Supermarket simulator with 50 products and 4 worlds")
        self.assertEqual((spec["genre"], spec["theme"]), ("simulator", "supermarket"))
        self.assertEqual((spec["counts"]["products"], spec["counts"]["worlds"]), (50, 4))
        self.assertEqual(self.gen.parse("obby with 30 stages")["genre"], "obby")
        self.assertEqual(self.gen.parse("pet game with 24 pets")["counts"]["pets"], 24)

    def test_plan_has_unique_products_with_margins_and_valid_generators(self):
        sys.path.insert(0, str(ROOT / "tools"))
        from rbxasset.generators import REGISTRY
        plan = self.gen.plan(self.gen.parse("supermarket simulator with 50 products"), "Mart")
        ids = [p["id"] for p in plan["products"]]
        self.assertEqual(len(ids), 50)
        self.assertEqual(len(set(ids)), 50)
        for p in plan["products"]:
            self.assertGreater(p["sellPrice"], p["buyPrice"])
            self.assertIn(p["generator"], REGISTRY)
        self.assertTrue(all(gp["name"] for gp in plan["passes"]))

    def test_generated_luau_mentions_every_product_and_pet(self):
        plan = self.gen.plan(self.gen.parse("pet simulator with 3 worlds and 12 pets"), "PetLand")
        text = self.gen.game_config_luau(plan)
        for pet in plan["pets"]:
            self.assertIn(f'["{pet["name"]}"]', text)
        self.assertIn("GameConfig.Progression", text)
        self.assertIn("PetsServer", self.gen.service_luau(plan))
        self.assertNotIn("PetsServer", self.gen.service_luau(self.gen.plan(self.gen.parse("obby with 5 stages"), "O")))

    def test_dry_run_prints_plan(self):
        code, out = quiet(self.gen.main, ["tycoon with 4 upgrades", "--name", "Burger", "--out", "/nonexistent", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["genre"], "tycoon")


class PackagesTests(unittest.TestCase):
    def setUp(self):
        self.pk = load("scripts/automation/packages.py", "packages")

    def test_manifest_puts_profilestore_in_server_dependencies(self):
        text = self.pk.update_manifest("", list(self.pk.PACKAGES), "My Game")
        self.assertIn('name = "you/my-game"', text)
        server = text.split("[server-dependencies]")[1]
        self.assertIn('ProfileStore = "lm-loleris/profilestore@1.0.3"', server)
        shared = text.split("[dependencies]")[1].split("[server-dependencies]")[0]
        self.assertIn('Fusion = "elttob/fusion@0.3.0"', shared)
        self.assertEqual(text, self.pk.update_manifest(text, list(self.pk.PACKAGES), "My Game"), "idempotent")

    def test_project_mapping_keeps_existing_entries(self):
        project = {"tree": {"$className": "DataModel", "ReplicatedStorage": {"$className": "ReplicatedStorage", "Shared": {"$path": "src/shared"}}}}
        out = self.pk.update_project(project, True, True)
        self.assertEqual(out["tree"]["ReplicatedStorage"]["Shared"], {"$path": "src/shared"})
        self.assertEqual(out["tree"]["ReplicatedStorage"]["Packages"], {"$path": "Packages"})
        self.assertEqual(out["tree"]["ServerScriptService"]["ServerPackages"], {"$path": "ServerPackages"})

    def test_writes_files_without_installing(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "default.project.json").write_text(json.dumps({"name": "x", "tree": {"$className": "DataModel"}}))
            code, _ = quiet(self.pk.main, ["--project", tmp, "--only", "promise", "--no-install"])
            self.assertEqual(code, 0)
            self.assertIn("evaera/promise@4.0.0", (Path(tmp) / "wally.toml").read_text())
            self.assertIn("Packages/", (Path(tmp) / ".gitignore").read_text())


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.audit = load("scripts/validate/audit.py", "audit")

    def test_bad_fixture_is_caught(self):
        base = ROOT / "tests/fixtures/audit/bad-game"
        rules = {f["rule"] for f in self.audit.audit_code(base / "src", base)}
        self.assertTrue({"client-trusts-amount", "remote-unvalidated", "loadstring", "require-asset-id"} <= rules, rules)

    def test_kit_library_has_no_high_findings(self):
        findings = self.audit.audit_code(ROOT / "library/src", ROOT)
        high = [f for f in findings if f["severity"] == "HIGH"]
        self.assertEqual(high, [], high[:3])

    def test_strict_exit_code(self):
        code, _ = quiet(self.audit.main, ["--project", str(ROOT / "tests/fixtures/audit/bad-game"), "--strict"])
        self.assertEqual(code, 1)


class MemoryAndReleaseTests(unittest.TestCase):
    def test_memory_round_trip_and_secret_refusal(self):
        mem = load("scripts/automation/memory.py", "memory")
        with tempfile.TemporaryDirectory() as tmp:
            quiet(mem.main, ["add", "decision", "Coins never drop on death", "--project", tmp])
            quiet(mem.main, ["add", "convention", "Remotes live in ReplicatedStorage.Remotes", "--project", tmp])
            items = mem.entries(Path(tmp))
            self.assertEqual([e["kind"] for e in items], ["decision", "convention"])
            _, out = quiet(mem.main, ["context", "--project", tmp])
            self.assertIn("Coins never drop", out)
            with self.assertRaises(SystemExit):
                quiet(mem.main, ["add", "note", "password: hunter2", "--project", tmp])
            quiet(mem.main, ["forget", "1", "--project", tmp])
            self.assertEqual(len(mem.entries(Path(tmp))), 1)

    def test_release_notes_contain_rollback(self):
        rel = load("scripts/validate/release.py", "release")
        with tempfile.TemporaryDirectory() as tmp:
            code, _ = quiet(rel.notes, Path(tmp), "1.0.0")
            self.assertEqual(code, 0)
            text = (Path(tmp) / ".urk/releases/1.0.0.md").read_text()
            self.assertIn("Roll back", text)
            self.assertIn("Version History", text)


class RoutingEvalTests(unittest.TestCase):
    def test_tuned_cases_route_correctly_and_heldout_is_reported(self):
        sk = load("scripts/automation/skills.py", "skills_cli")
        data = json.loads((ROOT / "catalog/route_eval.json").read_text())
        tuned = sk.evaluate(data["cases"])
        self.assertGreaterEqual(tuned["accuracy"], 0.9, [r for r in tuned["rows"] if not r["ok"]])
        self.assertGreaterEqual(len(data["heldout"]) + len(data["heldout2"]), 20)
        for case in data["cases"] + data["heldout"] + data["heldout2"]:
            for name in case["expect"]:
                self.assertTrue((ROOT / "skills").glob(f"*/{name}/SKILL.md"), name)


class CliTests(unittest.TestCase):
    def run_urk(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "urk.py"), *args], capture_output=True, text=True, cwd=ROOT)

    def test_new_commands_have_help(self):
        for cmd in ("generate", "packages", "audit", "build", "skills", "memory", "release"):
            r = self.run_urk(cmd, "--help")
            self.assertEqual(r.returncode, 0, cmd + r.stderr)
        self.assertEqual(self.run_urk("economy", "sim", "--help").returncode, 0)
        self.assertEqual(self.run_urk("ui", "extract", "--help").returncode, 0)


if __name__ == "__main__":
    unittest.main()
