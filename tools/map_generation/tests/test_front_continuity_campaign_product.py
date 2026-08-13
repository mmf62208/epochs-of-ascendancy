#!/usr/bin/env python3
"""Gates: front continuity campaign product (major #23)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from front_continuity_campaign_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_front_continuity_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_front_continuity_step(s).get("ok"))
        self.assertTrue(front_continuity_campaign_integrity().get("ok"))
        self.assertTrue(close_front_continuity_campaign_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_front_step(combat_score=0.2).get("step"), "combat")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func front_continuity_campaign_product(", fmt)
        body = fmt[fmt.find("static func front_continuity_campaign_product("):fmt.find("static func front_continuity_campaign_product(")+3500]
        for h in ("multi_phase_combat_product", "logistics_supply_theater_product", "force_readiness_day", "theater_command_product"):
            self.assertIn(h, body)
        self.assertIn("func front_continuity_campaign_product_live", mm)
        self.assertIn("func apply_front_continuity_campaign_product", gd)
        self.assertIn("Front continuity campaign (major #23)", panel)
        self.assertIn("build_front_continuity_campaign_product_chip_bbcode", pi)
        self.assertIn("test_front_continuity_campaign_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("front continuity", "front continuity combat", "major #23", "front"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
