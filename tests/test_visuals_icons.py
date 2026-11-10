"""Icon vault (tools/icons/vault.py): byte-for-byte import, integrity proof, registry, asset-id maps,
derivatives, preview and status. Uses the synthetic pack in tests/fixtures/visuals-icons/pack, so
no real (paid) pack is ever needed."""
import contextlib
import csv
import hashlib
import importlib.util
import io
import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from _util import ROOT

sys.path.insert(0, str(ROOT / "tools" / "icons"))
import vault  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "visuals-icons" / "pack"
HAS_PIL = importlib.util.find_spec("PIL") is not None
LUNE = shutil.which("lune")
GIT = shutil.which("git")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(base: Path):
    return {p.relative_to(base).as_posix(): sha(p) for p in sorted(base.rglob("*")) if p.is_file()}


def make_writable(base: Path):
    for p in base.rglob("*"):
        if p.is_file() and not p.is_symlink():
            os.chmod(p, 0o644)


class VaultCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="urk-vault-"))
        self.addCleanup(self.cleanup)
        self.vault = self.tmp / "vault"
        self.source = self.tmp / "Downloaded Pack"
        shutil.copytree(FIXTURE, self.source)

    def cleanup(self):
        make_writable(self.tmp)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_vault(self, *args, env=None):
        """(exit code, stdout, stderr) of vault.main with --vault pointing at the temp vault."""
        out, err = io.StringIO(), io.StringIO()
        old = dict(os.environ)
        os.environ.update(env or {})
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                try:
                    code = vault.main([*args, "--vault", str(self.vault)])
                except SystemExit as exit_:  # argparse errors
                    code = exit_.code
        finally:
            os.environ.clear()
            os.environ.update(old)
        return code, out.getvalue(), err.getvalue()

    def ok(self, *args, env=None):
        code, out, err = self.run_vault(*args, env=env)
        self.assertEqual(code, 0, out + err)
        return out

    def do_import(self, *extra):
        return self.ok("import", str(self.source), "--name", "demo", *extra)

    @property
    def pack(self) -> Path:
        return self.vault / "demo"

    def registry(self):
        return json.loads((self.pack / "registry.json").read_text())


class FixtureTests(unittest.TestCase):
    def test_fixture_is_generated_and_reproducible(self):
        spec = importlib.util.spec_from_file_location("make_fixture", FIXTURE.parent / "make_fixture.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        on_disk = {p.relative_to(FIXTURE).as_posix(): p.read_bytes() for p in FIXTURE.rglob("*") if p.is_file()}
        self.assertEqual(on_disk, module.FILES, "run tests/fixtures/visuals-icons/make_fixture.py")
        self.assertIn("LICENSE.txt", on_disk)
        self.assertGreaterEqual(sum(1 for name in on_disk if name.endswith(".png")), 6)


class ImportTests(VaultCase):
    def test_byte_for_byte_copy_keeps_structure_and_names(self):
        before = tree(self.source)
        out = self.do_import()
        self.assertEqual(tree(self.pack / "original"), before, "same relative paths, same SHA-256")
        self.assertEqual(tree(self.source), before, "the source is not touched")
        for rel in before:
            self.assertEqual((self.pack / "original" / rel).read_bytes(), (self.source / rel).read_bytes())
        self.assertTrue((self.pack / "original" / "Weapons" / "Sword (2).png").is_file(), "odd names are kept")
        self.assertTrue((self.pack / "original" / "UI" / "Buttons" / "Arrow-Left.png").is_file(), "nesting and case kept")
        self.assertIn("copied 11", out)
        self.assertIn("private", out)

    def test_odd_filenames_and_deep_nesting(self):
        odd = {
            "Deep/Er/Still Deeper/dot.name.with.dots.png": b"\x89PNG\r\n\x1a\n" + b"x" * 40,
            "Spaces  and (parens) [brackets]/50% off!.png": (FIXTURE / "star.png").read_bytes(),
            "UPPER.PNG": (FIXTURE / "star.png").read_bytes(),
            "no_extension": b"just bytes \x00\x01\x02",
            ".hidden/.dotfile.svg": b"<svg viewBox='0 0 8 8'/>",
            "caf\u00e9 \u2726/\u00fcn\u00efcode.png": (FIXTURE / "UI" / "close.png").read_bytes(),
            "empty.png": b"",
            "line\nbreak.png": (FIXTURE / "UI" / "close.png").read_bytes(),
        }
        written = {}
        for rel, data in odd.items():
            path = self.source / rel
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                written[rel] = data
            except (OSError, UnicodeError):
                continue  # a filesystem that cannot hold this name
        self.assertGreaterEqual(len(written), 5)
        before = tree(self.source)
        self.do_import()
        self.assertEqual(tree(self.pack / "original"), before)
        self.ok("verify", "demo", "--source", str(self.source))
        manifest = json.loads((self.pack / "manifest.json").read_text())
        self.assertEqual({f["path"] for f in manifest["files"]}, set(before))
        sums = vault.parse_sums((self.pack / "SHA256SUMS").read_text(encoding="utf-8"))
        self.assertEqual(sums, {"original/" + k: v for k, v in before.items()})

    def test_originals_are_read_only(self):
        self.do_import()
        for path in (self.pack / "original").rglob("*"):
            if path.is_file():
                self.assertEqual(stat.S_IMODE(path.stat().st_mode) & 0o222, 0, "%s is writable" % path)
        make_writable(self.source)
        for path in self.source.rglob("*"):
            if path.is_file():
                self.assertTrue(stat.S_IMODE(path.stat().st_mode) & 0o200, "the source keeps its own permissions")

    def test_manifest_contents(self):
        self.do_import()
        manifest = json.loads((self.pack / "manifest.json").read_text())
        self.assertEqual(manifest["pack"], "demo")
        self.assertEqual(manifest["source"], "Downloaded Pack", "basename only")
        self.assertNotIn(str(self.tmp), json.dumps(manifest), "no absolute private paths")
        self.assertRegex(manifest["importedAt"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(manifest["fileCount"], 11)
        self.assertEqual(manifest["iconCount"], 9)
        self.assertEqual(manifest["totalBytes"], sum(p.stat().st_size for p in self.source.rglob("*") if p.is_file()))
        self.assertEqual(manifest["formats"], {"png": 8, "svg": 1, "txt": 2})
        by_path = {f["path"]: f for f in manifest["files"]}
        self.assertEqual(set(by_path["star.png"]), {"path", "sha256", "bytes", "format", "width", "height"})
        self.assertEqual((by_path["star.png"]["width"], by_path["star.png"]["height"]), (64, 64))
        self.assertEqual((by_path["Weapons/Sword (2).png"]["width"], by_path["Weapons/Sword (2).png"]["height"]), (48, 16))
        self.assertEqual((by_path["UI/Buttons/close.svg"]["width"], by_path["UI/Buttons/close.svg"]["height"]), (24, 24))
        self.assertIsNone(by_path["notes.txt"]["width"])
        self.assertEqual(by_path["star.png"]["sha256"], sha(self.source / "star.png"))

    def test_sha256sums_is_sha256sum_compatible(self):
        self.do_import()
        lines = (self.pack / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(lines), 11)
        self.assertIn("%s *original/star.png" % sha(self.source / "star.png"), lines)
        tool = shutil.which("sha256sum")
        if tool:
            result = subprocess.run([tool, "-c", "--quiet", "SHA256SUMS"], cwd=self.pack, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_license_is_recorded_private_by_default(self):
        self.do_import()
        info = json.loads((self.pack / "manifest.json").read_text())["license"]
        self.assertEqual(info["file"], "license/LICENSE.txt", "auto-detected in the source root")
        self.assertEqual(info["sha256"], sha(self.source / "LICENSE.txt"))
        self.assertIs(info["redistributable"], False)
        self.assertEqual(info["original"], "original/LICENSE.txt")
        self.assertEqual((self.pack / "license" / "LICENSE.txt").read_bytes(), (self.source / "LICENSE.txt").read_bytes())

    def test_external_license_file_and_redistributable_flag(self):
        (self.source / "LICENSE.txt").unlink()
        outside = self.tmp / "Commercial Licence.pdf"
        outside.write_bytes(b"%PDF-1.4 terms")
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo", "--redistributable")
        self.assertEqual(code, 2)
        self.assertIn("licence", err)
        self.assertFalse(self.pack.exists(), "a refused import copies nothing")
        self.do_import("--license-file", str(outside), "--redistributable", "--license-notes", "Section 3 allows redistribution")
        info = json.loads((self.pack / "manifest.json").read_text())["license"]
        self.assertEqual(info["file"], "license/Commercial Licence.pdf")
        self.assertIs(info["redistributable"], True)
        self.assertEqual(info["notes"], "Section 3 allows redistribution")
        self.assertNotIn("original", info)
        self.assertFalse((self.pack / "original" / "Commercial Licence.pdf").exists(), "not copied into original/")

    def test_no_license_is_reported(self):
        (self.source / "LICENSE.txt").unlink()
        out = self.do_import()
        info = json.loads((self.pack / "manifest.json").read_text())["license"]
        self.assertIsNone(info["file"])
        self.assertIs(info["redistributable"], False)
        self.assertIn("none recorded", out)

    def test_reimport_is_idempotent(self):
        self.do_import()
        manifest_before = (self.pack / "manifest.json").read_bytes()
        mtimes = {p: p.stat().st_mtime_ns for p in (self.pack / "original").rglob("*") if p.is_file()}
        out = self.do_import()
        self.assertIn("copied 0, replaced 0, already identical 11", out)
        self.assertEqual((self.pack / "manifest.json").read_bytes(), manifest_before, "nothing changed, same manifest")
        self.assertEqual({p: p.stat().st_mtime_ns for p in mtimes}, mtimes, "files were not rewritten")
        self.ok("verify", "demo", "--source", str(self.source))

    def test_reimport_adds_new_files_and_keeps_old_ones(self):
        self.do_import()
        (self.source / "Weapons" / "axe.png").write_bytes((FIXTURE / "star.png").read_bytes())
        (self.source / "notes.txt").unlink()
        out = self.do_import()
        self.assertIn("copied 1", out)
        self.assertTrue((self.pack / "original" / "notes.txt").is_file(), "the vault never deletes originals")
        self.assertIn("not in this source", out)
        self.ok("verify", "demo")

    def test_refuses_to_overwrite_a_different_file(self):
        self.do_import()
        kept = sha(self.pack / "original" / "star.png")
        (self.source / "star.png").write_bytes((FIXTURE / "UI" / "close.png").read_bytes())
        (self.source / "brand-new.png").write_bytes((FIXTURE / "UI" / "close.png").read_bytes())
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo")
        self.assertEqual(code, 2)
        self.assertIn("star.png", err)
        self.assertIn("--force", err)
        self.assertEqual(sha(self.pack / "original" / "star.png"), kept, "the vault copy is untouched")
        self.assertFalse((self.pack / "original" / "brand-new.png").exists(), "a refused import copies nothing at all")
        out = self.do_import("--force")
        self.assertIn("replaced 1", out)
        self.assertEqual(sha(self.pack / "original" / "star.png"), sha(self.source / "star.png"))
        self.assertEqual(stat.S_IMODE((self.pack / "original" / "star.png").stat().st_mode) & 0o222, 0)
        self.ok("verify", "demo", "--source", str(self.source))

    def test_symlinks_escaping_the_source_are_refused(self):
        secret = self.tmp / "secret.txt"
        secret.write_text("outside the pack")
        try:
            os.symlink(secret, self.source / "leak.png")
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are not available here")
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo")
        self.assertEqual(code, 2)
        self.assertIn("leak.png", err)
        self.assertFalse(self.pack.exists())

    def test_symlinks_inside_the_source_are_skipped_not_followed(self):
        try:
            os.symlink(self.source / "star.png", self.source / "alias.png")
            os.symlink(self.source / "UI", self.source / "UI-link", target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks are not available here")
        out = self.do_import()
        self.assertIn("skipped 2", out)
        self.assertFalse((self.pack / "original" / "alias.png").exists())
        self.assertFalse((self.pack / "original" / "UI-link").exists())
        manifest = json.loads((self.pack / "manifest.json").read_text())
        self.assertEqual(manifest["skipped"], ["UI-link", "alias.png"])
        self.assertEqual(manifest["fileCount"], 11)

    def test_never_imports_from_or_into_itself(self):
        self.do_import()
        code, _, err = self.run_vault("import", str(self.pack / "original"), "--name", "again")
        self.assertEqual(code, 2)
        self.assertIn("inside the vault", err)
        # A vault that lives inside the source folder is not walked into.
        nested = self.source / "vault"
        out, err_ = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err_):
            code = vault.main(["import", str(self.source), "--name", "demo", "--vault", str(nested)])
        self.assertEqual(code, 0, err_.getvalue())
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err_):
            code = vault.main(["import", str(self.source), "--name", "demo", "--vault", str(nested)])
        self.assertEqual(code, 0, err_.getvalue())
        self.assertFalse((nested / "demo" / "original" / "vault").exists())
        self.assertEqual(json.loads((nested / "demo" / "manifest.json").read_text())["fileCount"], 11)

    def test_bad_arguments(self):
        for name in ("Demo", "1abc", "has space", "../escape", ""):
            code, _, err = self.run_vault("import", str(self.source), "--name", name)
            self.assertEqual(code, 2, name)
        code, _, err = self.run_vault("import", str(self.tmp / "missing"), "--name", "demo")
        self.assertEqual(code, 2)
        empty = self.tmp / "empty"
        empty.mkdir()
        code, _, err = self.run_vault("import", str(empty), "--name", "demo")
        self.assertEqual(code, 2)
        self.assertIn("no files", err)
        code, _, err = self.run_vault("verify", "nothere")
        self.assertEqual(code, 2)
        self.assertIn("no pack named", err)


@unittest.skipUnless(GIT, "git is not installed")
class GitSafetyTests(VaultCase):
    def setUp(self):
        super().setUp()
        self.repo = self.tmp / "repo"
        self.repo.mkdir()
        subprocess.run([GIT, "init", "-q", str(self.repo)], check=True, capture_output=True)
        self.vault = self.repo / "assets" / "icons" / "private"

    def test_refuses_a_vault_git_would_track(self):
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo")
        self.assertEqual(code, 2)
        self.assertIn("not git-ignored", err)
        self.assertFalse(self.pack.exists(), "nothing was copied")

    def test_imports_when_the_vault_is_ignored(self):
        (self.repo / ".gitignore").write_text("assets/icons/private/*\n!assets/icons/private/README.md\n")
        self.do_import()
        status = subprocess.run([GIT, "status", "--porcelain", "--untracked-files=all"], cwd=self.repo, capture_output=True, text=True)
        self.assertNotIn("private", status.stdout, "git sees none of the pack")

    def test_redistributable_with_a_licence_may_be_tracked(self):
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo", "--redistributable")
        self.assertEqual(code, 0, err)  # LICENSE.txt is auto-detected
        (self.source / "LICENSE.txt").unlink()
        make_writable(self.pack)
        shutil.rmtree(self.pack)
        code, _, err = self.run_vault("import", str(self.source), "--name", "demo", "--redistributable")
        self.assertEqual(code, 2, "no licence file, no redistribution")

    def test_the_kit_ignores_its_own_vault(self):
        probe = ROOT / "assets" / "icons" / "private" / "anypack" / "original" / "icon.png"
        ignored = subprocess.run([GIT, "check-ignore", "-q", "--no-index", str(probe)], cwd=ROOT)
        if ignored.returncode == 128:
            self.skipTest("the kit is not a git checkout here")
        self.assertEqual(ignored.returncode, 0, "assets/icons/private/* must be git-ignored")
        readme = subprocess.run([GIT, "check-ignore", "-q", "--no-index", str(ROOT / "assets/icons/private/README.md")], cwd=ROOT)
        self.assertEqual(readme.returncode, 1, "the README stays tracked")
        self.assertIsNone(vault.git_exposure(ROOT / "assets" / "icons" / "private" / "anypack"))


class VerifyTests(VaultCase):
    def setUp(self):
        super().setUp()
        self.do_import()

    def test_clean_pack_verifies(self):
        out = self.ok("verify", "demo")
        self.assertIn("OK: 11 files", out)
        report = json.loads(self.ok("verify", "demo", "--source", str(self.source), "--json"))
        self.assertTrue(report["ok"])
        self.assertEqual(report["modified"] + report["missing"] + report["extra"] + report["source-only"], [])

    def test_detects_a_modified_file(self):
        target = self.pack / "original" / "star.png"
        os.chmod(target, 0o644)
        data = bytearray(target.read_bytes())
        data[-1] ^= 0x01  # one flipped bit
        target.write_bytes(bytes(data))
        code, out, _ = self.run_vault("verify", "demo")
        self.assertEqual(code, 1)
        self.assertIn("MODIFIED: star.png", out)
        self.assertIn("FAILED VERIFICATION", self.ok("status"))

    def test_detects_a_missing_file(self):
        target = self.pack / "original" / "Currency" / "Coin Gold.png"
        target.unlink()
        code, out, _ = self.run_vault("verify", "demo")
        self.assertEqual(code, 1)
        self.assertIn("MISSING: Currency/Coin Gold.png", out)

    def test_detects_an_extra_file(self):
        (self.pack / "original" / "UI" / "sneaky.png").write_bytes(b"added later")
        code, out, _ = self.run_vault("verify", "demo")
        self.assertEqual(code, 1)
        self.assertIn("EXTRA: UI/sneaky.png", out)

    def test_detects_a_renamed_file(self):
        original = self.pack / "original" / "Weapons" / "sword.png"
        original.rename(original.with_name("blade.png"))
        code, out, _ = self.run_vault("verify", "demo", "--json")
        self.assertEqual(code, 1)
        report = json.loads(out)
        self.assertEqual(report["missing"], ["Weapons/sword.png"])
        self.assertEqual(report["extra"], ["Weapons/blade.png"])

    def test_detects_differences_from_the_source(self):
        (self.source / "star.png").write_bytes(b"changed in the download folder")
        (self.source / "new.png").write_bytes(b"new")
        (self.source / "notes.txt").unlink()
        code, out, _ = self.run_vault("verify", "demo", "--source", str(self.source))
        self.assertEqual(code, 1)
        self.assertIn("DIFFERS-FROM-SOURCE: star.png", out)
        self.assertIn("SOURCE-ONLY: new.png", out)
        self.assertIn("VAULT-ONLY: notes.txt", out)
        self.assertEqual(self.run_vault("verify", "demo")[0], 0, "the vault itself is still intact")

    def test_detects_a_tampered_sums_file(self):
        sums = self.pack / "SHA256SUMS"
        sums.write_text(sums.read_text().replace("star.png", "star2.png"))
        code, out, _ = self.run_vault("verify", "demo")
        self.assertEqual(code, 1)
        self.assertIn("SHA256SUMS", out)


class RegistryTests(VaultCase):
    def setUp(self):
        super().setUp()
        self.do_import()
        self.before = tree(self.pack / "original")

    def tearDown(self):
        self.assertEqual(tree(self.pack / "original"), self.before, "the originals were touched")

    def test_names_categories_and_collisions(self):
        self.ok("registry", "demo")
        registry = self.registry()
        by_path = {i["original"]: i for i in registry["icons"]}
        self.assertEqual(registry["count"], 9, "LICENSE.txt and notes.txt are not icons")
        names = [i["name"] for i in registry["icons"]]
        self.assertEqual(len(names), len(set(names)), "names are unique")
        for name in names:
            self.assertRegex(name, r"^[a-z0-9]+(-[a-z0-9]+)*$")
        self.assertEqual(by_path["Currency/gem_blue.png"]["name"], "gem-blue")
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["name"], "arrow-left")
        self.assertEqual(by_path["star.png"]["name"], "star")
        self.assertEqual(by_path["Weapons/sword.png"]["name"], "sword")
        self.assertEqual(by_path["Weapons/Sword (2).png"]["name"], "sword-2")
        # "Coin Gold" exists in two categories: both get the category prefix.
        self.assertEqual(by_path["Currency/Coin Gold.png"]["name"], "currency-coin-gold")
        self.assertEqual(by_path["Pets/coin gold.png"]["name"], "pets-coin-gold")
        # "close" exists twice in the same category: the folder path separates them.
        self.assertEqual(by_path["UI/close.png"]["name"], "ui-close")
        self.assertEqual(by_path["UI/Buttons/close.svg"]["name"], "ui-buttons-close")
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["category"], "ui")
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["subcategory"], "buttons")
        self.assertEqual(by_path["star.png"]["category"], "uncategorized")
        self.assertEqual(registry["categories"], ["currency", "pets", "ui", "uncategorized", "weapons"])
        entry = by_path["Currency/gem_blue.png"]
        self.assertEqual(entry["tags"], ["gem", "blue", "currency"])
        self.assertEqual(entry["sha256"], self.before["Currency/gem_blue.png"])
        self.assertEqual((entry["width"], entry["height"], entry["format"]), (32, 32, "png"))
        self.assertIsNone(entry["assetId"])
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["tags"], ["arrow", "left", "ui", "buttons"])
        self.assertNotIn(str(self.tmp), json.dumps(registry))

    def test_same_stem_different_format_in_one_folder(self):
        extra = self.source / "UI" / "close.svg"
        extra.write_bytes((FIXTURE / "UI" / "Buttons" / "close.svg").read_bytes())
        upper = self.source / "UI" / "Close.gif"
        upper.write_bytes(b"GIF89a" + struct.pack("<HH", 5, 7) + b"\x00" * 8)
        self.do_import()
        self.before = tree(self.pack / "original")
        self.ok("registry", "demo")
        names = {i["original"]: i["name"] for i in self.registry()["icons"]}
        self.assertEqual(names["UI/Buttons/close.svg"], "ui-buttons-close")
        self.assertEqual({names["UI/close.png"], names["UI/close.svg"], names["UI/Close.gif"]},
                         {"ui-close-png", "ui-close-svg", "ui-close-gif"})
        self.assertEqual(len(set(names.values())), len(names))

    def test_names_stay_stable_when_files_are_added(self):
        self.ok("registry", "demo")
        first = {i["original"]: i["name"] for i in self.registry()["icons"]}
        self.assertEqual(first["star.png"], "star")
        (self.source / "Rewards").mkdir()
        (self.source / "Rewards" / "Star.png").write_bytes((FIXTURE / "UI" / "close.png").read_bytes())
        self.do_import()
        self.before = tree(self.pack / "original")
        self.ok("registry", "demo")
        second = {i["original"]: i["name"] for i in self.registry()["icons"]}
        for path, name in first.items():
            self.assertEqual(second[path], name, "an existing icon was renamed")
        self.assertEqual(second["Rewards/Star.png"], "rewards-star")
        self.ok("registry", "demo", "--rename")
        renamed = {i["original"]: i["name"] for i in self.registry()["icons"]}
        self.assertEqual(renamed["star.png"], "uncategorized-star", "--rename recomputes from scratch")

    def test_category_level_and_synonyms(self):
        synonyms = self.tmp / "synonyms.json"
        synonyms.write_text(json.dumps({"coin": ["Money", "cash"], "gem-blue": ["sapphire"], "arrow": "direction"}))
        self.ok("registry", "demo", "--category-level", "last", "--synonyms", str(synonyms))
        by_path = {i["original"]: i for i in self.registry()["icons"]}
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["category"], "buttons")
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["subcategory"], "ui")
        self.assertIn("direction", by_path["UI/Buttons/Arrow-Left.png"]["tags"])
        self.assertIn("sapphire", by_path["Currency/gem_blue.png"]["tags"])
        self.assertEqual(by_path["Currency/Coin Gold.png"]["tags"][-2:], ["money", "cash"])
        self.ok("registry", "demo", "--category-level", "path", "--rename")
        by_path = {i["original"]: i for i in self.registry()["icons"]}
        self.assertEqual(by_path["UI/Buttons/Arrow-Left.png"]["category"], "ui/buttons")

    def test_export_map_template_lists_every_icon(self):
        out = self.ok("registry", "demo", "--export-map")
        self.assertIn("manual", out.lower())
        self.assertIn("Nothing was uploaded", out)
        with open(self.pack / "asset-map.csv", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(list(rows[0]), ["name", "category", "original", "width", "height", "assetId"])
        self.assertEqual(len(rows), 9)
        self.assertEqual({r["original"] for r in rows}, {i["original"] for i in self.registry()["icons"]})
        self.assertTrue(all(r["assetId"] == "" for r in rows))
        code, _, err = self.run_vault("registry", "demo", "--export-map", str(self.tmp / "outside.csv"))
        self.assertEqual(code, 2, "the template lists private file names, so it stays in the vault")

    def test_map_merge_from_csv_by_name_and_path(self):
        self.ok("registry", "demo", "--export-map")
        template = self.pack / "asset-map.csv"
        with open(template, newline="") as handle:
            rows = list(csv.DictReader(handle))
        ids = {"star": "111222333", "sword": "rbxassetid://444555666",
               "gem-blue": "https://create.roblox.com/store/asset/777888999/gem",
               "arrow-left": "https://www.roblox.com/library/123123123/Arrow"}
        for row in rows:
            row["assetId"] = ids.get(row["name"], "")
        with open(template, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        out = self.ok("registry", "demo", "--map", str(template))
        self.assertIn("4 applied", out)
        by_name = {i["name"]: i for i in self.registry()["icons"]}
        self.assertEqual(by_name["star"]["assetId"], 111222333)
        self.assertEqual(by_name["sword"]["assetId"], 444555666)
        self.assertEqual(by_name["gem-blue"]["assetId"], 777888999)
        self.assertEqual(by_name["arrow-left"]["assetId"], 123123123)
        self.assertIsNone(by_name["sword-2"]["assetId"])
        self.assertEqual(self.registry()["mapped"], 4)
        # Ids survive a rebuild without --map, and a second export keeps them in the template.
        self.ok("registry", "demo", "--export-map")
        self.assertEqual(self.registry()["mapped"], 4)
        with open(template, newline="") as handle:
            again = {r["name"]: r["assetId"] for r in csv.DictReader(handle)}
        self.assertEqual(again["star"], "111222333")
        self.assertEqual(again["sword-2"], "")

    def test_ids_typed_into_the_template_survive_a_second_export(self):
        self.ok("registry", "demo", "--export-map")
        template = self.pack / "asset-map.csv"
        template.write_text(template.read_text().replace("star,uncategorized,star.png,64,64,", "star,uncategorized,star.png,64,64,999000111"))
        self.ok("registry", "demo", "--export-map")
        self.assertIn("999000111", template.read_text())
        self.assertEqual({i["name"]: i["assetId"] for i in self.registry()["icons"]}["star"], 999000111)

    def test_map_merge_from_json_and_unknown_keys(self):
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"Weapons/Sword (2).png": 9001, "demo:star": "9002", "ghost": 5, "sword": None}))
        out = self.ok("registry", "demo", "--map", str(mapping))
        self.assertIn("2 applied, 1 unknown", out)
        self.assertIn("unknown: ghost", out)
        by_name = {i["name"]: i for i in self.registry()["icons"]}
        self.assertEqual(by_name["sword-2"]["assetId"], 9001)
        self.assertEqual(by_name["star"]["assetId"], 9002)
        listed = self.tmp / "list.json"
        listed.write_text(json.dumps([{"name": "gem-blue", "assetId": 77}, {"original": "UI/close.png", "id": "rbxassetid://88"}]))
        self.ok("registry", "demo", "--map", str(listed))
        by_name = {i["name"]: i for i in self.registry()["icons"]}
        self.assertEqual((by_name["gem-blue"]["assetId"], by_name["ui-close"]["assetId"], by_name["star"]["assetId"]), (77, 88, 9002))

    def test_bad_asset_ids_are_rejected_and_nothing_is_written(self):
        self.ok("registry", "demo")
        before = (self.pack / "registry.json").read_bytes()
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"star": "not-an-id", "sword": 5}))
        code, _, err = self.run_vault("registry", "demo", "--map", str(mapping))
        self.assertEqual(code, 2)
        self.assertIn("star", err)
        self.assertEqual((self.pack / "registry.json").read_bytes(), before)
        for value in (-4, 0, True, "12ab", "rbxassetid://"):
            with self.assertRaises(ValueError, msg=repr(value)):
                vault.parse_asset_id(value)
        self.assertIsNone(vault.parse_asset_id(""))
        self.assertIsNone(vault.parse_asset_id(None))
        self.assertEqual(vault.parse_asset_id(" 12345 "), 12345)

    def test_luau_module_has_data_only(self):
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"star": 4242}))
        out = self.ok("registry", "demo", "--map", str(mapping))
        module = self.pack / "DemoIcons.luau"
        self.assertIn("DemoIcons.luau", out)
        text = module.read_text()
        self.assertTrue(text.startswith("--!strict\n"))
        self.assertIn('pack = "demo"', text)
        self.assertIn('{ name = "star", category = "uncategorized", tags = { "star" }, width = 64, height = 64, assetId = 4242 },', text)
        self.assertIn('name = "gem-blue", category = "currency", tags = { "gem", "blue", "currency" }, width = 32, height = 32, assetId = 0', text)
        self.assertEqual(text.count("name = "), 9)
        for private in ("Coin Gold.png", "original", "sha256", str(self.tmp), "PNG"):
            self.assertNotIn(private, text, "no file names, hashes or bytes in the game module")
        custom = self.tmp / "game" / "src" / "Icons.luau"
        out = self.ok("registry", "demo", "--luau", str(custom))
        self.assertEqual(custom.read_text(), module.read_text())
        self.assertIn("outside the private vault", out)

    @unittest.skipUnless(LUNE, "lune is not on PATH")
    def test_generated_module_loads_in_lune_and_registers(self):
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"star": 4242, "sword": 77}))
        self.ok("registry", "demo", "--map", str(mapping))
        work = self.tmp / "lune"
        work.mkdir()
        shutil.copy(self.pack / "DemoIcons.luau", work / "DemoIcons.luau")
        shutil.copy(ROOT / "library/src/Visuals/Icons/IconVaultLogic.luau", work / "IconVaultLogic.luau")
        (work / "check.luau").write_text(
            'local Logic = require("./IconVaultLogic")\n'
            'local data = require("./DemoIcons")\n'
            'assert(Logic.register("demo", data) == 9, "count")\n'
            'assert(data.count == 9)\n'
            'assert(Logic.assetId("star") == "rbxassetid://4242", "star id")\n'
            'assert(Logic.assetId("demo:sword") == "rbxassetid://77", "sword id")\n'
            'assert(Logic.assetId("gem-blue") == nil, "unmapped")\n'
            'assert(#Logic.missingAssetIds("demo") == 7, "missing")\n'
            'assert(Logic.search("coin")[1] == "demo:currency-coin-gold", "search")\n'
            'assert(#Logic.categories("demo") == 5, "categories")\n'
            'assert(Logic.get("Gem Blue").width == 32, "size")\n'
            'print("LUNE-OK " .. #Logic.list({ pack = "demo" }))\n')
        result = subprocess.run([LUNE, "run", "check.luau"], cwd=work, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("LUNE-OK 9", result.stdout)


class QueryTests(VaultCase):
    def setUp(self):
        super().setUp()
        self.do_import()
        self.ok("registry", "demo")

    def test_search_is_ranked(self):
        hits = [i["name"] for i in json.loads(self.ok("search", "demo", "sword", "--json"))]
        self.assertEqual(hits, ["sword", "sword-2"])
        hits = [i["name"] for i in json.loads(self.ok("search", "demo", "coin", "--json"))]
        self.assertEqual(hits, ["currency-coin-gold", "pets-coin-gold"])
        hits = [i["name"] for i in json.loads(self.ok("search", "demo", "currency", "--json"))]
        self.assertEqual(hits, ["currency-coin-gold", "gem-blue"], "name prefix, then tag")
        hits = [i["name"] for i in json.loads(self.ok("search", "demo", "Arrow Left", "--json"))]
        self.assertEqual(hits, ["arrow-left"])
        self.assertEqual(len(json.loads(self.ok("search", "demo", "c", "--limit", "1", "--json"))), 1)
        code, out, _ = self.run_vault("search", "demo", "zzzz")
        self.assertEqual(code, 1)
        self.assertIn("0 icon(s)", out)

    def test_list_and_category_filter(self):
        self.assertIn("9 icon(s)", self.ok("list", "demo"))
        names = [i["name"] for i in json.loads(self.ok("list", "demo", "--category", "Weapons", "--json"))]
        self.assertEqual(names, ["sword", "sword-2"])
        self.assertEqual(len(json.loads(self.ok("list", "demo", "--unmapped", "--json"))), 9)
        self.assertEqual(json.loads(self.ok("list", "demo", "--category", "nope", "--json")), [])

    def test_autocomplete(self):
        self.assertEqual(self.ok("autocomplete", "demo", "s").split(), ["star", "sword", "sword-2"])
        self.assertEqual(json.loads(self.ok("autocomplete", "demo", "demo:sw", "--json")), ["sword", "sword-2"])
        self.assertEqual(len(json.loads(self.ok("autocomplete", "demo", "--json"))), 9)
        self.assertEqual(json.loads(self.ok("autocomplete", "demo", "", "--limit", "2", "--json")), ["arrow-left", "currency-coin-gold"])
        self.assertEqual(json.loads(self.ok("autocomplete", "demo", "zz", "--json")), [])

    def test_stats(self):
        stats = json.loads(self.ok("stats", "demo", "--json"))
        self.assertEqual((stats["icons"], stats["files"], stats["mapped"], stats["unmapped"]), (9, 11, 0, 9))
        self.assertEqual(stats["categories"], {"currency": 2, "pets": 1, "ui": 3, "uncategorized": 1, "weapons": 2})
        self.assertEqual(stats["sizes"]["16x16"], 2)
        self.assertIs(stats["redistributable"], False)
        self.assertIn("asset ids: 0 mapped, 9 missing", self.ok("stats", "demo"))

    def test_queries_work_before_the_registry_is_written(self):
        (self.pack / "registry.json").unlink()
        self.assertIn("9 icon(s)", self.ok("list", "demo"))
        self.assertFalse((self.pack / "registry.json").exists(), "read-only commands write nothing")

    def test_preview_is_self_contained_and_stays_in_the_vault(self):
        before = tree(self.pack / "original")
        self.ok("preview", "demo")
        page = (self.pack / "preview.html").read_text()
        self.assertIn("original/Weapons/Sword%20%282%29.png", page, "relative, URL-quoted link to the original")
        self.assertIn('id="q"', page)
        self.assertIn('id="cat"', page)
        self.assertIn("navigator.clipboard", page)
        self.assertNotIn("http://", page.replace("http://www.w3.org", ""))
        self.assertNotIn("https://", page)
        self.assertNotIn(str(self.tmp), page)
        self.assertNotIn("base64", page, "the images are referenced, not embedded")
        self.assertEqual(tree(self.pack / "original"), before)
        nested = self.pack / "gallery" / "index.html"
        self.ok("preview", "demo", "--out", str(nested))
        self.assertIn("../original/star.png", nested.read_text())
        code, _, err = self.run_vault("preview", "demo", "--out", str(self.tmp / "public.html"))
        self.assertEqual(code, 2)
        self.assertFalse((self.tmp / "public.html").exists())


class StatusTests(VaultCase):
    def test_no_pack_prints_pending_and_the_command(self):
        code, out, _ = self.run_vault("status")
        self.assertEqual(code, 0)
        self.assertIn("PENDING", out)
        self.assertIn("vault.py import <source_dir> --name <pack>", out)
        report = json.loads(self.ok("status", "--json"))
        self.assertTrue(report["pending"])
        self.assertEqual(report["packs"], [])
        self.assertFalse(self.vault.exists(), "status creates nothing")

    def test_the_kit_vault_reports_pending_until_the_pack_is_supplied(self):
        packs = vault.find_packs(vault.DEFAULT_VAULT)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = vault.main(["status"])
        self.assertEqual(code, 0)
        if packs:
            self.assertIn(packs[0].name, out.getvalue())
        else:
            self.assertIn("Icon pack import: PENDING", out.getvalue())

    def test_status_lists_packs_with_verification_and_id_counts(self):
        self.do_import()
        out = self.ok("status")
        self.assertIn("demo: 9 icons, 11 files, verified", out)
        self.assertIn("registry not built yet", out)
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"star": 1234, "sword": 5678}))
        self.ok("registry", "demo", "--map", str(mapping))
        out = self.ok("status")
        self.assertIn("asset ids: 2 of 9 mapped", out)
        self.assertNotIn("PENDING", out)
        report = json.loads(self.ok("status", "--json"))
        self.assertFalse(report["pending"])
        self.assertEqual((report["packs"][0]["mapped"], report["packs"][0]["verified"]), (2, True))


class DeriveTests(VaultCase):
    def setUp(self):
        super().setUp()
        self.do_import()
        self.ok("registry", "demo")
        self.before = tree(self.pack / "original")

    def tearDown(self):
        self.assertEqual(tree(self.pack / "original"), self.before, "derive must never write into original/")
        self.ok("verify", "demo")

    def derived_manifest(self, size):
        return json.loads((self.pack / "derived" / "manifest.json").read_text())["sizes"][str(size)]

    def test_without_pillow_only_straight_copies_and_honest_report(self):
        out = self.ok("derive", "demo", "--size", "32", env={"URK_VAULT_NO_PILLOW": "1"})
        self.assertIn("Pillow is not installed", out)
        self.assertIn("0 resized", out)
        info = self.derived_manifest(32)
        self.assertIs(info["pillow"], False)
        self.assertEqual(info["counts"], {"copy": 5, "resize": 0, "skipped": 4})
        by_name = {e["name"]: e for e in info["entries"]}
        copy = by_name["gem-blue"]
        self.assertEqual(copy["action"], "copy")
        self.assertEqual(copy["output"], "derived/32/Currency/gem_blue.png")
        self.assertEqual(copy["sourceSha256"], self.before["Currency/gem_blue.png"])
        self.assertEqual(copy["sha256"], copy["sourceSha256"], "a straight copy is byte-identical")
        self.assertEqual((self.pack / copy["output"]).read_bytes(), (self.source / "Currency" / "gem_blue.png").read_bytes())
        too_big = by_name["star"]
        self.assertEqual(too_big["action"], "skipped")
        self.assertIsNone(too_big["output"])
        self.assertIn("Pillow", too_big["reason"])
        self.assertFalse((self.pack / "derived" / "32" / "star.png").exists(), "no file is claimed that was not made")
        self.assertIn("SVG", by_name["ui-buttons-close"]["reason"])
        for path in (self.pack / "derived").rglob("*"):
            self.assertNotIn("original", path.relative_to(self.pack).parts)

    def test_sheets_without_pillow_fail_loudly(self):
        code, out, _ = self.run_vault("derive", "demo", "--size", "32", "--sheets", env={"URK_VAULT_NO_PILLOW": "1"})
        self.assertEqual(code, 1)
        self.assertIn("NOT built", out)
        self.assertFalse((self.pack / "derived" / "sheets").exists())

    def test_size_limits(self):
        for size in ("4", "2048"):
            code, _, err = self.run_vault("derive", "demo", "--size", size)
            self.assertEqual(code, 2)
        self.assertFalse((self.pack / "derived").exists())

    @unittest.skipUnless(HAS_PIL, "Pillow is not installed")
    def test_with_pillow_resizes_into_derived_only(self):
        out = self.ok("derive", "demo", "--size", "32")
        self.assertIn("3 resized with Pillow", out)
        info = self.derived_manifest(32)
        self.assertIs(info["pillow"], True)
        self.assertEqual(info["counts"], {"copy": 5, "resize": 3, "skipped": 1})
        by_name = {e["name"]: e for e in info["entries"]}
        self.assertEqual((by_name["star"]["action"], by_name["star"]["width"], by_name["star"]["height"]), ("resize", 32, 32))
        self.assertEqual((by_name["sword-2"]["width"], by_name["sword-2"]["height"]), (32, 11), "aspect ratio kept")
        self.assertEqual(vault.probe(self.pack / by_name["star"]["output"]), ("png", 32, 32))
        self.assertEqual(by_name["star"]["sourceSha256"], self.before["star.png"])
        self.assertEqual(by_name["ui-buttons-close"]["action"], "skipped", "SVG is never rasterised")

    @unittest.skipUnless(HAS_PIL, "Pillow is not installed")
    def test_sheets_with_rect_map_reach_the_registry_and_luau(self):
        out = self.ok("derive", "demo", "--size", "32", "--sheets")
        self.assertIn("1 sheet(s) with 8 icons", out)
        sheets = json.loads((self.pack / "derived" / "sheets" / "sheets.json").read_text())
        self.assertEqual(vault.probe(self.pack / "derived" / "sheets" / "sheet-1.png"), ("png", 1024, 1024))
        self.assertEqual(len(sheets["rects"]), 8)
        rect = sheets["rects"]["star.png"]
        self.assertEqual((rect["w"], rect["h"], rect["sheet"]), (32, 32, 1))
        boxes = [(r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]) for r in sheets["rects"].values()]
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                self.assertTrue(a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], "rects overlap")
        mapping = self.tmp / "ids.json"
        mapping.write_text(json.dumps({"@sheet-1": 31337}))
        self.ok("registry", "demo", "--map", str(mapping), "--export-map")
        registry = self.registry()
        self.assertEqual(registry["sheets"], [{"file": "derived/sheets/sheet-1.png", "width": 1024, "height": 1024, "assetId": 31337}])
        star = {i["name"]: i for i in registry["icons"]}["star"]
        self.assertEqual(star["sheet"], {"index": 1, "x": rect["x"], "y": rect["y"], "w": 32, "h": 32})
        text = (self.pack / "DemoIcons.luau").read_text()
        self.assertIn("{ width = 1024, height = 1024, assetId = 31337 },", text)
        self.assertIn("sheet = 1, x = %d, y = %d, w = 32, h = 32 }," % (rect["x"], rect["y"]), text)
        self.assertIn('name = "ui-buttons-close", category = "ui", tags = { "ui", "buttons", "close" }, width = 24, height = 24, '
                      "assetId = 0, sheet = 0, x = 0, y = 0, w = 0, h = 0 },", text)
        self.assertIn("@sheet-1,(sprite sheet),derived/sheets/sheet-1.png,1024,1024,31337", (self.pack / "asset-map.csv").read_text())


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="urk-probe-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def probe(self, name, data):
        path = self.tmp / name
        path.write_bytes(data)
        return vault.probe(path)

    def test_png(self):
        self.assertEqual(vault.probe(FIXTURE / "Weapons" / "Sword (2).png"), ("png", 48, 16))
        self.assertEqual(self.probe("cut.png", b"\x89PNG\r\n\x1a\n\x00\x00"), ("png", None, None))

    def test_jpeg(self):
        app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00" + b"\x00" * 9
        sof = b"\xff\xc2" + struct.pack(">HBHHB", 11, 8, 37, 61, 3) + b"\x00" * 6
        self.assertEqual(self.probe("a.jpg", b"\xff\xd8" + app0 + sof + b"\xff\xd9"), ("jpeg", 61, 37))
        self.assertEqual(self.probe("broken.jpg", b"\xff\xd8\xff\xe0\x00\x02"), ("jpeg", None, None))

    def test_webp_variants(self):
        def riff(chunk):
            return b"RIFF" + struct.pack("<I", len(chunk) + 4) + b"WEBP" + chunk
        vp8x = b"VP8X" + struct.pack("<I", 10) + b"\x10\x00\x00\x00" + (299).to_bytes(3, "little") + (149).to_bytes(3, "little")
        self.assertEqual(self.probe("x.webp", riff(vp8x)), ("webp", 300, 150))
        bits = (99) | (49 << 14)
        vp8l = b"VP8L" + struct.pack("<I", 5) + b"\x2f" + struct.pack("<I", bits)
        self.assertEqual(self.probe("l.webp", riff(vp8l)), ("webp", 100, 50))
        vp8 = b"VP8 " + struct.pack("<I", 10) + b"\x00\x00\x00\x9d\x01\x2a" + struct.pack("<HH", 64, 32)
        self.assertEqual(self.probe("lossy.webp", riff(vp8)), ("webp", 64, 32))
        self.assertEqual(self.probe("odd.webp", riff(b"ABCD" + b"\x00" * 20)), ("webp", None, None))

    def test_gif_and_svg(self):
        self.assertEqual(self.probe("a.gif", b"GIF89a" + struct.pack("<HH", 12, 34) + b"\x00" * 4), ("gif", 12, 34))
        self.assertEqual(self.probe("wh.svg", b'<svg xmlns="x" width="48px" height="32"><rect/></svg>'), ("svg", 48, 32))
        self.assertEqual(self.probe("vb.svg", b"<?xml version='1.0'?>\n<svg viewBox='0 0 12.5 20'></svg>"), ("svg", 12.5, 20))
        self.assertEqual(self.probe("pct.svg", b'<svg width="100%" height="100%" viewBox="0,0,256,128"/>'), ("svg", 256, 128))
        self.assertEqual(self.probe("none.svg", b"<svg></svg>"), ("svg", None, None))

    def test_unknown_files(self):
        self.assertEqual(self.probe("readme.txt", b"hello"), ("txt", None, None))
        self.assertEqual(self.probe("noext", b"hello"), ("other", None, None))
        self.assertEqual(self.probe("fake.png", b"not really a png"), ("png", None, None))

    def test_names(self):
        self.assertEqual(vault.kebab("Sword_Icon 02"), "sword-icon-02")
        self.assertEqual(vault.kebab("gemBlue"), "gem-blue")
        self.assertEqual(vault.kebab("Caf\u00e9 Cr\u00e8me"), "cafe-creme")
        self.assertEqual(vault.kebab("\u2726\u2726"), "icon")
        self.assertEqual(vault.pascal("my-pack-2"), "MyPack2")
        self.assertEqual(vault.sums_line("ab", "a b.png"), "ab *a b.png\n")
        self.assertEqual(vault.parse_sums(vault.sums_line("ab", "we\\ird\nname.png")), {"we\\ird\nname.png": "ab"})


class RepoTests(unittest.TestCase):
    def test_private_readme_and_docs_say_pending(self):
        readme = (ROOT / "assets/icons/private/README.md").read_text()
        self.assertIn("git-ignored", readme)
        doc = (ROOT / "docs/workflows/icon-pack-import.md").read_text()
        self.assertIn("pending", doc.lower())
        for step in ("vault.py import", "vault.py verify", "vault.py registry", "--export-map", "--map", "Visuals.Icons"):
            self.assertIn(step, doc)

    def test_vault_is_stdlib_only(self):
        text = (ROOT / "tools/icons/vault.py").read_text()
        imports = {line.split()[1].split(".")[0] for line in text.splitlines() if line.startswith(("import ", "from "))}
        if hasattr(sys, "stdlib_module_names"):  # Python 3.10+
            self.assertEqual(imports - set(sys.stdlib_module_names), set())
        self.assertIn("except ImportError", text, "Pillow is optional and guarded")


if __name__ == "__main__":
    unittest.main()
