#!/usr/bin/env python3
"""GAP-EUROPE-RESID-1: in-scope 36-vertex rings are real NUTS outlines or UNKNOWN.

Fails while any YUG/ROM/POR/FIN/TUR/ITA/IRE/LIT/SPA land ring is still a
36/72-vertex placeholder, except the listed UNKNOWNs whose admin source is
not in the local cache. The five GISCO rings must tile (overlap ≤ 1 px², no enclosed hole above
250 px², no self-crossing, no zero-neighbour province). HOLE-306 at (5990, 1303)
must sit inside 902534, and the China gate must reject an enclosed CHI face
above 250 px².
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_china2_outline import (  # noqa: E402
    CHI_LAND_IDS,
    HOLE_AREA_LIMIT,
    _chi_hole_problems,
    _open_ring,
    _winding,
)
from gap_europe_resid1_product import (  # noqa: E402
    HOLE_PROBE,
    HOLE_PROVINCE,
    META_RING,
    NUTS_RERINGS,
    UNKNOWN_PLACEHOLDER_IDS,
    audit_rerings,
    hole_306_open,
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


class GapEuropeResid1Test(unittest.TestCase):
    def test_only_listed_unknowns_stay_placeholders(self) -> None:
        geo, owners, _adj, domains = _load()
        self.assertEqual(len(geo["provinces"]), 3596)
        self.assertEqual(len(UNKNOWN_PLACEHOLDER_IDS), 57)
        remaining = scope_placeholder_ids(owners, geo["provinces"], domains)
        self.assertEqual(remaining, list(UNKNOWN_PLACEHOLDER_IDS))
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        for pid in UNKNOWN_PLACEHOLDER_IDS:
            self.assertTrue(is_placeholder_ring(by_id[pid]["points"]))
        for pid, nuts_id in NUTS_RERINGS:
            g = by_id[pid]
            self.assertFalse(is_placeholder_ring(g["points"]))
            self.assertIn(nuts_id, str((g.get("meta") or {}).get(META_RING) or ""))

    def test_nuts_rings_tile(self) -> None:
        geo, _owners, adj, domains = _load()
        problems = audit_rerings(geo["provinces"], domains, adj)
        self.assertEqual(problems, [])

    def test_hole_306_is_filled_and_china_limit_is_250(self) -> None:
        self.assertEqual(HOLE_AREA_LIMIT, 250.0)
        geo, _owners, _adj, domains = _load()
        self.assertFalse(hole_306_open(geo["provinces"]))
        rings = {}
        for g in geo["provinces"]:
            pid = int(g["id"])
            if pid not in CHI_LAND_IDS:
                continue
            ring = _open_ring(g.get("points"))
            if len(ring) >= 3:
                rings[pid] = ring
        holes = _chi_hole_problems(rings)
        self.assertEqual(holes, [])
        self.assertNotEqual(_winding(rings[HOLE_PROVINCE], HOLE_PROBE[0], HOLE_PROBE[1]), 0)


if __name__ == "__main__":
    unittest.main()
