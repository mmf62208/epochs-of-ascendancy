#!/usr/bin/env python3
"""Gates: medium-tank production honesty product (major #27)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from medium_tank_production_honesty_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_medium_tank_production_honesty_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertEqual(int(p.get("medium_tank_complete", 0)), 1)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_medium_honesty_step(s).get("ok"))
        self.assertTrue(medium_tank_production_honesty_integrity().get("ok"))
        self.assertTrue(close_medium_tank_production_honesty_product_loop().get("ok"))
    def test_project(self):
        u = project_medium_unit_completion(horizon_days=100, tank_line_progress=0.15, factories=14)
        self.assertTrue(u.get("will_complete"))
        self.assertGreaterEqual(int(u.get("units_projected", 0)), 1)
        self.assertEqual(int(u.get("crew_required", 0)), 5)

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func medium_tank_production_honesty_product(", fmt)
        self.assertIn("project_medium_unit_completion", fmt)
        self.assertIn("func medium_tank_production_honesty_product_live", mm)
        self.assertIn("func apply_medium_tank_production_honesty_product", gd)
        self.assertIn("Medium-tank production honesty (major #27)", panel)
        self.assertIn("build_medium_tank_production_honesty_product_chip_bbcode", pi)
        self.assertIn("medium_tank_complete=", sl)
        self.assertIn("test_medium_tank_production_honesty_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md", ROOT/"GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("medium-tank production honesty", "medium honesty", "major #27", "medium_tank_complete"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
