#!/usr/bin/env python3
"""Gates: next-40 campaign surface day packages (10) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next40_campaign_surface import (  # noqa: E402
    CAMPAIGN_SURFACE_DAY_IDS,
    sealane_health_day,
    convoy_package_day,
    theater_campaign_day,
    production_risk_day,
    leader_campaign_day,
    basing_repair_day,
    focus_order_day,
    naval_order_day,
    air_land_order_day,
    theater_order_day,
    close_next40_campaign_surface_loop,
    campaign_surface_integrity,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

DAY_FUNCS = [
    sealane_health_day,
    convoy_package_day,
    theater_campaign_day,
    production_risk_day,
    leader_campaign_day,
    basing_repair_day,
    focus_order_day,
    naval_order_day,
    air_land_order_day,
    theater_order_day,
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_ten_ids(self) -> None:
        self.assertEqual(len(CAMPAIGN_SURFACE_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)

    def test_each_nonempty_queue(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), msg=fn.__name__)
                self.assertTrue(str(day.get("summary", "")).strip(), msg=fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, msg=fn.__name__)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, CAMPAIGN_SURFACE_DAY_IDS)

    def test_close_loop(self) -> None:
        loop = close_next40_campaign_surface_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 10)
        self.assertTrue(campaign_surface_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")

        for aid in CAMPAIGN_SURFACE_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF missing %s" % aid)
            self.assertIn(aid, gd, msg="GameData missing %s" % aid)
            self.assertIn(aid, panel, msg="panel missing %s" % aid)

        for name in (
            "sealane_health_day_for_province",
            "convoy_package_day_for_province",
            "theater_campaign_day_for_province",
            "production_risk_day_for_province",
            "leader_campaign_day_for_province",
            "basing_repair_day_for_province",
            "focus_order_day_live",
            "naval_order_day_for_province",
            "air_land_order_day_for_province",
            "theater_order_day_for_province",
        ):
            self.assertIn("func %s" % name, mm, msg="MM missing %s" % name)

        for name in (
            "apply_sealane_health_day",
            "apply_convoy_package_day",
            "apply_theater_campaign_day",
            "apply_production_risk_day",
            "apply_leader_campaign_day",
            "apply_basing_repair_day",
            "apply_focus_order_day",
            "apply_naval_order_day",
            "apply_air_land_order_day",
            "apply_theater_order_day",
        ):
            self.assertIn("func %s" % name, gd, msg="GD apply missing %s" % name)

        self.assertIn("sealane_health_day", pi)
        self.assertIn("theater_campaign_day", pi)
        self.assertIn("theater_order_day", pi)

        self.assertIn("test_next20_campaign_surface_days.py", CI.read_text(encoding="utf-8"))

        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "sealane health day",
                "convoy package day",
                "theater campaign day",
                "production risk day",
                "leader campaign day",
                "basing repair day",
                "focus order day",
                "naval order day",
                "air-land order day",
                "theater order day",
                "next-40 campaign",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
