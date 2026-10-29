#!/usr/bin/env python3
"""GAP-USSR-WEST-2: SOV 1936 rings are real admin outlines, not 36-vertex blobs.

Baikonur lease 902132 has no geoBoundaries unit and stays a placeholder.
Every other SOV-1936 land ring must carry meta gap_ussr_west2, must not be
a 36- or 72-vertex placeholder, and must tile: land overlap ≤ 1 px², no
enclosed hole over 250 px², no self-crossing, no zero-neighbour province.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_ussr_west2_product import (  # noqa: E402
    UNKNOWN_PLACEHOLDER_IDS,
    audit_board,
    is_placeholder_ring,
    rasterize_centers,
    sov_placeholder_ids,
    trace_mask,
)

BOARD = ROOT / "data" / "provinces_world_accurate"


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    return geo, owners, adj, domains


class GapUssrWest2Test(unittest.TestCase):
    def test_orthogonal_contour_roundtrips(self) -> None:
        import numpy as np

        rect = np.zeros((8, 10), np.uint8)
        rect[2:6, 3:8] = 1
        ring = trace_mask(rect, 0, 0)
        back = rasterize_centers(ring, 0, 0, 10, 8)
        self.assertEqual(int(np.logical_xor(back, rect).sum()), 0)
        stair = np.zeros((6, 6), np.uint8)
        stair[1, 1] = stair[2, 1] = stair[2, 2] = stair[3, 2] = stair[3, 3] = 1
        ring = trace_mask(stair, 0, 0)
        back = rasterize_centers(ring, 0, 0, 6, 6)
        self.assertEqual(int(np.logical_xor(back, stair).sum()), 0)
        # A window that starts to the right of a span must not fill that row.
        left = [(0, 0), (4, 0), (4, 4), (0, 4)]
        self.assertEqual(int(rasterize_centers(left, 10, 0, 8, 8).sum()), 0)
        part = rasterize_centers(left, 3, -1, 6, 8)
        self.assertEqual(int(part.sum()), 4)

    def test_only_baikonur_may_stay_a_placeholder(self) -> None:
        geo, owners, _adj, domains = _load()
        self.assertEqual(UNKNOWN_PLACEHOLDER_IDS, (902132,))
        self.assertEqual(len(geo["provinces"]), 3596)
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        self.assertTrue(is_placeholder_ring(by_id[902132]["points"]))
        bad = sov_placeholder_ids(owners, geo["provinces"], domains)
        self.assertEqual(bad, [])

    def test_real_rings_tile_without_overlaps_or_holes(self) -> None:
        geo, _owners, adj, domains = _load()
        problems = audit_board(geo["provinces"], domains, adj)
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
