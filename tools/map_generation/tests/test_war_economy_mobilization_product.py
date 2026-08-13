#!/usr/bin/env python3
"""Gates: war economy mobilization product (major #21)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from war_economy_mobilization_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_war_economy_mobilization_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_war_economy_step(s).get("ok"))
        self.assertTrue(war_economy_mobilization_integrity().get("ok"))
        self.assertTrue(close_war_economy_mobilization_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_war_economy_step(board_score=0.2).get("step"), "board")
        self.assertEqual(recommend_war_economy_step(board_score=0.7, allocate_score=0.7, ready=True).get("step"), "sustain")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func war_economy_mobilization_product(", fmt)
        body = fmt[fmt.find("static func war_economy_mobilization_product("):fmt.find("static func war_economy_mobilization_product(")+3500]
        for h in ("war_economy_day_package", "industry_surge_day", "trade_chain_day", "medium_tank_oob_product"):
            self.assertIn(h, body)
        self.assertIn("func war_economy_mobilization_product_live", mm)
        self.assertIn("func apply_war_economy_mobilization_product", gd)
        self.assertIn("War economy mobilization (major #21)", panel)
        self.assertIn("build_war_economy_mobilization_product_chip_bbcode", pi)
        self.assertIn("test_war_economy_mobilization_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("war economy mobilization", "war economy board", "major #21", "economy"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
