#!/usr/bin/env python3
"""Gates: next-270 naval/theater/inspector (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next270_naval_theater_inspector import (
    NAVAL_THEATER_INSPECTOR_DAY_IDS, DAY_FUNCS, close_next270_naval_theater_inspector_loop,
    naval_theater_inspector_integrity, naval_basing_sustain_day, multi_day_theater_depth_day,
    inspector_decision_depth_day, theater_naval_inspector_close_day,
)
WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO, SUMMARY, ROADMAP = ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"
LIVE = {
 "naval_basing_sustain_day","port_fuel_depth_day","fleet_task_sustain_day","naval_basing_close_day",
 "multi_day_theater_depth_day","theater_campaign_continuity_day","theater_continuity_joint_day","theater_campaign_depth_close_day",
 "inspector_decision_depth_day","decision_strip_depth_day","province_decision_joint_day","theater_naval_inspector_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(NAVAL_THEATER_INSPECTOR_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        n = naval_basing_sustain_day()
        self.assertIn("rates", n)
        self.assertIn("fuel", n)
        self.assertGreater(float(n.get("basing_score", n.get("score", 0))), 0.1)
        t = multi_day_theater_depth_day()
        self.assertIn("brief", t)
        self.assertIn("plan", t)
        i = inspector_decision_depth_day()
        self.assertIn("strip", i)
        c = theater_naval_inspector_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next270_naval_theater_inspector_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(naval_theater_inspector_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (naval basing / theater multi-day / inspector decision)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("basing_repair_refuel_rates","basing_fleet_fuel_logistics","basing_repair_weather_loop",
                  "naval_campaign_package","naval_order_package","fleet_order_execute","convoy_package_compose",
                  "fleet_weather_mission_package","leader_formation_station_day",
                  "theater_daily_brief","multi_province_live_rank","campaign_day_risk",
                  "execution_decision_strip","campaign_decision_strip","player_order_surface_strip",
                  "execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func naval_basing_sustain_day"):sec.find("static func naval_basing_sustain_day")+900]
        self.assertIn("basing_fleet_fuel_logistics", body)
        self.assertNotIn("var score := 0.55", body)
        th = sec[sec.find("static func multi_day_theater_depth_day"):sec.find("static func multi_day_theater_depth_day")+700]
        self.assertIn("theater_daily_brief", th)
        ins = sec[sec.find("static func inspector_decision_depth_day"):sec.find("static func inspector_decision_depth_day")+700]
        self.assertIn("execution_decision_strip", ins)
        for aid in NAVAL_THEATER_INSPECTOR_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next270_live_day", mm)
        self.assertIn("basing_score", mm)
        self.assertIn("theater_score", mm)
        self.assertIn("inspector_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in NAVAL_THEATER_INSPECTOR_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_naval_theater_inspector_section", panel)
        self.assertIn("— Next-270 naval/theater/inspector (20) —", panel)
        self.assertIn("format_theater_naval_inspector_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_naval_theater_inspector_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("naval_basing_sustain_day","multi_day_theater_depth_day","inspector_decision_depth_day","theater_naval_inspector_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_naval_theater_inspector_days.py", CI.read_text())
        labels = [
            "naval basing sustain day","port fuel depth day","basing repair depth day","fleet task sustain day",
            "convoy basing joint day","naval logistics depth day","naval basing close day",
            "multi day theater depth day","theater campaign continuity day","campaign day chain day",
            "theater session ops day","daily theater sustain day","theater continuity joint day","theater campaign depth close day",
            "inspector decision depth day","decision strip depth day","insight strip depth day",
            "province decision joint day","inspector campaign ops day","theater naval inspector close day","next-270 naval",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
