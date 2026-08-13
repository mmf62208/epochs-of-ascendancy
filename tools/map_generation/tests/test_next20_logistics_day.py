#!/usr/bin/env python3
"""Gates: logistics day — sealane/choke, leader-station day, inspector chips, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from logistics_day_depth import (  # noqa: E402
    sealane_choke_logistics_day,
    leader_formation_station_day,
    logistics_day_package,
    logistics_day_integrity,
    close_logistics_day_loop,
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

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0}
FOUL = {"precip_intensity": 0.85, "visibility": 0.3}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestSealaneChoke(unittest.TestCase):
    def test_weather_and_actions(self) -> None:
        c = sealane_choke_logistics_day(weather=CLEAR)
        f = sealane_choke_logistics_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertTrue(
            any(a.get("action_id") == "apply_supply" for a in (c.get("actions") or []))
        )
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)


class TestStationDay(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        self.assertTrue(leader_formation_station_day([]).get("empty"))
        day = leader_formation_station_day(
            [
                {"province_id": 1, "basing_level": "port", "fuel_level": 0.7},
                {"province_id": 2, "basing_level": "none", "fuel_level": 0.2},
            ],
            weather=CLEAR,
        )
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        self.assertTrue(
            any(q.get("action_id") == "apply_station" for q in (day.get("apply_queue") or []))
        )


class TestLogisticsDay(unittest.TestCase):
    def test_package(self) -> None:
        day = logistics_day_package(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        self.assertIn("strip", day)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(logistics_day_integrity().get("ok"))
        loop = close_logistics_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["empty_station"].get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func sealane_choke_logistics_day_for_province", mm)
        self.assertIn("func leader_formation_station_day_for_tag", mm)
        self.assertIn("func logistics_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_logistics_day", gd)
        self.assertIn("func apply_leader_station_day", gd)
        self.assertIn("func format_logistics_day_plain", gd)
        self.assertIn("logistics_day", gd)
        self.assertIn("leader_station_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("logistics_day", panel)
        self.assertIn("leader_station_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func sealane_choke_logistics_day", fmt)
        self.assertIn("func leader_formation_station_day", fmt)
        self.assertIn("func logistics_day_package", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_war_economy_day_chip_bbcode", insight)
        self.assertIn("build_logistics_day_chip_bbcode", insight)
        self.assertIn("build_theater_day_command_strip_chip_bbcode", insight)

        self.assertIn("test_next20_logistics_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "logistics day",
                "sealane choke",
                "leader station day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
