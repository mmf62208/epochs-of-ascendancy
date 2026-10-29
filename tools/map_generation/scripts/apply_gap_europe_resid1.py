#!/usr/bin/env python3
"""Replace in-scope GISCO placeholder rings and fill China HOLE-306.

  python3 tools/map_generation/scripts/apply_gap_europe_resid1.py
  python3 tools/map_generation/scripts/apply_gap_europe_resid1.py --apply

Five NUTS-3 rings come from data/gis/NUTS_RG_20M_2021_4326_LEVL_3.geojson.
A GISCO outer ring that is still 36 vertices keeps that outline and gains one
on-edge midpoint (fill unchanged). Provinces with no local admin source stay
as they are and are written to the UNKNOWN list. HOLE-306 is spliced into
the existing CHI province 902534. Province ids are not added or renumbered.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from apply_gap_ussr_west2 import _find_object, _mask_touches_ring, _splice_field  # noqa: E402
from gap_china2_outline import HOLE_AREA_LIMIT, audit_play_gaps  # noqa: E402
from gap_europe_resid1_product import (  # noqa: E402
    BOARD,
    HOLE_PROVINCE,
    META_HOLE,
    META_RING,
    NUTS_RERINGS,
    UNKNOWN_PLACEHOLDER_IDS,
    audit_rerings,
    fill_hole_306,
    nuts_source_ring,
    scope_placeholder_ids,
    with_midpoint_if_placeholder,
)
from gap_ussr_west2_product import (  # noqa: E402
    integer_bounds,
    open_ring,
    ring_area,
    vertex_count,
)

EVIDENCE = Path.home() / "gapeuro1" / "evidence"
GEO_PATH = BOARD / "provinces_geometry.json"
ADJ_PATH = BOARD / "province_adjacency.json"


def _json_pt(x, y):
    return [round(float(x), 6), round(float(y), 6)]


def _order_preserving(old, new_set):
    """Keep surviving neighbours in their old order. Append additions, sorted."""
    kept = [n for n in old if n in new_set]
    have = set(kept)
    added = sorted(n for n in new_set if n not in have)
    return kept + added, added, [n for n in old if n not in new_set]


def _touches(pid, ring, rings):
    """Ids whose pixel mask 4-touches this ring, including water."""
    bb = integer_bounds(ring, 2)
    from gap_ussr_west2_product import rasterize_centers

    w, h = bb[2] - bb[0], bb[3] - bb[1]
    mask = rasterize_centers(ring, bb[0], bb[1], w, h)
    found = set()
    for oid, opts in rings.items():
        if oid == pid:
            continue
        ob = integer_bounds(opts, 1)
        if ob[2] < bb[0] - 2 or ob[0] > bb[2] + 2 or ob[3] < bb[1] - 2 or ob[1] > bb[3] + 2:
            continue
        if _mask_touches_ring(bb, mask, opts):
            found.add(oid)
    return found


def build(apply: bool) -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    base_rows = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    base = {int(p["id"]): p for p in base_rows}
    geo_doc = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    domains = {pid: row.get("domain") for pid, row in base.items()}
    print("provinces", len(base))
    if len(base) != 3596 or len(geo_doc["provinces"]) != 3596:
        print("refuse: province count")
        return 2

    before = []
    for pid in scope_placeholder_ids(owners, geo_doc["provinces"], domains):
        g = geo[pid]
        before.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "owner": owners.get(str(pid)),
                "verts": vertex_count(g["points"]),
                "area": round(ring_area(g["points"]), 2),
                "source": (g.get("meta") or {}).get("source"),
                "nuts_id": (g.get("meta") or {}).get("nuts_id"),
                "adm0_a3": (g.get("meta") or {}).get("adm0_a3"),
                "level": (g.get("meta") or {}).get("level"),
            }
        )
    (EVIDENCE / "placeholders_before.json").write_text(
        json.dumps({"province_count": len(base), "n": len(before), "rows": before}, indent=2) + "\n",
        encoding="utf-8",
    )
    print("in-scope placeholders", len(before))

    updates = {}
    notes = {}
    for pid, nuts_id in NUTS_RERINGS:
        canvas, added = with_midpoint_if_placeholder(nuts_source_ring(nuts_id))
        updates[pid] = [_json_pt(p[0], p[1]) for p in canvas]
        notes[pid] = {
            "nuts_id": nuts_id,
            "midpoint": added,
            "source": "NUTS_RG_20M_2021_4326_LEVL_3:%s" % nuts_id,
        }
        print(
            "nuts",
            pid,
            base[pid]["name"],
            nuts_id,
            "verts",
            vertex_count(geo[pid]["points"]),
            "->",
            len(updates[pid]),
            "area",
            round(ring_area(geo[pid]["points"]), 2),
            "->",
            round(ring_area(updates[pid]), 2),
            "midpoint",
            added,
        )

    hole_ring = fill_hole_306(geo[HOLE_PROVINCE]["points"])
    updates[HOLE_PROVINCE] = [_json_pt(p[0], p[1]) for p in hole_ring]
    print(
        "hole",
        HOLE_PROVINCE,
        "verts",
        vertex_count(geo[HOLE_PROVINCE]["points"]),
        "->",
        len(updates[HOLE_PROVINCE]),
        "area",
        round(ring_area(geo[HOLE_PROVINCE]["points"]), 2),
        "->",
        round(ring_area(updates[HOLE_PROVINCE]), 2),
    )

    patched = []
    for g in geo_doc["provinces"]:
        pid = int(g["id"])
        if pid not in updates:
            patched.append(g)
            continue
        g2 = dict(g)
        g2["points"] = updates[pid]
        meta = dict(g.get("meta") or {})
        if pid in notes:
            meta[META_RING] = notes[pid]["source"]
            meta["vertex_n"] = len(open_ring(updates[pid]))
            meta["area"] = round(ring_area(updates[pid]), 6)
        else:
            meta[META_HOLE] = "HOLE-306"
        g2["meta"] = meta
        patched.append(g2)

    adj_doc = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj = {k: [int(n) for n in v] for k, v in adj_doc["adjacency"].items()}
    rings = {}
    for g in patched:
        pid = int(g["id"])
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            rings[pid] = pts

    old_rings = {}
    for pid, g in geo.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            old_rings[pid] = pts
    adj_changes = []
    for pid in sorted(updates):
        old_list = list(adj.get(str(pid), []))
        # Diff pixel touches of the old ring against the new ring. A neighbour
        # the border did not start or stop touching stays in its old place.
        before_touch = _touches(pid, old_rings[pid], old_rings)
        after_touch = _touches(pid, rings[pid], rings)
        if not after_touch:
            print("refuse: zero neighbours", pid)
            return 2
        gained = after_touch - before_touch
        lost = before_touch - after_touch
        new_set = (set(old_list) - lost) | gained
        updated, added, dropped = _order_preserving(old_list, new_set)
        if added or dropped:
            adj_changes.append({"id": pid, "added": added, "dropped": dropped})
            adj[str(pid)] = updated
            for oid in dropped:
                key = str(oid)
                adj[key] = [n for n in adj.get(key, []) if n != pid]
            for oid in added:
                key = str(oid)
                cur = list(adj.get(key, []))
                if pid not in cur:
                    adj[key] = cur + [pid]
            print("adj", pid, "add", added, "drop", dropped)
    for pid in updates:
        for nid in adj[str(pid)]:
            if pid not in adj.get(str(nid), []):
                print("refuse: asymmetric", pid, nid)
                return 2
    if not adj_changes:
        print("adjacency unchanged")

    problems = audit_rerings(patched, domains, adj)
    if problems:
        print("AUDIT", problems)
        return 2
    if HOLE_AREA_LIMIT != 250.0:
        print("refuse: china hole limit", HOLE_AREA_LIMIT)
        return 2
    gaps = audit_play_gaps(patched, domains)
    if gaps:
        print("CHINA", gaps)
        return 2
    print("audit ok")

    rows = []
    for pid, nuts_id in NUTS_RERINGS:
        rows.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "owner": owners.get(str(pid)),
                "role": "rering",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(updates[pid])),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(updates[pid]), 2),
                "source": notes[pid]["source"],
                "midpoint": notes[pid]["midpoint"],
            }
        )
    rows.append(
        {
            "id": HOLE_PROVINCE,
            "name": base[HOLE_PROVINCE]["name"],
            "owner": owners.get(str(HOLE_PROVINCE)),
            "role": "hole306",
            "verts_before": vertex_count(geo[HOLE_PROVINCE]["points"]),
            "verts_after": len(open_ring(updates[HOLE_PROVINCE])),
            "area_before": round(ring_area(geo[HOLE_PROVINCE]["points"]), 2),
            "area_after": round(ring_area(updates[HOLE_PROVINCE]), 2),
            "source": "splice lens of 902534 into itself",
        }
    )
    unknown_rows = [row for row in before if row["id"] in UNKNOWN_PLACEHOLDER_IDS]
    (EVIDENCE / "rering_table.json").write_text(json.dumps({"rows": rows}, indent=2) + "\n", encoding="utf-8")
    (EVIDENCE / "unknown.json").write_text(
        json.dumps(
            {
                "reason": "admin geojson is not in the repo or the local geoBoundaries cache",
                "rows": unknown_rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (EVIDENCE / "adjacency.json").write_text(
        json.dumps({"changes": adj_changes}, indent=2) + "\n", encoding="utf-8"
    )
    (EVIDENCE / "hole306.json").write_text(json.dumps(rows[-1], indent=2) + "\n", encoding="utf-8")
    print("evidence", EVIDENCE)

    if not apply:
        print("dry-run: geometry not written")
        return 0

    raw = GEO_PATH.read_text(encoding="utf-8")
    for pid in sorted(updates, reverse=True):
        start, end = _find_object(raw, pid)
        raw = _splice_field(raw, start, end, "points", json.dumps(updates[pid], separators=(",", ":")))
        start, end = _find_object(raw, pid)
        obj, _rel = json.JSONDecoder().raw_decode(raw, start)
        meta = dict(obj.get("meta") or {})
        if pid in notes:
            meta[META_RING] = notes[pid]["source"]
            meta["vertex_n"] = len(open_ring(updates[pid]))
            meta["area"] = round(ring_area(updates[pid]), 6)
        else:
            meta[META_HOLE] = "HOLE-306"
        raw = _splice_field(raw, start, end, "meta", json.dumps(meta, separators=(",", ":")))
    # The spliced document must still be one JSON object with the same ids.
    check = json.loads(raw)
    if len(check["provinces"]) != 3596:
        print("refuse: written count", len(check["provinces"]))
        return 2
    ids = [int(g["id"]) for g in check["provinces"]]
    if ids != [int(g["id"]) for g in geo_doc["provinces"]]:
        print("refuse: id order changed")
        return 2
    GEO_PATH.write_text(raw, encoding="utf-8")
    print("geometry written")
    if adj_changes:
        # Rewrite only the changed adjacency lists, keeping file order.
        adj_raw = ADJ_PATH.read_text(encoding="utf-8")
        changed_ids = set()
        for row in adj_changes:
            changed_ids.add(row["id"])
            changed_ids.update(row["added"])
            changed_ids.update(row["dropped"])
        for pid in sorted(changed_ids, reverse=True):
            token = '\n    "%d": [' % pid
            at = adj_raw.find(token)
            if at < 0:
                print("refuse: adjacency key missing", pid)
                return 2
            end = adj_raw.find("]", at)
            if end < 0:
                print("refuse: adjacency list", pid)
                return 2
            body = ",\n".join("      %d" % n for n in adj[str(pid)])
            repl = '\n    "%d": [\n%s\n    ]' % (pid, body)
            adj_raw = adj_raw[:at] + repl + adj_raw[end + 1 :]
        json.loads(adj_raw)
        ADJ_PATH.write_text(adj_raw, encoding="utf-8")
        print("adjacency written", sorted(changed_ids))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    return build(args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
