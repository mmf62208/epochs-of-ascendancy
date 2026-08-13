#!/usr/bin/env python3
"""Gates: next-410 Phase 5 depth (12)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next410_phase5_depth import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = {
    "historical_oob_catalog_day", "historical_oob_seed_day", "historical_oob_equip_day", "historical_oob_content_close_day",
    "tech_tree_branches_day", "tech_tree_path_day", "tech_tree_field_day", "tech_tree_branching_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twelve(self):
        self.assertEqual(len(PHASE5_DEPTH_DAY_IDS), 12)
        self.assertEqual(len(DAY_FUNCS), 12)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
    def test_close(self):
        self.assertTrue(close_next410_phase5_depth_loop().get("ok"))
        self.assertTrue(phase5_depth_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in PHASE5_DEPTH_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg=live)
            self.assertIn(aid, pi)
        self.assertIn("_next410_live_day", mm)
        self.assertIn("func _rebuild_phase5_depth_section", panel)
        self.assertIn("test_next12_phase5_depth_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        labels = [
            "historical oob catalog day", "historical oob seed day", "historical oob equip day",
            "historical oob content close day", "tech tree branches day", "tech tree path day",
            "tech tree field day", "tech tree branching close day", "save resume checkpoint day",
            "save resume save day", "save resume resume day", "save resume campaign close day", "next-410",
        ]
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
