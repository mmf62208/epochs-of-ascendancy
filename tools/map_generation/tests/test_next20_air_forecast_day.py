#!/usr/bin/env python3
"""Gates: air-ops day, forecast planning day, reinforced assault day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from air_forecast_day import (  # noqa: E402
    air_ops_day_package,
    weather_forecast_planning_day,
    reinforced_assault_day,
    air_forecast_assault_day,
    air_forecast_integrity,
    close_air_forecast_day_loop,
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


class TestAirOpsDay(unittest.TestCase):
    def test_grounded_and_score(self) -> None:
        c = air_ops_day_package(weather=CLEAR)
        f = air_ops_day_package(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(c.get("grounded"))
        self.assertTrue(f.get("grounded"))
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)
        self.assertTrue(c.get("apply_ready"))
        self.assertFalse(f.get("apply_ready"))


class TestForecastDay(unittest.TestCase):
    def test_wait_go(self) -> None:
        c = weather_forecast_planning_day(weather=CLEAR)
        f = weather_forecast_planning_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(c.get("recommend_wait"))
        self.assertTrue(f.get("recommend_wait"))


class TestReinforced(unittest.TestCase):
    def test_empty_and_queue(self) -> None:
        self.assertTrue(reinforced_assault_day([]).get("empty"))
        day = reinforced_assault_day(
            [{"province_id": 1, "defender_power": 70.0}], weather=CLEAR
        )
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestCompose(unittest.TestCase):
    def test_air_forecast_day(self) -> None:
        day = air_forecast_assault_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        foul = air_forecast_assault_day(weather=FOUL)
        # foul prefers focus hold over assault spam
        aids = {q.get("action_id") for q in (foul.get("apply_queue") or [])}
        self.assertTrue("apply_focus" in aids or foul.get("forecast", {}).get("recommend_wait"))


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(air_forecast_integrity().get("ok"))
        loop = close_air_forecast_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["empty_assault"].get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func air_ops_day_for_province", mm)
        self.assertIn("func weather_forecast_planning_day_for_province", mm)
        self.assertIn("func reinforced_assault_day_for_tag", mm)
        self.assertIn("func air_forecast_assault_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_air_forecast_day", gd)
        self.assertIn("func apply_reinforced_assault_day", gd)
        self.assertIn("func format_air_ops_day_plain", gd)
        self.assertIn("air_forecast_day", gd)
        self.assertIn("reinforced_assault_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("air_forecast_day", panel)
        self.assertIn("reinforced_assault_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func air_ops_day_package", fmt)
        self.assertIn("func weather_forecast_planning_day", fmt)
        self.assertIn("func reinforced_assault_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_air_ops_day_chip_bbcode", insight)
        self.assertIn("build_forecast_planning_day_chip_bbcode", insight)

        self.assertIn("test_next20_air_forecast_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "air ops day",
                "forecast planning day",
                "reinforced assault day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
