#!/usr/bin/env python3
"""Gates: next-20 theater expand beyond ops-expand — GIS×192, task group, multi-front, escalation, quarterly, polish."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from fleet_task_group import compose_task_group  # noqa: E402
from multi_front_assault import rank_assault_targets  # noqa: E402
from agent_escalation_ladder import plan_agent_escalation  # noqa: E402
from hh_quarterly_rollup import format_hh_quarterly_rollup  # noqa: E402
from theater_ops_polish import (  # noqa: E402
    campaign_day_risk,
    convoy_weather_window,
    production_weather_alert,
    sea_naval_weather_ops,
    combat_morale_weather,
    depot_weather_capacity,
    daylight_combat_mod,
    choke_weather_synergy,
    focus_weather_aware_score,
    format_ops_dashboard,
)
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_WM = ROOT / "scripts" / "weather" / "WeatherManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGis192(unittest.TestCase):
    def test_stamped_ge_192(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 192)
        self.assertGreater(stamped, 168)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)
        self.assertGreaterEqual(st["min"], 16)


class TestFleetTaskGroup(unittest.TestCase):
    def test_convoy_prefers_screen(self) -> None:
        convoy = compose_task_group(
            available_strength=100.0, mission="convoy", zone_relation="hostile", escort_need=40.0
        )
        strike = compose_task_group(
            available_strength=100.0, mission="strike", zone_relation="hostile", escort_need=0.0
        )
        self.assertFalse(convoy["empty"])
        self.assertEqual(convoy["primary_role"], "SCREEN")
        self.assertEqual(strike["primary_role"], "STRIKE")
        self.assertNotEqual(convoy["primary_role"], strike["primary_role"])


class TestMultiFrontAndEscalation(unittest.TestCase):
    def test_rank_and_ladder(self) -> None:
        ranked = rank_assault_targets(
            [
                {"province_id": 1, "defender_power": 40.0, "weather_mult": 1.0},
                {"province_id": 2, "defender_power": 120.0, "weather_mult": 0.4},
            ],
            attacker_power=100.0,
        )
        self.assertFalse(ranked["empty"])
        self.assertEqual(ranked["best_province_id"], 1)
        esc = plan_agent_escalation(
            {"action_class": "sabotage", "influence": 0.9, "active": True},
            network_strength=0.1,
            loyalty=0.2,
            available_agents=3,
        )
        self.assertFalse(esc["empty"])
        self.assertGreaterEqual(esc["level"], 2)
        empty = plan_agent_escalation({})
        self.assertTrue(empty["empty"])
        self.assertEqual(empty["plain"], "")


class TestHhQuarterly(unittest.TestCase):
    def test_empty_and_rollup(self) -> None:
        empty = format_hh_quarterly_rollup([])
        self.assertTrue(empty["empty"])
        self.assertEqual(empty["plain"], "")
        trail = []
        for i, ac in enumerate(["sabotage", "infiltration", "economic_pressure", "sabotage"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": (i % 3) + 1,
                    "action_class": ac,
                    "province_id": i,
                    "influence": 0.6,
                    "active": True,
                },
                None,
            )
        roll = format_hh_quarterly_rollup(trail, quarter_label="1936-Q1")
        self.assertFalse(roll["empty"])
        self.assertIn("rollup", roll["plain"].lower())
        self.assertGreaterEqual(roll["class_totals"].get("sabotage", 0), 1)

    def test_three_month_window_excludes_older_months(self) -> None:
        """Quarterly pilot keeps only last ≤3 unique (year,month) buckets."""
        trail = []
        # 5 distinct months: only last 3 should remain in window count
        for month, ac in [
            (1, "propaganda"),
            (2, "propaganda"),
            (3, "sabotage"),
            (4, "infiltration"),
            (5, "economic_pressure"),
        ]:
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": month,
                    "action_class": ac,
                    "province_id": month,
                    "influence": 0.5,
                    "active": True,
                },
                None,
            )
        roll = format_hh_quarterly_rollup(trail)
        self.assertFalse(roll["empty"])
        self.assertLessEqual(roll["months_covered"], 3)
        # Oldest propaganda months drop out of the 3-month window
        self.assertEqual(roll["class_totals"].get("propaganda", 0), 0)
        self.assertGreaterEqual(roll["class_totals"].get("sabotage", 0), 1)
        self.assertGreaterEqual(roll["class_totals"].get("infiltration", 0), 1)
        self.assertGreaterEqual(roll["class_totals"].get("economic_pressure", 0), 1)

    def test_gd_quarterly_entry_point_uses_three_month_window(self) -> None:
        """Shipped GameData entry point must call formatter with 3-month window (not whole trail)."""
        gd = GD_GD.read_text(encoding="utf-8")
        # Empty trail stays empty on the real GameData surface
        self.assertRegex(
            gd,
            r"func format_hh_quarterly_rollup_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        # Real path: GameData delegates to MapPolishFormatters (not a whole-trail local sum)
        self.assertIn("format_hh_quarterly_rollup_from_trail", gd)
        self.assertRegex(
            gd,
            r"func format_hh_quarterly_rollup_plain[\s\S]{0,200}MapPolishFormatters\.format_hh_quarterly_rollup_from_trail",
        )
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func format_hh_quarterly_rollup_from_trail", fmt)
        # 3-month unique (year,month) window must be present on the shipped GD helper
        self.assertIn("months.size() >= 3", fmt)
        self.assertIn("month_set", fmt)
        self.assertIn('"%d-%d"', fmt)
        # Inspector surface calls the GameData entry point (not only Python)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("format_hh_quarterly_rollup_plain", insight)
        self.assertIn("build_hh_quarterly_rollup_inspector_bbcode", insight)


class TestTheaterPolish(unittest.TestCase):
    def test_day_risk_convoy_depot_focus(self) -> None:
        clear = {
            "visibility": 1.0,
            "precip_intensity": 0.0,
            "ground_state": "dry",
            "temp": 15,
            "wind": 0.1,
        }
        storm = {
            "visibility": 0.25,
            "precip_intensity": 0.9,
            "ground_state": "mud",
            "temp": -20,
            "wind": 0.8,
        }
        self.assertGreater(campaign_day_risk(storm, 1)["risk"], campaign_day_risk(clear, 7)["risk"])
        win = convoy_weather_window(
            [
                {**storm, "day_index": 0},
                {**clear, "day_index": 1},
                {"visibility": 0.6, "precip_intensity": 0.3, "ground_state": "wet", "day_index": 2},
            ]
        )
        self.assertEqual(win["best_day"], 1)
        self.assertTrue(production_weather_alert(storm)["alert"])
        self.assertLess(
            sea_naval_weather_ops(1.12, storm)["combined"],
            sea_naval_weather_ops(1.12, clear)["combined"],
        )
        self.assertLess(
            combat_morale_weather(storm)["morale_mult"],
            combat_morale_weather(clear)["morale_mult"],
        )
        self.assertLess(
            depot_weather_capacity(storm, 100)["capacity"],
            depot_weather_capacity(clear, 100)["capacity"],
        )
        self.assertLess(daylight_combat_mod(1)["combat_mult"], daylight_combat_mod(7)["combat_mult"])
        self.assertFalse(
            choke_weather_synergy(is_choke=True, controller_friendly=True, weather=storm)["empty"]
        )
        self.assertTrue(choke_weather_synergy(is_choke=False)["empty"])
        fw = focus_weather_aware_score(50, "industrial_effort", storm)
        self.assertGreater(fw["boost"], 0.0)
        dash = format_ops_dashboard(
            day_risk=campaign_day_risk(storm, 1),
            task_group=compose_task_group(available_strength=80, mission="patrol"),
            assault=rank_assault_targets(
                [{"province_id": 3, "defender_power": 50, "weather_mult": 1.0}],
                attacker_power=100,
            ),
            escalation=plan_agent_escalation(
                {"action_class": "sabotage", "influence": 0.8, "active": True}
            ),
        )
        self.assertFalse(dash["empty"])


class TestLiveWiring(unittest.TestCase):
    def test_gd_call_sites_not_define_only(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func compose_fleet_task_group_for_province", mm)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func rank_multi_front_assault_targets", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_quarterly_rollup_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_quarterly_rollup_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("format_hh_quarterly_rollup_from_trail", gd)
        self.assertIn("func format_agent_escalation_ladder_plain", gd)
        wm = GD_WM.read_text(encoding="utf-8")
        self.assertIn("func format_campaign_day_risk_bbcode", wm)
        self.assertIn("func format_production_weather_alert_bbcode", wm)
        self.assertIn("func get_combat_morale_weather_mult", wm)
        self.assertIn("func get_depot_weather_capacity", wm)
        self.assertIn("func format_daylight_combat_mod_bbcode", wm)
        self.assertIn("func format_convoy_weather_window_bbcode", wm)
        self.assertIn("func format_sea_naval_weather_ops_bbcode", wm)
        self.assertIn("func format_choke_weather_synergy_bbcode", wm)
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertTrue("get_depot_weather_capacity" in sm or "supply_chain_health_compose" in sm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_task_group_chip_bbcode", insight)
        self.assertIn("build_multi_front_assault_chip_bbcode", insight)
        self.assertIn("build_hh_quarterly_rollup_inspector_bbcode", insight)
        self.assertIn("build_agent_escalation_chip_bbcode", insight)
        self.assertIn("build_ops_dashboard_chip_bbcode", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func compose_fleet_task_group", fmt)
        self.assertIn("func rank_assault_targets", fmt)
        self.assertIn("func plan_agent_escalation", fmt)
        self.assertIn("func campaign_day_risk", fmt)
        self.assertIn("func format_ops_dashboard", fmt)
        self.assertIn("func format_hh_quarterly_rollup_from_trail", fmt)
        self.assertIn("months.size() >= 3", fmt)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue("240" in summary or "216" in summary or "192" in summary)
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue("240" in todo or "216" in todo or "192" in todo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
