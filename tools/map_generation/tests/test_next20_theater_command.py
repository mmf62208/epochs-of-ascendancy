#!/usr/bin/env python3
"""Gates: next-20 theater command + player order surface beyond live-mutation — GIS×336."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from theater_commander import (  # noqa: E402
    theater_fleet_auto_command,
    theater_combat_auto_command,
    theater_agent_auto_dispatch,
    theater_hh_auto_commit,
    theater_production_auto,
    theater_supply_auto,
    theater_daily_brief,
    order_queue_board,
    execute_one_order,
    apply_best_station_package,
    apply_best_assault_package,
    player_order_surface_strip,
    theater_command_strip,
    command_integrity_gate,
    close_theater_command_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_PM = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry", "temperature_c": 15.0}
FOUL = {
    "precip_intensity": 0.9,
    "visibility": 0.2,
    "ground_state": "mud",
    "wind": 0.9,
    "temperature_c": -8.0,
}


class TestGis336(unittest.TestCase):
    def test_stamped_gt_312(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 336)
        self.assertGreater(stamped, 312)


class TestTheaterCommand(unittest.TestCase):
    def test_multi_system_weather_and_empty_trail(self) -> None:
        fleet = theater_fleet_auto_command(weather=CLEAR)
        self.assertFalse(fleet.get("empty"))
        self.assertGreaterEqual(int(fleet.get("count", 0)), 2)
        self.assertIn("plan", fleet.get("top") or {})

        combat = theater_combat_auto_command(weather=CLEAR)
        self.assertFalse(combat.get("empty"))

        agent = theater_agent_auto_dispatch()
        self.assertFalse(agent.get("empty"))

        hh = theater_hh_auto_commit(trail=[{"class": "sabotage", "influence": 0.5}])
        self.assertFalse(hh.get("empty"))
        empty_hh = theater_hh_auto_commit(trail=[])
        self.assertTrue(empty_hh.get("empty"))
        self.assertEqual(empty_hh.get("plain", ""), "")

        prod_c = theater_production_auto(weather=CLEAR)
        prod_f = theater_production_auto(weather=FOUL)
        self.assertTrue(prod_c.get("sole_mult"))
        # Foul weather should change production risk scores (real shipped mult path)
        self.assertNotAlmostEqual(
            float(prod_c.get("score", 0)), float(prod_f.get("score", 0)), places=3
        )

        supply = theater_supply_auto(weather=FOUL)
        self.assertTrue(supply.get("sole_mult"))

        brief_c = theater_daily_brief(weather=CLEAR, trail=[{"class": "sabotage"}])
        brief_f = theater_daily_brief(weather=FOUL, trail=[{"class": "sabotage"}])
        self.assertFalse(brief_c.get("empty"))
        self.assertGreaterEqual(int(brief_c.get("count", 0)), 4)
        self.assertNotAlmostEqual(
            float(brief_c["score"]), float(brief_f["score"]), places=3
        )

        queue = order_queue_board(weather=CLEAR, trail=[{"class": "economic_pressure"}])
        self.assertFalse(queue.get("empty"))
        self.assertGreaterEqual(int(queue.get("count", 0)), 2)
        top = queue.get("top") or {}
        self.assertIn("api", top)
        self.assertIn("domain", top)

        one = execute_one_order(weather=CLEAR, trail=[{"class": "sabotage"}])
        self.assertFalse(one.get("empty"))
        self.assertTrue(str(one.get("api", "")).strip() or str(one.get("domain", "")).strip())

        station = apply_best_station_package(weather=CLEAR)
        self.assertFalse(station.get("empty"))
        self.assertIn("apply_fleet_station", str(station.get("api", "")))
        self.assertTrue(station.get("apply_ready"))

        assault = apply_best_assault_package(weather=CLEAR)
        self.assertFalse(assault.get("empty"))
        self.assertIn("apply_assault", str(assault.get("api", "")))

        surface = player_order_surface_strip(
            weather=CLEAR, trail=[{"class": "sabotage", "influence": 0.4}]
        )
        self.assertFalse(surface.get("empty"))
        self.assertGreaterEqual(int(surface.get("count", 0)), 2)

        strip = theater_command_strip(weather=CLEAR, trail=[{"class": "sabotage"}])
        self.assertFalse(strip.get("empty"))
        self.assertGreaterEqual(int(strip.get("count", 0)), 2)

        gate = command_integrity_gate(theater_mult=1.15)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        loop = close_theater_command_loop(
            weather=CLEAR, trail=[{"class": "sabotage", "influence": 0.5}]
        )
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertIn("player_surface", loop.get("integration", []))


class TestLiveWiring(unittest.TestCase):
    def test_gd_theater_command_and_order_surface(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func theater_daily_brief_for_province", mm)
        self.assertIn("func order_queue_for_province", mm)
        self.assertIn("func execute_one_order_for_province", mm)
        self.assertIn("func player_order_surface_for_province", mm)
        self.assertIn("func theater_command_surface_for_province", mm)
        self.assertIn("func apply_best_station_for_province", mm)
        idx = mm.find("func theater_daily_brief_for_province")
        self.assertIn("WeatherManager", mm[idx : idx + 1800])
        idx2 = mm.find("func apply_best_station_for_province")
        self.assertIn("apply_fleet_station_mutation", mm[idx2 : idx2 + 1200])

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_theater_daily_brief_plain", gd)
        self.assertIn("func format_player_order_surface_plain", gd)
        self.assertIn("func format_theater_command_surface_plain", gd)
        self.assertIn("func apply_execute_one_order", gd)
        self.assertIn("func format_theater_hh_auto_commit_plain", gd)
        self.assertRegex(
            gd,
            r"func format_theater_hh_auto_commit_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        # apply_execute_one routes to real manager paths
        aidx = gd.find("func apply_execute_one_order")
        chunk = gd[aidx : aidx + 2200]
        self.assertIn("apply_fleet_station_mutation", chunk)
        self.assertIn("apply_production_priority_mutation", chunk)
        self.assertIn("apply_assault_stage_mutation", chunk)

        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("func move_formation_to_province", sm)
        pm = GD_PM.read_text(encoding="utf-8")
        self.assertIn("func set_unit_priority_reinforcement", pm)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_theater_command_strip_chip_bbcode", insight)
        self.assertIn("build_player_order_surface_chip_bbcode", insight)
        self.assertIn("build_theater_daily_brief_chip_bbcode", insight)
        self.assertIn("build_order_queue_chip_bbcode", insight)

        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func theater_fleet_auto_command",
            "func theater_combat_auto_command",
            "func theater_production_auto",
            "func theater_supply_auto",
            "func theater_hh_auto_commit",
            "func theater_daily_brief",
            "func order_queue_board",
            "func execute_one_order",
            "func player_order_surface_strip",
            "func theater_command_strip",
            "func command_integrity_gate",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("336", "360", "384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("336", "360", "384", "408", "480", "528", "564")))
        for label in (
            "theater fleet",
            "player order surface",
            "order queue",
            "theater command",
            "command integrity",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
