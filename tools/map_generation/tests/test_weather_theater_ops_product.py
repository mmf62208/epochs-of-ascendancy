#!/usr/bin/env python3
"""Gates: weather theater ops product (major #22)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from weather_theater_ops_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_weather_theater_ops_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_weather_theater_step(s).get("ok"))
        self.assertTrue(weather_theater_ops_integrity().get("ok"))
        self.assertTrue(close_weather_theater_ops_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_weather_step(pressure_score=0.2).get("step"), "pressure")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func weather_theater_ops_product(", fmt)
        body = fmt[fmt.find("static func weather_theater_ops_product("):fmt.find("static func weather_theater_ops_product(")+3500]
        for h in ("weather_crisis_day", "weather_pressure_depth_day", "logistics_supply_theater_product", "force_readiness_day"):
            self.assertIn(h, body)
        self.assertIn("func weather_theater_ops_product_live", mm)
        self.assertIn("func apply_weather_theater_ops_product", gd)
        self.assertIn("Weather theater ops (major #22)", panel)
        self.assertIn("build_weather_theater_ops_product_chip_bbcode", pi)
        self.assertIn("test_weather_theater_ops_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("weather theater ops", "weather theater pressure", "major #22", "weather"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
