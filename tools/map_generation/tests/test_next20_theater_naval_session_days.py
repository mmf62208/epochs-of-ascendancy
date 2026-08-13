#!/usr/bin/env python3
"""Gates: next-160 theater/naval/session (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next160_theater_naval_session import (
    THEATER_NAVAL_SESSION_DAY_IDS, DAY_FUNCS, close_next160_theater_naval_session_loop,
    theater_naval_session_integrity, multi_province_campaign_day, basing_fleet_sustain_day,
    player_surface_session_day, theater_naval_session_close_day, sealane_joint_ops_day,
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
 "multi_province_campaign_day","theater_auto_campaign_day","theater_readiness_ops_day",
 "theater_campaign_close_day","basing_fleet_sustain_day","convoy_sustain_ops_day",
 "sealane_joint_ops_day","naval_sealane_close_day","player_surface_session_day",
 "order_panel_session_day","theater_naval_session_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(THEATER_NAVAL_SESSION_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        m = multi_province_campaign_day()
        self.assertIn("ranked", m)
        b = basing_fleet_sustain_day()
        self.assertIn("fuel", b)
        s = sealane_joint_ops_day()
        self.assertIn("joint", s)
        p = player_surface_session_day()
        self.assertIn("strip", p)
        c = theater_naval_session_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next160_theater_naval_session_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(theater_naval_session_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (theater / naval / session)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("multi_province_live_rank","theater_daily_brief","theater_day_report_compose",
                  "daily_apply_integrity_gate","theater_readiness_board","fleet_weather_mission_package",
                  "assault_readiness_compose","campaign_day_risk","move_path_ops_loop",
                  "theater_order_board","theater_campaign_strip","execution_integrity_gate",
                  "basing_fleet_fuel_logistics","basing_repair_weather_loop","fleet_order_execute",
                  "convoy_package_compose","sealane_joint_health","naval_order_package",
                  "fleet_station_mutation","player_order_surface_strip","order_panel_actions_compose",
                  "next_day_mutation_feedback","mutation_decision_strip","day_package_apply_audit",
                  "campaign_decision_strip","execution_decision_strip","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func multi_province_campaign_day"):sec.find("static func multi_province_campaign_day")+700]
        self.assertIn("multi_province_live_rank", body)
        self.assertNotIn("var score := 0.55", body)
        basing = sec[sec.find("static func basing_fleet_sustain_day"):sec.find("static func basing_fleet_sustain_day")+700]
        self.assertIn("basing_fleet_fuel_logistics", basing)
        player = sec[sec.find("static func player_surface_session_day"):sec.find("static func player_surface_session_day")+700]
        self.assertIn("player_order_surface_strip", player)
        self.assertIn("_next160_live_day", mm)
        self.assertIn("rank_score", mm)
        self.assertIn("logistics_score", mm)
        self.assertIn("joint_score", mm)
        self.assertIn("panel_action_count", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in THEATER_NAVAL_SESSION_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("multi_province_campaign_day","basing_fleet_sustain_day","player_surface_session_day","theater_naval_session_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_theater_naval_session_days.py", CI.read_text())
        labels = [
            "multi province campaign day","theater auto campaign day","daily command ops day","theater readiness ops day",
            "move path campaign day","theater order board day","theater campaign close day",
            "basing fleet sustain day","fleet wx sustain day","convoy sustain ops day",
            "sealane joint ops day","naval order ops day","fleet station sustain day","naval sealane close day",
            "player surface session day","order panel session day","mutation feedback ops day",
            "apply audit session day","decision strip ops day","theater naval session close day","next-160 theater",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
