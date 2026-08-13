#!/usr/bin/env python3
"""Gates: next-460 Phase 10 world-class GS (12)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next460_phase10_gs import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = {
    "war_goal_board_day", "war_goal_justify_day", "war_goal_execute_day", "strategic_war_goal_close_day",
    "multi_front_plan_day", "multi_front_weekly_day", "multi_front_execute_day", "multi_front_campaign_ai_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twelve(self):
        self.assertEqual(len(PHASE10_GS_DAY_IDS), 12)
        self.assertEqual(len(DAY_FUNCS), 12)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
    def test_close(self):
        self.assertTrue(close_next460_phase10_gs_loop().get("ok"))
        self.assertTrue(phase10_gs_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in PHASE10_GS_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg=live)
            self.assertIn(aid, pi)
        self.assertIn("_next460_live_day", mm)
        self.assertIn("func _rebuild_phase10_gs_section", panel)
        self.assertIn("test_next12_phase10_gs_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        labels = [
            "war goal board day", "war goal justify day", "war goal execute day",
            "strategic war goal close day", "multi front plan day", "multi front weekly day",
            "multi front execute day", "multi front campaign ai close day", "gs cycle scan day",
            "gs cycle rank day", "gs cycle execute day", "grand strategy cycle close day", "next-460",
        ]
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
