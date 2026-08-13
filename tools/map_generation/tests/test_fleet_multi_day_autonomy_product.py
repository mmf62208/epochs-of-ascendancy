#!/usr/bin/env python3
"""Gates: fleet multi-day autonomy product (major #2) + playability/execution wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from fleet_multi_day_autonomy_product import (  # noqa: E402
    DAY_STEPS,
    build_fleet_multi_day_autonomy_product,
    execute_fleet_day_step,
    recommend_fleet_multi_day_step,
    fleet_multi_day_autonomy_integrity,
    close_fleet_multi_day_autonomy_product_loop,
)
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"
WF = ROOT / "data" / "provinces_world_full"


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_three_days(self):
        p = build_fleet_multi_day_autonomy_product([1, 2, 3], fuel_level=0.65)
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("day_count", 0)), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn("recommendation", p)
        self.assertIn("decision_strip", p)
        steps = [str(r.get("step")) for r in (p.get("day_rows") or [])]
        self.assertEqual(steps, list(DAY_STEPS))
        leaves = {str(q.get("step")): str(q.get("action_id")) for q in (p.get("apply_queue") or [])}
        self.assertEqual(leaves.get("posture"), "apply_station")
        self.assertEqual(leaves.get("station_escort"), "apply_supply")
        self.assertEqual(leaves.get("follow_through"), "apply_station")
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("fleet_multi_day_autonomy_product", aids)

    def test_execute_and_fuel_shift(self):
        for step in DAY_STEPS:
            e = execute_fleet_day_step(step, 4)
            self.assertEqual(str(e.get("step")), step)
            self.assertTrue(e.get("ok"))
            self.assertGreaterEqual(len(e.get("apply_queue") or []), 1)
        full = build_fleet_multi_day_autonomy_product([1, 2], fuel_level=0.75)
        low = build_fleet_multi_day_autonomy_product([1, 2], fuel_level=0.25)
        self.assertGreater(float(full.get("score", 0)), float(low.get("score", 0)))
        rec = recommend_fleet_multi_day_step(0.2, 0.8)
        self.assertEqual(rec.get("step"), "station_escort")

    def test_integrity_close(self):
        self.assertTrue(fleet_multi_day_autonomy_integrity().get("ok"))
        loop = close_fleet_multi_day_autonomy_product_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreater(float(loop.get("fuel_shift", 0)), 0.01)


class TestLive(unittest.TestCase):
    def test_composition_and_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func fleet_multi_day_autonomy_product(", fmt)
        self.assertIn("static func recommend_fleet_multi_day_step(", fmt)
        self.assertIn("static func execute_fleet_day_step(", fmt)
        start = fmt.find("static func fleet_multi_day_autonomy_product(")
        body = fmt[start : start + 5500]
        for h in ("fleet_autonomy_plan", "basing_fleet_fuel_logistics", "compose_fleet_task_group",
                  "fleet_order_execute", "naval_order_package", "plan_fleet_theater_posture",
                  "sealane_joint_health", "execution_decision_strip"):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func fleet_multi_day_autonomy_product_for_province", mm)
        self.assertIn("func apply_fleet_day_step_for_province", mm)
        self.assertIn("func apply_fleet_multi_day_autonomy_product", mm)
        self.assertIn("func apply_fleet_multi_day_autonomy_product", gd)
        self.assertIn("func apply_fleet_day_posture", gd)
        self.assertIn("func apply_fleet_day_station_escort", gd)
        self.assertIn("func apply_fleet_day_follow_through", gd)
        self.assertIn("format_fleet_multi_day_autonomy_product_plain", gd)
        sec_i = panel.find("func _rebuild_fleet_section")
        sec = panel[sec_i : sec_i + 2200]
        self.assertIn("Fleet multi-day autonomy product (major #2)", sec)
        self.assertIn("fleet_multi_day_autonomy_product_for_province", sec)
        self.assertIn("fleet_day_posture", sec)
        self.assertIn("fleet_day_station_escort", sec)
        self.assertIn("fleet_day_follow_through", sec)
        self.assertGreaterEqual(panel.count("_rebuild_fleet_section"), 2)
        self.assertIn("build_fleet_multi_day_autonomy_product_chip_bbcode", pi)
        self.assertIn("test_fleet_multi_day_autonomy_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "fleet multi-day autonomy",
            "fleet day posture",
            "fleet day station escort",
            "fleet day follow-through",
            "major #2",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
