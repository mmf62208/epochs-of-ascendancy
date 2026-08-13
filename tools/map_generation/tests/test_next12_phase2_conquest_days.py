#!/usr/bin/env python3
"""Gates: next-380 Phase 2 conquest depth (12)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next380_phase2_conquest import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = {
    "occupation_resistance_board_day", "occupation_resistance_policy_day", "occupation_resistance_tick_day",
    "occupation_resistance_close_day", "manpower_law_board_day", "manpower_train_pipeline_day",
    "manpower_field_trained_day", "manpower_laws_training_close_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twelve(self):
        self.assertEqual(len(PHASE2_CONQUEST_DAY_IDS), 12)
        self.assertEqual(len(DAY_FUNCS), 12)

    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)

    def test_close(self):
        self.assertTrue(close_next380_phase2_conquest_loop().get("ok"))
        self.assertTrue(phase2_conquest_depth_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in PHASE2_CONQUEST_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg=live)
            self.assertIn(aid, pi)
        self.assertIn("_next380_live_day", mm)
        self.assertIn("func _rebuild_phase2_conquest_section", panel)
        self.assertIn("test_next12_phase2_conquest_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        labels = [
            "occupation resistance board day", "occupation resistance policy day", "occupation resistance tick day",
            "occupation resistance close day", "manpower law board day", "manpower train pipeline day",
            "manpower field trained day", "manpower laws training close day", "peace conference board day",
            "peace conference demands day", "peace conference settle day", "peace conference campaign close day",
            "next-380",
        ]
        for path in (ROOT / "TODO.md", ROOT / "Project_State_Summary.md", ROOT / "Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
