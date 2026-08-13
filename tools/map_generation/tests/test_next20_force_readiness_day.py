#!/usr/bin/env python3
"""Gates: force posture day, theater readiness day, force readiness day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from force_readiness_day import (  # noqa: E402
    force_posture_day,
    theater_readiness_day,
    force_readiness_day,
    force_readiness_integrity,
    close_force_readiness_day_loop,
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


class TestPosture(unittest.TestCase):
    def test_supply_strain(self) -> None:
        healthy = force_posture_day(weather=CLEAR, force_strength=90.0, supply_health=0.95)
        strained = force_posture_day(weather=FOUL, force_strength=90.0, supply_health=0.35)
        self.assertFalse(healthy.get("empty"))
        self.assertFalse(strained.get("empty"))
        self.assertTrue(any(q.get("action_id") == "apply_supply" for q in strained.get("apply_queue") or []))
        self.assertGreaterEqual(len(healthy.get("apply_queue") or []), 1)


class TestTheater(unittest.TestCase):
    def test_wx_shift(self) -> None:
        c = theater_readiness_day(weather=CLEAR)
        f = theater_readiness_day(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertFalse(f.get("empty"))
        self.assertGreaterEqual(float(c.get("score", 0)), float(f.get("score", 0)) - 0.05)


class TestCompose(unittest.TestCase):
    def test_force_readiness(self) -> None:
        day = force_readiness_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("posture", day)
        self.assertIn("readiness", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(force_readiness_integrity().get("ok"))
        loop = close_force_readiness_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("supply_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func force_posture_day_for_province", mm)
        self.assertIn("func theater_readiness_day_for_province", mm)
        self.assertIn("func force_readiness_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_force_readiness_day", gd)
        self.assertIn("func apply_force_posture_day", gd)
        self.assertIn("func apply_theater_readiness_day", gd)
        self.assertIn("force_readiness_day", gd)
        self.assertIn("force_posture_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("force_readiness_day", panel)
        self.assertIn("force_posture_day", panel)
        self.assertIn("theater_readiness_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func force_posture_day", fmt)
        self.assertIn("func theater_readiness_day", fmt)
        self.assertIn("func force_readiness_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_force_posture_day_chip_bbcode", insight)
        self.assertIn("build_force_readiness_day_chip_bbcode", insight)

        self.assertIn("test_next20_force_readiness_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "force posture day",
                "theater readiness day",
                "force readiness day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
