#!/usr/bin/env python3
"""Unit tests for Europe-theater province name assignment (shipped path)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = ROOT / "tools" / "map_generation" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from assign_europe_province_names import (  # noqa: E402
    PLACEHOLDER_RE,
    assign_names_to_provinces,
    build_gazetteer_canvas,
    europe_gazetteer,
    lonlat_to_canvas,
    run_on_dir,
)


class TestLonLatFit(unittest.TestCase):
    def test_berlin_near_known_canvas(self) -> None:
        # Berlin lon/lat should land near live geometry centroid ~ (2183, 431)
        x, y = lonlat_to_canvas(13.40, 52.52)
        self.assertAlmostEqual(x, 2183.0, delta=25.0)
        self.assertAlmostEqual(y, 431.0, delta=25.0)

    def test_london_west_of_berlin(self) -> None:
        lx, _ = lonlat_to_canvas(-0.13, 51.51)
        bx, _ = lonlat_to_canvas(13.40, 52.52)
        self.assertLess(lx, bx)


class TestAssignmentPure(unittest.TestCase):
    def test_replaces_placeholders_with_unique_names(self) -> None:
        base = [
            {"id": 1, "name": "Province 9000"},
            {"id": 2, "name": "Tokyo"},
            {"id": 3, "name": "Berlin"},
            {"id": 4, "name": "New Settlement"},
        ]
        geom = [
            {"id": 1, "points": [[2100.0, 430.0], [2110.0, 430.0], [2110.0, 440.0]]},
            {"id": 2, "points": [[2000.0, 450.0], [2010.0, 450.0], [2010.0, 460.0]]},
            {"id": 3, "points": [[2180.0, 430.0], [2190.0, 430.0], [2190.0, 440.0]]},
            {"id": 4, "points": [[2050.0, 470.0], [2060.0, 470.0], [2060.0, 480.0]]},
        ]
        out = assign_names_to_provinces(base, geom)
        names = [p["name"] for p in out["provinces"]]
        self.assertEqual(len(names), len(set(n.lower() for n in names)))
        self.assertEqual(out["stats"]["placeholders_remaining"], 0)
        self.assertEqual(out["stats"]["non_europe_remaining"], 0)
        # Berlin locked
        berlin = next(p for p in out["provinces"] if p["id"] == 3)
        self.assertEqual(berlin["name"], "Berlin")
        for n in names:
            self.assertIsNone(PLACEHOLDER_RE.match(n), msg=n)

    def test_gazetteer_has_enough_capacity(self) -> None:
        gaz = europe_gazetteer()
        self.assertGreaterEqual(len(gaz), 400)
        canvas = build_gazetteer_canvas(gaz)
        self.assertEqual(len(canvas), len(gaz))


class TestShippedFullEuropeData(unittest.TestCase):
    """Drive the real shipped data path (not a reimplementation)."""

    def test_full_europe_base_has_no_placeholders(self) -> None:
        path = ROOT / "data" / "provinces_full_europe" / "provinces_base.json"
        self.assertTrue(path.exists(), "missing provinces_base.json")
        data = json.loads(path.read_text(encoding="utf-8"))
        provs = data["provinces"]
        self.assertGreaterEqual(len(provs), 400)
        names = [str(p.get("name", "")) for p in provs]
        self.assertEqual(len(names), len(set(n.lower() for n in names)))
        placeholders = [n for n in names if PLACEHOLDER_RE.match(n)]
        self.assertEqual(placeholders, [], msg=f"placeholders still present: {placeholders[:10]}")
        non_eu = {"tokyo", "beijing", "silicon valley", "washington dc", "houston energy corridor"}
        hits = [n for n in names if n.lower() in non_eu]
        self.assertEqual(hits, [], msg=f"global seed names still present: {hits}")

    def test_run_on_dir_idempotent_quality_gates(self) -> None:
        stats = run_on_dir(ROOT / "data" / "provinces_full_europe", write=False)
        self.assertEqual(stats["placeholders_remaining"], 0)
        self.assertEqual(stats["non_europe_remaining"], 0)
        self.assertEqual(stats["unique_names"], stats["total"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
