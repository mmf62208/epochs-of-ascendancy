#!/usr/bin/env python3
"""Gates: air ops campaign product (major #13)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from air_ops_campaign_product import (  # noqa: E402
    PRODUCT_STEPS,
    air_ops_campaign_integrity,
    build_air_ops_campaign_product,
    close_air_ops_campaign_product_loop,
    execute_air_ops_step,
    recommend_air_ops_step,
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
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_three_steps(self):
        p = build_air_ops_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertIn((p.get("recommendation") or {}).get("step"), PRODUCT_STEPS)
        for s in PRODUCT_STEPS:
            e = execute_air_ops_step(s, 1)
            self.assertTrue(e.get("ok"), msg=s)
        self.assertTrue(air_ops_campaign_integrity().get("ok"))
        self.assertTrue(close_air_ops_campaign_product_loop().get("ok"))

    def test_recommend_shift(self):
        low = recommend_air_ops_step(sortie_score=0.2)
        self.assertEqual(low.get("step"), "sortie")
        foul = recommend_air_ops_step(sortie_score=0.7, weather_ok=False)
        self.assertEqual(foul.get("step"), "weather_gate")
        ready = recommend_air_ops_step(sortie_score=0.7, weather_ok=True, joint_ready=True)
        self.assertEqual(ready.get("step"), "air_land")


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func air_ops_campaign_product(", fmt)
        self.assertIn("static func execute_air_ops_step(", fmt)
        start = fmt.find("static func air_ops_campaign_product(")
        body = fmt[start : start + 4500]
        for h in (
            "air_ops_day_package",
            "air_sortie_weather_readiness",
            "air_land_campaign_day",
            "multi_phase_combat_product",
            "weather_forecast_planning_day",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func air_ops_campaign_product_live", mm)
        self.assertIn("func apply_air_ops_campaign_product", mm)
        self.assertIn("func apply_air_ops_campaign_product", gd)
        self.assertIn("func apply_air_ops_sortie", gd)
        self.assertIn("func apply_air_ops_air_land", gd)
        self.assertIn("Air ops campaign (major #13)", panel)
        self.assertIn("air_ops_campaign_product_live", panel)
        self.assertIn("air_ops_sortie", panel)
        self.assertIn("build_air_ops_campaign_product_chip_bbcode", pi)
        self.assertIn("test_air_ops_campaign_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "air ops campaign",
            "air ops sortie",
            "air ops weather gate",
            "major #13",
            "air ops",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
