#!/usr/bin/env python3
"""Gates: next-250 leader/intel/theater (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next250_leader_intel_theater import (
    LEADER_INTEL_THEATER_DAY_IDS, DAY_FUNCS, close_next250_leader_intel_theater_loop,
    leader_intel_theater_integrity, leader_assign_depth_day, intel_counter_depth_day,
    theater_daily_depth_day, leader_intel_theater_close_day,
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
 "leader_assign_depth_day","formation_ready_depth_day","leader_formation_joint_depth_day","leader_formation_close_depth_day",
 "intel_counter_depth_day","agent_response_depth_day","intel_counter_close_day",
 "theater_daily_depth_day","multi_province_rank_depth_day","multi_province_command_day","leader_intel_theater_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(LEADER_INTEL_THEATER_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        l = leader_assign_depth_day()
        self.assertIn("assign", l)
        self.assertGreater(float(l.get("leader_score", l.get("score", 0))), 0.1)
        i = intel_counter_depth_day()
        self.assertIn("board", i)
        t = theater_daily_depth_day()
        self.assertIn("brief", t)
        c = leader_intel_theater_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next250_leader_intel_theater_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(leader_intel_theater_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (leader / intel / theater)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("leader_campaign_assign","leader_weather_assign","leader_formation_station_day",
                  "medium_horizon_equip_plan","counter_ops_board","counter_ops_execute_order",
                  "agent_response_day","plan_agent_escalation","plan_agent_coverage",
                  "theater_daily_brief","multi_province_live_rank","execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func leader_assign_depth_day"):sec.find("static func leader_assign_depth_day")+900]
        self.assertIn("leader_campaign_assign", body)
        self.assertNotIn("var score := 0.55", body)
        intel = sec[sec.find("static func intel_counter_depth_day"):sec.find("static func intel_counter_depth_day")+700]
        self.assertIn("counter_ops_board", intel)
        th = sec[sec.find("static func theater_daily_depth_day"):sec.find("static func theater_daily_depth_day")+700]
        self.assertIn("theater_daily_brief", th)
        for aid in LEADER_INTEL_THEATER_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next250_live_day", mm)
        self.assertIn("leader_score", mm)
        self.assertIn("intel_score", mm)
        self.assertIn("theater_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in LEADER_INTEL_THEATER_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_leader_intel_theater_section", panel)
        self.assertIn("— Next-250 leader/intel/theater (20) —", panel)
        self.assertIn("format_leader_intel_theater_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_leader_intel_theater_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("leader_assign_depth_day","intel_counter_depth_day","theater_daily_depth_day","leader_intel_theater_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_leader_intel_theater_days.py", CI.read_text())
        labels = [
            "leader assign depth day","formation ready depth day","leader weather depth day","formation station depth day",
            "leader formation joint depth day","oob leader ops day","leader formation close depth day",
            "intel counter depth day","hh counterplay depth day","agent response depth day","trail intel ops day",
            "counterintel board ops day","intel response joint day","intel counter close day",
            "theater daily depth day","multi province rank depth day","daily auto depth day","theater brief ops day",
            "multi province command day","leader intel theater close day","next-250 leader",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
