#!/usr/bin/env python3
"""Gates: next-20 live sim mutation beyond execution — GIS×312, station/assault/priority apply plans."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from live_mutation import (  # noqa: E402
    fleet_station_mutation,
    assault_stage_mutation,
    agent_dispatch_mutation,
    hh_commit_mutation,
    production_priority_mutation,
    supply_route_mutation,
    map_effect_store_mutation,
    next_day_mutation_feedback,
    naval_task_mutation,
    air_land_stage_mutation,
    theater_mutation_board,
    focus_mutation_path,
    mutation_decision_strip,
    mutation_integrity_gate,
    mutation_result,
    close_mutation_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_PM = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
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


class TestGis312(unittest.TestCase):
    def test_stamped_gt_288(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 312)


class TestLiveMutation(unittest.TestCase):
    def test_plans_and_weather_shift(self) -> None:
        st_c = fleet_station_mutation(
            weather=CLEAR, province_id=1, formation_id="div_a", country_tag="GER"
        )
        st_f = fleet_station_mutation(
            weather=FOUL, province_id=1, formation_id="div_a", country_tag="GER"
        )
        self.assertFalse(st_c.get("empty"))
        self.assertTrue((st_c.get("plan") or {}).get("apply_ready"))
        self.assertIn("move_formation", str((st_c.get("plan") or {}).get("api", "")))
        self.assertNotAlmostEqual(float(st_c["score"]), float(st_f["score"]), places=3)

        assault = assault_stage_mutation(
            weather=CLEAR,
            from_province_id=1,
            target_province_id=2,
            formation_id="div_a",
        )
        self.assertIn("step", assault.get("plan") or {})
        self.assertTrue((assault.get("plan") or {}).get("apply_ready"))

        agent = agent_dispatch_mutation()
        self.assertTrue((agent.get("plan") or {}).get("apply_ready"))

        hh = hh_commit_mutation(trail=[{"class": "sabotage", "influence": 0.5}])
        self.assertFalse(hh.get("empty"))
        empty_hh = hh_commit_mutation(trail=[])
        self.assertTrue(empty_hh.get("empty"))

        prod = production_priority_mutation(weather=FOUL, unit_id="infantry")
        self.assertTrue(prod.get("sole_mult"))
        self.assertIn("set_unit_priority_reinforcement", str((prod.get("plan") or {}).get("api", "")))

        supply = supply_route_mutation(weather=FOUL, province_id=1)
        self.assertTrue(supply.get("sole_mult"))

        effect = map_effect_store_mutation(
            order=str((st_c.get("plan") or {}).get("order", "")),
            province_id=1,
            score=float(st_c["score"]),
        )
        self.assertFalse(effect.get("empty"))
        self.assertIn("store_campaign_map_effect", str((effect.get("plan") or {}).get("api", "")))

        fb = next_day_mutation_feedback(0.5, 0.4, "station")
        self.assertEqual(fb.get("trend"), "worsened")

        naval = naval_task_mutation(weather=CLEAR, province_id=1, formation_id="n1")
        self.assertFalse(naval.get("empty"))
        air = air_land_stage_mutation(
            weather=CLEAR, from_province_id=1, target_province_id=2, formation_id="d1"
        )
        self.assertFalse(air.get("empty"))
        theater = theater_mutation_board(weather=CLEAR, province_id=1, formation_id="d1")
        self.assertGreaterEqual(int(theater.get("count", 0)), 2)
        focus = focus_mutation_path(weather=CLEAR, trail=[{"class": "economic_pressure"}])
        self.assertIn("apply_focus_order_mutation", str((focus.get("plan") or {}).get("api", "")))

        strip = mutation_decision_strip([st_c, prod], fb)
        self.assertFalse(strip.get("empty"))
        self.assertGreaterEqual(int(strip.get("count", 0)), 2)

        gate = mutation_integrity_gate(mutation_mult=1.15)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        applied = mutation_result(True, "station", "PATROL")
        self.assertTrue(applied.get("ok"))

        loop = close_mutation_loop(
            weather=CLEAR,
            trail=[{"class": "sabotage", "influence": 0.5}],
            province_id=1,
            formation_id="div_a",
        )
        self.assertFalse(loop.get("empty"))
        self.assertIn("mutation", loop.get("integration", []))


class TestLiveWiring(unittest.TestCase):
    def test_gd_live_mutation(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_station_mutation_for_province", mm)
        self.assertIn("func apply_fleet_station_mutation", mm)
        self.assertIn("func assault_stage_mutation_for_province", mm)
        self.assertIn("func apply_assault_stage_mutation", mm)
        self.assertIn("func production_priority_mutation_for_province", mm)
        idx = mm.find("func apply_fleet_station_mutation")
        self.assertIn("move_formation_to_province", mm[idx : idx + 2000])
        self.assertIn("WeatherManager", mm[mm.find("func fleet_station_mutation_for_province") : mm.find("func fleet_station_mutation_for_province") + 1600])

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func store_campaign_map_effect", gd)
        self.assertIn("func apply_hh_order_commit_mutation", gd)
        self.assertIn("func apply_supply_route_mutation", gd)
        self.assertIn("func apply_production_priority_mutation", gd)
        self.assertIn("func format_mutation_decision_strip_plain", gd)
        self.assertRegex(
            gd,
            r"func apply_hh_order_commit_mutation[\s\S]{0,200}if trail\.is_empty\(\):\s*\n\s*return",
        )

        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("func move_formation_to_province", sm)
        pm = GD_PM.read_text(encoding="utf-8")
        self.assertIn("func set_unit_priority_reinforcement", pm)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_station_mutation_chip_bbcode", insight)
        self.assertIn("build_mutation_decision_strip_chip_bbcode", insight)

        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func fleet_station_mutation",
            "func assault_stage_mutation",
            "func production_priority_mutation",
            "func supply_route_mutation",
            "func map_effect_store_mutation",
            "func hh_commit_mutation",
            "func next_day_mutation_feedback",
            "func mutation_decision_strip",
            "func mutation_integrity_gate",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("312", "336", "360", "384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("312", "336", "360", "384", "408", "480", "528", "564")))
        for label in (
            "fleet station mutation",
            "assault stage",
            "production priority",
            "map effect store",
            "mutation integrity",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
