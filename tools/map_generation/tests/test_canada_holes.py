#!/usr/bin/env python3
"""MAP-2a: enclosed holes in Canadian land stay at or under 100 px².

The 1466.8 px² wedge west of Yukon is Alaska land and must stay inside
Alaska West. Real lake margins over 100 px² stay inside the existing lake
province. No new province id.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import measure_canada_holes  # noqa: E402
from gap_china2_outline import _winding  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
# Area-weighted centroid of the 1466.8 px² face measured on f5d7b5ba.
ALASKA_WEDGE = (864.9, 636.3)
# New shared edges this slice added. Each pair is stored both ways.
NEW_EDGES = (
    (800015, 903085),
    (800284, 903049),
    (800446, 903049),
    (800627, 950232),
    (800648, 903031),
    (802754, 903031),
    (903031, 903033),
    (903033, 903035),
    (903033, 903037),
    (903045, 903049),
    (903046, 903049),
    (903048, 903049),
    (903049, 903050),
    (903049, 903051),
    (903049, 903052),
)


class CanadaHoleTest(unittest.TestCase):
    def test_province_count_and_alaska_wedge(self) -> None:
        geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
        self.assertEqual(len(geo["provinces"]), 3596)
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        ring = [(float(p[0]), float(p[1])) for p in by_id[800015]["points"]]
        self.assertNotEqual(_winding(ring, ALASKA_WEDGE[0], ALASKA_WEDGE[1]), 0)
        ids = {int(g["id"]) for g in geo["provinces"]}
        self.assertNotIn(906139, ids)
        self.assertLess(max(i for i in ids if i < 950000), 906139)

    def test_new_edges_are_symmetric(self) -> None:
        adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
        for a, b in NEW_EDGES:
            self.assertIn(b, [int(x) for x in adj[str(a)]])
            self.assertIn(a, [int(x) for x in adj[str(b)]])

    def test_no_enclosed_hole_over_100(self) -> None:
        report = measure_canada_holes(BOARD, use_natural_earth=False)
        self.assertEqual(report["province_count"], 3596)
        big = [h for h in report["holes"] if h["area_px2"] > 100.0]
        self.assertEqual(
            [(h["area_px2"], h["centroid"]) for h in big],
            [],
        )


if __name__ == "__main__":
    unittest.main()
