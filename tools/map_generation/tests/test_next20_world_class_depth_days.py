#!/usr/bin/env python3
"""Gates: next-330 world-class depth (20)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next330_world_class_depth import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = set(WORLD_CLASS_DEPTH_DAY_IDS[:12])

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(WORLD_CLASS_DEPTH_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
    def test_close(self):
        self.assertTrue(close_next330_world_class_depth_loop().get("ok"))
        self.assertTrue(world_class_depth_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_composition(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        idx = fmt.find("Next-330 world-class depth pillars (20)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("logistics_supply_theater_product", "intelligence_network_product", "world_class_campaign_command_product", "naval_multi_phase_campaign_product", "air_ops_campaign_product", "theater_command_product"):
            self.assertIn(h, sec, msg=h)
        for aid in WORLD_CLASS_DEPTH_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next330_live_day", mm)
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in WORLD_CLASS_DEPTH_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
            self.assertIn(aid, pi)
        self.assertIn("func _rebuild_world_class_depth_section", panel)
        self.assertIn("— Next-330 world-class depth (20) —", panel)
        self.assertIn("test_next20_world_class_depth_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        labels = [
            "logistics route advanced day", "logistics sustain advanced day", "logistics readiness advanced day",
            "logistics naval joint day", "logistics tech industry joint day", "logistics supply close day",
            "intel coverage advanced day", "intel counterintel advanced day", "intel counterplay advanced day",
            "intel diplomacy joint day", "intel session joint day", "intelligence network close day",
            "world class scan advanced day", "world class rank advanced day", "world class execute advanced day",
            "world class logistics intel joint day", "world class air naval joint day", "world class session ai joint day",
            "world class theater command joint day", "world class campaign close day", "next-330 world",
        ]
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
