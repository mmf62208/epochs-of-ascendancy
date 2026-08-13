#!/usr/bin/env python3
"""Gates: diplomacy peace campaign product (major #16)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from diplomacy_peace_campaign_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_diplomacy_peace_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_diplomacy_peace_step(s).get("ok"))
        self.assertTrue(diplomacy_peace_campaign_integrity().get("ok"))
        self.assertTrue(close_diplomacy_peace_campaign_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_diplomacy_step(board_score=0.2).get("step"), "board")
        self.assertEqual(recommend_diplomacy_step(board_score=0.7, leverage_ready=True, settle_ready=True).get("step"), "settle")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func diplomacy_peace_campaign_product(", fmt)
        body = fmt[fmt.find("static func diplomacy_peace_campaign_product("):fmt.find("static func diplomacy_peace_campaign_product(")+4000]
        for h in ("war_economy_day_package", "trade_chain_day", "agent_campaign_product", "hh_multi_month_agenda_product", "campaign_decision_day"):
            self.assertIn(h, body)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func diplomacy_peace_campaign_product_live", mm)
        self.assertIn("func apply_diplomacy_peace_campaign_product", gd)
        self.assertIn("Diplomacy peace campaign (major #16)", panel)
        self.assertIn("build_diplomacy_peace_campaign_product_chip_bbcode", pi)
        self.assertIn("test_diplomacy_peace_campaign_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("diplomacy peace", "diplomacy peace board", "major #16", "diplomacy"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
