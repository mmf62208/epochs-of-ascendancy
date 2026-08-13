#!/usr/bin/env python3
"""Gates: war-economy day — focus+production, multi-front assault day, command strip, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from war_economy_day import (  # noqa: E402
    war_economy_day_package,
    multi_front_assault_day,
    theater_day_command_strip,
    war_economy_theater_day,
    war_economy_integrity,
    close_war_economy_day_loop,
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


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestWarEconomy(unittest.TestCase):
    def test_weather_and_actions(self) -> None:
        c = war_economy_day_package(weather=CLEAR)
        f = war_economy_day_package(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertTrue(c.get("sole_mult"))
        self.assertTrue(
            any(a.get("action_id") == "apply_production" for a in (c.get("actions") or []))
        )
        self.assertTrue(
            any(a.get("action_id") == "apply_focus" for a in (c.get("actions") or []))
        )
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)


class TestMultiFront(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        self.assertTrue(multi_front_assault_day([]).get("empty"))
        day = multi_front_assault_day(
            [
                {"province_id": 1, "defender_power": 50.0},
                {"province_id": 2, "defender_power": 120.0},
            ],
            weather=CLEAR,
        )
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        self.assertTrue(
            any(q.get("action_id") == "apply_assault" for q in (day.get("apply_queue") or []))
        )


class TestStripAndCompose(unittest.TestCase):
    def test_strip_and_day(self) -> None:
        self.assertTrue(
            theater_day_command_strip(None, None, None, []).get("empty")
        )
        day = war_economy_theater_day(
            weather=CLEAR,
            trail=[{"class": "sabotage"}],
            signal={
                "active": True,
                "action_class": "sabotage",
                "influence": 0.5,
                "province_id": 1,
            },
        )
        self.assertFalse(day.get("empty"))
        self.assertFalse(day.get("strip", {}).get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 2)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(war_economy_integrity().get("ok"))
        loop = close_war_economy_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["empty_fronts"].get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func war_economy_day_for_province", mm)
        self.assertIn("func multi_front_assault_day_for_tag", mm)
        self.assertIn("func war_economy_theater_day_for_tag", mm)
        self.assertIn("func theater_day_command_strip_live", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_war_economy_day", gd)
        self.assertIn("func apply_multi_front_assault_day", gd)
        self.assertIn("func format_war_economy_day_plain", gd)
        self.assertIn("func format_theater_day_command_strip_plain", gd)
        self.assertIn("war_economy_day", gd)
        self.assertIn("multi_front_assault_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("war_economy_day", panel)
        self.assertIn("multi_front_assault_day", panel)
        self.assertTrue(
            "command strip" in panel.lower() or "war economy" in panel.lower()
        )

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func war_economy_day_package", fmt)
        self.assertIn("func multi_front_assault_day", fmt)
        self.assertIn("func theater_day_command_strip", fmt)

        self.assertIn("test_next20_war_economy_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "war economy day",
                "multi-front assault day",
                "theater day command strip",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
