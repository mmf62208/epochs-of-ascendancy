#!/usr/bin/env python3
"""Gates: naval campaign day, air-land joint day, joint campaign day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from joint_campaign_day import (  # noqa: E402
    naval_campaign_day,
    air_land_joint_day,
    joint_campaign_day,
    joint_campaign_integrity,
    close_joint_campaign_day_loop,
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
FOUL = {"precip_intensity": 0.9, "visibility": 0.25, "wind": 0.85, "ground_state": "mud"}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestNaval(unittest.TestCase):
    def test_fuel_and_queue(self) -> None:
        good = naval_campaign_day(weather=CLEAR, fuel_level=0.8)
        low = naval_campaign_day(weather=FOUL, fuel_level=0.25)
        self.assertFalse(good.get("empty"))
        self.assertFalse(low.get("empty"))
        self.assertTrue(any(q.get("action_id") == "apply_supply" for q in low.get("apply_queue") or []))
        self.assertGreaterEqual(len(good.get("apply_queue") or []), 1)


class TestAirLand(unittest.TestCase):
    def test_wx(self) -> None:
        c = air_land_joint_day(weather=CLEAR)
        f = air_land_joint_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(f.get("empty"))
        self.assertGreaterEqual(float(c.get("score", 0)), float(f.get("score", 0)) - 0.05)


class TestCompose(unittest.TestCase):
    def test_joint_campaign(self) -> None:
        day = joint_campaign_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("naval", day)
        self.assertIn("air_land", day)
        self.assertIn("leader", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(joint_campaign_integrity().get("ok"))
        loop = close_joint_campaign_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("fuel_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func naval_campaign_day_for_province", mm)
        self.assertIn("func air_land_joint_day_for_province", mm)
        self.assertIn("func joint_campaign_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_joint_campaign_day", gd)
        self.assertIn("func apply_naval_campaign_day", gd)
        self.assertIn("func apply_air_land_joint_day", gd)
        self.assertIn("joint_campaign_day", gd)
        self.assertIn("naval_campaign_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("joint_campaign_day", panel)
        self.assertIn("naval_campaign_day", panel)
        self.assertIn("air_land_joint_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func naval_campaign_day", fmt)
        self.assertIn("func air_land_joint_day", fmt)
        self.assertIn("func joint_campaign_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_naval_campaign_day_chip_bbcode", insight)
        self.assertIn("build_joint_campaign_day_chip_bbcode", insight)

        self.assertIn("test_next20_joint_campaign_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "naval campaign day",
                "air-land joint day",
                "joint campaign day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
