"""The deterministic router picks the expected workflow and skills for example tasks."""
import json
import unittest

from _util import ROOT
from automation_route import route


class RoutingTests(unittest.TestCase):
    def test_cases(self):
        cases = json.loads((ROOT / "tests/routing_cases.json").read_text())["cases"]
        for c in cases:
            with self.subTest(task=c["task"]):
                r = route(c["task"])
                if "workflow" in c:
                    self.assertIn(c["workflow"], r["workflows"])
                missing = [s for s in c["expect"] if s not in r["load_order"]]
                self.assertEqual(missing, [], f"routed to {r['load_order']}")

    def test_load_is_bounded(self):
        r = route("Create 20 supermarket products")
        self.assertLessEqual(len(r["load_order"]), 14, "router should not load the whole library")

    def test_every_workflow_skill_exists(self):
        from lib.skills import discover
        skills = discover()
        for wf in json.loads((ROOT / "catalog/workflows.json").read_text())["workflows"]:
            for s in wf["skills"]:
                with self.subTest(workflow=wf["id"], skill=s):
                    self.assertIn(s, skills)


if __name__ == "__main__":
    unittest.main()
