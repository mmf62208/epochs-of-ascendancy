#!/usr/bin/env python3
"""Gates: manpower cohort/reserve product (major #36)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from manpower_cohort_reserve_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_manpower_cohort_reserve_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreater(float(p.get("eligible", 0)), 0)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_manpower_cohort_step(s).get("ok"))
        self.assertTrue(manpower_cohort_reserve_integrity().get("ok"))
        self.assertTrue(close_manpower_cohort_reserve_product_loop().get("ok"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func manpower_cohort_reserve_product(", fmt)
        self.assertIn("func manpower_cohort_reserve_product_live", mm)
        self.assertIn("func apply_manpower_cohort_live", gd)
        self.assertIn("Manpower cohort/reserve (major #36)", panel)
        self.assertIn("build_manpower_cohort_reserve_product_chip_bbcode", pi)
        self.assertIn("phase4_depth_live", sl)
        self.assertIn("test_manpower_cohort_reserve_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md", ROOT/"GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("manpower cohort", "major #36", "phase4_depth", "reserve"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
