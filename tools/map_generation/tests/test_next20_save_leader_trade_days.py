#!/usr/bin/env python3
"""Gates: next-190 save/leader/trade (20) + GIS×753 + composed GD wiring."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next190_save_leader_trade import (
    SAVE_LEADER_TRADE_DAY_IDS, DAY_FUNCS, close_next190_save_leader_trade_loop,
    save_leader_trade_integrity, save_slot_integrity_ops_day, leader_assign_ops_day,
    trade_chain_ops_day, save_leader_trade_close_day, convoy_escort_ops_day,
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
 "save_slot_integrity_ops_day","autosave_session_ops_day","save_session_close_day",
 "leader_assign_ops_day","formation_ready_ops_day","leader_formation_close_day",
 "trade_chain_ops_day","convoy_escort_ops_day","sealane_economy_ops_day","save_leader_trade_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(SAVE_LEADER_TRADE_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        s = save_slot_integrity_ops_day()
        self.assertIn("package", s)
        l = leader_assign_ops_day()
        self.assertIn("assign", l)
        t = trade_chain_ops_day()
        self.assertIn("joint", t)
        c = convoy_escort_ops_day()
        self.assertIn("plan", c)
        close = save_leader_trade_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next190_save_leader_trade_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(save_leader_trade_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (save / leader / trade)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("save_slot_browser_day","save_slot_browser_flair","execution_integrity_gate",
                  "leader_campaign_assign","leader_weather_assign","medium_horizon_equip_plan",
                  "leader_formation_station_day","trade_supply_weather_chain","supply_route_mutation",
                  "convoy_package_compose","convoy_weather_window","sealane_joint_health",
                  "sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func save_slot_integrity_ops_day"):sec.find("static func save_slot_integrity_ops_day")+700]
        self.assertIn("save_slot_browser_day", body)
        self.assertNotIn("var score := 0.55", body)
        leader = sec[sec.find("static func leader_assign_ops_day"):sec.find("static func leader_assign_ops_day")+700]
        self.assertIn("leader_campaign_assign", leader)
        trade = sec[sec.find("static func trade_chain_ops_day"):sec.find("static func trade_chain_ops_day")+700]
        self.assertIn("trade_supply_weather_chain", trade)
        for aid in SAVE_LEADER_TRADE_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next190_live_day", mm)
        self.assertIn("slot_ok", mm)
        self.assertIn("leader_score", mm)
        self.assertIn("trade_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in SAVE_LEADER_TRADE_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        for key in ("save_slot_integrity_ops_day","leader_assign_ops_day","trade_chain_ops_day","save_leader_trade_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_save_leader_trade_days.py", CI.read_text())
        labels = [
            "save slot integrity ops day","autosave session ops day","campaign session ops day","save resume ops day",
            "session checkpoint ops day","save audit ops day","save session close day",
            "leader assign ops day","formation ready ops day","oob assign ops day","leader command ops day",
            "formation station ops day","leader formation joint day","leader formation close day",
            "trade chain ops day","convoy escort ops day","sealane economy ops day","trade route ops day",
            "convoy trade joint day","save leader trade close day","next-190 save",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
