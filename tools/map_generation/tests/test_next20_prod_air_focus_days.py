#!/usr/bin/env python3
"""Gates: next-180 production/air/focus (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next180_prod_air_focus import (
    PROD_AIR_FOCUS_DAY_IDS, DAY_FUNCS, close_next180_prod_air_focus_loop,
    prod_air_focus_integrity, prod_factory_risk_ops_day, medium_equip_horizon_ops_day,
    air_sortie_front_ops_day, focus_path_ops_day, prod_air_focus_close_day,
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
 "prod_factory_risk_ops_day","medium_equip_horizon_ops_day","production_priority_ops_day",
 "production_oob_close_day","air_sortie_front_ops_day","multi_front_rank_ops_day",
 "air_land_joint_ops_day","air_front_close_day","focus_path_ops_day","war_cabinet_ops_day",
 "prod_air_focus_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(PROD_AIR_FOCUS_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        f = prod_factory_risk_ops_day()
        self.assertIn("loop", f)
        e = medium_equip_horizon_ops_day()
        self.assertIn("equip", e)
        a = air_sortie_front_ops_day()
        self.assertIn("readiness", a)
        p = focus_path_ops_day()
        self.assertIn("path", p)
        c = prod_air_focus_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next180_prod_air_focus_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(prod_air_focus_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (production / air / focus)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("oob_factory_risk_loop","production_campaign_risk","medium_horizon_equip_plan",
                  "production_priority_mutation","production_order_resolve","execution_integrity_gate",
                  "air_sortie_weather_readiness","rank_assault_targets","air_land_joint_package",
                  "air_land_order_package","assault_readiness_compose","air_forecast_assault_day",
                  "supply_route_mutation","focus_order_path","focus_weather_aware_score",
                  "war_cabinet_day","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func prod_factory_risk_ops_day"):sec.find("static func prod_factory_risk_ops_day")+700]
        self.assertIn("oob_factory_risk_loop", body)
        self.assertNotIn("var score := 0.55", body)
        equip = sec[sec.find("static func medium_equip_horizon_ops_day"):sec.find("static func medium_equip_horizon_ops_day")+700]
        self.assertIn("medium_horizon_equip_plan", equip)
        air = sec[sec.find("static func air_sortie_front_ops_day"):sec.find("static func air_sortie_front_ops_day")+700]
        self.assertIn("air_sortie_weather_readiness", air)
        focus = sec[sec.find("static func focus_path_ops_day"):sec.find("static func focus_path_ops_day")+700]
        self.assertIn("focus_order_path", focus)
        # no name collisions for new packages
        for aid in PROD_AIR_FOCUS_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next180_live_day", mm)
        self.assertIn("equip_score", mm)
        self.assertIn("sortie_score", mm)
        self.assertIn("focus_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in PROD_AIR_FOCUS_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("prod_factory_risk_ops_day","air_sortie_front_ops_day","focus_path_ops_day","prod_air_focus_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_prod_air_focus_days.py", CI.read_text())
        labels = [
            "prod factory risk ops day","medium equip horizon ops day","production priority ops day","oob equip continuity day",
            "factory line ops day","stockpile growth ops day","production oob close day",
            "air sortie front ops day","multi front rank ops day","air land joint ops day","assault front ops day",
            "air forecast ops day","multi front supply ops day","air front close day",
            "focus path ops day","war cabinet ops day","strategic strip ops day","focus priority ops day",
            "strategic continuity ops day","prod air focus close day","next-180 production",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
