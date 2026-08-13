#!/usr/bin/env python3
"""Gates: next-20 integration expand — GIS×216, multi-system compose packages, live wiring."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from integrated_theater_ops import (  # noqa: E402
    fleet_weather_mission_package,
    assault_readiness_compose,
    counter_ops_board,
    format_hh_agenda_commitments,
    choke_sea_weather_package,
    trade_supply_weather_chain,
    factory_risk_compose,
    theater_readiness_board,
    convoy_package_compose,
    war_cabinet_board,
    supply_chain_health,
    air_ops_package,
    format_campaign_strip,
    cross_system_coherence_delta,
)
from theater_ops_polish import campaign_day_risk  # noqa: E402
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_TM = ROOT / "scripts" / "national" / "TradeManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGis216(unittest.TestCase):
    def test_stamped_gt_192(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 216)
        self.assertGreater(stamped, 192)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)


class TestIntegrationCompose(unittest.TestCase):
    def test_fleet_wx_and_assault_and_counter(self) -> None:
        clear = {
            "visibility": 1.0,
            "precip_intensity": 0.0,
            "ground_state": "dry",
            "temp": 15,
            "wind": 0.1,
        }
        foul = {
            "visibility": 0.25,
            "precip_intensity": 0.9,
            "ground_state": "mud",
            "temp": -10,
            "wind": 0.8,
        }
        foul_fleet = fleet_weather_mission_package(
            "strike", weather=foul, zone_relation="hostile"
        )
        clear_fleet = fleet_weather_mission_package(
            "strike", weather=clear, zone_relation="hostile"
        )
        self.assertNotEqual(
            foul_fleet.get("mission_effective"), clear_fleet.get("mission_effective")
        )
        foul_a = assault_readiness_compose(
            [{"province_id": 1, "defender_power": 80}], weather=foul
        )
        clear_a = assault_readiness_compose(
            [{"province_id": 1, "defender_power": 80}], weather=clear
        )
        self.assertFalse(foul_a["empty"])
        self.assertLess(foul_a["effective_supply"], clear_a["effective_supply"])
        board = counter_ops_board(
            {"action_class": "sabotage", "influence": 0.85, "province_id": 3, "active": True}
        )
        self.assertFalse(board["empty"])
        self.assertIn("escalation", board["integration"])

    def test_hh_commits_empty_and_cross_system(self) -> None:
        empty = format_hh_agenda_commitments([])
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
                    "province_id": i,
                    "influence": 0.7,
                    "active": True,
                },
                None,
            )
        commits = format_hh_agenda_commitments(trail)
        self.assertFalse(commits["empty"])
        self.assertGreaterEqual(commits["count"], 1)
        clear = {
            "visibility": 1.0,
            "precip_intensity": 0.0,
            "ground_state": "dry",
            "temp": 15,
            "wind": 0.1,
        }
        foul = {
            "visibility": 0.25,
            "precip_intensity": 0.9,
            "ground_state": "mud",
            "temp": -10,
            "wind": 0.8,
        }
        delta = cross_system_coherence_delta(clear, foul)
        self.assertTrue(delta["changed"], delta)
        self.assertLess(delta["foul_trade_health"], delta["clear_trade_health"])

    def test_packages_nonempty(self) -> None:
        foul = {
            "visibility": 0.25,
            "precip_intensity": 0.9,
            "ground_state": "mud",
            "temp": -10,
            "wind": 0.8,
        }
        clear = {
            "visibility": 1.0,
            "precip_intensity": 0.0,
            "ground_state": "dry",
            "temp": 15,
            "wind": 0.1,
        }
        self.assertFalse(
            choke_sea_weather_package(
                {"unowned": False, "contested": False, "controller": "ENG"},
                weather=foul,
                is_choke=True,
            )["empty"]
        )
        self.assertLess(
            trade_supply_weather_chain(sea_trade_mult=1.1, weather=foul)["health"],
            trade_supply_weather_chain(sea_trade_mult=1.1, weather=clear)["health"],
        )
        self.assertGreater(factory_risk_compose(foul)["risk"], factory_risk_compose(clear)["risk"])
        fp = fleet_weather_mission_package("patrol", weather=foul)
        ar = assault_readiness_compose(
            [{"province_id": 2, "defender_power": 70}], weather=foul
        )
        tb = theater_readiness_board(
            fleet_package=fp, assault=ar, day_risk=campaign_day_risk(foul, 1)
        )
        self.assertFalse(tb["empty"])
        self.assertGreaterEqual(tb["count"], 2)
        self.assertFalse(convoy_package_compose(["hostile"], weather=foul)["empty"])
        trail = append_hh_agenda_trail(
            [],
            {
                "year": 1936,
                "month": 1,
                "action_class": "sabotage",
                "province_id": 1,
                "influence": 0.8,
                "active": True,
            },
            None,
        )
        self.assertFalse(
            war_cabinet_board(
                weather=foul,
                signal={"action_class": "sabotage", "influence": 0.8, "active": True},
                trail=trail,
            )["empty"]
        )
        self.assertLess(
            supply_chain_health(sea_mult=1.1, weather=foul)["health"],
            supply_chain_health(sea_mult=1.1, weather=clear)["health"],
        )
        air = air_ops_package(foul, 1)
        self.assertTrue(air["grounded"] or air["effective"] < 0.5)
        strip = format_campaign_strip([fp, ar, tb])
        self.assertGreaterEqual(strip["count"], 2)


class TestLiveWiring(unittest.TestCase):
    def test_gd_cross_system_call_sites(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_weather_mission_package_for_province", mm)
        self.assertIn("func choke_sea_weather_package_for_province", mm)
        # Cross-system: fleet package reads WeatherManager
        self.assertIn("fleet_weather_mission_package_for_province", mm)
        self.assertIn("WeatherManager.get_naval_spot_weather_multiplier", mm)
        # Same function body composes weather into fleet package (cross-system).
        idx = mm.find("func fleet_weather_mission_package_for_province")
        self.assertGreaterEqual(idx, 0)
        body = mm[idx : idx + 2200]
        self.assertIn("WeatherManager", body)
        self.assertIn("fleet_weather_mission_package", body)
        self.assertIn("get_naval_spot_weather_multiplier", body)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_assault_readiness_compose", bm)
        self.assertRegex(
            bm,
            r"func build_assault_readiness_compose[\s\S]{0,600}get_combat_weather_multiplier",
        )
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_commitments_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_agenda_commitments_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_counter_ops_board_plain", gd)
        self.assertIn("func format_war_cabinet_board_plain", gd)
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("supply_chain_health_compose", sm)
        # Sole mult: chain health applied once (no sea_weather_supply_combined * chain stack).
        self.assertIn("Sole mult for sea + depot + weather", sm)
        self.assertNotIn("delivery = clampf(delivery * float(sea_wx.get", sm)
        tm = GD_TM.read_text(encoding="utf-8")
        self.assertIn("trade_supply_weather_chain", tm)
        # Sole mult: chain includes sea×wx; must not multiply sea_trade then chain.
        self.assertIn("Sole mult: trade_supply_weather_chain", tm)
        self.assertNotIn("amount *= sea_trade", tm)
        self.assertNotIn("amount *= wx_trade", tm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_weather_package_chip_bbcode", insight)
        self.assertIn("build_assault_readiness_chip_bbcode", insight)
        self.assertIn("build_counter_ops_chip_bbcode", insight)
        self.assertIn("build_campaign_strip_chip_bbcode", insight)
        self.assertIn("build_war_cabinet_chip_bbcode", insight)
        self.assertIn("build_convoy_package_chip_bbcode", insight)
        self.assertIn("build_theater_readiness_chip_bbcode", insight)
        self.assertIn("theater_readiness_board", insight)
        self.assertIn("convoy_package_for_province", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func fleet_weather_mission_package", fmt)
        self.assertIn("func assault_readiness_compose", fmt)
        self.assertIn("func counter_ops_board", fmt)
        self.assertIn("func format_hh_agenda_commitments_from_trail", fmt)
        self.assertIn("func trade_supply_weather_chain", fmt)
        self.assertIn("func supply_chain_health_compose", fmt)
        self.assertIn("func format_campaign_strip", fmt)
        self.assertIn("func convoy_package_compose", fmt)
        self.assertIn("func theater_readiness_board", fmt)
        mm2 = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func convoy_package_for_province", mm2)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue("240" in summary or "216" in summary)
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue("240" in todo or "216" in todo)
        # docs list integration polish slots
        self.assertTrue(
            "Fleet+wx" in todo
            or "fleet+weather" in todo.lower()
            or "integration" in todo.lower()
            or "Assault readiness" in todo
            or "Counter-ops" in todo
            or "campaign strip" in todo.lower()
        )
        # Acceptance: next20 items 13/14/19 named with landed status in live docs
        for label in (
            "theater readiness board",
            "convoy package compose",
            "cross-system coherence",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must land item: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must land item: %s" % label)
        roadmap = (ROOT / "Next_30_Days_Roadmap.md").read_text(encoding="utf-8")
        for label in (
            "theater readiness board",
            "convoy package compose",
            "cross-system coherence",
        ):
            self.assertIn(label, roadmap.lower(), msg="Roadmap must land item: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
