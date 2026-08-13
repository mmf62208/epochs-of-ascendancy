#!/usr/bin/env python3
"""Tests for strategic region rebuild (shipped path)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from rebuild_strategic_regions import (  # noqa: E402
    kmeans,
    label_center,
    quality_gates,
    rebuild_regions,
    rebalance_payload,
    run_on_dir,
)


class TestKMeans(unittest.TestCase):
    def test_separates_two_clouds(self) -> None:
        pts = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (100.0, 100.0), (101.0, 100.0), (100.0, 101.0)]
        labels, centers = kmeans(pts, k=2, seed=1)
        self.assertEqual(len(centers), 2)
        self.assertEqual(len(labels), 6)
        # First three should share a label; last three the other
        self.assertEqual(len(set(labels[:3])), 1)
        self.assertEqual(len(set(labels[3:])), 1)
        self.assertNotEqual(labels[0], labels[3])

    def test_label_center_unique(self) -> None:
        used: set = set()
        a = label_center(2030.0, 442.0, used)
        b = label_center(2031.0, 443.0, used)
        self.assertNotEqual(a, b)


class TestRebuild(unittest.TestCase):
    def test_coverage_and_count(self) -> None:
        # Spread points so k-means can form multiple clusters
        geom = []
        for i in range(30):
            x = 1000 + (i % 6) * 400
            y = 400 + (i // 6) * 200
            geom.append(
                {
                    "id": i + 1,
                    "points": [[x, y], [x + 10, y], [x + 10, y + 10], [x, y + 10]],
                }
            )
        payload = rebuild_regions(geom, k=12, seed=42)
        gates = quality_gates(payload, 30)
        self.assertTrue(gates["full_coverage"], msg=gates)
        self.assertTrue(gates["no_dup_ids"])
        self.assertGreaterEqual(gates["region_count"], 12)


class TestShipped(unittest.TestCase):
    def test_full_europe_regions_file(self) -> None:
        path = ROOT / "data" / "provinces_full_europe" / "strategic_regions.json"
        self.assertTrue(path.exists())
        data = json.loads(path.read_text(encoding="utf-8"))
        geom = json.loads(
            (ROOT / "data" / "provinces_full_europe" / "provinces_geometry.json").read_text()
        )
        expected = len(geom["provinces"])
        if data.get("source") == "rebuild_strategic_regions.py":
            gates = quality_gates(data, expected)
            self.assertGreaterEqual(gates["region_count"], 12)
            self.assertTrue(gates["full_coverage"], msg=gates)
            self.assertTrue(gates["no_dup_ids"])
            self.assertEqual(gates["empty_regions"], [])
            self.assertLessEqual(gates["max_region_share"], 0.35)

    def test_run_on_dir_dry(self) -> None:
        result = run_on_dir(ROOT / "data" / "provinces_full_europe", write=False)
        self.assertTrue(result["gates"]["full_coverage"])
        self.assertGreaterEqual(result["gates"]["region_count"], 12)
        self.assertLessEqual(result["gates"]["max_region_share"], 0.35)

    def test_world_full_rebalanced_share(self) -> None:
        path = ROOT / "data" / "provinces_world_full" / "strategic_regions.json"
        self.assertTrue(path.is_file())
        data = json.loads(path.read_text(encoding="utf-8"))
        geom = json.loads(
            (ROOT / "data" / "provinces_world_full" / "provinces_geometry.json").read_text()
        )
        expected = len(geom["provinces"])
        gates = quality_gates(data, expected)
        self.assertTrue(gates["full_coverage"], msg=gates)
        self.assertTrue(gates["no_dup_ids"])
        self.assertGreaterEqual(gates["region_count"], 12)
        self.assertGreaterEqual(gates["min_region_size"], 8)
        self.assertLessEqual(gates["max_region_share"], 0.12 + 1e-6)

    def test_rebalance_splits_mega_region(self) -> None:
        # Synthetic: one mega + one tiny
        id_to_pt = {i: (float(i % 10), float(i // 10)) for i in range(1, 101)}
        payload = {
            "regions": [
                {
                    "id": 1,
                    "name": "Mega",
                    "province_ids": list(range(1, 91)),
                    "province_count": 90,
                    "center": [5.0, 5.0],
                },
                {
                    "id": 2,
                    "name": "Tiny",
                    "province_ids": list(range(91, 101)),
                    "province_count": 10,
                    "center": [50.0, 50.0],
                },
            ]
        }
        out = rebalance_payload(payload, id_to_pt, max_share=0.25, min_size=8, seed=1)
        gates = quality_gates(out, 100)
        self.assertTrue(gates["full_coverage"], msg=gates)
        self.assertLessEqual(gates["max_region_share"], 0.25 + 1e-6)
        self.assertGreaterEqual(gates["min_region_size"], 8)


if __name__ == "__main__":
    unittest.main(verbosity=2)
