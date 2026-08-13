#!/usr/bin/env python3
"""Gates: next-140 logistics/force/panel (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next140_logistics_force_panel import (
    LOGISTICS_FORCE_PANEL_DAY_IDS, DAY_FUNCS, close_next140_logistics_force_panel_loop,
    logistics_force_panel_integrity, depot_logistics_day, force_readiness_ops_day,
    order_panel_ops_day, logistics_force_panel_close_day, medium_equip_ops_day,
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
 "depot_logistics_day","supply_route_ops_day","theater_auto_tick_day","force_readiness_ops_day",
 "oob_factory_ops_day","medium_equip_ops_day","player_surface_ops_day","order_panel_ops_day",
 "panel_sections_ops_day","logistics_force_panel_close_day","force_oob_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(LOGISTICS_FORCE_PANEL_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        d = depot_logistics_day()
        self.assertIn("depot", d)
        f = force_readiness_ops_day()
        self.assertIn("equip", f)
        e = medium_equip_ops_day()
        self.assertIn("equip", e)
        p = order_panel_ops_day()
        self.assertIn("primary", p)
        c = logistics_force_panel_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next140_logistics_force_panel_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(logistics_force_panel_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (logistics / force / panel)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("depot_weather_capacity","supply_route_mutation","move_path_ops_loop",
                  "oob_factory_risk_loop","medium_horizon_equip_plan","order_panel_actions_compose",
                  "player_order_surface_strip","tooltip_sfx_flair_strip","execution_integrity_gate",
                  "day_package_apply_audit"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func depot_logistics_day"):sec.find("static func depot_logistics_day")+700]
        self.assertIn("depot_weather_capacity", body)
        self.assertNotIn("var score := 0.55", body)
        equip = sec[sec.find("static func medium_equip_ops_day"):sec.find("static func medium_equip_ops_day")+700]
        self.assertIn("medium_horizon_equip_plan", equip)
        panel = sec[sec.find("static func order_panel_ops_day"):sec.find("static func order_panel_ops_day")+700]
        self.assertIn("order_panel_actions_compose", panel)
        self.assertIn("_next140_live_day", mm)
        self.assertIn("equip_score", mm)
        self.assertIn("panel_action_count", mm)
        self.assertIn("depot_capacity", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in LOGISTICS_FORCE_PANEL_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("depot_logistics_day","force_readiness_ops_day","order_panel_ops_day","logistics_force_panel_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_logistics_force_panel_days.py", CI.read_text())
        labels = [
            "depot logistics day","supply route ops day","move path ops day","multi province ops day",
            "theater auto tick day","daily supply ops day","logistics theater close day",
            "force readiness ops day","oob factory ops day","medium equip ops day","naval skim ops day",
            "basing logistics ops day","production force ops day","force oob close day",
            "player surface ops day","order panel ops day","panel sections ops day","tooltip flair ops day",
            "apply audit ops day","logistics force panel close day","next-140 logistics",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
