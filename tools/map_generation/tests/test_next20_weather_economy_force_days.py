#!/usr/bin/env python3
"""Gates: next-280 weather/economy/force (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next280_weather_economy_force import (
    WEATHER_ECONOMY_FORCE_DAY_IDS, DAY_FUNCS, close_next280_weather_economy_force_loop,
    weather_economy_force_integrity, weather_pressure_depth_day, war_economy_sustain_day,
    force_ready_surface_day, weather_economy_force_close_day,
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
 "weather_pressure_depth_day","foul_combat_ops_day","weather_crisis_depth_day","weather_ops_close_depth_day",
 "trade_pressure_depth_day","war_economy_sustain_day","trade_sealane_joint_day","war_economy_close_depth_day",
 "force_ready_surface_day","formation_equip_depth_day","force_reinforce_joint_day","weather_economy_force_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(WEATHER_ECONOMY_FORCE_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        w = weather_pressure_depth_day()
        self.assertIn("pressure", w)
        self.assertGreater(float(w.get("weather_score", w.get("score", 0))), 0.1)
        e = war_economy_sustain_day()
        self.assertIn("economy", e)
        self.assertGreater(float(e.get("economy_score", e.get("score", 0))), 0.1)
        f = force_ready_surface_day()
        self.assertIn("readiness", f)
        c = weather_economy_force_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next280_weather_economy_force_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(weather_economy_force_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (weather pressure / war-economy / force readiness)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("weather_pressure_index","campaign_day_risk","weather_crisis_day","move_path_ops_loop",
                  "estimate_multi_phase_combat","supply_route_mutation","sealane_joint_health",
                  "war_economy_day_package","production_priority_mutation","convoy_package_compose",
                  "force_readiness_day","theater_readiness_day","medium_horizon_equip_plan",
                  "theater_readiness_board","reinforced_assault_loop","execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func weather_pressure_depth_day"):sec.find("static func weather_pressure_depth_day")+900]
        self.assertIn("weather_pressure_index", body)
        self.assertNotIn("var score := 0.55", body)
        econ = sec[sec.find("static func war_economy_sustain_day"):sec.find("static func war_economy_sustain_day")+700]
        self.assertIn("war_economy_day_package", econ)
        force = sec[sec.find("static func force_ready_surface_day"):sec.find("static func force_ready_surface_day")+700]
        self.assertIn("force_readiness_day", force)
        for aid in WEATHER_ECONOMY_FORCE_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next280_live_day", mm)
        self.assertIn("weather_score", mm)
        self.assertIn("economy_score", mm)
        self.assertIn("force_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in WEATHER_ECONOMY_FORCE_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_weather_economy_force_section", panel)
        self.assertIn("— Next-280 weather/economy/force (20) —", panel)
        self.assertIn("format_weather_economy_force_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_weather_economy_force_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("weather_pressure_depth_day","war_economy_sustain_day","force_ready_surface_day","weather_economy_force_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_weather_economy_force_days.py", CI.read_text())
        labels = [
            "weather pressure depth day","foul combat ops day","weather logistics depth day","weather move depth day",
            "weather crisis depth day","weather pressure joint day","weather ops close depth day",
            "trade pressure depth day","sealane health depth day","war economy sustain day","stockpile economy depth day",
            "convoy economy joint day","trade sealane joint day","war economy close depth day",
            "force ready surface day","formation equip depth day","reinforce stockpile depth day",
            "readiness board ops day","force reinforce joint day","weather economy force close day","next-280 weather",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
