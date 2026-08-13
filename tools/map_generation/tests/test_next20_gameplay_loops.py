#!/usr/bin/env python3
"""Gates: next-20 gameplay loops beyond integration-expand — GIS×240, basing logistics, follow-on, execute, sole-mult."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from gameplay_loops import (  # noqa: E402
    basing_fleet_fuel_logistics,
    assault_follow_on_loop,
    counter_ops_execute_order,
    agenda_execute_pick,
    move_path_ops_loop,
    basing_repair_weather_loop,
    sealane_joint_health,
    reinforced_assault_loop,
    war_path_urgency,
    oob_factory_risk_loop,
    force_supply_posture,
    leader_weather_assign,
    joint_ops_loop_strip,
    sole_mult_integrity,
)
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_PL = ROOT / "scripts" / "production" / "ProductionLine.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"


class TestGis240(unittest.TestCase):
    def test_stamped_gt_216(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 240)
        self.assertGreater(stamped, 216)
        self.assertEqual(geometry_stats(geom["provinces"])["triangles"], 0)


class TestGameplayLoops(unittest.TestCase):
    def test_basing_logistics_and_follow_on(self) -> None:
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
        major = basing_fleet_fuel_logistics(
            "major_base", 0.25, 100.0, "hostile", foul, "strike"
        )
        none = basing_fleet_fuel_logistics("none", 0.25, 100.0, "hostile", foul, "strike")
        self.assertGreater(major["logistics_score"], none["logistics_score"])
        # Cross-system: fuel changes mission bias
        low = basing_fleet_fuel_logistics("port", 0.2, 100.0, "contested", clear, "strike")
        high = basing_fleet_fuel_logistics("port", 0.95, 100.0, "contested", clear, "strike")
        self.assertNotEqual(low.get("mission_effective"), high.get("mission_effective"))
        fo = assault_follow_on_loop(
            [{"province_id": 1, "defender_power": 40}], weather=clear
        )
        self.assertIn(fo["next_step"], ("press", "hold", "soften"))
        self.assertFalse(fo["empty"])
        weak = assault_follow_on_loop(
            [{"province_id": 1, "defender_power": 200}], weather=foul, attacker_power=50
        )
        self.assertNotEqual(fo["next_step"], weak["next_step"])

    def test_execute_and_agenda_empty(self) -> None:
        empty_pick = agenda_execute_pick([])
        self.assertTrue(empty_pick["empty"])
        self.assertEqual(empty_pick["plain"], "")
        trail = append_hh_agenda_trail(
            [],
            {
                "year": 1936,
                "month": 1,
                "action_class": "sabotage",
                "province_id": 2,
                "influence": 0.8,
                "active": True,
            },
            None,
        )
        pick = agenda_execute_pick(trail)
        self.assertFalse(pick["empty"])
        self.assertIn("NEXT", pick["pick"])
        order = counter_ops_execute_order(
            {"action_class": "sabotage", "influence": 0.9, "province_id": 3, "active": True}
        )
        self.assertFalse(order["empty"])
        self.assertIn("DEPLOY", order["order"])

    def test_loops_change_with_weather_and_sole_mult(self) -> None:
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
        self.assertGreater(
            move_path_ops_loop(1.0, foul, 0.7, True)["path_cost"],
            move_path_ops_loop(1.0, clear, 1.0, False)["path_cost"],
        )
        self.assertLess(
            basing_repair_weather_loop("port", foul)["repair_org_rate"],
            basing_repair_weather_loop("port", clear)["repair_org_rate"],
        )
        self.assertLess(
            sealane_joint_health(["hostile"], 1.1, foul)["score"],
            sealane_joint_health(["friendly"], 1.1, clear)["score"],
        )
        self.assertLess(
            oob_factory_risk_loop(foul, 1.0)["effective_output"],
            oob_factory_risk_loop(clear, 1.0)["effective_output"],
        )
        self.assertLess(
            force_supply_posture(80, 0.5, foul)["posture"],
            force_supply_posture(80, 1.0, clear)["posture"],
        )
        si = sole_mult_integrity(1.1, 0.8, 0.2)
        self.assertTrue(si["integrity_ok"])
        trail = append_hh_agenda_trail(
            [],
            {
                "year": 1936,
                "month": 2,
                "action_class": "infiltration",
                "province_id": 1,
                "influence": 0.7,
                "active": True,
            },
            None,
        )
        bl = basing_fleet_fuel_logistics("port", 0.3, 90, "contested", foul)
        fo = assault_follow_on_loop(
            [{"province_id": 1, "defender_power": 70}], weather=clear
        )
        strip = joint_ops_loop_strip(bl, fo, agenda_execute_pick(trail))
        self.assertGreaterEqual(strip["count"], 2)


class TestLiveWiring(unittest.TestCase):
    def test_gd_cross_system_loops(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func basing_fleet_fuel_logistics_for_province", mm)
        self.assertIn("func basing_repair_weather_for_province", mm)
        self.assertIn("func sealane_joint_health_for_province", mm)
        self.assertIn("func move_path_ops_for_province", mm)
        # Cross-system: basing logistics uses WeatherManager
        idx = mm.find("func basing_fleet_fuel_logistics_for_province")
        self.assertGreaterEqual(idx, 0)
        self.assertIn("WeatherManager", mm[idx : idx + 1800])
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_assault_follow_on_loop", bm)
        self.assertIn("func build_reinforced_assault_loop", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_execute_pick_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_agenda_execute_pick_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_counter_ops_execute_order_plain", gd)
        self.assertIn("func format_war_path_urgency_plain", gd)
        pl = GD_PL.read_text(encoding="utf-8")
        self.assertIn("oob_factory_risk_loop", pl)
        self.assertIn("Sole mult", pl)
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("basing_repair_weather_for_province", sm)
        self.assertIn("Sole mult for sea + depot + weather", sm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_basing_logistics_chip_bbcode", insight)
        self.assertIn("build_assault_follow_on_chip_bbcode", insight)
        self.assertIn("build_agenda_execute_pick_chip_bbcode", insight)
        self.assertIn("build_joint_ops_loop_strip_chip_bbcode", insight)
        self.assertIn("build_sealane_joint_health_chip_bbcode", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func basing_fleet_fuel_logistics", fmt)
        self.assertIn("func assault_follow_on_loop", fmt)
        self.assertIn("func counter_ops_execute_order", fmt)
        self.assertIn("func agenda_execute_pick_from_trail", fmt)
        self.assertIn("func sole_mult_integrity", fmt)
        self.assertIn("func joint_ops_loop_strip", fmt)
        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("240", "288", "312", "336", "360", "384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("240", "288", "312", "336", "360", "384", "408", "480", "528", "564")))
        for label in (
            "basing logistics",
            "follow-on",
            "agenda execute",
            "sole-mult",
            "joint ops loop",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
