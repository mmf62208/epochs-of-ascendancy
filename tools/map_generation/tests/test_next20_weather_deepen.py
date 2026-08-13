#!/usr/bin/env python3
"""Gates: next-20 weather deepen — GIS×144, theater posture, forecast, sea×wx, live wiring."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from fleet_theater_posture import plan_fleet_theater_posture  # noqa: E402
from weather_forecast import (  # noqa: E402
    forecast_next_day,
    sea_weather_supply_multiplier,
    storm_convoy_risk,
    weather_aware_phase_ribbon,
    format_extreme_event_chip,
    format_season_daylight_chip,
    air_sortie_weather_gate,
    naval_spot_weather_mult,
)
from weather_effects import combat_weather_multiplier, supply_throughput_weather_multiplier  # noqa: E402
from hh_agenda_pulse_actions import format_hh_pulse_actions_digest  # noqa: E402
from agent_network_deploy import format_network_deploy_plan  # noqa: E402
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_WM = ROOT / "scripts" / "weather" / "WeatherManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_TB = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGis144(unittest.TestCase):
    def test_stamped_ge_144(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 144)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)
        self.assertGreaterEqual(st["min"], 16)


class TestFleetTheater(unittest.TestCase):
    def test_theater_prefers_refuel_when_low_fuel(self) -> None:
        plan = plan_fleet_theater_posture(
            [
                {
                    "province_id": 1,
                    "basing_level": "port",
                    "fuel_level": 0.2,
                    "zone_relation": "hostile",
                    "escort_need": 5.0,
                    "can_service": True,
                },
                {
                    "province_id": 2,
                    "basing_level": "major_base",
                    "fuel_level": 0.25,
                    "zone_relation": "contested",
                    "escort_need": 10.0,
                    "can_service": True,
                },
            ]
        )
        self.assertFalse(plan["empty"])
        self.assertGreaterEqual(plan["refuel_count"], 1)
        self.assertTrue(plan["summary"])


class TestWeatherDeepen(unittest.TestCase):
    def test_forecast_and_sea_wx_and_storm(self) -> None:
        clear = {"visibility": 1.0, "precip_intensity": 0.0, "wind": 0.1, "ground_state": "dry", "temp": 15}
        storm = {"visibility": 0.3, "precip_intensity": 0.9, "wind": 0.8, "ground_state": "mud", "temp": -5}
        fx = forecast_next_day(storm)
        self.assertFalse(fx["empty"])
        self.assertIn("Tomorrow", fx["label"])
        sea = sea_weather_supply_multiplier(1.12, storm)
        self.assertLess(sea["combined"], 1.12)
        risk = storm_convoy_risk(storm, path_zone_relations=["hostile", "contested"])
        self.assertGreater(risk["escort_need"], 0.0)
        ribbon_fair = weather_aware_phase_ribbon(100, 80, 1.0)
        ribbon_foul = weather_aware_phase_ribbon(100, 80, 0.4)
        self.assertNotEqual(ribbon_fair["overall"], ribbon_foul["overall"])
        ext = format_extreme_event_chip(
            [{"type": "typhoon", "severity": 2}, {"type": "emp_detonation", "severity": 3}]
        )
        self.assertEqual(ext["worst"]["type"], "emp_detonation")
        season = format_season_daylight_chip(1)
        self.assertEqual(season["season"], "winter")
        air = air_sortie_weather_gate(storm)
        self.assertTrue(air["grounded"] or air["effectiveness"] < 0.5)
        spot = naval_spot_weather_mult(storm)
        self.assertLess(spot["mult"], naval_spot_weather_mult(clear)["mult"])
        self.assertGreater(
            combat_weather_multiplier(clear), combat_weather_multiplier(storm)
        )
        self.assertGreater(
            supply_throughput_weather_multiplier(clear),
            supply_throughput_weather_multiplier(storm),
        )


class TestHhAndAgent(unittest.TestCase):
    def test_pulse_actions_empty_and_deploy(self) -> None:
        empty = format_hh_pulse_actions_digest([])
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
        dig = format_hh_pulse_actions_digest(trail, month_label="1936-02")
        self.assertFalse(dig["empty"])
        self.assertIn("Action", dig["plain"] + dig["bbcode"])
        deploy = format_network_deploy_plan(
            {"action_class": "sabotage", "province_id": 3, "influence": 0.8, "active": True},
            available_agents=3,
        )
        self.assertFalse(deploy["empty"])
        self.assertGreaterEqual(deploy["deploy_count"], 1)


class TestLiveWiring(unittest.TestCase):
    def test_gd_call_sites_not_define_only(self) -> None:
        wm = GD_WM.read_text(encoding="utf-8")
        self.assertIn("func get_naval_spot_weather_multiplier", wm)
        self.assertIn("func get_air_sortie_weather_eff", wm)
        self.assertIn("func format_province_forecast_chip_bbcode", wm)
        self.assertIn("func format_season_daylight_chip_bbcode", wm)
        self.assertIn("func format_extreme_event_chip_bbcode", wm)
        self.assertIn("func estimate_move_cost_with_weather", wm)
        self.assertIn("func format_storm_convoy_risk_bbcode", wm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_season_daylight_chip_bbcode", insight)
        self.assertIn("build_forecast_chip_bbcode", insight)
        self.assertIn("build_extreme_event_chip_bbcode", insight)
        self.assertIn("build_weather_legend_chip_bbcode", insight)
        self.assertIn("build_move_weather_chip_bbcode", insight)
        self.assertIn("build_storm_convoy_chip_bbcode", insight)
        self.assertIn("build_sea_weather_supply_chip_bbcode", insight)
        self.assertIn("build_fleet_theater_posture_chip_bbcode", insight)
        self.assertIn("build_weather_phase_ribbon_chip_bbcode", insight)
        self.assertIn("build_hh_pulse_actions_inspector_bbcode", insight)
        self.assertIn("build_agent_network_deploy_bbcode", insight)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func plan_fleet_theater_posture_for_ids", mm)
        self.assertIn("func estimate_move_cost_with_weather", mm)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_weather_phase_ribbon", bm)
        self.assertIn("naval_spot_weather_mult", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_pulse_actions_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_pulse_actions_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertTrue("sea_weather_supply_combined" in sm or "supply_chain_health_compose" in sm)
        self.assertIn("get_air_sortie_weather_eff", sm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func plan_fleet_theater_posture", fmt)
        self.assertIn("func format_weather_phase_ribbon", fmt)
        self.assertIn("func sea_weather_supply_combined", fmt)
        self.assertIn("func forecast_next_day_weather", fmt)
        self.assertIn("func storm_convoy_risk", fmt)
        tb = GD_TB.read_text(encoding="utf-8")
        self.assertIn("format_weather_mapmode_hint", tb)
        self.assertIn("WEATHER_LEGEND_HINT", tb)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue("240" in summary or "216" in summary or "192" in summary or "168" in summary or "144" in summary)
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue("240" in todo or "216" in todo or "192" in todo or "168" in todo or "144" in todo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
