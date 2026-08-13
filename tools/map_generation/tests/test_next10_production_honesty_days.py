#!/usr/bin/env python3
"""Gates: next-360 medium production honesty (10)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next360_production_honesty import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = set(PRODUCTION_HONESTY_DAY_IDS[:6])

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_ten(self):
        self.assertEqual(len(PRODUCTION_HONESTY_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
    def test_close(self):
        self.assertTrue(close_next360_production_honesty_loop().get("ok"))
        self.assertTrue(production_honesty_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in PRODUCTION_HONESTY_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
            self.assertIn(aid, pi)
        self.assertIn("_next360_live_day", mm)
        self.assertIn("func _rebuild_production_honesty_section", panel)
        self.assertIn("test_next10_production_honesty_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        labels = [
            "medium honesty 60d day", "medium honesty 80d day", "medium honesty 100d day",
            "medium honesty unit stats day", "medium honesty factory risk day", "medium honesty stockpile day",
            "medium honesty readiness joint day", "medium honesty manpower joint day", "medium honesty economy joint day",
            "medium tank production honesty close day", "next-360",
        ]
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
