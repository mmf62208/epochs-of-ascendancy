#!/usr/bin/env python3
"""Gates: production surge day, depot capacity day, industry surge day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from industry_surge_day import (  # noqa: E402
    production_surge_day,
    depot_capacity_day,
    industry_surge_day,
    industry_surge_integrity,
    close_industry_surge_day_loop,
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

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "temperature_c": 12.0, "ground_state": "dry"}
FOUL = {"precip_intensity": 0.9, "visibility": 0.3, "temperature_c": -12.0, "ground_state": "mud"}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestProduction(unittest.TestCase):
    def test_surge_queue(self) -> None:
        c = production_surge_day(weather=CLEAR)
        f = production_surge_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(f.get("empty"))
        self.assertTrue(any(q.get("action_id") == "apply_production" for q in c.get("apply_queue") or []))
        # Foul should be more alert-prone
        self.assertTrue(any(q.get("action_id") == "apply_supply" for q in f.get("apply_queue") or []) or f.get("priority"))


class TestDepot(unittest.TestCase):
    def test_sea_and_wx(self) -> None:
        good = depot_capacity_day(weather=CLEAR, sea_mult=1.1, base_capacity=100.0)
        bad = depot_capacity_day(weather=FOUL, sea_mult=0.4, base_capacity=100.0)
        self.assertFalse(good.get("empty"))
        self.assertFalse(bad.get("empty"))
        self.assertGreaterEqual(float(good.get("capacity", 0)), float(bad.get("capacity", 0)) - 0.01)
        self.assertGreaterEqual(float(good.get("score", 0)), float(bad.get("score", 0)) - 0.01)


class TestCompose(unittest.TestCase):
    def test_industry_surge(self) -> None:
        day = industry_surge_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("surge", day)
        self.assertIn("depot", day)
        self.assertIn("industry", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(industry_surge_integrity().get("ok"))
        loop = close_industry_surge_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("sea_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func production_surge_day_for_province", mm)
        self.assertIn("func depot_capacity_day_for_province", mm)
        self.assertIn("func industry_surge_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_industry_surge_day", gd)
        self.assertIn("func apply_production_surge_day", gd)
        self.assertIn("func apply_depot_capacity_day", gd)
        self.assertIn("industry_surge_day", gd)
        self.assertIn("production_surge_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("industry_surge_day", panel)
        self.assertIn("production_surge_day", panel)
        self.assertIn("depot_capacity_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func production_surge_day", fmt)
        self.assertIn("func depot_capacity_day", fmt)
        self.assertIn("func industry_surge_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_production_surge_day_chip_bbcode", insight)
        self.assertIn("build_industry_surge_day_chip_bbcode", insight)

        self.assertIn("test_next20_industry_surge_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "production surge day",
                "depot capacity day",
                "industry surge day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
