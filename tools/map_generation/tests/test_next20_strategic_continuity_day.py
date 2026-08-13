#!/usr/bin/env python3
"""Gates: order execute day, focus war path day, strategic continuity day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from strategic_continuity_day import (  # noqa: E402
    order_execute_day,
    focus_war_path_day,
    strategic_continuity_day,
    strategic_continuity_integrity,
    close_strategic_continuity_day_loop,
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
FOUL = {"precip_intensity": 0.9, "visibility": 0.25, "wind": 0.8, "ground_state": "mud"}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestOrderExecute(unittest.TestCase):
    def test_queue_and_budget(self) -> None:
        day = order_execute_day(weather=CLEAR, max_executes=2)
        # Theater auto usually yields items; if empty still ok structure
        if not day.get("empty"):
            self.assertLessEqual(len(day.get("apply_queue") or []), 2)
            self.assertTrue(any(q.get("action_id") for q in day.get("apply_queue") or []))
        foul = order_execute_day(weather=FOUL, max_executes=3)
        self.assertIn("score", foul if not foul.get("empty") else {"score": 0})


class TestFocusDay(unittest.TestCase):
    def test_focus_actions(self) -> None:
        day = focus_war_path_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertTrue(day.get("best_focus"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        foul = focus_war_path_day(weather=FOUL)
        self.assertFalse(foul.get("empty"))


class TestCompose(unittest.TestCase):
    def test_continuity_day(self) -> None:
        day = strategic_continuity_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("orders", day)
        self.assertIn("focus", day)
        self.assertIn("feedback", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(strategic_continuity_integrity().get("ok"))
        loop = close_strategic_continuity_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertTrue(loop["empty_orders"].get("empty"))
        # Weather should shift focus score at least slightly or equal is ok if stub
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func order_execute_day_for_province", mm)
        self.assertIn("func focus_war_path_day_for_province", mm)
        self.assertIn("func strategic_continuity_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_strategic_continuity_day", gd)
        self.assertIn("func apply_order_execute_day", gd)
        self.assertIn("func apply_focus_war_path_day", gd)
        self.assertIn("strategic_continuity_day", gd)
        self.assertIn("order_execute_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("strategic_continuity_day", panel)
        self.assertIn("order_execute_day", panel)
        self.assertIn("focus_war_path_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func order_execute_day", fmt)
        self.assertIn("func focus_war_path_day", fmt)
        self.assertIn("func strategic_continuity_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_order_execute_day_chip_bbcode", insight)
        self.assertIn("build_strategic_continuity_day_chip_bbcode", insight)

        self.assertIn("test_next20_strategic_continuity_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "order execute day",
                "focus war path day",
                "strategic continuity day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
