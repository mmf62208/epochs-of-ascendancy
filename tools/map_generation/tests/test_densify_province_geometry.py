#!/usr/bin/env python3
"""Unit tests for province geometry densification (shipped path)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from densify_province_geometry import (  # noqa: E402
    densify_geometry_payload,
    densify_ring,
    geometry_stats,
    run_on_dir,
)


class TestDensifyRing(unittest.TestCase):
    def test_triangle_becomes_at_least_min_vertices(self) -> None:
        tri = [[0.0, 0.0], [30.0, 0.0], [15.0, 26.0]]
        out = densify_ring(tri, max_edge=10.0, min_vertices=12, max_vertices=64)
        self.assertGreaterEqual(len(out), 12)
        self.assertNotEqual(len(out), 3)

    def test_preserves_rough_centroid(self) -> None:
        quad = [[0.0, 0.0], [40.0, 0.0], [40.0, 40.0], [0.0, 40.0]]
        out = densify_ring(quad, max_edge=12.0, min_vertices=12)
        cx0 = sum(p[0] for p in quad) / 4
        cy0 = sum(p[1] for p in quad) / 4
        cx1 = sum(p[0] for p in out) / len(out)
        cy1 = sum(p[1] for p in out) / len(out)
        self.assertAlmostEqual(cx0, cx1, delta=3.0)
        self.assertAlmostEqual(cy0, cy1, delta=3.0)

    def test_empty_and_tiny(self) -> None:
        self.assertEqual(densify_ring([]), [])
        self.assertEqual(len(densify_ring([[0, 0], [1, 0]])), 2)


class TestDensifyPayload(unittest.TestCase):
    def test_ids_and_count_stable(self) -> None:
        payload = {
            "meta": {"version": 1},
            "provinces": [
                {"id": 1, "points": [[0, 0], [20, 0], [10, 17]]},
                {"id": 2, "points": [[0, 0], [25, 0], [25, 25], [0, 25]]},
            ],
        }
        out = densify_geometry_payload(payload, max_edge=10.0, min_vertices=12)
        self.assertEqual([p["id"] for p in out["provinces"]], [1, 2])
        stats = geometry_stats(out["provinces"])
        self.assertEqual(stats["triangles"], 0)
        self.assertGreaterEqual(stats["median"], 12)
        self.assertEqual(out["meta"].get("densified"), "densify_province_geometry.py")


class TestShippedFullEuropeGeometry(unittest.TestCase):
    """Drive real shipped geometry path after densify has been applied (or dry-run)."""

    def test_full_europe_geometry_quality_gates(self) -> None:
        path = ROOT / "data" / "provinces_full_europe" / "provinces_geometry.json"
        self.assertTrue(path.exists())
        data = json.loads(path.read_text(encoding="utf-8"))
        provs = data["provinces"]
        stats = geometry_stats(provs)
        self.assertGreaterEqual(stats["count"], 400)
        # After densify write these should hold; if not yet densified, run_on_dir dry proves transform
        if data.get("meta", {}).get("densified") == "densify_province_geometry.py":
            self.assertEqual(stats["triangles"], 0, msg=stats)
            self.assertGreaterEqual(stats["median"], 12, msg=stats)
            self.assertEqual(stats["below_12"], 0, msg=stats)
        else:
            # Prove pure path would meet gates without writing in this assertion
            dry = densify_geometry_payload(data, max_edge=14.0, min_vertices=12)
            st = geometry_stats(dry["provinces"])
            self.assertEqual(st["triangles"], 0)
            self.assertGreaterEqual(st["median"], 12)

    def test_run_on_dir_dry_run_gates(self) -> None:
        stats = run_on_dir(
            ROOT / "data" / "provinces_full_europe",
            write=False,
            max_edge=14.0,
            min_vertices=12,
        )
        after = stats["after"]
        self.assertTrue(stats["ids_stable"])
        self.assertEqual(after["triangles"], 0)
        self.assertGreaterEqual(after["median"], 12)
        self.assertEqual(after["below_12"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
