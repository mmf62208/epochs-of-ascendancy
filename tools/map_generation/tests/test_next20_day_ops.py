#!/usr/bin/env python3
"""Gates: day-ops depth — integrated day fleet/agent/HH, HH product screen, naval multi-phase, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from day_ops_depth import (  # noqa: E402
    estimate_naval_multi_phase,
    hh_agenda_product_screen,
    day_ops_integrated_plan,
    day_ops_integrity,
    close_day_ops_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGisFloor(unittest.TestCase):
    def test_stamped_ge_564(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestNavalMultiPhase(unittest.TestCase):
    def test_phases_weather_fuel(self) -> None:
        c = estimate_naval_multi_phase(visibility=1.0, fuel_level=0.85)
        f = estimate_naval_multi_phase(visibility=0.2, fuel_level=0.85)
        low = estimate_naval_multi_phase(visibility=1.0, fuel_level=0.2)
        self.assertEqual(int(c.get("phase_count", 0)), 4)
        phases = [r["phase"] for r in (c.get("phase_rows") or [])]
        self.assertEqual(phases, ["search", "detect", "engage", "disengage"])
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)
        self.assertLess(float(low["score"]), float(c["score"]))
        self.assertFalse(low.get("apply_ready"))


class TestHhProduct(unittest.TestCase):
    def test_empty_trail_and_sections(self) -> None:
        self.assertTrue(hh_agenda_product_screen([]).get("empty"))
        hh = hh_agenda_product_screen(
            [{"class": "sabotage", "influence": 0.55}],
            {"active": True, "action_class": "sabotage", "influence": 0.55, "province_id": 1},
        )
        self.assertFalse(hh.get("empty"))
        self.assertGreaterEqual(len(hh.get("sections") or []), 2)
        self.assertTrue(
            any(a.get("action_id") == "apply_hh_commit" for a in (hh.get("actions") or []))
        )


class TestDayOpsIntegrated(unittest.TestCase):
    def test_plan_and_empty(self) -> None:
        self.assertTrue(day_ops_integrated_plan([], [], []).get("empty"))
        plan = day_ops_integrated_plan(
            theaters=[{"theater_id": "A", "province_ids": [1, 2], "fuel_level": 0.8}],
            signals=[
                {
                    "active": True,
                    "action_class": "sabotage",
                    "influence": 0.6,
                    "province_id": 1,
                }
            ],
            trail=[{"class": "sabotage", "influence": 0.5}],
        )
        self.assertFalse(plan.get("empty"))
        self.assertGreaterEqual(len(plan.get("apply_queue") or []), 1)
        aids = {q.get("action_id") for q in (plan.get("apply_queue") or [])}
        self.assertTrue(
            "fleet_autonomy" in aids
            or "apply_agent_dispatch" in aids
            or "apply_hh_commit" in aids
        )


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(day_ops_integrity().get("ok"))
        loop = close_day_ops_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["empty_plan"].get("empty"))
        self.assertTrue(loop["hh_empty"].get("empty"))


class TestLiveWiring(unittest.TestCase):
    def test_gd_docs_ci(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func naval_multi_phase_for_province", mm)
        self.assertIn("func hh_agenda_product_for_live", mm)
        self.assertIn("func day_ops_integrated_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_day_ops_integrated", gd)
        self.assertIn("func format_naval_multi_phase_plain", gd)
        self.assertIn("func format_hh_agenda_product_plain", gd)
        self.assertIn("day_ops_integrated", gd)
        # Day multi tick wires fleet/agent/day ops
        self.assertIn("apply_fleet_multi_theater_day", gd)
        self.assertIn("apply_agent_auto_dispatch_day", gd)
        self.assertRegex(
            gd,
            r"func run_daily_theater_auto_tick_multi[\s\S]{0,2500}apply_day_ops_integrated|apply_fleet_multi_theater_day",
        )

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("day_ops_integrated", panel)
        self.assertIn("naval multi-phase", panel.lower() or "Naval multi-phase" in panel)
        self.assertTrue(
            "hh agenda product" in panel.lower() or "HH agenda product" in panel or "apply_hh_commit" in panel
        )

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func estimate_naval_multi_phase", fmt)
        self.assertIn("func hh_agenda_product_screen", fmt)
        self.assertIn("func day_ops_integrated_plan", fmt)

        self.assertIn("test_next20_day_ops.py", CI.read_text(encoding="utf-8"))
        todo = TODO.read_text(encoding="utf-8").lower()
        summary = SUMMARY.read_text(encoding="utf-8").lower()
        roadmap = ROADMAP.read_text(encoding="utf-8").lower()
        for label in (
            "day ops integrated",
            "hh agenda product",
            "naval multi-phase",
        ):
            self.assertIn(label, todo, msg=label)
            self.assertIn(label, summary, msg=label)
            self.assertIn(label, roadmap, msg=label)
        self.assertIn("564", TODO.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
