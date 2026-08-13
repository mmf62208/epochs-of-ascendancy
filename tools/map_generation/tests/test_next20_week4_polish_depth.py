#!/usr/bin/env python3
"""Gates: GPU pan/zoom day, tooltip/SFX flair strip, GIS×753."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from week4_polish_depth import (  # noqa: E402
    gpu_pan_zoom_day,
    tooltip_sfx_flair_strip,
    close_week4_polish_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestGpu(unittest.TestCase):
    def test_advisory(self) -> None:
        day = gpu_pan_zoom_day(zoom=0.4, province_count=2665)
        self.assertFalse(day.get("empty"))
        self.assertTrue(day.get("deferred_hard_gate"))
        self.assertGreaterEqual(len(day.get("advice") or []), 1)
        heavy = gpu_pan_zoom_day(zoom=0.95, province_count=2665)
        self.assertGreaterEqual(float(heavy.get("load", 0)), float(day.get("load", 0)) - 0.01)


class TestFlair(unittest.TestCase):
    def test_strip(self) -> None:
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        strip = tooltip_sfx_flair_strip(flair_source=helpers)
        self.assertFalse(strip.get("empty"))
        self.assertGreaterEqual(len(strip.get("rows") or []), 3)
        self.assertTrue((strip.get("audit") or {}).get("ok"))
        sfx = strip.get("sfx_set") or []
        self.assertGreaterEqual(len(sfx), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        loop = close_week4_polish_loop(helpers)
        self.assertFalse(loop.get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func gpu_pan_zoom_day", fmt)
        self.assertIn("func tooltip_sfx_flair_strip", fmt)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func gpu_pan_zoom_day_live", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_gpu_pan_zoom_day", gd)
        self.assertIn("func format_gpu_pan_zoom_day_plain", gd)
        self.assertIn("func format_tooltip_sfx_flair_strip_plain", gd)
        self.assertIn("gpu_pan_zoom_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("gpu_pan_zoom_day", panel)
        self.assertIn("format_tooltip_sfx_flair_strip_plain", panel)

        helpers = GD_HELPERS.read_text(encoding="utf-8")
        self.assertIn("format_province_select_flair", helpers)
        self.assertIn("format_infra_project_flair", helpers)
        self.assertIn("format_capture", helpers)

        self.assertIn("test_next20_week4_polish_depth.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "gpu pan/zoom day",
                "tooltip/sfx flair strip",
                "week-4 polish",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
