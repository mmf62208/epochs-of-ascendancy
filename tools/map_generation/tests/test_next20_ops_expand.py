#!/usr/bin/env python3
"""Gates: next-20 ops expand beyond weather-deepen — GIS×168, redeploy route, briefing, coverage, polish."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from fleet_redeploy_route import plan_fleet_redeploy_routes, score_redeploy_route  # noqa: E402
from weather_combat_briefing import build_weather_combat_briefing  # noqa: E402
from agent_coverage_plan import plan_agent_coverage  # noqa: E402
from hh_monthly_brief import format_hh_monthly_brief  # noqa: E402
from weather_ops_polish import (  # noqa: E402
    weather_pressure_index,
    rank_supply_route_weather_risk,
    trade_weather_multiplier,
    naval_engagement_weather_tip,
    air_grounding_alert,
    freeze_thaw_transition,
    infra_weather_wear,
    coastal_fog_naval_gate,
    joint_focus_agent_priority,
    format_inspector_weather_section,
)
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_WM = ROOT / "scripts" / "weather" / "WeatherManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_TM = ROOT / "scripts" / "national" / "TradeManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGis168(unittest.TestCase):
    def test_stamped_ge_168(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 168)
        self.assertGreater(stamped, 144)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)
        self.assertGreaterEqual(st["min"], 16)


class TestFleetRedeployRoute(unittest.TestCase):
    def test_major_base_beats_hostile_none(self) -> None:
        plan = plan_fleet_redeploy_routes(
            [
                {
                    "province_id": 10,
                    "basing_level": "major_base",
                    "zone_relation": "friendly",
                    "path_hostile_segments": 0,
                    "path_length": 1,
                },
                {
                    "province_id": 11,
                    "basing_level": "none",
                    "zone_relation": "hostile",
                    "path_hostile_segments": 3,
                    "path_length": 5,
                },
            ],
            fuel_level=0.9,
            origin_basing="anchorage",
        )
        self.assertFalse(plan["empty"])
        self.assertEqual(plan["best_province_id"], 10)
        self.assertGreater(
            score_redeploy_route(dest_basing="port", fuel_level=0.9)["score"],
            score_redeploy_route(dest_basing="none", fuel_level=0.9)["score"],
        )


class TestCombatBriefAndCoverage(unittest.TestCase):
    def test_weather_briefing_and_coverage(self) -> None:
        fair = build_weather_combat_briefing(100, 80, weather_mult=1.0)
        foul = build_weather_combat_briefing(100, 80, weather_mult=0.4)
        self.assertNotEqual(fair["overall"], foul["overall"])
        self.assertIn("briefing", fair["headline"].lower())
        self.assertTrue(str(fair["recommendation"]).strip())
        cov = plan_agent_coverage(
            [
                {
                    "province_id": 1,
                    "influence": 0.9,
                    "loyalty": 0.2,
                    "action_class": "sabotage",
                    "active": True,
                },
                {
                    "province_id": 2,
                    "influence": 0.2,
                    "loyalty": 0.9,
                    "action_class": "influence",
                    "active": True,
                },
            ],
            available_agents=3,
        )
        self.assertFalse(cov["empty"])
        self.assertGreaterEqual(cov["agents_used"], 1)
        self.assertGreaterEqual(int(cov["assignments"][0]["agents"]), int(cov["assignments"][1]["agents"]))


class TestHhMonthlyBrief(unittest.TestCase):
    def test_empty_and_nonempty(self) -> None:
        empty = format_hh_monthly_brief([])
        self.assertTrue(empty["empty"])
        self.assertEqual(empty["plain"], "")
        trail = []
        for i, ac in enumerate(["sabotage", "infiltration"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": i + 1,
                    "action_class": ac,
                    "province_name": "P%d" % i,
                    "province_id": i,
                    "influence": 0.7,
                    "active": True,
                },
                None,
            )
        brief = format_hh_monthly_brief(trail, month_label="1936-02")
        self.assertFalse(brief["empty"])
        self.assertIn("brief", brief["plain"].lower())
        self.assertGreater(brief["count"], 0)


class TestWeatherOpsPolish(unittest.TestCase):
    def test_pressure_route_trade_fog_joint(self) -> None:
        clear = {
            "visibility": 1.0,
            "precip_intensity": 0.0,
            "wind": 0.1,
            "ground_state": "dry",
            "temp": 15,
            "province_id": 1,
        }
        storm = {
            "visibility": 0.25,
            "precip_intensity": 0.9,
            "wind": 0.8,
            "ground_state": "mud",
            "temp": -5,
            "province_id": 9,
        }
        self.assertGreater(
            weather_pressure_index(storm)["pressure"],
            weather_pressure_index(clear)["pressure"],
        )
        ranked = rank_supply_route_weather_risk([clear, storm])
        self.assertEqual(ranked["worst_province_id"], 9)
        self.assertLess(trade_weather_multiplier(storm), trade_weather_multiplier(clear))
        self.assertFalse(naval_engagement_weather_tip(storm)["empty"])
        air = air_grounding_alert(storm)
        self.assertTrue(air.get("grounded") or float(air.get("effectiveness", 1.0)) < 0.5)
        ft = freeze_thaw_transition("snow_covered", 8.0, 0.0)
        self.assertIn(ft["to"], ("mud", "wet", "dry"))
        self.assertLessEqual(infra_weather_wear(storm)["wear_factor"], 1.1)
        self.assertTrue(coastal_fog_naval_gate(storm)["fog"])
        joint = joint_focus_agent_priority(
            [{"id": "ind", "score": 80}],
            [{"mission": "counterintel", "score": 90}],
        )
        self.assertEqual(joint["best"]["id"], "counterintel")
        sec = format_inspector_weather_section(storm)
        self.assertFalse(sec["empty"])


class TestLiveWiring(unittest.TestCase):
    def test_gd_call_sites_not_define_only(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func plan_fleet_redeploy_routes_from", mm)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_weather_combat_briefing", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_monthly_brief_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_monthly_brief_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_agent_coverage_plan_plain", gd)
        wm = GD_WM.read_text(encoding="utf-8")
        self.assertIn("func get_trade_weather_multiplier", wm)
        self.assertIn("func format_weather_pressure_chip_bbcode", wm)
        self.assertIn("func format_inspector_weather_section_bbcode", wm)
        self.assertIn("func format_naval_engagement_weather_tip_bbcode", wm)
        self.assertIn("func format_air_grounding_alert_bbcode", wm)
        self.assertIn("func format_freeze_thaw_chip_bbcode", wm)
        self.assertIn("func format_infra_weather_wear_bbcode", wm)
        self.assertIn("func format_coastal_fog_gate_bbcode", wm)
        tm = GD_TM.read_text(encoding="utf-8")
        self.assertIn("get_trade_weather_multiplier", tm)
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("rank_supply_route_weather_risk", sm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_redeploy_route_chip_bbcode", insight)
        self.assertIn("build_weather_combat_briefing_chip_bbcode", insight)
        self.assertIn("build_hh_monthly_brief_inspector_bbcode", insight)
        self.assertIn("build_agent_coverage_chip_bbcode", insight)
        self.assertIn("build_inspector_weather_ops_section_bbcode", insight)
        self.assertIn("build_joint_focus_agent_chip_bbcode", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func plan_fleet_redeploy_routes", fmt)
        self.assertIn("func build_weather_combat_briefing", fmt)
        self.assertIn("func plan_agent_coverage", fmt)
        self.assertIn("func weather_pressure_index", fmt)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue("240" in summary or "216" in summary or "192" in summary or "168" in summary)
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue("240" in todo or "216" in todo or "192" in todo or "168" in todo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
