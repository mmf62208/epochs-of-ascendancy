#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from organicize_seed_geometry import (  # noqa: E402
    is_stub_like,
    organic_polygon,
    organicize_geometry,
    run_on_dir,
)


class TestOrganic(unittest.TestCase):
    def test_regular_hex_is_stub(self) -> None:
        cx, cy, r = 100.0, 100.0, 30.0
        hex_pts = [
            [cx + r * math.cos(i * math.tau / 6), cy + r * math.sin(i * math.tau / 6)]
            for i in range(6)
        ]
        self.assertTrue(is_stub_like(hex_pts))

    def test_organic_not_stub(self) -> None:
        pts = organic_polygon(100.0, 100.0, 30.0, seed=42, n_points=18)
        self.assertEqual(len(pts), 18)
        self.assertFalse(is_stub_like(pts))

    def test_organicize_changes_hotspots(self) -> None:
        base = [
            {"id": 1, "name": "Hot", "domain": "land", "hotspot_densify": True, "theater": "far_east"},
            {"id": 2, "name": "Sea", "domain": "sea", "theater": "sea"},
        ]
        # Regular hex for hot
        cx, cy, r = 50.0, 50.0, 20.0
        hex_pts = [
            [cx + r * math.cos(i * math.tau / 6), cy + r * math.sin(i * math.tau / 6)]
            for i in range(6)
        ]
        geom = [
            {"id": 1, "points": hex_pts, "label_anchor": [cx, cy]},
            {"id": 2, "points": [[0, 0], [10, 0], [10, 10], [0, 10]]},
        ]
        out, stats = organicize_geometry(base, geom)
        self.assertEqual(stats["changed"], 1)
        self.assertTrue(out[0].get("organicized"))
        self.assertNotEqual(out[0]["points"], hex_pts)

    def test_shipped_world_has_organic_meta(self) -> None:
        path = ROOT / "data" / "provinces_world_full" / "provinces_geometry.json"
        data = json.loads(path.read_text())
        meta = data.get("meta") or {}
        self.assertTrue(meta.get("organicized_seed_geometry") or meta.get("organicized_count", 0) > 0)
        self.assertEqual(meta.get("geometry_space"), "world")
        sizes = [len(g.get("points") or []) for g in data["provinces"]]
        self.assertEqual(sum(1 for s in sizes if s == 3), 0)
        self.assertGreaterEqual(sorted(sizes)[len(sizes) // 2], 12)


if __name__ == "__main__":
    unittest.main(verbosity=2)
