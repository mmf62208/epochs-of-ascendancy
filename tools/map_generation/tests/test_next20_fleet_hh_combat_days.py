#!/usr/bin/env python3
"""Gates: next-130 fleet/HH/combat loops (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next130_fleet_hh_combat import (
    FLEET_HH_COMBAT_DAY_IDS, DAY_FUNCS, close_next130_fleet_hh_combat_loop,
    fleet_hh_combat_integrity, fleet_ai_task_day, hh_order_path_day,
    combat_inspect_stack_day, fleet_hh_combat_close_day,
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
    "fleet_ai_task_day","fleet_wx_ops_day","fleet_station_mut_day","naval_task_mut_day",
    "hh_agenda_pick_day","hh_agenda_actions_day","hh_order_path_day","theater_hh_path_day",
    "hh_trail_ops_day","agent_mission_ops_day","agent_campaign_ops_day",
    "combat_inspect_stack_day","fleet_hh_combat_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(FLEET_HH_COMBAT_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        f = fleet_ai_task_day()
        self.assertIn("task_group", f)
        h = hh_order_path_day()
        self.assertIn("order", h)
        c = combat_inspect_stack_day()
        self.assertIn("estimate", c)
        self.assertIn("card", c)
        cl = fleet_hh_combat_close_day()
        self.assertTrue(cl.get("ok") or cl.get("gate"))
    def test_close(self):
        loop = close_next130_fleet_hh_combat_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty",0)), 20)
        self.assertTrue(fleet_hh_combat_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (fleet / HH / combat)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("compose_fleet_task_group","fleet_weather_mission_package","basing_fleet_fuel_logistics",
                  "estimate_naval_multi_phase","fleet_station_mutation","hh_order_commit",
                  "agent_campaign_response","estimate_multi_phase_combat","joint_combat_timeline",
                  "rank_assault_targets","multi_phase_combat_ui_product"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func fleet_ai_task_day"):sec.find("static func fleet_ai_task_day")+700]
        self.assertIn("compose_fleet_task_group", body)
        self.assertNotIn("var score := 0.55", body)
        hh = sec[sec.find("static func hh_order_path_day"):sec.find("static func hh_order_path_day")+700]
        self.assertIn("hh_order_commit", hh)
        combat = sec[sec.find("static func combat_inspect_stack_day"):sec.find("static func combat_inspect_stack_day")+800]
        self.assertIn("estimate_multi_phase_combat", combat)
        self.assertIn("_next130_live_day", mm)
        self.assertIn("primary_role", mm)
        self.assertIn("hh_order", mm)
        self.assertIn("win_chance", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in FLEET_HH_COMBAT_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("fleet_ai_task_day","hh_order_path_day","combat_inspect_stack_day","fleet_hh_combat_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_fleet_hh_combat_days.py", CI.read_text())
        labels = [
            "fleet ai task day","fleet wx ops day","basing fuel ops day","naval phase ops day",
            "coastal fog ops day","fleet station mut day","naval task mut day",
            "hh agenda pick day","hh agenda actions day","hh order path day","theater hh path day",
            "hh trail ops day","agent mission ops day","agent campaign ops day",
            "combat inspect stack day","phase ribbon inspect day","joint timeline inspect day",
            "assault rank inspect day","combat campaign ops day","fleet hh combat close day",
            "next-130 fleet",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
