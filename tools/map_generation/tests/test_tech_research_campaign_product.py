#!/usr/bin/env python3
"""Gates: tech research campaign product (major #17)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from tech_research_campaign_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_tech_research_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("catalog_count", 0)), 4)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_tech_research_step(s).get("ok"))
        self.assertTrue(tech_research_campaign_integrity().get("ok"))
        self.assertTrue(close_tech_research_campaign_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_tech_research_step(catalog_count=2).get("step"), "catalog")
        self.assertEqual(recommend_tech_research_step(catalog_count=8, priority_score=0.7, field_ready=True).get("step"), "field")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func tech_research_campaign_product(", fmt)
        body = fmt[fmt.find("static func tech_research_campaign_product("):fmt.find("static func tech_research_campaign_product(")+4000]
        for h in ("designer_suite_product", "production_priority_mutation", "medium_tank_oob_product", "execute_designer_suite_step"):
            self.assertIn(h, body)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func tech_research_campaign_product_live", mm)
        self.assertIn("func apply_tech_research_campaign_product", gd)
        self.assertIn("Tech research campaign (major #17)", panel)
        self.assertIn("build_tech_research_campaign_product_chip_bbcode", pi)
        self.assertIn("test_tech_research_campaign_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("tech research", "tech research catalog", "major #17", "research"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
