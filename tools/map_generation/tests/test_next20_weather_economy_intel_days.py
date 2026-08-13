#!/usr/bin/env python3
"""Gates: next-150 weather/economy/intel (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next150_weather_economy_intel import (
    WEATHER_ECONOMY_INTEL_DAY_IDS, DAY_FUNCS, close_next150_weather_economy_intel_loop,
    weather_economy_intel_integrity, combat_wx_ops_day, prod_wx_ops_day,
    convoy_wx_ops_day, war_economy_ops_day, focus_wx_ops_day,
    intel_counter_ops_day, weather_economy_intel_close_day,
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
 "combat_wx_ops_day","prod_wx_ops_day","convoy_wx_ops_day","weather_ops_close_day",
 "war_economy_ops_day","focus_wx_ops_day","war_economy_close_day",
 "intel_counter_ops_day","agent_intel_ops_day","weather_economy_intel_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(WEATHER_ECONOMY_INTEL_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        c = combat_wx_ops_day()
        self.assertIn("mult", c)
        self.assertIn("estimate", c)
        p = prod_wx_ops_day()
        self.assertIn("mult", p)
        self.assertIn("mutation", p)
        v = convoy_wx_ops_day()
        self.assertIn("window", v)
        w = war_economy_ops_day()
        self.assertIn("production", w)
        f = focus_wx_ops_day()
        self.assertIn("focus", f)
        i = intel_counter_ops_day()
        self.assertIn("counter", i)
        close = weather_economy_intel_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next150_weather_economy_intel_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(weather_economy_intel_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (weather / economy / intel)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("weather_combat_multiplier","estimate_multi_phase_combat","weather_production_multiplier",
                  "production_weather_alert","air_sortie_weather_readiness","combat_morale_weather",
                  "convoy_weather_window","fleet_weather_mission_package","daylight_combat_mod",
                  "campaign_day_risk","coastal_fog_naval_gate","war_economy_day_package",
                  "production_priority_mutation","supply_route_mutation","production_campaign_risk",
                  "focus_weather_aware_score","sole_mult_integrity","depot_weather_capacity",
                  "execution_integrity_gate","intel_counter_day","counter_ops_execute_order",
                  "rank_agent_missions","agent_campaign_response","hh_agenda_player_path",
                  "map_effect_resolve","assault_readiness_compose","next_day_mutation_feedback",
                  "cohesion_integrity_gate"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func combat_wx_ops_day"):sec.find("static func combat_wx_ops_day")+700]
        self.assertIn("weather_combat_multiplier", body)
        self.assertNotIn("var score := 0.55", body)
        we = sec[sec.find("static func war_economy_ops_day"):sec.find("static func war_economy_ops_day")+700]
        self.assertIn("war_economy_day_package", we)
        intel = sec[sec.find("static func intel_counter_ops_day"):sec.find("static func intel_counter_ops_day")+700]
        self.assertIn("intel_counter_day", intel)
        self.assertIn("_next150_live_day", mm)
        self.assertIn("combat_mult", mm)
        self.assertIn("economy_score", mm)
        self.assertIn("counter_score", mm)
        self.assertIn("window_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in WEATHER_ECONOMY_INTEL_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("combat_wx_ops_day","war_economy_ops_day","intel_counter_ops_day","weather_economy_intel_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_weather_economy_intel_days.py", CI.read_text())
        labels = [
            "combat wx ops day","prod wx ops day","air sortie wx day","morale wx ops day",
            "convoy wx ops day","daylight wx ops day","weather ops close day",
            "war economy ops day","prod campaign ops day","focus wx ops day",
            "focus mut ops day","supply economy ops day","depot economy ops day",
            "war economy close day","intel counter ops day","agent intel ops day",
            "hh counter ops day","map effect ops day","coherence intel day",
            "weather economy intel close day","next-150 weather",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
