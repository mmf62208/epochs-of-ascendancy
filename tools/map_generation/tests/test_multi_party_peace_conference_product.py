#!/usr/bin/env python3
"""Gates: multi-party peace conference product (major #37)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from multi_party_peace_conference_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_multi_party_peace_conference_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(int(p.get("winner_n", 0)), 2)
        self.assertGreaterEqual(int(p.get("package_n", 0)), 2)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_multi_party_peace_step(s).get("ok"))
        self.assertTrue(multi_party_peace_conference_integrity().get("ok"))
        self.assertTrue(close_multi_party_peace_conference_product_loop().get("ok"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func multi_party_peace_conference_product(", fmt)
        self.assertIn("func multi_party_peace_conference_product_live", mm)
        self.assertIn("func apply_multi_party_peace_live", gd)
        self.assertIn("Multi-party peace conference (major #37)", panel)
        self.assertIn("build_multi_party_peace_conference_product_chip_bbcode", pi)
        self.assertIn("phase4_depth_live", sl)
        self.assertIn("test_multi_party_peace_conference_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md", ROOT/"GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("multi-party peace", "major #37", "phase4_depth", "war-goal"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
