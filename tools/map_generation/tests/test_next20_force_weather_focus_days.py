#!/usr/bin/env python3
"""Gates: next-230 force/weather/focus (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next230_force_weather_focus import (
    FORCE_WEATHER_FOCUS_DAY_IDS, DAY_FUNCS, close_next230_force_weather_focus_loop,
    force_weather_focus_integrity, force_readiness_depth_day, weather_pressure_ops_day,
    focus_war_path_ops_day, force_weather_focus_close_day, multi_front_supply_depth_day,
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
 "force_readiness_depth_day","multi_front_supply_depth_day","force_posture_depth_day","force_supply_close_day",
 "weather_pressure_ops_day","campaign_crisis_ops_day","weather_crisis_close_day",
 "focus_war_path_ops_day","strategic_continuity_depth_day","war_cabinet_pulse_ops_day","force_weather_focus_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(FORCE_WEATHER_FOCUS_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        f = force_readiness_depth_day()
        self.assertIn("posture", f)
        self.assertGreater(float(f.get("posture_score", f.get("score", 0))), 0.1)
        m = multi_front_supply_depth_day()
        self.assertIn("plan", m)
        w = weather_pressure_ops_day()
        self.assertIn("pressure", w)
        foc = focus_war_path_ops_day()
        self.assertIn("board", foc)
        c = force_weather_focus_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next230_force_weather_focus_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(force_weather_focus_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (force / weather / focus)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("force_supply_posture","force_posture_board","multi_province_live_rank",
                  "depot_weather_capacity","weather_pressure_index","campaign_day_risk",
                  "weather_crisis_day","production_campaign_risk","focus_war_path_board",
                  "war_path_urgency","plan_agent_escalation","rank_assault_targets",
                  "execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func force_readiness_depth_day"):sec.find("static func force_readiness_depth_day")+900]
        self.assertIn("force_supply_posture", body)
        self.assertNotIn("var score := 0.55", body)
        wx = sec[sec.find("static func weather_pressure_ops_day"):sec.find("static func weather_pressure_ops_day")+700]
        self.assertIn("weather_pressure_index", wx)
        foc = sec[sec.find("static func focus_war_path_ops_day"):sec.find("static func focus_war_path_ops_day")+800]
        self.assertIn("focus_war_path_board", foc)
        for aid in FORCE_WEATHER_FOCUS_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next230_live_day", mm)
        self.assertIn("posture_score", mm)
        self.assertIn("weather_score", mm)
        self.assertIn("focus_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in FORCE_WEATHER_FOCUS_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_force_weather_focus_section", panel)
        self.assertIn("— Next-230 force/weather/focus (20) —", panel)
        self.assertIn("format_force_weather_focus_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_force_weather_focus_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("force_readiness_depth_day","weather_pressure_ops_day","focus_war_path_ops_day","force_weather_focus_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_force_weather_focus_days.py", CI.read_text())
        labels = [
            "force readiness depth day","multi front supply depth day","depot route ops day","force posture depth day",
            "front supply rank day","force supply joint day","force supply close day",
            "weather pressure ops day","campaign crisis ops day","prod weather crisis day","combat weather ops day",
            "weather crisis brief day","weather campaign joint day","weather crisis close day",
            "focus war path ops day","strategic strip depth day","strategic continuity depth day",
            "war cabinet pulse ops day","focus continuity joint day","force weather focus close day","next-230 force",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
