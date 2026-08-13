#!/usr/bin/env python3
"""Gates: next-220 OOB/fleet/HH (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next220_oob_fleet_hh import (
    OOB_FLEET_HH_DAY_IDS, DAY_FUNCS, close_next220_oob_fleet_hh_loop,
    oob_fleet_hh_integrity, equip_horizon_depth_day, fleet_multi_theater_ops_day,
    hh_monthly_ops_day, oob_fleet_hh_close_day, medium_horizon_plan_day,
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
 "equip_horizon_depth_day","oob_line_continuity_day","medium_horizon_plan_day","equip_oob_close_day",
 "fleet_multi_theater_ops_day","fleet_redeploy_ops_day","fleet_redeploy_close_day",
 "hh_monthly_ops_day","hh_quarterly_ops_day","agenda_pulse_ops_day","oob_fleet_hh_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(OOB_FLEET_HH_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        e = equip_horizon_depth_day()
        self.assertIn("equip", e)
        self.assertGreater(float(e.get("equip_score", e.get("score", 0))), 0.2)
        m = medium_horizon_plan_day()
        self.assertIn("horizon_days", m)
        f = fleet_multi_theater_ops_day()
        self.assertIn("multi", f)
        h = hh_monthly_ops_day()
        self.assertIn("monthly", h)
        c = oob_fleet_hh_close_day()
        self.assertTrue(c.get("ok") or c.get("gate"))
    def test_close(self):
        loop = close_next220_oob_fleet_hh_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(oob_fleet_hh_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (oob / fleet / hh)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("medium_horizon_equip_plan","oob_factory_risk_loop","production_priority_mutation",
                  "fleet_multi_theater_day","fleet_redeploy_day","plan_fleet_redeploy_routes",
                  "compose_fleet_task_group","hh_agenda_product_screen","hh_campaign_board","hh_order_commit",
                  "execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func equip_horizon_depth_day"):sec.find("static func equip_horizon_depth_day")+900]
        self.assertIn("medium_horizon_equip_plan", body)
        self.assertNotIn("var score := 0.55", body)
        fleet = sec[sec.find("static func fleet_multi_theater_ops_day"):sec.find("static func fleet_multi_theater_ops_day")+900]
        self.assertIn("fleet_multi_theater_day", fleet)
        hh = sec[sec.find("static func hh_monthly_ops_day"):sec.find("static func hh_monthly_ops_day")+900]
        self.assertIn("hh_agenda_product_screen", hh)
        for aid in OOB_FLEET_HH_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next220_live_day", mm)
        self.assertIn("equip_score", mm)
        self.assertIn("fleet_score", mm)
        self.assertIn("hh_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in OOB_FLEET_HH_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        # Section must be defined (not only called)
        self.assertIn("func _rebuild_oob_fleet_hh_section", panel)
        self.assertIn("— Next-220 oob/fleet/hh (20) —", panel)
        self.assertIn("format_oob_fleet_hh_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_oob_fleet_hh_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("equip_horizon_depth_day","fleet_multi_theater_ops_day","hh_monthly_ops_day","oob_fleet_hh_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_oob_fleet_hh_days.py", CI.read_text())
        labels = [
            "equip horizon depth day","stockpile line ops day","oob line continuity day","factory oob depth day",
            "medium horizon plan day","equip stockpile joint day","equip oob close day",
            "fleet multi theater ops day","fleet redeploy ops day","task group posture ops day","fleet posture ops day",
            "redeploy route ops day","fleet theater joint day","fleet redeploy close day",
            "hh monthly ops day","hh quarterly ops day","agenda pulse ops day","trail counterplay ops day",
            "hh agenda depth joint day","oob fleet hh close day","next-220 oob",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
