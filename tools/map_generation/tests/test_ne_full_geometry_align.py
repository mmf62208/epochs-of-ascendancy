#!/usr/bin/env python3
"""Gates: Natural Earth full-world geometry align — all 2665 id-stable."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from ne_full_geometry_align import (  # noqa: E402
    DEFAULT_NE_LAND,
    geometry_stats,
    lonlat_to_canvas,
    ne_full_integrity_report,
    ensure_min_vertices,
)

WF = ROOT / "data" / "provinces_world_full"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
DESIGN = ROOT / "docs" / "GIS_COASTLINE_INGEST_DESIGN.md"
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "align_ne_full_geometry.py"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestHelpers(unittest.TestCase):
    def test_lonlat_canvas_and_densify(self):
        x, y = lonlat_to_canvas(0.0, 0.0)
        self.assertGreater(x, 3000)
        self.assertLess(x, 5200)
        ring = ensure_min_vertices([[0, 0], [10, 0], [10, 10], [0, 10]], min_vertices=20)
        self.assertGreaterEqual(len(ring), 20)


class TestStamped(unittest.TestCase):
    def test_all_2665_ne_full(self):
        self.assertTrue(DEFAULT_NE_LAND.is_file(), msg="NE land geojson missing from cache")
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        report = ne_full_integrity_report(geom)
        self.assertTrue(report.get("ok"), msg=report.get("summary"))
        self.assertEqual(int(report.get("province_count") or 0), 2665)
        self.assertGreaterEqual(int(report.get("gis_ne_full_count") or 0), 2665)
        self.assertGreaterEqual(int(report.get("gis_pilot_count") or 0), 2665)
        stats = report.get("stats") or {}
        self.assertEqual(int(stats.get("triangles") or 0), 0)
        self.assertGreaterEqual(int(stats.get("min") or 0), 16)
        meta = geom.get("meta") or {}
        self.assertTrue(meta.get("gis_ne_full"))
        self.assertEqual(str(meta.get("gis_ne_source", "")), "ne_10m_land")
        # Domain split present
        self.assertGreaterEqual(int(meta.get("gis_ne_land_count") or 0), 2000)
        self.assertGreaterEqual(int(meta.get("gis_ne_water_count") or 0), 300)


class TestTooling(unittest.TestCase):
    def test_script_and_ci(self):
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("--write", script)
        self.assertIn("--full", script)
        self.assertTrue(
            "ne_10m_land" in script or "NE 10m" in script or "Natural Earth 10m" in script
        )
        self.assertIn("test_ne_full_geometry_align.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "natural earth",
            "ne full",
            "2665",
            "ne_10m_land",
            "gis_ne_full",
        ]
        for path in (TODO, SUMMARY, ROADMAP, DESIGN):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
