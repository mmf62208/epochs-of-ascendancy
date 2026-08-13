#!/usr/bin/env python3
"""Gates: fleet redeploy day, task group day, fleet campaign day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from fleet_campaign_day import (  # noqa: E402
    fleet_redeploy_day,
    fleet_task_group_day,
    fleet_campaign_day,
    fleet_campaign_integrity,
    close_fleet_campaign_day_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestRedeploy(unittest.TestCase):
    def test_queue(self) -> None:
        day = fleet_redeploy_day(fuel_level=0.8)
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        low = fleet_redeploy_day(fuel_level=0.3)
        self.assertTrue(
            any(q.get("action_id") == "fleet_autonomy" for q in low.get("apply_queue") or [])
        )


class TestTaskGroup(unittest.TestCase):
    def test_compose(self) -> None:
        patrol = fleet_task_group_day(mission="patrol", zone_relation="friendly")
        strike = fleet_task_group_day(
            mission="strike", zone_relation="hostile", escort_need=30.0
        )
        self.assertFalse(patrol.get("empty"))
        self.assertFalse(strike.get("empty"))
        self.assertIn(str(patrol.get("primary_role", "")), ("SCREEN", "STRIKE", "SUPPORT"))
        self.assertGreaterEqual(len(strike.get("apply_queue") or []), 1)


class TestCompose(unittest.TestCase):
    def test_fleet_campaign(self) -> None:
        day = fleet_campaign_day()
        self.assertFalse(day.get("empty"))
        self.assertIn("redeploy", day)
        self.assertIn("task_group", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(fleet_campaign_integrity().get("ok"))
        loop = close_fleet_campaign_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("fuel_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("task_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_redeploy_day_for_province", mm)
        self.assertIn("func fleet_task_group_day_for_province", mm)
        self.assertIn("func fleet_campaign_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_fleet_campaign_day", gd)
        self.assertIn("func apply_fleet_redeploy_day", gd)
        self.assertIn("func apply_fleet_task_group_day", gd)
        self.assertIn("fleet_campaign_day", gd)
        self.assertIn("fleet_redeploy_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("fleet_campaign_day", panel)
        self.assertIn("fleet_redeploy_day", panel)
        self.assertIn("fleet_task_group_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func fleet_redeploy_day", fmt)
        self.assertIn("func fleet_task_group_day", fmt)
        self.assertIn("func fleet_campaign_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fleet_redeploy_day_chip_bbcode", insight)
        self.assertIn("build_fleet_campaign_day_chip_bbcode", insight)

        self.assertIn("test_next20_fleet_campaign_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "fleet redeploy day",
                "fleet task group day",
                "fleet campaign day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
