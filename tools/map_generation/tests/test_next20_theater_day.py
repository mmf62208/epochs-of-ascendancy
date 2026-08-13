#!/usr/bin/env python3
"""Gates: theater-day depth — readiness/cabinet, convoy-supply day, joint combat timeline, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from theater_day_depth import (  # noqa: E402
    joint_combat_timeline,
    convoy_supply_day_package,
    theater_day_cabinet_package,
    theater_day_integrity,
    close_theater_day_loop,
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


class TestTimeline(unittest.TestCase):
    def test_joint_timeline_weather(self) -> None:
        c = joint_combat_timeline(weather=CLEAR)
        f = joint_combat_timeline(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertGreaterEqual(int(c.get("phase_count", 0)), 7)  # 3 land + 4 naval
        domains = {t.get("domain") for t in (c.get("timeline") or [])}
        self.assertIn("land", domains)
        self.assertIn("naval", domains)
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)


class TestConvoySupply(unittest.TestCase):
    def test_foul_wait_and_apply(self) -> None:
        c = convoy_supply_day_package(weather=CLEAR)
        f = convoy_supply_day_package(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertTrue(c.get("apply_ready"))
        self.assertTrue(f.get("recommend_wait"))
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)
        self.assertTrue(
            any(a.get("action_id") == "apply_supply" for a in (c.get("actions") or []))
        )


class TestCabinet(unittest.TestCase):
    def test_cabinet_queue(self) -> None:
        cab = theater_day_cabinet_package(
            weather=CLEAR,
            trail=[{"class": "sabotage", "influence": 0.5}],
            signal={
                "active": True,
                "action_class": "sabotage",
                "influence": 0.6,
                "province_id": 2,
            },
        )
        self.assertFalse(cab.get("empty"))
        self.assertGreaterEqual(len(cab.get("apply_queue") or []), 2)
        self.assertIn("timeline", cab)
        self.assertIn("convoy", cab)
        self.assertIn("readiness", cab)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(theater_day_integrity().get("ok"))
        loop = close_theater_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func joint_combat_timeline_for_province", mm)
        self.assertIn("func convoy_supply_day_for_province", mm)
        self.assertIn("func theater_day_cabinet_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_theater_day_cabinet", gd)
        self.assertIn("func format_joint_combat_timeline_plain", gd)
        self.assertIn("func format_convoy_supply_day_plain", gd)
        self.assertIn("theater_day_cabinet", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("theater_day_cabinet", panel)
        self.assertTrue(
            "joint combat timeline" in panel.lower() or "timeline" in panel.lower()
        )
        self.assertIn("apply_supply", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func joint_combat_timeline", fmt)
        self.assertIn("func convoy_supply_day_package", fmt)
        self.assertIn("func theater_day_cabinet_package", fmt)

        self.assertIn("test_next20_theater_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "theater day cabinet",
                "joint combat timeline",
                "convoy supply day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
