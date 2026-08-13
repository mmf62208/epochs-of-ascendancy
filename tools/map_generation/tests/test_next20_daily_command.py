#!/usr/bin/env python3
"""Gates: next-20 daily theater auto-apply + command result log beyond theater-command — GIS×360."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from daily_command_tick import (  # noqa: E402
    command_log_entry,
    append_command_log,
    format_command_log_surface,
    day_apply_budget,
    multi_province_day_plan,
    daily_fleet_auto_apply_plan,
    daily_combat_auto_apply_plan,
    daily_production_auto_apply_plan,
    daily_supply_auto_apply_plan,
    daily_hh_auto_apply_plan,
    daily_agent_auto_apply_plan,
    simulate_day_apply_results,
    apply_result_feedback,
    theater_day_report,
    daily_theater_auto_tick,
    daily_apply_integrity_gate,
    command_log_strip,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_TM = ROOT / "scripts" / "autoload" / "TimeManager.gd"
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


class TestGis360(unittest.TestCase):
    def test_stamped_gt_336(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 360)
        self.assertGreater(stamped, 336)


class TestDailyCommandTick(unittest.TestCase):
    def test_budget_log_empty_weather_tick(self) -> None:
        empty = format_command_log_surface([])
        self.assertTrue(empty.get("empty"))
        self.assertEqual(empty.get("plain", ""), "")

        e = command_log_entry(domain="fleet", order="DEPLOY X", ok=True, province_id=1)
        self.assertTrue(e.get("ok"))
        board = append_command_log([], e)
        self.assertFalse(board.get("empty"))
        surf = format_command_log_surface(board.get("entries"))
        self.assertFalse(surf.get("empty"))
        self.assertIn("DEPLOY", surf.get("plain", "") + surf.get("summary", ""))

        b_clear = day_apply_budget(5, 3, CLEAR)
        b_foul = day_apply_budget(5, 3, FOUL)
        self.assertEqual(int(b_clear["allowed"]), 3)
        self.assertEqual(int(b_foul["allowed"]), 2)  # foul reduces cap
        self.assertLess(int(b_foul["cap"]), int(b_clear["cap"]))

        multi = multi_province_day_plan(weather=CLEAR, trail=[{"class": "sabotage"}])
        self.assertFalse(multi.get("empty"))
        self.assertGreaterEqual(int(multi.get("count", 0)), 1)

        fleet = daily_fleet_auto_apply_plan(weather=CLEAR)
        self.assertFalse(fleet.get("empty"))
        self.assertTrue(fleet.get("apply_ready"))

        combat = daily_combat_auto_apply_plan(weather=CLEAR)
        self.assertFalse(combat.get("empty"))

        prod_c = daily_production_auto_apply_plan(weather=CLEAR)
        prod_f = daily_production_auto_apply_plan(weather=FOUL)
        self.assertTrue(prod_c.get("sole_mult"))
        self.assertNotAlmostEqual(float(prod_c["score"]), float(prod_f["score"]), places=3)

        supply = daily_supply_auto_apply_plan(weather=FOUL)
        self.assertTrue(supply.get("sole_mult"))

        hh = daily_hh_auto_apply_plan(trail=[{"class": "sabotage", "influence": 0.5}])
        self.assertFalse(hh.get("empty"))
        hh_e = daily_hh_auto_apply_plan(trail=[])
        self.assertTrue(hh_e.get("empty"))

        agent = daily_agent_auto_apply_plan()
        self.assertFalse(agent.get("empty"))

        results = simulate_day_apply_results([fleet, combat, prod_c])
        self.assertFalse(results.get("empty"))
        self.assertGreaterEqual(int(results.get("count", 0)), 2)

        fb = apply_result_feedback(0.5, 0.4, "fleet", "DEPLOY")
        self.assertEqual(fb.get("trend"), "worsened")

        report = theater_day_report(
            weather=CLEAR,
            trail=[{"class": "sabotage"}],
            log_trail=results.get("entries"),
        )
        self.assertFalse(report.get("empty"))

        tick_c = daily_theater_auto_tick(weather=CLEAR, trail=[{"class": "sabotage"}])
        tick_f = daily_theater_auto_tick(weather=FOUL, trail=[{"class": "sabotage"}])
        self.assertFalse(tick_c.get("empty"))
        self.assertGreaterEqual(int(tick_c.get("count", 0)), 1)
        # Foul day selects fewer applies and/or different scores
        if int(tick_c["count"]) == int(tick_f["count"]):
            self.assertNotAlmostEqual(
                float(tick_c["score"]), float(tick_f["score"]), places=3
            )
        else:
            self.assertLess(int(tick_f["count"]), int(tick_c["count"]))
        self.assertGreater(float(tick_c.get("weather_score_shift", 0)), 0.01)
        self.assertFalse((tick_c.get("log") or {}).get("empty"))

        gate = daily_apply_integrity_gate(day_mult=1.15)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        strip = command_log_strip(results.get("entries"), fb)
        self.assertFalse(strip.get("empty"))


class TestLiveWiring(unittest.TestCase):
    def test_gd_day_tick_and_command_log(self) -> None:
        tm = GD_TM.read_text(encoding="utf-8")
        self.assertIn("signal game_day_advanced", tm)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func _on_game_day_advanced", mm)
        # Day path must call daily theater auto-tick
        idx = mm.find("func _on_game_day_advanced")
        self.assertGreaterEqual(idx, 0)
        chunk = mm[idx : idx + 900]
        self.assertIn("run_daily_theater_auto_tick", chunk)
        self.assertIn("advance_daily_infrastructure_repair", chunk)
        self.assertIn("func command_result_log_surface", mm)
        self.assertIn("func theater_day_report_for_province", mm)
        self.assertIn("func run_daily_theater_auto_tick_for_province", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func run_daily_theater_auto_tick", gd)
        self.assertIn("func get_command_result_log", gd)
        self.assertIn("func append_command_result_log", gd)
        self.assertIn("func format_command_result_log_plain", gd)
        self.assertIn("func format_theater_day_report_plain", gd)
        self.assertRegex(
            gd,
            r"func format_command_result_log_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        aidx = gd.find("func run_daily_theater_auto_tick")
        achunk = gd[aidx : aidx + 3500]
        self.assertIn("apply_execute_one_order", achunk)
        self.assertIn("append_command_result_log", achunk)
        self.assertIn("day_apply_budget", achunk)
        self.assertIn("command_log_entry", achunk)

        # Real manager APIs still present for apply path
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("func move_formation_to_province", sm)
        pm = GD_PM.read_text(encoding="utf-8")
        self.assertIn("func set_unit_priority_reinforcement", pm)
        self.assertIn("func apply_execute_one_order", gd)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_command_result_log_chip_bbcode", insight)
        self.assertIn("build_theater_day_report_chip_bbcode", insight)

        fmt = GD_FMT.read_text(encoding="utf-8")
        for name in (
            "func command_log_entry",
            "func format_command_log_surface",
            "func day_apply_budget",
            "func daily_apply_integrity_gate",
            "func command_log_strip",
            "func theater_day_report_compose",
        ):
            self.assertIn(name, fmt, msg="missing %s" % name)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("360", "384", "408", "480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("360", "384", "408", "480", "528", "564")))
        for label in (
            "daily theater",
            "command result log",
            "day apply budget",
            "theater day report",
            "daily apply integrity",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
