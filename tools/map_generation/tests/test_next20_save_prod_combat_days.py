#!/usr/bin/env python3
"""Gates: next-260 save/prod/combat (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next260_save_prod_combat import (
    SAVE_PROD_COMBAT_DAY_IDS, DAY_FUNCS, close_next260_save_prod_combat_loop,
    save_prod_combat_integrity, save_slot_depth_day, production_priority_depth_day,
    multi_phase_estimate_depth_day, save_prod_combat_close_day,
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
 "save_slot_depth_day","campaign_session_depth_day","save_session_close_depth_day",
 "factory_risk_surge_day","production_priority_depth_day","industry_surge_joint_day","production_surge_close_day",
 "multi_phase_estimate_depth_day","assault_ready_surface_day","multi_phase_joint_day","save_prod_combat_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(SAVE_PROD_COMBAT_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        s = save_slot_depth_day()
        self.assertIn("package", s)
        self.assertGreater(float(s.get("save_score", s.get("score", 0))), 0.1)
        p = production_priority_depth_day()
        self.assertIn("mutation", p)
        self.assertGreater(float(p.get("prod_score", p.get("score", 0))), 0.1)
        c = multi_phase_estimate_depth_day()
        self.assertIn("estimate", c)
        close = save_prod_combat_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next260_save_prod_combat_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(save_prod_combat_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (save / production / combat)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("save_slot_browser_day","save_slot_browser_flair","execution_integrity_gate","sole_mult_integrity",
                  "production_priority_mutation","production_order_resolve","oob_factory_risk_loop",
                  "production_campaign_risk","factory_risk_compose","estimate_multi_phase_combat",
                  "multi_phase_combat_ui_product","assault_readiness_compose","combat_order_execute"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func save_slot_depth_day"):sec.find("static func save_slot_depth_day")+900]
        self.assertIn("save_slot_browser", body)
        self.assertNotIn("var score := 0.55", body)
        prod = sec[sec.find("static func production_priority_depth_day"):sec.find("static func production_priority_depth_day")+700]
        self.assertIn("production_priority_mutation", prod)
        combat = sec[sec.find("static func multi_phase_estimate_depth_day"):sec.find("static func multi_phase_estimate_depth_day")+700]
        self.assertIn("estimate_multi_phase_combat", combat)
        for aid in SAVE_PROD_COMBAT_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next260_live_day", mm)
        self.assertIn("save_score", mm)
        self.assertIn("prod_score", mm)
        self.assertIn("combat_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in SAVE_PROD_COMBAT_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_save_prod_combat_section", panel)
        self.assertIn("— Next-260 save/prod/combat (20) —", panel)
        self.assertIn("format_save_prod_combat_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_save_prod_combat_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("save_slot_depth_day","production_priority_depth_day","multi_phase_estimate_depth_day","save_prod_combat_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_save_prod_combat_days.py", CI.read_text())
        labels = [
            "save slot depth day","autosave session depth day","campaign session depth day","save resume depth day",
            "session checkpoint depth day","save audit depth day","save session close depth day",
            "factory risk surge day","production priority depth day","stockpile surge ops day","line continuity depth day",
            "industry surge joint day","production oob depth day","production surge close day",
            "multi phase estimate depth day","assault ready surface day","combat order surface day","phase product ops day",
            "multi phase joint day","save prod combat close day","next-260 save",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
