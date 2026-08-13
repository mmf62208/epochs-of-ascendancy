#!/usr/bin/env python3
"""Gates: medium-tank OOB multi-month product (major #3)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from medium_tank_oob_product import (  # noqa: E402
    HORIZON_STEPS,
    build_medium_tank_oob_product,
    execute_oob_horizon_step,
    recommend_oob_horizon_step,
    medium_tank_oob_product_integrity,
    close_medium_tank_oob_product_loop,
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
    def test_product_three_horizons(self):
        p = build_medium_tank_oob_product(1, tank_line_progress=0.15, factories=14)
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn("recommendation", p)
        horizons = [int(r.get("horizon_days")) for r in (p.get("day_rows") or [])]
        self.assertEqual(horizons, list(HORIZON_STEPS))
        self.assertTrue(p.get("will_complete_100d"))
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("medium_tank_oob_product", aids)
        self.assertIn("oob_horizon_60d", aids)

    def test_execute_and_progress_shift(self):
        for d in HORIZON_STEPS:
            e = execute_oob_horizon_step(d, 4)
            self.assertEqual(int(e.get("horizon_days")), d)
            self.assertTrue(e.get("ok"))
            self.assertGreaterEqual(len(e.get("apply_queue") or []), 1)
        full = build_medium_tank_oob_product(1, tank_line_progress=0.3, factories=18)
        early = build_medium_tank_oob_product(1, tank_line_progress=0.05, factories=8)
        self.assertGreaterEqual(float(full.get("score", 0)), float(early.get("score", 0)) * 0.85)
        rec = recommend_oob_horizon_step(False, False, tank_progress=0.1)
        self.assertEqual(int(rec.get("step")), 60)

    def test_integrity_close(self):
        self.assertTrue(medium_tank_oob_product_integrity().get("ok"))
        loop = close_medium_tank_oob_product_loop()
        self.assertTrue(loop.get("ok"))


class TestLive(unittest.TestCase):
    def test_composition_and_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func medium_tank_oob_product(", fmt)
        self.assertIn("static func recommend_oob_horizon_step(", fmt)
        self.assertIn("static func execute_oob_horizon_step(", fmt)
        start = fmt.find("static func medium_tank_oob_product(")
        body = fmt[start : start + 5500]
        for h in (
            "medium_horizon_equip_plan",
            "oob_factory_risk_loop",
            "production_priority_mutation",
            "production_order_resolve",
            "production_campaign_risk",
            "force_readiness_day",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func medium_tank_oob_product_for_province", mm)
        self.assertIn("func apply_oob_horizon_step_for_province", mm)
        self.assertIn("func apply_medium_tank_oob_product", mm)
        self.assertIn("func apply_medium_tank_oob_product", gd)
        self.assertIn("func apply_oob_horizon_60d", gd)
        self.assertIn("func apply_oob_horizon_80d", gd)
        self.assertIn("func apply_oob_horizon_100d", gd)
        self.assertIn("format_medium_tank_oob_product_plain", gd)
        sec_i = panel.find("func _rebuild_industry_section")
        sec = panel[sec_i : sec_i + 2500]
        self.assertIn("Medium-tank OOB product (major #3)", sec)
        self.assertIn("medium_tank_oob_product_for_province", sec)
        self.assertIn("oob_horizon_60d", sec)
        self.assertIn("oob_horizon_80d", sec)
        self.assertIn("oob_horizon_100d", sec)
        self.assertGreaterEqual(panel.count("_rebuild_industry_section"), 2)
        self.assertIn("build_medium_tank_oob_product_chip_bbcode", pi)
        self.assertIn("test_medium_tank_oob_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "medium-tank oob",
            "oob horizon",
            "major #3",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
