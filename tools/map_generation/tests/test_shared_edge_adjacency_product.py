#!/usr/bin/env python3
"""Gates: shared-edge adjacency better than pure centroid-KNN."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from shared_edge_adjacency_product import (  # noqa
    adjacency_integrity,
    build_shared_edge_adjacency,
    load_board_geometry,
    write_shared_edge_adjacency,
)

PILOT = ROOT / "data" / "provinces_pilot_europe"
WORLD = ROOT / "data" / "provinces_world_full"


class TestSharedEdgeAdjacency(unittest.TestCase):
    def test_build_synthetic_shared_edge(self):
        # Two unit squares sharing the edge x=1
        rings = {
            1: [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
            2: [[1.0, 0.0], [2.0, 0.0], [2.0, 1.0], [1.0, 1.0]],
            3: [[10.0, 10.0], [11.0, 10.0], [11.0, 11.0], [10.0, 11.0]],  # isolated → knn
        }
        water = {1: False, 2: False, 3: False}
        built = build_shared_edge_adjacency(rings, water, quant=0.25, knn_k=2, multi_quant=False)
        adj = built["adjacency"]
        self.assertIn(2, adj["1"])
        self.assertIn(1, adj["2"])
        self.assertEqual(built["stats"]["land_with_shared_edge"], 2)
        self.assertEqual(built["stats"]["orphan_land_after"], 0)
        # island 3 must get knn neighbors
        self.assertGreaterEqual(len(adj["3"]), 1)

    def test_near_vertex_links_cracked_rings(self):
        """Two almost-touching squares (gap < touch) should link without pure KNN alone."""
        # Share no quantized edge at fine quant, but vertices 0.05 apart
        rings = {
            1: [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
            2: [[1.05, 0.0], [2.05, 0.0], [2.05, 1.0], [1.05, 1.0]],
            3: [[50.0, 50.0], [51.0, 50.0], [51.0, 51.0], [50.0, 51.0]],
        }
        water = {1: False, 2: False, 3: False}
        no_near = build_shared_edge_adjacency(
            rings, water, quant=0.01, knn_k=1, multi_quant=False, near_vertex_touch=0.0
        )
        with_near = build_shared_edge_adjacency(
            rings, water, quant=0.01, knn_k=1, multi_quant=False, near_vertex_touch=0.2
        )
        # Without near-vertex, 1 and 2 may only connect via knn (deg1 to island)
        # With near-vertex, 1 should touch 2 as geometry residual
        self.assertIn(2, with_near["adjacency"]["1"])
        self.assertIn(1, with_near["adjacency"]["2"])
        self.assertGreaterEqual(
            int(with_near["stats"].get("near_vertex_edges_added") or 0), 1
        )
        self.assertGreaterEqual(
            float(with_near["stats"].get("land_shared_coverage") or 0),
            float(no_near["stats"].get("land_shared_coverage") or 0),
        )

    def test_pilot_file_integrity(self):
        g = adjacency_integrity(PILOT)
        self.assertTrue(g.get("ok"), msg=g)
        data = json.loads((PILOT / "province_adjacency.json").read_text())
        self.assertIn("shared_edge", str(data.get("method")))
        self.assertNotEqual(data.get("method"), "k_nearest_centroid")
        stats = data.get("stats") or {}
        self.assertGreaterEqual(float(stats.get("land_shared_coverage") or 0), 0.5)
        self.assertEqual(int(stats.get("orphan_land_after") or 0), 0)
        # Not fixed-k-only (old pilot was always deg 5)
        degs = [len(v) for v in (data.get("adjacency") or {}).values()]
        self.assertTrue(min(degs) < max(degs))

    def test_world_file_integrity(self):
        g = adjacency_integrity(WORLD)
        self.assertTrue(g.get("ok"), msg=g)
        data = json.loads((WORLD / "province_adjacency.json").read_text())
        self.assertIn("shared_edge", str(data.get("method")))
        self.assertEqual(int((data.get("stats") or {}).get("orphan_land_after") or 0), 0)
        self.assertGreater(int((data.get("stats") or {}).get("land_with_shared_edge") or 0), 200)

    def test_loader_uses_current_dir_adjacency(self):
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("load_from_dict", sl)
        self.assertIn("adjacency_live=1", sl)
        self.assertIn("province_adjacency", sl)
        # Must not only hardcode default provinces path without data-dir fallback
        self.assertIn("current_province_data_dir", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_shared_edge_adjacency_product.py", ci)

    def test_membership_not_regressed(self):
        for year in (1910, 1918, 1936, 2026):
            for d in (PILOT, WORLD):
                p = d / ("hierarchy_membership_%d.json" % year)
                self.assertTrue(p.is_file(), msg=str(p))
                snap = json.loads(p.read_text())
                self.assertEqual(snap.get("mode"), "full")


if __name__ == "__main__":
    unittest.main(verbosity=2)
