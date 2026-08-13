#!/usr/bin/env python3
"""Gates: HH agenda screen day, fleet autonomy day, sealane contest visual, GIS×753."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from week3_naval_hh_depth import (  # noqa: E402
    hh_agenda_screen_day,
    fleet_autonomy_day,
    sealane_contest_visual,
    close_week3_naval_hh_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_OVERLAY = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

TRAIL = [
    {"class": "sabotage", "influence": 0.55, "month": 1},
    {"class": "economic_pressure", "influence": 0.4, "month": 2},
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestHHScreen(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        self.assertTrue(hh_agenda_screen_day([]).get("empty"))
        day = hh_agenda_screen_day(TRAIL, province_id=1)
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        self.assertTrue(
            any(q.get("action_id") == "apply_hh_commit" for q in day.get("apply_queue") or [])
        )
        self.assertGreaterEqual(len(day.get("sections") or []), 1)


class TestFleetAuto(unittest.TestCase):
    def test_queue(self) -> None:
        day = fleet_autonomy_day([5, 6, 7], fuel_level=0.4, zone_relation="hostile")
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        low = fleet_autonomy_day([5], fuel_level=0.25)
        self.assertTrue(
            any(q.get("action_id") == "apply_supply" for q in low.get("apply_queue") or [])
            or float(low.get("fuel_level", 1)) < 0.4
        )


class TestSealaneVisual(unittest.TestCase):
    def test_tint_keys(self) -> None:
        h = sealane_contest_visual(zone_relation="hostile", is_choke=True, controller_tag="GER")
        f = sealane_contest_visual(zone_relation="friendly", is_choke=False)
        self.assertIn("hostile", str(h.get("tint_key", "")))
        self.assertIn("friendly", str(f.get("tint_key", "")))
        self.assertGreaterEqual(float(h.get("strength", 0)), float(f.get("strength", 0)) - 0.01)
        self.assertEqual(h.get("mapmode_hint"), "naval")


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        loop = close_week3_naval_hh_loop()
        self.assertFalse(loop.get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func hh_agenda_screen_day", fmt)
        self.assertIn("func fleet_autonomy_day", fmt)
        self.assertIn("func sealane_contest_visual", fmt)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func hh_agenda_screen_day_for_tag", mm)
        self.assertIn("func fleet_autonomy_day_for_tag", mm)
        self.assertIn("func sealane_contest_visual_for_province", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_hh_agenda_screen_day", gd)
        self.assertIn("func apply_fleet_autonomy_day", gd)
        self.assertIn("hh_agenda_screen_day", gd)
        self.assertIn("fleet_autonomy_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("hh_agenda_screen_day", panel)
        self.assertIn("fleet_autonomy_day", panel)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_hh_agenda_screen_day_chip_bbcode", insight)
        self.assertIn("build_fleet_autonomy_day_chip_bbcode", insight)
        self.assertIn("build_sealane_contest_visual_chip_bbcode", insight)

        overlay = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("sealane_contest_visual", overlay)
        self.assertIn("tint_key", overlay)

        self.assertIn("test_next20_week3_naval_hh_depth.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "hh agenda screen day",
                "fleet autonomy day",
                "sealane contest visual",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
