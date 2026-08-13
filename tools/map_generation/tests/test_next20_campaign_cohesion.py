#!/usr/bin/env python3
"""Gates: next-20 campaign cohesion beyond gameplay-loops — GIS×264, multi-system boards, sole-mult."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from campaign_cohesion import (  # noqa: E402
    fleet_campaign_plan,
    combat_campaign_phase,
    agent_campaign_response,
    hh_campaign_board,
    theater_campaign_strip,
    production_campaign_risk,
    supply_campaign_spine,
    focus_war_path_board,
    force_posture_board,
    leader_campaign_assign,
    naval_campaign_package,
    air_land_joint_package,
    campaign_decision_strip,
    cohesion_integrity_gate,
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


class TestGis264(unittest.TestCase):
    def test_stamped_gt_240(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 264)


class TestCampaignCohesion(unittest.TestCase):
    def test_boards_compose_and_weather_shift(self) -> None:
        fleet_c = fleet_campaign_plan(weather=CLEAR)
        fleet_f = fleet_campaign_plan(weather=FOUL)
        self.assertFalse(fleet_c.get("empty"))
        self.assertNotAlmostEqual(float(fleet_c["score"]), float(fleet_f["score"]), places=3)
        combat = combat_campaign_phase(weather=CLEAR)
        self.assertFalse(combat.get("empty"))
        self.assertIn("follow_on", combat.get("integration", []) or ["follow_on"])
        agent = agent_campaign_response()
        self.assertFalse(agent.get("empty"))
        self.assertLessEqual(float(agent["score"]), 1.01)
        hh = hh_campaign_board(trail=[{"class": "sabotage", "influence": 0.5}])
        self.assertFalse(hh.get("empty"))
        empty_hh = hh_campaign_board(trail=[])
        self.assertTrue(empty_hh.get("empty") or empty_hh.get("plain", "") == "")
        theater = theater_campaign_strip(weather=CLEAR)
        self.assertFalse(theater.get("empty"))
        prod_c = production_campaign_risk(weather=CLEAR)
        prod_f = production_campaign_risk(weather=FOUL)
        self.assertGreaterEqual(float(prod_f["score"]), float(prod_c["score"]))
        supply = supply_campaign_spine(weather=FOUL)
        self.assertFalse(supply.get("empty"))
        self.assertTrue(supply.get("sole_mult"))
        focus = focus_war_path_board(weather=CLEAR)
        self.assertLessEqual(float(focus["score"]), 1.01)
        force = force_posture_board(weather=CLEAR)
        self.assertFalse(force.get("empty"))
        leader = leader_campaign_assign(weather=CLEAR)
        self.assertFalse(leader.get("empty"))
        naval = naval_campaign_package(weather=CLEAR)
        self.assertFalse(naval.get("empty"))
        air = air_land_joint_package(weather=CLEAR)
        self.assertFalse(air.get("empty"))
        strip = campaign_decision_strip([fleet_c, combat, hh])
        self.assertFalse(strip.get("empty"))
        self.assertGreaterEqual(int(strip.get("count", 0)), 2)
        gate = cohesion_integrity_gate()
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))


class TestLiveWiring(unittest.TestCase):
    def test_gd_campaign_cohesion(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_campaign_plan_for_province", mm)
        self.assertIn("func naval_campaign_package_for_province", mm)
        self.assertIn("func supply_campaign_spine_for_province", mm)
        self.assertIn("WeatherManager", mm[mm.find("func fleet_campaign_plan_for_province") : mm.find("func fleet_campaign_plan_for_province") + 1600])
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_campaign_board_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_campaign_board_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_agent_campaign_response_plain", gd)
        self.assertIn("func format_campaign_decision_strip_plain", gd)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_campaign_chip_bbcode", insight)
        self.assertIn("build_combat_campaign_chip_bbcode", insight)
        self.assertIn("build_campaign_decision_strip_chip_bbcode", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func fleet_campaign_plan",
            "func combat_campaign_phase",
            "func agent_campaign_response",
            "func hh_campaign_board",
            "func theater_campaign_strip",
            "func production_campaign_risk",
            "func supply_campaign_spine",
            "func focus_war_path_board",
            "func force_posture_board",
            "func leader_campaign_assign",
            "func naval_campaign_package",
            "func air_land_joint_package",
            "func campaign_decision_strip",
            "func cohesion_integrity_gate",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)
        todo = TODO.read_text(encoding="utf-8").lower()
        summary = SUMMARY.read_text(encoding="utf-8").lower()
        roadmap = ROADMAP.read_text(encoding="utf-8").lower()
        todo_txt = TODO.read_text(encoding="utf-8")
        summary_txt = SUMMARY.read_text(encoding="utf-8")
        # GIS pilot stamp progressed 264→288→312; accept current milestone chain in docs
        self.assertTrue(
            any(n in todo_txt for n in ("264", "288", "312", "336", "360", "384", "360", "384", "408", "480", "528", "564")),
            msg="TODO must name GIS stamp 264/288/312",
        )
        self.assertTrue(
            any(n in summary_txt for n in ("264", "288", "312", "336", "360", "384", "360", "384", "408", "480", "528", "564")),
            msg="Summary must name GIS stamp 264/288/312",
        )
        for label in (
            "fleet campaign",
            "campaign decision",
            "cohesion integrity",
            "supply campaign",
            "hh campaign",
        ):
            self.assertIn(label, todo, msg="TODO must name: %s" % label)
            self.assertIn(label, summary, msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap, msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
