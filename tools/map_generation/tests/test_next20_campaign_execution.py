#!/usr/bin/env python3
"""Gates: next-20 campaign execution beyond cohesion — GIS×288, orders, map effect, feedback."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from campaign_execution import (  # noqa: E402
    fleet_order_execute,
    combat_order_execute,
    agent_order_dispatch,
    hh_order_commit,
    map_effect_resolve,
    next_day_feedback,
    production_order_resolve,
    supply_order_resolve,
    naval_order_package,
    air_land_order_package,
    theater_order_board,
    focus_order_path,
    execution_decision_strip,
    execution_integrity_gate,
    close_the_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
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


class TestGis288(unittest.TestCase):
    def test_stamped_gt_264(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 288)


class TestCampaignExecution(unittest.TestCase):
    def test_orders_effects_feedback_integrity(self) -> None:
        fleet_c = fleet_order_execute(weather=CLEAR, province_id=1)
        fleet_f = fleet_order_execute(weather=FOUL, province_id=1)
        self.assertFalse(fleet_c.get("empty"))
        self.assertIn("DEPLOY", str(fleet_c.get("order", "")))
        self.assertNotAlmostEqual(float(fleet_c["score"]), float(fleet_f["score"]), places=3)

        combat = combat_order_execute(weather=CLEAR, province_id=1)
        self.assertIn("COMBAT", str(combat.get("order", "")))

        agent = agent_order_dispatch()
        self.assertTrue(str(agent.get("order", "")).strip())

        hh = hh_order_commit(trail=[{"class": "sabotage", "influence": 0.5}])
        self.assertFalse(hh.get("empty"))
        self.assertTrue(str(hh.get("order", "")).strip())
        empty_hh = hh_order_commit(trail=[])
        self.assertTrue(empty_hh.get("empty"))
        self.assertEqual(empty_hh.get("order", ""), "")

        effect = map_effect_resolve(
            order=str(fleet_c.get("order", "")), province_id=1, score=float(fleet_c["score"])
        )
        self.assertFalse(effect.get("empty"))
        self.assertEqual(effect["effect"]["province_id"], 1)

        fb = next_day_feedback(0.5, 0.4, str(fleet_c.get("order", "")))
        self.assertEqual(fb.get("trend"), "worsened")
        self.assertAlmostEqual(float(fb["delta"]), -0.1, places=5)

        prod = production_order_resolve(weather=FOUL)
        self.assertIn("PROD", str(prod.get("order", "")))
        self.assertTrue(prod.get("sole_mult"))

        supply = supply_order_resolve(weather=FOUL)
        self.assertIn("SUPPLY", str(supply.get("order", "")))
        self.assertTrue(supply.get("sole_mult"))

        naval = naval_order_package(weather=CLEAR, province_id=1)
        self.assertIn("NAVAL", str(naval.get("order", "")))

        air = air_land_order_package(weather=CLEAR, province_id=1)
        self.assertIn("AIR-LAND", str(air.get("order", "")))

        theater = theater_order_board(weather=CLEAR, province_id=1)
        self.assertGreaterEqual(int(theater.get("count", 0)), 2)

        focus = focus_order_path(weather=CLEAR, trail=[{"class": "economic_pressure"}])
        self.assertIn("FOCUS", str(focus.get("order", "")))

        strip = execution_decision_strip([fleet_c, combat], fb)
        self.assertFalse(strip.get("empty"))
        self.assertGreaterEqual(int(strip.get("count", 0)), 2)

        gate = execution_integrity_gate(order_mult=1.15)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        loop = close_the_loop(
            weather=CLEAR,
            trail=[{"class": "sabotage", "influence": 0.5}],
            province_id=1,
        )
        self.assertFalse(loop.get("empty"))
        self.assertIn("order", loop.get("integration", []))


class TestLiveWiring(unittest.TestCase):
    def test_gd_campaign_execution(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_order_execute_for_province", mm)
        self.assertIn("func combat_order_execute_for_province", mm)
        self.assertIn("func naval_order_package_for_province", mm)
        self.assertIn("func supply_order_resolve_for_province", mm)
        self.assertIn("func map_effect_for_order", mm)
        idx = mm.find("func fleet_order_execute_for_province")
        self.assertIn("WeatherManager", mm[idx : idx + 1600])

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_order_commit_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_order_commit_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_agent_order_dispatch_plain", gd)
        self.assertIn("func format_execution_decision_strip_plain", gd)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_order_chip_bbcode", insight)
        self.assertIn("build_combat_order_chip_bbcode", insight)
        self.assertIn("build_execution_decision_strip_chip_bbcode", insight)
        self.assertIn("build_map_effect_order_chip_bbcode", insight)

        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func fleet_order_execute",
            "func combat_order_execute",
            "func agent_order_dispatch",
            "func hh_order_commit",
            "func map_effect_resolve",
            "func next_day_feedback",
            "func production_order_resolve",
            "func supply_order_resolve",
            "func naval_order_package",
            "func air_land_order_package",
            "func theater_order_board",
            "func focus_order_path",
            "func execution_decision_strip",
            "func execution_integrity_gate",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("288", "312", "336", "360", "384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("288", "312", "336", "360", "384", "408", "480", "528", "564")))
        for label in (
            "fleet order",
            "map effect",
            "next-day feedback",
            "execution decision",
            "execution integrity",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
