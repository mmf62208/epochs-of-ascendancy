#!/usr/bin/env python3
"""GAP-SIA-1: SIA 1936 land rings are real Thai amphoe outlines.

Fails while any in-scope SIA 1936 land ring is still a 36/72-vertex
placeholder. Province ids stay the 3596 set. A province may lose more than
AREA_LOSS_MAX of its pre-slice area only when this slice re-ringed it or
notched it. No new enclosed hole over 250 px². Every UNKNOWN id has a reason.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_sia1_product import (  # noqa: E402
    BASE_AREA,
    EXPECTED_RERINGS,
    HOLE_PX_MAX,
    META_RING,
    META_YIELD,
    SCOPE_PLACEHOLDER_IDS,
    UNKNOWN_PLACEHOLDER_IDS,
    UNKNOWN_REASONS,
    area_change_ok,
    audit_rerings,
    ring_area,
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
    return geo, base, owners, adj, domains


class GapSia1Test(unittest.TestCase):
    def test_only_listed_unknowns_stay_placeholders(self) -> None:
        geo, _base, owners, _adj, domains = _load()
        self.assertEqual(len(geo["provinces"]), 3596)
        self.assertEqual(len(SCOPE_PLACEHOLDER_IDS), 66)
        self.assertEqual(len(UNKNOWN_PLACEHOLDER_IDS), 0)
        self.assertEqual(EXPECTED_RERINGS, 66)
        self.assertEqual(set(UNKNOWN_REASONS), set(UNKNOWN_PLACEHOLDER_IDS))
        for pid in UNKNOWN_PLACEHOLDER_IDS:
            self.assertTrue(str(UNKNOWN_REASONS.get(pid) or "").strip())
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
            self.assertFalse(is_placeholder_ring(g["points"]), pid)
            self.assertTrue((g.get("meta") or {}).get(META_RING), pid)

    def test_province_ids_unchanged(self) -> None:
        geo, base, _owners, _adj, _domains = _load()
        geo_ids = [int(g["id"]) for g in geo["provinces"]]
        base_ids = [int(p["id"]) for p in base["provinces"]]
        self.assertEqual(len(geo_ids), 3596)
        self.assertEqual(len(base_ids), 3596)
        self.assertEqual(set(geo_ids), set(base_ids))
        self.assertEqual(len(set(geo_ids)), 3596)

    def test_area_loss_only_on_rerings_and_notches(self) -> None:
        geo, _base, _owners, _adj, _domains = _load()
        self.assertEqual(set(BASE_AREA), {int(g["id"]) for g in geo["provinces"]})
        for g in geo["provinces"]:
            pid = int(g["id"])
            meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
            before = float(BASE_AREA[pid])
            after = ring_area(g.get("points") or [])
            self.assertTrue(
                area_change_ok(before, after, meta),
                "%s before %.2f after %.2f ring=%s yield=%s" % (
                    pid, before, after, bool(meta.get(META_RING)), bool(meta.get(META_YIELD)),
                ),
            )
            if meta.get(META_YIELD):
                self.assertGreater(after, 1.0, pid)

    def test_rerings_tile(self) -> None:
        geo, _base, _owners, adj, domains = _load()
        self.assertEqual(HOLE_PX_MAX, 250)
        problems = audit_rerings(geo["provinces"], domains, adj)
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
