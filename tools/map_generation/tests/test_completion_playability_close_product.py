#!/usr/bin/env python3
"""Gates: close deferred combat/naval/HH playability majors as live products."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from completion_playability_close_product import (  # noqa
    close_all_three_live,
    completion_playability_integrity,
    apply_combat_ops_live,
    apply_naval_ops_live,
    apply_hh_agenda_live,
    _new_runtime,
)


class TestCompletionPlayability(unittest.TestCase):
    def test_close_all_three(self):
        r = close_all_three_live(1)
        self.assertTrue(r.get("ok"), msg=r)
        self.assertEqual(len(r.get("closed_majors") or []), 3)
        self.assertTrue(r["combat"]["ok"])
        self.assertTrue(r["naval"]["ok"])
        self.assertTrue(r["hh"]["ok"])

    def test_combat_three_phases(self):
        rt = _new_runtime()
        phases = []
        for _ in range(3):
            res = apply_combat_ops_live(rt, 42)
            self.assertTrue(res.get("ok"))
            phases.append(res["applied_phase"])
        self.assertEqual(phases, ["approach", "engage", "disengage"])
        self.assertTrue(rt["combat_phase"].get("complete"))

    def test_naval_three_steps(self):
        rt = _new_runtime()
        steps = []
        for _ in range(3):
            res = apply_naval_ops_live(rt, 42)
            self.assertTrue(res.get("ok"))
            steps.append(res["applied_step"])
        self.assertEqual(steps, ["posture", "escort", "strike"])
        self.assertTrue(rt["naval_campaign"].get("complete"))

    def test_hh_three_steps_with_months(self):
        rt = _new_runtime()
        for _ in range(3):
            res = apply_hh_agenda_live(rt, 42)
            self.assertTrue(res.get("ok"))
        self.assertGreaterEqual(int(rt["hh_agenda"].get("months_committed") or 0), 1)
        self.assertTrue(rt["hh_agenda"].get("complete"))
        self.assertGreaterEqual(len(rt["hh_agenda"].get("trail") or []), 3)

    def test_gamedata_and_loader_wired(self):
        g = completion_playability_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("apply_combat_ops_close_live", gd)
        self.assertIn("apply_naval_ops_close_live", gd)
        self.assertIn("apply_hh_agenda_close_live", gd)
        self.assertIn("apply_completion_playability_close_live", gd)
        self.assertIn("completion_playability_live=1", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_completion_playability_close_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
