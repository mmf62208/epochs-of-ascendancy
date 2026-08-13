#!/usr/bin/env python3
"""Gates: next-210 assault/choke/agent (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next210_assault_choke_agent import (
    ASSAULT_CHOKE_AGENT_DAY_IDS, DAY_FUNCS, close_next210_assault_choke_agent_loop,
    assault_choke_agent_integrity, follow_on_assault_ops_day, reinforced_combat_ops_day,
    war_path_urgency_ops_day, choke_sea_wx_ops_day, agent_escalation_ops_day,
    assault_choke_agent_close_day,
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
 "follow_on_assault_ops_day","reinforced_combat_ops_day","war_path_urgency_ops_day",
 "follow_reinforce_close_day","choke_sea_wx_ops_day","basing_choke_ops_day",
 "choke_control_ops_day","choke_sea_close_day","agent_escalation_ops_day",
 "coverage_ops_day","counter_ops_board_ops_day","assault_choke_agent_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(ASSAULT_CHOKE_AGENT_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        f = follow_on_assault_ops_day()
        self.assertIn("follow_on", f)
        self.assertGreater(float(f.get("score", 0)), 0.2)
        r = reinforced_combat_ops_day()
        self.assertIn("reinforced", r)
        w = war_path_urgency_ops_day()
        self.assertIn("war_path", w)
        self.assertGreater(float(w.get("score", 0)), 0.0)
        c = choke_sea_wx_ops_day()
        self.assertIn("package", c)
        a = agent_escalation_ops_day()
        self.assertIn("escalation", a)
        close = assault_choke_agent_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next210_assault_choke_agent_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(assault_choke_agent_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (assault / choke / agent)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("assault_follow_on_loop","reinforced_assault_loop","war_path_urgency",
                  "assault_readiness_compose","estimate_multi_phase_combat",
                  "choke_sea_weather_package","choke_weather_synergy","sea_zone_strategic_modifiers",
                  "basing_fleet_fuel_logistics","choke_basing_synergy_score",
                  "plan_agent_escalation","plan_agent_coverage","counter_ops_board",
                  "counter_ops_execute_order","execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func follow_on_assault_ops_day"):sec.find("static func follow_on_assault_ops_day")+900]
        self.assertIn("assault_follow_on_loop", body)
        self.assertNotIn("var score := 0.55", body)
        reinf = sec[sec.find("static func reinforced_combat_ops_day"):sec.find("static func reinforced_combat_ops_day")+900]
        self.assertIn("reinforced_assault_loop", reinf)
        choke = sec[sec.find("static func choke_sea_wx_ops_day"):sec.find("static func choke_sea_wx_ops_day")+700]
        self.assertIn("choke_sea_weather_package", choke)
        agent = sec[sec.find("static func agent_escalation_ops_day"):sec.find("static func agent_escalation_ops_day")+700]
        self.assertIn("plan_agent_escalation", agent)
        for aid in ASSAULT_CHOKE_AGENT_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next210_live_day", mm)
        self.assertIn("win_chance", mm)
        self.assertIn("urgency", mm)
        self.assertIn("choke_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in ASSAULT_CHOKE_AGENT_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        # Section must be defined (not only called) — missing body is a Godot parse/load failure.
        self.assertIn("func _rebuild_assault_choke_agent_section", panel)
        self.assertIn("— Next-210 assault/choke/agent (20) —", panel)
        self.assertIn("format_assault_choke_agent_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_assault_choke_agent_section"), 2)
        # Avoid class_name.has_method() which is a Godot 4 parse error on static class_names.
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("follow_on_assault_ops_day","choke_sea_wx_ops_day","agent_escalation_ops_day","assault_choke_agent_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_assault_choke_agent_days.py", CI.read_text())
        labels = [
            "follow on assault ops day","reinforced combat ops day","war path urgency ops day",
            "assault follow ops day","reinforce step ops day","combat urgency ops day","follow reinforce close day",
            "choke sea wx ops day","sea zone mod ops day","basing choke ops day","choke control ops day",
            "sea zone control ops day","choke basing joint day","choke sea close day",
            "agent escalation ops day","coverage ops day","counter ops board ops day",
            "escalation ladder ops day","agent coverage joint day","assault choke agent close day",
            "next-210 assault",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
