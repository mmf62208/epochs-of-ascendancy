#!/usr/bin/env python3
"""Gates: next-20 completion package (OPEN majors #1–#5, 20 live steps)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next20_completion_package_product import (  # noqa
    NEXT20_STEPS,
    _LIVE_API_BY_STEP,
    apply_next20_step,
    assert_live_routing_for_majors_3_and_4,
    close_next20_package,
    extract_next20_step_live_body,
    next20_completion_integrity,
    _new_runtime,
)


class TestNext20Completion(unittest.TestCase):
    def test_exactly_twenty_steps(self):
        self.assertEqual(len(NEXT20_STEPS), 20)
        self.assertEqual(len(set(NEXT20_STEPS)), 20)

    def test_close_all_twenty(self):
        r = close_next20_package(1)
        self.assertTrue(r.get("ok"), msg=r)
        self.assertEqual(int(r.get("applied_n") or 0), 20)
        self.assertEqual(int(r.get("majors_done") or 0), 5)
        self.assertTrue(r.get("complete"))
        self.assertEqual(len(r.get("closed") or []), 20)

    def test_step_order_and_majors(self):
        rt = _new_runtime()
        for i, step in enumerate(NEXT20_STEPS):
            res = apply_next20_step(rt, step, 42)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res["step"], step)
            self.assertEqual(int(res.get("applied_n") or 0), i + 1)
        self.assertTrue(rt.get("complete"))
        # combat history three phases
        self.assertIn("approach", rt["combat"]["history"])
        self.assertIn("engage", rt["combat"]["history"])
        self.assertIn("disengage", rt["combat"]["history"])
        # fleet multi-day
        self.assertGreaterEqual(int(rt["fleet"].get("day") or 0), 2)
        # medium 100d
        self.assertGreaterEqual(int(rt["medium"].get("horizon_d") or 0), 100)
        # save checkpoint
        self.assertTrue(rt["save"].get("checkpoint"))
        # hh months
        self.assertGreaterEqual(int(rt["hh"].get("months") or 0), 1)

    def test_gamedata_loader_wired(self):
        g = next20_completion_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("apply_next20_completion_live", gd)
        self.assertIn("apply_next20_step_live", gd)
        self.assertIn("NEXT20_STEPS", gd)
        self.assertIn("next20_completion_live=1", sl)
        # all 20 step ids present in product file (shipped catalogue)
        prod = (ROOT / "tools" / "map_generation" / "lib" / "next20_completion_package_product.py").read_text()
        for step in NEXT20_STEPS:
            self.assertIn('"%s"' % step, prod)

    def test_live_routing_major3_medium_oob(self):
        """Shipped GameData.apply_next20_step_live must call real OOB horizon APIs."""
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        body = extract_next20_step_live_body(gd)
        self.assertIn("func apply_next20_step_live(", body)
        # Real APIs exist on GameData
        self.assertIn("func apply_medium_tank_oob_product(", gd)
        self.assertIn("func apply_oob_horizon_60d(", gd)
        self.assertIn("func apply_oob_horizon_100d(", gd)
        # Per-step routing inside apply_next20_step_live
        self.assertIn('s == "medium_line_scan"', body)
        self.assertIn("apply_medium_tank_oob_product", body)
        self.assertIn('s == "medium_horizon_60d"', body)
        self.assertIn("apply_oob_horizon_60d", body)
        self.assertIn('s == "medium_horizon_100d"', body)
        self.assertIn("apply_oob_horizon_100d", body)
        self.assertIn('s == "medium_oob_equip_close"', body)
        self.assertIn("apply_medium_tank_oob_sequence", body)
        # Must not only generic-production-leaf medium
        self.assertNotIn(
            'elif s.begins_with("medium"):\n\t\tmajor = 3\n\t\tleaf = "apply_production"',
            body.replace("    ", "\t"),
        )
        r = assert_live_routing_for_majors_3_and_4(gd)
        self.assertTrue(r.get("ok"), msg=r)

    def test_live_routing_major4_save_browser(self):
        """Shipped GameData.apply_next20_step_live must call save_browser live APIs, not apply_focus."""
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        body = extract_next20_step_live_body(gd)
        self.assertIn("func apply_save_browser_resume(", gd)
        self.assertIn("func apply_save_browser_checkpoint(", gd)
        self.assertIn("func save_browser_campaign_product_live(", gd)
        self.assertIn('s == "save_browser_list"', body)
        self.assertIn("save_browser_campaign_product_live", body)
        self.assertIn('s == "save_browser_resume"', body)
        self.assertIn("apply_save_browser_resume", body)
        self.assertIn('s == "save_checkpoint"', body)
        self.assertIn("apply_save_browser_checkpoint", body)
        self.assertIn('s == "save_browser_close"', body)
        # No apply_focus leaf for save major
        self.assertNotIn('leaf = "apply_focus"', body)
        for step, api in _LIVE_API_BY_STEP.items():
            if step.startswith("save_"):
                self.assertIn(step, body)
                self.assertIn(api, body)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_next20_completion_package_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
