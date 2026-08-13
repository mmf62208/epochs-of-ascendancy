#!/usr/bin/env python3
"""Gates: ground transition day, fog/air crisis day, weather crisis day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from weather_crisis_day import (  # noqa: E402
    ground_transition_day,
    fog_air_crisis_day,
    weather_crisis_day,
    weather_crisis_integrity,
    close_weather_crisis_day_loop,
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

CLEAR = {
    "precip_intensity": 0.0,
    "visibility": 1.0,
    "temperature_c": 12.0,
    "ground_state": "dry",
    "wind": 0.2,
}
FOUL = {
    "precip_intensity": 0.9,
    "visibility": 0.25,
    "temperature_c": -8.0,
    "ground_state": "mud",
    "wind": 0.9,
}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestGround(unittest.TestCase):
    def test_transition_queue(self) -> None:
        c = ground_transition_day(weather=CLEAR)
        f = ground_transition_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(f.get("empty"))
        self.assertGreaterEqual(len(c.get("apply_queue") or []), 1)
        self.assertGreaterEqual(float(f.get("score", 0)), float(c.get("score", 0)) - 0.01)


class TestFogAir(unittest.TestCase):
    def test_crisis_higher_in_foul(self) -> None:
        c = fog_air_crisis_day(weather=CLEAR)
        f = fog_air_crisis_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(f.get("empty"))
        self.assertGreaterEqual(float(f.get("score", 0)), float(c.get("score", 0)) - 0.01)
        self.assertTrue(
            any(q.get("action_id") in ("fleet_autonomy", "apply_focus", "apply_supply") for q in f.get("apply_queue") or [])
        )


class TestCompose(unittest.TestCase):
    def test_weather_crisis(self) -> None:
        day = weather_crisis_day(weather=FOUL)
        self.assertFalse(day.get("empty"))
        self.assertIn("ground", day)
        self.assertIn("fog_air", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(weather_crisis_integrity().get("ok"))
        loop = close_weather_crisis_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("ground_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func ground_transition_day_for_province", mm)
        self.assertIn("func fog_air_crisis_day_for_province", mm)
        self.assertIn("func weather_crisis_day_for_province", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_weather_crisis_day", gd)
        self.assertIn("func apply_ground_transition_day", gd)
        self.assertIn("func apply_fog_air_crisis_day", gd)
        self.assertIn("weather_crisis_day", gd)
        self.assertIn("ground_transition_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("weather_crisis_day", panel)
        self.assertIn("ground_transition_day", panel)
        self.assertIn("fog_air_crisis_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func ground_transition_day", fmt)
        self.assertIn("func fog_air_crisis_day", fmt)
        self.assertIn("func weather_crisis_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_fog_air_crisis_day_chip_bbcode", insight)
        self.assertIn("build_weather_crisis_day_chip_bbcode", insight)

        self.assertIn("test_next20_weather_crisis_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "ground transition day",
                "fog/air crisis day",
                "weather crisis day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
