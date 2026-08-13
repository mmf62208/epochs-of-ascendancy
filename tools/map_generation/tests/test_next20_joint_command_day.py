#!/usr/bin/env python3
"""Gates: naval interdiction day, intel counter day, joint command day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from joint_command_day import (  # noqa: E402
    naval_interdiction_day,
    intel_counter_day,
    joint_command_day,
    joint_command_integrity,
    close_joint_command_day_loop,
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

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2}
FOUL = {"precip_intensity": 0.95, "visibility": 0.2, "wind": 0.9, "ground_state": "mud"}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestNaval(unittest.TestCase):
    def test_interdiction_wx(self) -> None:
        c = naval_interdiction_day(weather=CLEAR)
        f = naval_interdiction_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertGreater(float(c["interdiction_score"]), float(f["interdiction_score"]) - 0.01)
        self.assertTrue(len(c.get("apply_queue") or []) >= 1)
        empty = naval_interdiction_day(path_zone_relations=[])
        self.assertTrue(empty.get("empty"))


class TestIntel(unittest.TestCase):
    def test_signal_and_empty(self) -> None:
        day = intel_counter_day(
            {"action_class": "sabotage", "province_id": 9},
            [{"month": 1}],
            province_id=9,
        )
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 2)
        empty = intel_counter_day({}, [])
        self.assertTrue(empty.get("empty"))


class TestCompose(unittest.TestCase):
    def test_joint_command_day(self) -> None:
        day = joint_command_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("naval", day)
        self.assertIn("intel", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        foul = joint_command_day(weather=FOUL)
        self.assertFalse(foul.get("empty"))


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(joint_command_integrity().get("ok"))
        loop = close_joint_command_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertTrue(loop["empty_intel"].get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func naval_interdiction_day_for_province", mm)
        self.assertIn("func intel_counter_day_for_tag", mm)
        self.assertIn("func joint_command_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_joint_command_day", gd)
        self.assertIn("func apply_naval_interdiction_day", gd)
        self.assertIn("func apply_intel_counter_day", gd)
        self.assertIn("joint_command_day", gd)
        self.assertIn("naval_interdiction_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("joint_command_day", panel)
        self.assertIn("naval_interdiction_day", panel)
        self.assertIn("intel_counter_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func naval_interdiction_day", fmt)
        self.assertIn("func intel_counter_day", fmt)
        self.assertIn("func joint_command_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_naval_interdiction_day_chip_bbcode", insight)
        self.assertIn("build_joint_command_day_chip_bbcode", insight)

        self.assertIn("test_next20_joint_command_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "naval interdiction day",
                "intel counter day",
                "joint command day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
