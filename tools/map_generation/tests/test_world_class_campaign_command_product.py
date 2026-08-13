#!/usr/bin/env python3
"""Gates: world-class campaign command product (major #20)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from world_class_campaign_command_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_world_class_campaign_command_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_world_class_step(s).get("ok"))
        self.assertTrue(world_class_campaign_command_integrity().get("ok"))
        self.assertTrue(close_world_class_campaign_command_product_loop().get("ok"))
    def test_recommend(self):
        r = recommend_world_class_step()
        self.assertIn(r.get("step"), PRODUCT_STEPS)
        self.assertFalse(r.get("empty", True))

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func world_class_campaign_command_product(", fmt)
        body = fmt[fmt.find("static func world_class_campaign_command_product("):fmt.find("static func world_class_campaign_command_product(")+5000]
        for h in ("logistics_supply_theater_product", "intelligence_network_product", "theater_command_product", "strategic_ai_daily"):
            self.assertIn(h, body)
        self.assertIn("func world_class_campaign_command_product_live", mm)
        self.assertIn("func apply_world_class_campaign_command_product", gd)
        self.assertIn("World-class campaign command (major #20)", panel)
        self.assertIn("build_world_class_campaign_command_product_chip_bbcode", pi)
        self.assertIn("test_world_class_campaign_command_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("world-class campaign command", "world class scan", "major #20", "world class"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
