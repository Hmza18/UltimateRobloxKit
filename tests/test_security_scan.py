"""Backdoor scanner: flags the malicious fixtures, passes clean code, rule ids match the Lune twin."""
import importlib.util
import re
import unittest

from _util import ROOT

_spec = importlib.util.spec_from_file_location("scan_models", ROOT / "scripts/security/scan_models.py")
scan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scan)
FIX = ROOT / "tests/fixtures/security"


class ScannerTests(unittest.TestCase):
    def rules(self, path):
        findings, scanned = scan.scan_path(path)
        return {f["rule"] for f in findings}, findings, scanned

    def test_luau_backdoor_fixture(self):
        rules, _, scanned = self.rules(FIX / "bad-model/Vaccine.server.luau")
        self.assertEqual(scanned, 1)
        for r in ("require-asset-id", "require-tonumber", "loadstring", "getfenv-setfenv", "string-char-chain", "hidden-name"):
            self.assertIn(r, rules)

    def test_xml_model_scripts_extracted(self):
        rules, findings, scanned = self.rules(FIX / "infected.rbxmx")
        self.assertEqual(scanned, 1)
        self.assertIn("webhook", rules)
        self.assertIn("require-asset-id", rules)
        self.assertIn("hidden-name", rules, "script named Spread")
        self.assertTrue(any("FreeTree" in f["where"] or "Spread" in f["where"] for f in findings))

    def test_clean_code_has_no_high_findings(self):
        _, findings, _ = self.rules(FIX / "clean.luau")
        self.assertEqual([f for f in findings if f["severity"] == "high"], [])

    def test_exit_code_gates_high(self):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(scan.main([str(FIX / "clean.luau"), "--json"]), 0)
            self.assertEqual(scan.main([str(FIX / "infected.rbxmx"), "--json"]), 1)

    def test_kit_luau_is_clean(self):
        """The kit's own templates and library must not trip HIGH rules."""
        for folder in ("templates", "library/src"):
            findings, _ = scan.scan_path(ROOT / folder)
            high = [f for f in findings if f["severity"] == "high"]
            self.assertEqual(high, [], f"{folder}: {high[:3]}")

    def test_rule_ids_match_lune_twin(self):
        lune = (ROOT / "scripts/security/scan_models.luau").read_text()
        lune_ids = set(re.findall(r'id = "([a-z0-9-]+)"', lune)) | {"hidden-name"}
        self.assertEqual(lune_ids, {r[0] for r in scan.RULES})


if __name__ == "__main__":
    unittest.main()
