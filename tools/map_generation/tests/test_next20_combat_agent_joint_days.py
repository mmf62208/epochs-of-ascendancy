#!/usr/bin/env python3
"""Gates: next-170 combat/agent/joint (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next170_combat_agent_joint import (
    COMBAT_AGENT_JOINT_DAY_IDS, DAY_FUNCS, close_next170_combat_agent_joint_loop,
    combat_agent_joint_integrity, combat_phase_ops_day, agent_mission_campaign_day,
    joint_command_ops_day, combat_agent_joint_close_day, multi_phase_est_ops_day,
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
 "combat_phase_ops_day","assault_ready_ops_day","multi_phase_est_ops_day",
 "combat_phase_close_day","agent_mission_campaign_day","counterplay_campaign_day",
 "agent_hh_close_day","joint_theater_combat_day","joint_naval_combat_day",
 "joint_command_ops_day","combat_agent_joint_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(COMBAT_AGENT_JOINT_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        c = combat_phase_ops_day()
        self.assertIn("estimate", c)
        self.assertIn("win_chance", c)
        m = multi_phase_est_ops_day()
        self.assertIn("estimate", m)
        a = agent_mission_campaign_day()
        self.assertIn("missions", a)
        j = joint_command_ops_day()
        self.assertIn("joint", j)
        close = combat_agent_joint_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next170_combat_agent_joint_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(combat_agent_joint_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (combat / agent / joint)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("estimate_multi_phase_combat","combat_campaign_phase","combat_phase_depth_score",
                  "assault_readiness_compose","multi_phase_combat_ui_product","assault_stage_mutation",
                  "execution_integrity_gate","rank_agent_missions","agent_campaign_response",
                  "hh_commit_mutation","hh_agenda_player_path","intel_counter_day",
                  "counter_ops_execute_order","theater_campaign_strip","theater_order_board",
                  "combat_air_naval_joint","naval_order_package","focus_weather_aware_score",
                  "joint_command_day","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func combat_phase_ops_day"):sec.find("static func combat_phase_ops_day")+700]
        self.assertIn("estimate_multi_phase_combat", body)
        self.assertNotIn("var score := 0.55", body)
        agent = sec[sec.find("static func agent_mission_campaign_day"):sec.find("static func agent_mission_campaign_day")+700]
        self.assertIn("rank_agent_missions", agent)
        joint = sec[sec.find("static func joint_command_ops_day"):sec.find("static func joint_command_ops_day")+700]
        self.assertIn("joint_command_day", joint)
        self.assertIn("_next170_live_day", mm)
        self.assertIn("win_chance", mm)
        self.assertIn("agent_score", mm)
        self.assertIn("joint_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in COMBAT_AGENT_JOINT_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("combat_phase_ops_day","agent_mission_campaign_day","joint_command_ops_day","combat_agent_joint_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_combat_agent_joint_days.py", CI.read_text())
        labels = [
            "combat phase ops day","assault ready ops day","multi phase est ops day","combat order ops day",
            "assault rank ops day","phase ribbon ops day","combat phase close day",
            "agent mission campaign day","agent dispatch ops day","hh commit campaign day","counterplay campaign day",
            "hh agenda ops day","agent hh joint day","agent hh close day","joint theater combat day",
            "joint naval combat day","focus joint ops day","joint command ops day","multi domain strip day",
            "combat agent joint close day","next-170 combat",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
