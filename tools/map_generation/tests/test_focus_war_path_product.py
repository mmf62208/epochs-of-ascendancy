#!/usr/bin/env python3
"""Gates: focus war path product (major #14)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from focus_war_path_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_focus_war_path_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_focus_war_step(s).get("ok"))
        self.assertTrue(focus_war_path_product_integrity().get("ok"))
        self.assertTrue(close_focus_war_path_product_loop().get("ok"))
    def test_recommend(self):
        self.assertEqual(recommend_focus_war_step(pick_score=0.2).get("step"), "pick")
        self.assertEqual(recommend_focus_war_step(pick_score=0.7, path_score=0.7, commit_ready=True).get("step"), "commit")

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        self.assertIn("static func focus_war_path_product(", fmt)
        body = fmt[fmt.find("static func focus_war_path_product("):fmt.find("static func focus_war_path_product(")+3500]
        for h in ("rank_focus_picks", "focus_order_path", "focus_war_path_day", "focus_pick_day"):
            self.assertIn(h, body)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func focus_war_path_product_live", mm)
        self.assertIn("func apply_focus_war_path_product", gd)
        self.assertIn("Focus war path product (major #14)", panel)
        self.assertIn("build_focus_war_path_product_chip_bbcode", pi)
        self.assertIn("test_focus_war_path_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in ("focus war path", "focus war pick", "major #14", "war path"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
