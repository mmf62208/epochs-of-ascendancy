#!/usr/bin/env python3
"""Gates: strategic war goal product (major #53)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from strategic_war_goal_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_strategic_war_goal_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(int(p.get("goal_n", 0)), 3)
        self.assertTrue(close_strategic_war_goal_product_loop().get("ok"))
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_war_goal_step(s).get("ok"))
        self.assertTrue(strategic_war_goal_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func strategic_war_goal_product(", fmt)
        self.assertIn("func strategic_war_goal_product_live", mm)
        self.assertIn("func apply_war_goal_live", gd)
        self.assertIn("Strategic war goals (major #53)", panel)
        self.assertIn("build_strategic_war_goal_product_chip_bbcode", pi)
        self.assertIn("phase10_gs_live", sl)
        self.assertIn("test_strategic_war_goal_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md", ROOT/"GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ('strategic war', 'major #53', 'phase10_gs', 'world_class_gs'):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
