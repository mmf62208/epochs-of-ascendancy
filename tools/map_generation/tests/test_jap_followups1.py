#!/usr/bin/env python3
"""JAP-FOLLOWUPS-1: 950247 off Kanto/Tohoku land, Kinmen not a placeholder.

Fails on 33c0722f: Scotia Sea Edge 950247 still covers eastern Honshu
(Iwate ~1026 px², Fukushima 940, …) and Kinmen 903981 is a 36-vertex
circle. Passes once every land×950247 polygon overlap is ≤ 1 px² and
Kinmen is a real admin ring. Jaggedness on JPN home-island rings must
not exceed the 33c0722f metric (already 0 at >150° / <1 px).
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_ussr_west2_product import is_placeholder_ring, open_ring, overlap_px  # noqa: E402
from jap_followups1_product import (  # noqa: E402
    CHI_FUJIAN_ID,
    HOME_ISLAND_IDS,
    JAGGED_SIMPLIFIED,
    JAGGEDNESS_BEFORE,
    KINMEN_ADM1_SHA256,
    KINMEN_ADM1_URL,
    KINMEN_ID,
    KINMEN_UNKNOWN,
    OVERLAP_PX_MAX,
    POLY_OVERLAP_MAX,
    SEA_ID,
    measure_jaggedness,
    measure_kinmen,
    measure_sea_overlaps,
    poly_overlap,
)

BOARD = ROOT / "data" / "provinces_world_accurate"


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    return geo, base, owners, adj


class JapFollowups1Test(unittest.TestCase):
    def test_ids_unchanged(self) -> None:
        geo, base, _owners, adj = _load()
        geo_ids = [int(g["id"]) for g in geo["provinces"]]
        base_ids = [int(p["id"]) for p in base["provinces"]]
        self.assertEqual(geo_ids, base_ids)
        self.assertEqual(len(geo_ids), 3596)
        self.assertEqual(geo_ids[0], 710000)
        self.assertEqual(geo_ids[-1], 906138)
        self.assertEqual(len(adj), 3596)
        for key, nbs in adj.items():
            pid = int(key)
            self.assertIn(pid, geo_ids)
            for nb in nbs:
                self.assertIn(pid, adj.get(str(int(nb))) or [])

    def test_sea_950247_off_land(self) -> None:
        sea = measure_sea_overlaps(BOARD)
        self.assertEqual(sea["id"], SEA_ID)
        self.assertFalse(sea["raw_invalid"])
        self.assertEqual(sea["land_overlap_n_over_1"], 0)
        for row in sea["land_overlaps"]:
            self.assertLessEqual(row["poly_px2"], POLY_OVERLAP_MAX, row)
            self.assertLessEqual(row["px"], OVERLAP_PX_MAX, row)
        # 950247 is the only sea over these Kanto/Tohoku land rings.
        self.assertEqual(sea["other_water_overlaps"], [])

    def test_kinmen_not_placeholder(self) -> None:
        geo, _base, _owners, adj = _load()
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        kin = measure_kinmen(BOARD)
        if KINMEN_UNKNOWN:
            self.assertTrue(kin["placeholder"])
            return
        self.assertFalse(kin["placeholder"])
        self.assertGreater(kin["verts"], 36)
        self.assertGreaterEqual(kin["area"], 4.0)
        self.assertFalse(kin["raw_invalid"])
        g = by_id[KINMEN_ID]
        self.assertFalse(is_placeholder_ring(g["points"]))
        meta = g.get("meta") or {}
        self.assertEqual(meta.get("jap_followups1_sha256"), KINMEN_ADM1_SHA256)
        self.assertEqual(meta.get("jap_followups1_url"), KINMEN_ADM1_URL)
        chi = open_ring(by_id[CHI_FUJIAN_ID]["points"])
        kpts = open_ring(g["points"])
        self.assertLessEqual(poly_overlap(kpts, chi), POLY_OVERLAP_MAX)
        self.assertLessEqual(overlap_px(kpts, chi), OVERLAP_PX_MAX)
        kinmen_nbs = {int(x) for x in adj["903981"]}
        self.assertIn(902598, kinmen_nbs)
        self.assertIn(902633, kinmen_nbs)

    def test_jaggedness_not_worse(self) -> None:
        jag = measure_jaggedness(BOARD)
        self.assertEqual(len(HOME_ISLAND_IDS), 47)
        self.assertLessEqual(jag["sharp_gt150"], JAGGEDNESS_BEFORE["sharp_gt150"])
        self.assertLessEqual(jag["coast_sharp_gt150"], JAGGEDNESS_BEFORE["coast_sharp_gt150"])
        self.assertLessEqual(jag["short_spikes"], JAGGEDNESS_BEFORE["short_spikes"])
        if JAGGED_SIMPLIFIED:
            self.assertLess(
                jag["sharp_gt150"] + jag["short_spikes"],
                JAGGEDNESS_BEFORE["sharp_gt150"] + JAGGEDNESS_BEFORE["short_spikes"],
            )


if __name__ == "__main__":
    unittest.main()
