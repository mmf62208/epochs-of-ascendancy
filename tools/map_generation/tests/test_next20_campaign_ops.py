#!/usr/bin/env python3
"""Gates: campaign ops depth — combat air-naval joint, multi-theater fleet day, agent auto-dispatch, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from campaign_ops_depth import (  # noqa: E402
    combat_air_naval_joint,
    fleet_multi_theater_day,
    agent_auto_dispatch_day,
    campaign_ops_integrity,
    close_campaign_ops_loop,
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

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0}
FOUL = {"precip_intensity": 0.9, "visibility": 0.2, "ground_state": "mud"}


class TestGis564(unittest.TestCase):
    def test_stamped_all_coastal_floor(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)
        self.assertGreater(stamped, 528)


class TestCombatAirNaval(unittest.TestCase):
    def test_joint_phases_and_weather(self) -> None:
        c = combat_air_naval_joint(weather=CLEAR)
        f = combat_air_naval_joint(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertEqual(len(c.get("phase_rows") or []), 3)
        self.assertIn("air", c)
        self.assertIn("naval", c)
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)
        self.assertTrue(any(a.get("action_id") == "apply_assault" for a in (c.get("actions") or [])))


class TestFleetMultiTheater(unittest.TestCase):
    def test_empty_and_fuel_queue(self) -> None:
        self.assertTrue(fleet_multi_theater_day([]).get("empty"))
        day = fleet_multi_theater_day(
            [
                {"theater_id": "A", "province_ids": [1, 2], "fuel_level": 0.8},
                {"theater_id": "B", "province_ids": [3], "fuel_level": 0.12},
            ],
            max_applies=2,
        )
        self.assertFalse(day.get("empty"))
        self.assertEqual(int(day.get("theater_count", 0)), 2)
        self.assertEqual(int(day.get("ready_count", 0)), 1)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        self.assertLessEqual(len(day.get("apply_queue") or []), 2)


class TestAgentAutoDay(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        self.assertTrue(agent_auto_dispatch_day([]).get("empty"))
        day = agent_auto_dispatch_day(
            [
                {
                    "active": True,
                    "action_class": "sabotage",
                    "influence": 0.7,
                    "province_id": 1,
                },
                {
                    "active": True,
                    "action_class": "economic_pressure",
                    "influence": 0.55,
                    "province_id": 2,
                },
            ]
        )
        self.assertFalse(day.get("empty"))
        q = day.get("dispatch_queue") or []
        self.assertGreaterEqual(len(q), 1)
        aids = {x.get("action_id") for x in q}
        self.assertIn("apply_agent_dispatch", aids)
        self.assertGreaterEqual(float(day.get("affinity", 0)), 0.5)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(campaign_ops_integrity().get("ok"))
        loop = close_campaign_ops_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["agent_empty"].get("empty"))


class TestLiveWiring(unittest.TestCase):
    def test_gd_and_docs(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func combat_air_naval_joint_for_province", mm)
        self.assertIn("func fleet_multi_theater_day_for_tag", mm)
        self.assertIn("func agent_auto_dispatch_day_live", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_fleet_multi_theater_day", gd)
        self.assertIn("func apply_agent_auto_dispatch_day", gd)
        self.assertIn("func format_combat_air_naval_joint_plain", gd)
        self.assertIn("fleet_multi_day", gd)
        self.assertIn("agent_auto_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        panel_l = panel.lower()
        self.assertTrue(
            "air-naval" in panel_l or "air_naval" in panel_l or "joint" in panel_l,
            msg="panel must surface air-naval joint combat",
        )
        self.assertIn("fleet_multi_day", panel)
        self.assertIn("agent_auto_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func combat_air_naval_joint", fmt)
        self.assertIn("func fleet_multi_theater_day", fmt)
        self.assertIn("func agent_auto_dispatch_day", fmt)

        self.assertIn("test_next20_campaign_ops.py", CI.read_text(encoding="utf-8"))
        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertIn("564", todo)
        self.assertIn("564", summary)
        for label in (
            "combat air-naval",
            "fleet multi-theater",
            "agent auto-dispatch",
        ):
            self.assertIn(label, todo.lower(), msg=label)
            self.assertIn(label, summary.lower(), msg=label)
            self.assertIn(label, roadmap.lower(), msg=label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
