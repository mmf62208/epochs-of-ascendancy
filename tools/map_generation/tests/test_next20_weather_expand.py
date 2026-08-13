#!/usr/bin/env python3
"""Gates: next-20 expand pilots — GIS×120, fleet posture, weather effects, HH pulse, agent network."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from fleet_redeploy_posture import rank_fleet_postures, score_fleet_posture  # noqa: E402
from weather_effects import (  # noqa: E402
    air_sortie_readiness,
    combat_weather_multiplier,
    format_weather_chip,
    format_weather_legend,
    movement_multiplier,
    naval_spotting_multiplier,
    parse_weather_ready_line,
    production_weather_multiplier,
    rank_extreme_events,
    season_label,
    storm_interdiction_bump,
    supply_throughput_weather_multiplier,
)
from assault_estimate_card import build_assault_estimate_card  # noqa: E402
from combat_phase_estimate import estimate_multi_phase_combat  # noqa: E402
from agent_network_response import plan_agent_network_response  # noqa: E402
from hh_agenda_pulse import format_hh_agenda_pulse  # noqa: E402
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


class TestGis120(unittest.TestCase):
    def test_stamped_ge_120(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 120)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)
        self.assertGreaterEqual(st["min"], 16)


class TestFleetPosture(unittest.TestCase):
    def test_low_fuel_prefers_refuel_over_projection(self) -> None:
        low = rank_fleet_postures(
            basing_level="port",
            fuel_level=0.25,
            zone_relation="hostile",
            escort_need=10.0,
            can_service=True,
        )
        high = rank_fleet_postures(
            basing_level="major_base",
            fuel_level=1.0,
            zone_relation="hostile",
            escort_need=10.0,
            can_service=True,
        )
        self.assertEqual(low["best_posture"], "REFUEL_RETURN")
        self.assertIn(high["best_posture"], ("POWER_PROJECTION", "CONVOY_COVER", "PATROL_SCREEN"))
        self.assertNotEqual(low["best_posture"], high["best_posture"])
        convoy = score_fleet_posture(
            "CONVOY_COVER",
            basing_level="port",
            fuel_level=0.9,
            zone_relation="contested",
            escort_need=40.0,
        )
        patrol = score_fleet_posture(
            "PATROL_SCREEN",
            basing_level="port",
            fuel_level=0.9,
            zone_relation="contested",
            escort_need=40.0,
        )
        self.assertGreater(convoy["score"], patrol["score"])


class TestWeatherEffects(unittest.TestCase):
    def test_storm_worse_than_clear(self) -> None:
        clear = {"visibility": 1.0, "precip_intensity": 0.0, "wind": 0.1, "ground_state": "dry", "temp": 15}
        storm = {"visibility": 0.3, "precip_intensity": 0.9, "wind": 0.8, "ground_state": "mud", "temp": -5}
        self.assertGreater(combat_weather_multiplier(clear), combat_weather_multiplier(storm))
        self.assertGreater(
            supply_throughput_weather_multiplier(clear),
            supply_throughput_weather_multiplier(storm),
        )
        self.assertGreater(movement_multiplier(clear), movement_multiplier(storm, unit_tags=["armor"]))
        self.assertGreater(production_weather_multiplier(clear), production_weather_multiplier(storm))
        self.assertGreater(naval_spotting_multiplier(clear), naval_spotting_multiplier(storm))
        air_s = air_sortie_readiness(storm)
        air_c = air_sortie_readiness(clear)
        self.assertTrue(air_s["grounded"] or air_s["effectiveness"] < air_c["effectiveness"])
        bump = storm_interdiction_bump(storm, 0.1)
        self.assertGreater(bump["interdiction_chance"], 0.1)
        self.assertEqual(season_label(1)["season"], "winter")
        self.assertEqual(season_label(7)["season"], "summer")
        chip = format_weather_chip(storm, season="winter")
        self.assertIn("combat", chip["bbcode"].lower())
        leg = format_weather_legend()
        self.assertGreaterEqual(len(leg["lines"]), 3)
        ev = rank_extreme_events(
            [{"type": "typhoon", "severity": 2}, {"type": "emp_detonation", "severity": 3}]
        )
        self.assertEqual(ev["worst"]["type"], "emp_detonation")
        self.assertTrue(parse_weather_ready_line("WeatherManager ready (lightweight season + event stub)")["ok"])

    def test_weather_changes_assault_estimate(self) -> None:
        fair = estimate_multi_phase_combat(100, 80, weather_mult=1.0)
        foul = estimate_multi_phase_combat(100, 80, weather_mult=0.4)
        self.assertNotEqual(fair["overall_attacker_win_chance"], foul["overall_attacker_win_chance"])
        card = build_assault_estimate_card(100, 80, weather_mult=0.5)
        self.assertFalse(card["empty"])
        self.assertTrue(str(card["recommendation"]).strip())


class TestAgentNetworkAndPulse(unittest.TestCase):
    def test_network_response_and_empty_pulse(self) -> None:
        empty_pulse = format_hh_agenda_pulse([])
        self.assertTrue(empty_pulse["empty"])
        self.assertEqual(empty_pulse["plain"], "")
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
        pulse = format_hh_agenda_pulse(trail, month_label="1936-02")
        self.assertFalse(pulse["empty"])
        self.assertIn("pulse", pulse["plain"].lower())
        resp = plan_agent_network_response(
            {"action_class": "sabotage", "province_id": 3, "influence": 0.8, "active": True},
            network_strength=0.2,
            available_agents=3,
        )
        self.assertFalse(resp["empty"])
        self.assertGreaterEqual(resp["deploy_count"], 1)
        self.assertIn("sabotage_defense", [a["mission"] for a in resp["actions"]] + [resp["best_mission"]])


class TestLiveWiring(unittest.TestCase):
    def test_gd_call_sites_not_define_only(self) -> None:
        wm = GD_WM.read_text(encoding="utf-8")
        self.assertIn("func get_combat_weather_multiplier", wm)
        self.assertIn("func format_province_weather_chip_bbcode", wm)
        self.assertIn("weather_combat_multiplier", wm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_weather_chip_bbcode", insight)
        self.assertIn("format_province_weather_chip_bbcode", insight)
        self.assertIn("build_fleet_posture_chip_bbcode", insight)
        self.assertIn("rank_fleet_posture_for_province", insight)
        self.assertIn("build_hh_agenda_pulse_inspector_bbcode", insight)
        self.assertIn("format_hh_agenda_pulse_plain", insight)
        self.assertIn("build_agent_network_response_bbcode", insight)
        self.assertIn("build_weather_aware_assault_estimate_card", insight)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func rank_fleet_posture_for_province", mm)
        self.assertIn("rank_fleet_postures", mm)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_weather_aware_assault_estimate_card", bm)
        self.assertIn("get_combat_weather_multiplier", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_pulse_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_agenda_pulse_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("get_supply_weather_multiplier", sm)
        self.assertIn("get_storm_interdiction_chance", sm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func weather_combat_multiplier", fmt)
        self.assertIn("func rank_fleet_postures", fmt)
        self.assertIn("func format_weather_legend_bbcode", fmt)
        summary = SUMMARY.read_text(encoding="utf-8")
        # GIS pilot count (expanded 120→144); docs may cite either while expanding.
        self.assertTrue("240" in summary or "216" in summary or "192" in summary or "168" in summary or "144" in summary or "120" in summary, "docs should cite GIS pilot count")
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue("240" in todo or "216" in todo or "192" in todo or "168" in todo or "144" in todo or "120" in todo, "TODO should cite GIS pilot count")


if __name__ == "__main__":
    unittest.main(verbosity=2)
