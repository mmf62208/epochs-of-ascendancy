#!/usr/bin/env python3
"""GAP-FRA-1: FRA 1936 land rings are real admin outlines, except five UNKNOWNs.

Fails while any in-scope FRA 1936 land ring is still a 36/72-vertex
placeholder, other than NCL, SPM, PYF, and ATF (gbOpen has no ADM file).
The re-ringed provinces must tile: land overlap ≤ 1 px², no new enclosed
hole over 250 px², no self-crossing, no zero-neighbour province.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_fra1_product import (  # noqa: E402
    EXPECTED_RERINGS,
    META_RING,
    SCOPE_PLACEHOLDER_IDS,
    UNKNOWN_PLACEHOLDER_IDS,
    audit_rerings,
    scope_placeholder_ids,
)
from gap_ussr_west2_product import is_placeholder_ring  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    return geo, owners, adj, domains


class GapFra1Test(unittest.TestCase):
    def test_only_listed_unknowns_stay_placeholders(self) -> None:
        geo, owners, _adj, domains = _load()
        self.assertEqual(len(geo["provinces"]), 3596)
        self.assertEqual(len(SCOPE_PLACEHOLDER_IDS), 142)
        self.assertEqual(len(UNKNOWN_PLACEHOLDER_IDS), 5)
        self.assertEqual(EXPECTED_RERINGS, 137)
        remaining = scope_placeholder_ids(owners, geo["provinces"], domains)
        self.assertEqual(remaining, list(UNKNOWN_PLACEHOLDER_IDS))
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        for pid in UNKNOWN_PLACEHOLDER_IDS:
            self.assertTrue(is_placeholder_ring(by_id[pid]["points"]))
            self.assertFalse((by_id[pid].get("meta") or {}).get(META_RING))
        for pid in SCOPE_PLACEHOLDER_IDS:
            if pid in UNKNOWN_PLACEHOLDER_IDS:
                continue
            g = by_id[pid]
            self.assertFalse(is_placeholder_ring(g["points"]))
            self.assertTrue((g.get("meta") or {}).get(META_RING))

    def test_rerings_tile(self) -> None:
        geo, _owners, adj, domains = _load()
        problems = audit_rerings(geo["provinces"], domains, adj)
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
