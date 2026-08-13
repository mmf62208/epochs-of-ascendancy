#!/usr/bin/env python3
"""Gates: next-470 phase11 depth day package (12)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next470_phase11_depth import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_days(self):
        self.assertEqual(len(PHASE11_DEPTH_DAY_IDS), 12)
        self.assertEqual(len(DAY_FUNCS), 12)
        for fn in DAY_FUNCS:
            d = fn()
            self.assertFalse(d.get("empty"), msg=fn.__name__)
            self.assertGreaterEqual(float(d.get("score", 0)), 0.35)
        self.assertTrue(close_next470_phase11_depth_loop().get("ok"))
        self.assertTrue(phase11_depth_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        for aid in PHASE11_DEPTH_DAY_IDS:
            self.assertIn("static func %s(" % aid, fmt)
            self.assertTrue(
                ("func %s_live" % aid in mm) or ("func %s_for_province" % aid in mm),
                msg=aid,
            )
            self.assertIn("func apply_%s" % aid, gd)
            self.assertIn("format_%s_plain" % aid, gd)
        self.assertIn("func _rebuild_phase11_depth_section", panel)
        self.assertIn("test_next12_phase11_depth_days.py", (ROOT / "tools/run_map_ci.sh").read_text())

if __name__ == "__main__":
    unittest.main(verbosity=2)
