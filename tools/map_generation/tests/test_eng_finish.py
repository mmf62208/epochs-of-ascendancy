#!/usr/bin/env python3
"""ENG-MAP-FINISH: seven Natural Earth rings, no Oman face over 1 px², Abu Dhabi overlap ≤ 1.

Fails on the MAP-2a base: twelve ENG placeholders remain, three Oman-touching
faces are still open, and Abu Dhabi still overlaps Central Indian Basin North
by more than 1 px². Passes once those are closed. Province ids stay 3596
in the same order. Canada lake rings are not part of this edit.

PR #181 r1: the inland gap west/SW of Hayma and leftover Yemen-coast NE land
must not be CIBN / Unowned / Sea. Those asserts fail on c60409ee (Hayma's
own ring already tiles) and pass after CIBN is clipped off that land.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from eng_finish_product import (  # noqa: E402
    COAST_FRAGMENT_PROBES,
    HAYMA_ID,
    HAYMA_RING_SHA256,
    INLAND_GAP_PROBES,
    MAP_UNITS_SHA256,
    MAP_UNITS_URL,
    OMAN_HOLE_MIN,
    OVERLAP_PAIR,
    POLY_OVERLAP_MAX,
    RERING_ADMIN,
    STILL_UNKNOWN,
    choose_oman_target,
    coast_fragment_uncovered_sea_px,
    hayma_ring_sha256,
    inland_gap_uncovered_sea_px,
    measure_oman_holes,
    pair_overlap_area,
    probe_hits,
)
from gap_eng1_product import META_RING, UNKNOWN_PLACEHOLDER_IDS, scope_placeholder_ids  # noqa: E402
from gap_ussr_west2_product import is_placeholder_ring  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
CANADA_LAKE_IDS = (903053, 903054, 950333, 950335)


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    return geo, base, owners, adj, domains


class EngFinishTest(unittest.TestCase):
    def test_ids_and_placeholders(self) -> None:
        geo, base, owners, adj, domains = _load()
        geo_ids = [int(g["id"]) for g in geo["provinces"]]
        base_ids = [int(p["id"]) for p in base["provinces"]]
        self.assertEqual(geo_ids, base_ids)
        self.assertEqual(len(geo_ids), 3596)
        self.assertEqual(geo_ids[0], 710000)
        self.assertEqual(geo_ids[-1], 906138)
        self.assertEqual(tuple(STILL_UNKNOWN), tuple(UNKNOWN_PLACEHOLDER_IDS))
        self.assertEqual(len(STILL_UNKNOWN), 5)
        remaining = scope_placeholder_ids(owners, geo["provinces"], domains)
        self.assertEqual(remaining, sorted(STILL_UNKNOWN))
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        for pid, admin in RERING_ADMIN.items():
            g = by_id[pid]
            self.assertFalse(is_placeholder_ring(g["points"]), pid)
            meta = g.get("meta") or {}
            self.assertTrue(meta.get(META_RING), pid)
            self.assertIn(admin, str(meta.get(META_RING)))
            self.assertEqual(meta.get("eng_finish_sha256"), MAP_UNITS_SHA256)
            self.assertEqual(meta.get("eng_finish_url"), MAP_UNITS_URL)
        for pid in CANADA_LAKE_IDS:
            meta = by_id[pid].get("meta") or {}
            self.assertNotIn("eng_finish_absorb", meta)
            self.assertNotIn("eng_finish_clip", meta)
            self.assertNotIn("eng_finish_sha256", meta)
        # Adjacency stays a symmetric map of the same ids. This slice adds no link.
        self.assertEqual(len(adj), 3596)
        for key, nbs in adj.items():
            pid = int(key)
            self.assertIn(pid, geo_ids)
            for nb in nbs:
                self.assertIn(pid, adj.get(str(int(nb))) or [])

    def test_oman_faces_and_abu_dhabi_overlap(self) -> None:
        report = measure_oman_holes(BOARD, use_natural_earth=True)
        big = [h for h in report["holes"] if h["area_px2"] > OMAN_HOLE_MIN]
        self.assertEqual([(h["area_px2"], h["centroid"]) for h in big], [])
        overlap = pair_overlap_area(BOARD)
        self.assertEqual((overlap["land"], overlap["sea"]), OVERLAP_PAIR)
        self.assertLessEqual(overlap["poly_px2"], POLY_OVERLAP_MAX)
        self.assertLessEqual(overlap["px"], 1)

    def test_oman_land_face_uses_longest_land_edge(self) -> None:
        hole = {
            "on_land": True,
            "surrounding": [
                {"id": 950283, "domain": "sea", "adm0": "", "edge_px": 40.0},
                {"id": 905731, "domain": "land", "adm0": "OMN", "edge_px": 24.0},
                {"id": 903839, "domain": "land", "adm0": "SAU", "edge_px": 20.0},
            ],
        }
        self.assertEqual(choose_oman_target(hole), 905731)
        water = dict(hole)
        water["on_land"] = False
        self.assertIsNone(choose_oman_target(water))

    def test_hayma_ring_not_rewritten(self) -> None:
        """Play: Hayma #905731 is already a complete land ring. Do not replace it."""
        self.assertEqual(hayma_ring_sha256(BOARD), HAYMA_RING_SHA256)
        geo, _base, _owners, _adj, _domains = _load()
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        hay = by_id[HAYMA_ID]
        self.assertEqual(len(hay["points"]), 183)
        self.assertEqual((hay.get("meta") or {}).get("eng_finish_absorb"), "oman_face_110.4")

    def test_inland_gap_west_of_hayma_is_land_not_cibn(self) -> None:
        """Fails on c60409ee: probes west/SW of Hayma are CIBN / Unowned / Sea."""
        self.assertEqual(inland_gap_uncovered_sea_px(BOARD), 0)
        for hits in probe_hits(BOARD, INLAND_GAP_PROBES):
            seas = [h for h in hits if h["domain"] in ("sea", "ocean", "lake", "strait") or h["id"] >= 950000]
            lands = [h for h in hits if h["domain"] not in ("sea", "ocean", "lake", "strait") and h["id"] < 950000]
            self.assertEqual(seas, [], hits)
            self.assertTrue(lands, hits)

    def test_oman_yemen_coast_has_no_cibn_land_faces(self) -> None:
        """Fails on c60409ee: leftover CIBN on NE land along the Yemen coast."""
        self.assertEqual(coast_fragment_uncovered_sea_px(BOARD), 0)
        for hits in probe_hits(BOARD, COAST_FRAGMENT_PROBES):
            seas = [h for h in hits if h["domain"] in ("sea", "ocean", "lake", "strait") or h["id"] >= 950000]
            lands = [h for h in hits if h["domain"] not in ("sea", "ocean", "lake", "strait") and h["id"] < 950000]
            self.assertEqual(seas, [], hits)
            self.assertTrue(lands, hits)


if __name__ == "__main__":
    unittest.main()
