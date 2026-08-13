#!/usr/bin/env python3
"""Gates: next-20 ops depth — multi-province live, order panel UI, combat/fleet depth, GIS×384."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from ops_depth import (  # noqa: E402
    multi_province_live_plan,
    multi_province_daily_tick_plan,
    order_panel_actions,
    order_panel_refresh_surface,
    combat_phase_depth,
    fleet_patrol_depth,
    combat_phase_order_strip,
    fleet_patrol_strip,
    ops_depth_integrity_gate,
    close_ops_depth_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_TIB = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SCN_PANEL = ROOT / "scenes" / "ui" / "OrderCommandPanel.tscn"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"}
FOUL = {"precip_intensity": 0.9, "visibility": 0.2, "ground_state": "mud", "wind": 0.8}


class TestGis384(unittest.TestCase):
    def test_stamped_gt_360(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 384)
        self.assertGreater(stamped, 360)


class TestOpsDepth(unittest.TestCase):
    def test_live_multi_panel_depth(self) -> None:
        empty = multi_province_live_plan(province_ids=[], weather=CLEAR)
        self.assertTrue(empty.get("empty"))

        live_c = multi_province_live_plan([10, 20, 30, 40, 50], weather=CLEAR)
        live_f = multi_province_live_plan([10, 20, 30, 40, 50], weather=FOUL)
        self.assertFalse(live_c.get("empty"))
        self.assertGreaterEqual(int(live_c.get("count", 0)), 2)
        top_ids = [int(t["province_id"]) for t in live_c.get("top") or []]
        self.assertTrue(all(pid in (10, 20, 30, 40, 50) for pid in top_ids))
        self.assertNotAlmostEqual(float(live_c["score"]), float(live_f["score"]), places=3)

        multi = multi_province_daily_tick_plan(
            [10, 20, 30], weather=CLEAR, trail=[{"class": "sabotage"}], max_applies=3
        )
        self.assertFalse(multi.get("empty"))
        self.assertGreaterEqual(int(multi.get("count", 0)), 1)

        panel = order_panel_actions(weather=CLEAR, trail=[{"class": "sabotage"}], province_id=10)
        self.assertFalse(panel.get("empty"))
        self.assertGreaterEqual(int(panel.get("count", 0)), 3)
        aids = [str(a.get("action_id")) for a in panel.get("actions") or []]
        self.assertIn("execute_one", aids)
        self.assertIn("apply_station", aids)

        surface = order_panel_refresh_surface(
            weather=CLEAR, trail=[{"class": "sabotage"}], province_id=10
        )
        self.assertFalse(surface.get("empty"))

        combat_c = combat_phase_depth(weather=CLEAR)
        combat_f = combat_phase_depth(weather=FOUL)
        self.assertFalse(combat_c.get("empty"))
        self.assertNotAlmostEqual(float(combat_c["score"]), float(combat_f["score"]), places=3)
        self.assertLessEqual(float(combat_c["score"]), 1.01)

        fleet = fleet_patrol_depth([1, 2, 3], fuel_level=0.7)
        fleet_low = fleet_patrol_depth([1, 2, 3], fuel_level=0.2)
        self.assertFalse(fleet.get("empty"))
        self.assertLessEqual(float(fleet["score"]), 1.01)
        self.assertLess(float(fleet_low["score"]), float(fleet["score"]))

        self.assertFalse(combat_phase_order_strip(weather=CLEAR).get("empty"))
        self.assertFalse(fleet_patrol_strip([1, 2], fuel_level=0.7, weather=CLEAR).get("empty"))

        gate = ops_depth_integrity_gate(ops_mult=1.15)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        loop = close_ops_depth_loop([10, 20, 30], weather=CLEAR, trail=[{"class": "sabotage"}])
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)


class TestLiveWiring(unittest.TestCase):
    def test_gd_multi_province_and_order_panel(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func collect_live_theater_province_ids", mm)
        self.assertIn("func multi_province_live_plan_for_tag", mm)
        self.assertIn("func order_panel_actions_for_province", mm)
        self.assertIn("func order_panel_surface_for_province", mm)
        self.assertIn("func combat_phase_depth_for_province", mm)
        self.assertIn("func fleet_patrol_depth_for_tag", mm)
        self.assertIn("get_owned_coastal_or_port_provinces", mm)
        self.assertIn("run_daily_theater_auto_tick_multi", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func run_daily_theater_auto_tick_multi", gd)
        self.assertIn("func apply_order_panel_action", gd)
        self.assertIn("func format_order_panel_plain", gd)
        self.assertIn("func format_order_panel_surface_plain", gd)
        aidx = gd.find("func apply_order_panel_action")
        # Function grows with product-depth day routes; keep core mutation routes in window.
        # Function grows with product-depth day routes (next-280+); keep core mutation routes in window.
        chunk = gd[aidx : aidx + 90000]
        self.assertIn("apply_execute_one_order", chunk)
        self.assertIn("apply_fleet_station_mutation", chunk)
        self.assertIn("apply_production_priority_mutation", chunk)

        tib = GD_TIB.read_text(encoding="utf-8")
        self.assertIn("func _on_orders_pressed", tib)
        self.assertIn("OrderCommandPanel", tib)
        self.assertIn("res://scenes/ui/OrderCommandPanel.tscn", tib)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("class_name OrderCommandPanel", panel)
        self.assertIn("apply_order_panel_action", panel)
        self.assertIn("func refresh", panel)
        self.assertTrue(SCN_PANEL.is_file())

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_order_panel_chip_bbcode", insight)
        self.assertIn("build_multi_province_live_chip_bbcode", insight)

        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func multi_province_live_rank",
            "func order_panel_actions_compose",
            "func combat_phase_depth_score",
            "func fleet_patrol_depth_score",
            "func ops_depth_integrity_gate",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("384", "408", "480", "528", "564")))
        for label in (
            "multi-province live",
            "order panel",
            "combat phase depth",
            "fleet patrol depth",
            "ops depth integrity",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
