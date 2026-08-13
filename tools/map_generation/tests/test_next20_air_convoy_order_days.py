#!/usr/bin/env python3
"""Gates: next-240 air/convoy/order (20) + GIS×753 + composed GD wiring + panel body."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from gis_coastline_ingest import load_geometry_payload
from next240_air_convoy_order import (
    AIR_CONVOY_ORDER_DAY_IDS, DAY_FUNCS, close_next240_air_convoy_order_loop,
    air_convoy_order_integrity, air_sortie_depth_day, convoy_escort_depth_day,
    order_execute_depth_day, air_convoy_order_close_day, air_land_joint_depth_day,
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
 "air_sortie_depth_day","air_land_joint_depth_day","multi_domain_ops_day","air_domain_close_day",
 "convoy_escort_depth_day","sealane_health_ops_day","convoy_sealane_close_day",
 "order_execute_depth_day","map_effect_resolve_day","next_day_feedback_depth_day","air_convoy_order_close_day",
}

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(AIR_CONVOY_ORDER_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id","")), fn.__name__)
    def test_theme_helpers_shipped(self):
        a = air_sortie_depth_day()
        self.assertIn("air", a)
        self.assertGreater(float(a.get("air_score", a.get("score", 0))), 0.1)
        j = air_land_joint_depth_day()
        self.assertIn("joint", j)
        c = convoy_escort_depth_day()
        self.assertIn("convoy", c)
        o = order_execute_depth_day()
        self.assertIn("order", o)
        close = air_convoy_order_close_day()
        self.assertTrue(close.get("ok") or close.get("gate"))
    def test_close(self):
        loop = close_next240_air_convoy_order_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(air_convoy_order_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (air / convoy / order)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("air_ops_package","air_land_joint_package","air_sortie_weather_readiness",
                  "convoy_package_compose","sealane_joint_health","order_execute_day",
                  "map_effect_resolve","next_day_feedback","execution_integrity_gate","sole_mult_integrity"):
            self.assertIn(h, sec, msg=h)
        body = sec[sec.find("static func air_sortie_depth_day"):sec.find("static func air_sortie_depth_day")+900]
        self.assertIn("air_ops_package", body)
        self.assertNotIn("var score := 0.55", body)
        convoy = sec[sec.find("static func convoy_escort_depth_day"):sec.find("static func convoy_escort_depth_day")+700]
        self.assertIn("convoy_package_compose", convoy)
        order = sec[sec.find("static func map_effect_resolve_day"):sec.find("static func map_effect_resolve_day")+700]
        self.assertIn("map_effect_resolve", order)
        for aid in AIR_CONVOY_ORDER_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next240_live_day", mm)
        self.assertIn("air_score", mm)
        self.assertIn("convoy_score", mm)
        self.assertIn("order_score", mm)
    def test_wiring(self):
        fmt, mm, gd = GD_FMT.read_text(), GD_MM.read_text(), GD_GD.read_text()
        panel, pi = GD_PANEL.read_text(), GD_PI.read_text()
        for aid in AIR_CONVOY_ORDER_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
        self.assertIn("func _rebuild_air_convoy_order_section", panel)
        self.assertIn("— Next-240 air/convoy/order (20) —", panel)
        self.assertIn("format_air_convoy_order_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_air_convoy_order_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        for key in ("air_sortie_depth_day","convoy_escort_depth_day","order_execute_depth_day","air_convoy_order_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_air_convoy_order_days.py", CI.read_text())
        labels = [
            "air sortie depth day","air land joint depth day","multi domain ops day","air front readiness day",
            "domain joint ops day","air land campaign day","air domain close day",
            "convoy escort depth day","sealane health ops day","trade pressure ops day","convoy sealane joint day",
            "sealane logistics ops day","wartime trade ops day","convoy sealane close day",
            "order execute depth day","map effect resolve day","next day feedback depth day",
            "order effect joint day","feedback loop ops day","air convoy order close day","next-240 air",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))

if __name__ == "__main__":
    unittest.main(verbosity=2)
