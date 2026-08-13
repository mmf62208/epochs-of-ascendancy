#!/usr/bin/env python3
"""Gates: intelligence network product (major #19)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from intelligence_network_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_intelligence_network_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_intel_network_step(s).get("ok"))
        self.assertTrue(intelligence_network_product_integrity().get("ok"))
        self.assertTrue(close_intelligence_network_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_intel_step(coverage_score=0.2).get("step"), "coverage")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func intelligence_network_product(", fmt)
        body = fmt[fmt.find("static func intelligence_network_product("):fmt.find("static func intelligence_network_product(")+4000]
        for h in ("agent_campaign_product", "counterintel", "hh_multi_month"):
            self.assertIn(h, body)
        self.assertIn("func intelligence_network_product_live", mm)
        self.assertIn("func apply_intelligence_network_product", gd)
        self.assertIn("Intelligence network (major #19)", panel)
        self.assertIn("build_intelligence_network_product_chip_bbcode", pi)
        self.assertIn("test_intelligence_network_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("intelligence network", "intel network coverage", "major #19", "intelligence"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
