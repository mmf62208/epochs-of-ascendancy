#!/usr/bin/env python3
"""GAP-PER-1: PER 1936 land rings are real admin outlines.

Fails while any in-scope PER 1936 land ring is still a 36/72-vertex
placeholder, other than the UNKNOWN list. Province ids stay the 3596
set. A province may lose more than AREA_LOSS_MAX of its e0388c58 area
only when this slice re-ringed it or notched it. No new enclosed hole
over 250 px². Every UNKNOWN id has a reason. Every non-PER ring is
byte-identical to e0388c58.

Runtime tests read base ring md5s and areas only from the committed
fixture tools/map_generation/tests/fixtures/gap_ring_base_hashes.json.
They must not call git or subprocess.

This test owns that fixture. Regenerate it from the repo root (git is
allowed only at authoring time; the command must reproduce the file
byte-for-byte):

    python3 - <<'PY'
    import hashlib, json, subprocess, sys
    from pathlib import Path
    ROOT = Path.cwd()
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from gap_ussr_west2_product import ring_area
    BASES = (
        "e0388c58fb3a72d38084a9ff812a4d99d518e543",
        "a34d23a76af751c1c72239bc680a780662998e26",
    )
    GEO = "data/provinces_world_accurate/provinces_geometry.json"
    OUT = ROOT / "tools/map_generation/tests/fixtures/gap_ring_base_hashes.json"

    def points_md5(points):
        raw = json.dumps(points, separators=(",", ":"), ensure_ascii=True)
        return hashlib.md5(raw.encode("utf-8")).hexdigest()

    payload = {}
    for sha in BASES:
        raw = subprocess.check_output(["git", "show", "%s:%s" % (sha, GEO)], cwd=str(ROOT))
        recs = {}
        for g in json.loads(raw.decode("utf-8"))["provinces"]:
            pts = g.get("points") or []
            recs[str(int(g["id"]))] = {
                "md5": points_md5(pts),
                "area": round(ring_area(pts), 2),
            }
        payload[sha] = {k: recs[k] for k in sorted(recs, key=int)}
    text = json.dumps(payload, indent=2, ensure_ascii=True) + "\n"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    print(OUT)
    PY
"""
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_per1_product import (  # noqa: E402
    EXPECTED_RERINGS,
    HOLE_PX_MAX,
    HORMUZ_APPROACHES_ID,
    KEEP_ADJACENCY,
    KEEP_ADJACENCY_REASONS,
    META_RING,
    META_YIELD,
    OWNER,
    SCOPE_PLACEHOLDER_IDS,
    TABAS_ID,
    UNKNOWN_PLACEHOLDER_IDS,
    UNKNOWN_REASONS,
    area_change_ok,
    audit_rerings,
    ring_area,
    scope_placeholder_ids,
)
from gap_ussr_west2_product import is_placeholder_ring, overlap_px  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
BASE_COMMIT = "e0388c58fb3a72d38084a9ff812a4d99d518e543"
# PER is the later slice on this base; no later-slice owners to exempt.
LATER_SLICE_EXEMPT_OWNERS = ()
FIXTURE_PATH = (
    Path(__file__).resolve().parent / "fixtures" / "gap_ring_base_hashes.json"
)


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    return geo, base, owners, adj, domains


def _points_md5(points) -> str:
    raw = json.dumps(points, separators=(",", ":"), ensure_ascii=True)
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


def _fixture_base(sha: str):
    data = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    return data[sha]


class GapPer1Test(unittest.TestCase):
    def test_only_listed_unknowns_stay_placeholders(self) -> None:
        geo, _base, owners, _adj, domains = _load()
        self.assertEqual(len(geo["provinces"]), 3596)
        self.assertEqual(len(SCOPE_PLACEHOLDER_IDS), 65)
        self.assertEqual(len(UNKNOWN_PLACEHOLDER_IDS), len(UNKNOWN_REASONS))
        self.assertEqual(EXPECTED_RERINGS, 65 - len(UNKNOWN_PLACEHOLDER_IDS))
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
        geo, _base, owners, _adj, _domains = _load()
        fixture = _fixture_base(BASE_COMMIT)
        self.assertEqual(set(int(pid) for pid in fixture), {int(g["id"]) for g in geo["provinces"]})
        exempt = set(LATER_SLICE_EXEMPT_OWNERS)
        for g in geo["provinces"]:
            pid = int(g["id"])
            if owners.get(str(pid)) in exempt:
                continue
            meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
            before = float(fixture[str(pid)]["area"])
            after = ring_area(g.get("points") or [])
            self.assertTrue(
                area_change_ok(before, after, meta),
                "%s before %.2f after %.2f ring=%s yield=%s" % (
                    pid, before, after, bool(meta.get(META_RING)), bool(meta.get(META_YIELD)),
                ),
            )
            if meta.get(META_YIELD):
                self.assertEqual(owners.get(str(pid)), OWNER, pid)
                self.assertGreater(after, 1.0, pid)

    def test_rerings_tile(self) -> None:
        geo, _base, _owners, adj, domains = _load()
        self.assertEqual(HOLE_PX_MAX, 250)
        problems = audit_rerings(geo["provinces"], domains, adj)
        self.assertEqual(problems, [])

    def test_non_per_rings_match_base_commit(self) -> None:
        geo, _base, owners, _adj, _domains = _load()
        fixture = _fixture_base(BASE_COMMIT)
        self.assertEqual(set(int(pid) for pid in fixture), {int(g["id"]) for g in geo["provinces"]})
        exempt = set(LATER_SLICE_EXEMPT_OWNERS)
        for g in geo["provinces"]:
            pid = int(g["id"])
            if owners.get(str(pid)) == OWNER or owners.get(str(pid)) in exempt:
                continue
            self.assertEqual(_points_md5(g.get("points")), fixture[str(pid)]["md5"], pid)

    def test_sarbaz_baluchistan_edge_kept(self) -> None:
        self.assertEqual(KEEP_ADJACENCY, ((903351, 903586),))
        for a, b in KEEP_ADJACENCY:
            reason = KEEP_ADJACENCY_REASONS.get((a, b)) or KEEP_ADJACENCY_REASONS.get((b, a))
            self.assertTrue(str(reason or "").strip(), (a, b))
        _geo, _base, _owners, adj, _domains = _load()
        for a, b in KEEP_ADJACENCY:
            self.assertIn(b, adj.get(str(a), []), a)
            self.assertIn(a, adj.get(str(b), []), b)

    def test_hormuz_approaches_ring_unchanged_and_tabas_misses_it(self) -> None:
        geo, _base, _owners, _adj, _domains = _load()
        fixture = _fixture_base(BASE_COMMIT)
        by_id = {int(g["id"]): g for g in geo["provinces"]}
        self.assertEqual(
            _points_md5(by_id[HORMUZ_APPROACHES_ID].get("points")),
            fixture[str(HORMUZ_APPROACHES_ID)]["md5"],
        )
        self.assertEqual(
            overlap_px(by_id[TABAS_ID]["points"], by_id[HORMUZ_APPROACHES_ID]["points"]),
            0,
        )


if __name__ == "__main__":
    unittest.main()
