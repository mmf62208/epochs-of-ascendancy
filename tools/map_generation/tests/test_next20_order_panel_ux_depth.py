#!/usr/bin/env python3
"""Gates: order panel collapsible sections, naval skim, HH player path, medium-horizon equip, GIS×720."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from order_panel_ux_depth import (  # noqa: E402
    order_panel_section_plan,
    order_panel_action_ids,
    order_panel_primary_actions,
    naval_campaign_skim,
    hh_agenda_player_path,
    medium_horizon_equip_plan,
    close_order_panel_ux_depth_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

# Core live routes that must remain in the section plan (not removed by collapse UX)
REQUIRED_ACTIONS = (
    "day_ops_integrated",
    "logistics_day",
    "combat_campaign_day",
    "fleet_campaign_day",
    "weather_crisis_day",
    "agent_campaign_day",
    "hh_campaign_day",
    "industry_surge_day",
)


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 720)


class TestSections(unittest.TestCase):
    def test_compact_collapse(self) -> None:
        plan = order_panel_section_plan(compact=True, max_expanded=2)
        self.assertFalse(plan.get("empty"))
        secs = plan.get("sections") or []
        self.assertGreaterEqual(len(secs), 4)
        expanded = [s for s in secs if s.get("start_expanded")]
        collapsed = [s for s in secs if not s.get("start_expanded")]
        self.assertGreaterEqual(len(expanded), 1)
        self.assertGreaterEqual(len(collapsed), 1)
        self.assertLessEqual(len(expanded), 3)
        ids = order_panel_action_ids(plan)
        for aid in REQUIRED_ACTIONS:
            self.assertIn(aid, ids, msg="missing live route %s" % aid)
        primary = order_panel_primary_actions(plan)
        self.assertGreaterEqual(len(primary), 2)
        # Primary should be smaller than full catalogue
        self.assertLess(len(primary), len(ids))


class TestNavalSkim(unittest.TestCase):
    def test_urgency(self) -> None:
        calm = naval_campaign_skim(fuel_level=0.9, zone_relation="friendly", is_choke=False)
        foul = naval_campaign_skim(fuel_level=0.3, zone_relation="hostile", is_choke=True)
        self.assertFalse(calm.get("empty"))
        self.assertGreaterEqual(float(foul.get("urgency", 0)), float(calm.get("urgency", 0)))


class TestHHPath(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        empty = hh_agenda_player_path([])
        self.assertTrue(empty.get("empty"))
        path = hh_agenda_player_path([{"class": "sabotage", "influence": 0.6}])
        self.assertFalse(path.get("empty"))
        q = path.get("apply_queue") or []
        self.assertGreaterEqual(len(q), 2)
        self.assertTrue(any(x.get("action_id") == "apply_hh_commit" for x in q))
        self.assertTrue(any(x.get("action_id") == "apply_counterplay" for x in q))


class TestEquip(unittest.TestCase):
    def test_seed_when_tanks_slow(self) -> None:
        plan = medium_horizon_equip_plan(
            tank_stock=0.0, tank_line_progress=0.05, days_horizon=60, factories=12
        )
        self.assertFalse(plan.get("empty"))
        self.assertTrue(plan.get("seed_needed") or plan.get("will_complete_tank"))
        fast = medium_horizon_equip_plan(
            tank_stock=0.0, tank_line_progress=0.95, days_horizon=60, factories=20
        )
        self.assertTrue(fast.get("will_complete_tank") or float(fast.get("projected_progress", 0)) >= 0.9)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        loop = close_order_panel_ux_depth_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(len(loop.get("action_ids") or []), 8)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("func _add_collapsible_section", panel)
        self.assertIn("order_panel_section_plan", panel)
        self.assertIn("_section_expanded", panel)
        # Live routes still present as action strings
        for aid in REQUIRED_ACTIONS:
            self.assertIn(aid, panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func order_panel_section_plan", fmt)
        self.assertIn("func naval_campaign_skim", fmt)
        self.assertIn("func hh_agenda_player_path", fmt)
        self.assertIn("func medium_horizon_equip_plan", fmt)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func naval_campaign_skim_for_province", mm)
        self.assertIn("func hh_agenda_player_path_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_hh_player_path", gd)
        self.assertIn("func format_naval_campaign_skim_plain", gd)
        self.assertIn("func format_medium_horizon_equip_plain", gd)
        self.assertIn("hh_player_path", gd)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_naval_campaign_skim_chip_bbcode", insight)
        self.assertIn("build_hh_player_path_chip_bbcode", insight)

        self.assertIn("test_next20_order_panel_ux_depth.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "order panel sections",
                "naval campaign skim",
                "hh player path",
                "medium-horizon equip",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
