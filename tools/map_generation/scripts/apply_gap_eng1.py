#!/usr/bin/env python3
"""Replace ENG 1936 placeholder rings with geoBoundaries admin rings.

Source GeoJSON is gbOpen simplified geometry, downloaded into
~/gapeng1/scratch/geoboundaries (not committed). Numpy only.

  python3 tools/map_generation/scripts/apply_gap_eng1.py --match-only
  python3 tools/map_generation/scripts/apply_gap_eng1.py --adm0 CAN --limit 40
  python3 tools/map_generation/scripts/apply_gap_eng1.py --adm0 QAT --apply

Matching is the normalized admin name. A multipolygon uses the part that
contains the province centroid (the mainland, not a speck). A name miss
may use the admin part that contains the centroid when its area is within
half to double the placeholder. UNKNOWN provinces are not reshaped.

New rings win overlapping land pixels (neighbours are notched). Sea zones
keep their pixels. Old placeholder pixels that covered no other province
stay with the province so a densify bulge cannot open a hole. Every ring
written is strictly simple, and polygon intersection area stays within 1 px².
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from apply_gap_ussr_west2 import (  # noqa: E402
    _bboxes_overlap,
    _box_gap,
    _canvas_ring,
    _find_object,
    _interior_point,
    _is_water,
    _json_pt,
    _mask_touches_ring,
    _or_into,
    _point_in,
    _ring_from_mask,
    _shave_new_border_slivers,
    _splice_field,
    _subtract,
)
from gap_eng1_product import (  # noqa: E402
    DO_NOT_EDIT_IDS,
    META_RING,
    META_YIELD,
    POLY_OVERLAP_MAX,
    SCOPE_PLACEHOLDER_IDS,
    UNKNOWN_PLACEHOLDER_IDS,
    UNKNOWN_REASONS,
    audit_changed,
    names_match,
    norm_name,
    ring_is_raw_invalid,
)
from gap_ussr_west2_product import (  # noqa: E402
    HOLE_PX_MAX,
    integer_bounds,
    open_ring,
    overlap_px,
    point_in_ring,
    rasterize_centers,
    ring_area,
    ring_bbox,
    self_crosses,
    vertex_count,
)
from ne_full_geometry_align import polygon_centroid  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
GEO_PATH = BOARD / "provinces_geometry.json"
ADJ_PATH = BOARD / "province_adjacency.json"
SRC = Path.home() / "gapeng1" / "scratch" / "geoboundaries"
EVIDENCE = Path.home() / "gapeng1" / "evidence"
GARRISON_TAGS = ("GER", "FRA", "ENG", "SOV", "ITA", "JAP", "USA", "POL", "CZE")
# Unknowns stay circles. Pre-existing raw-invalid rings, including the FRA
# defects, are subtracted from new rings and never rewritten.
FROZEN = set(UNKNOWN_PLACEHOLDER_IDS) | set(DO_NOT_EDIT_IDS)
ADM_ALIASES = {
    "SDS": ("SSD",),
    "PSX": ("PSE",),
    "SOL": ("SOM",),
    "KAS": ("PAK", "IND"),
}


def _outers(geom: dict):
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    if gtype == "Polygon":
        if coords and coords[0]:
            yield coords[0]
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                yield poly[0]


def load_parts(only: Sequence[str] = ()) -> Dict[Tuple[str, str], List[dict]]:
    out: Dict[Tuple[str, str], List[dict]] = defaultdict(list)
    want = {code.upper() for code in only}
    for path in sorted(SRC.glob("geoBoundaries-*_simplified.geojson")):
        stem = path.name
        # geoBoundaries-VNM-ADM2_simplified.geojson
        body = stem[len("geoBoundaries-") : -len("_simplified.geojson")]
        adm0, level = body.split("-")
        if want and adm0 not in want:
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        n = 0
        for feat_i, feat in enumerate(doc.get("features") or []):
            props = feat.get("properties") if isinstance(feat.get("properties"), dict) else {}
            name = str(props.get("shapeName") or props.get("name") or "")
            folded = norm_name(name)
            if not folded:
                continue
            for part_i, outer in enumerate(_outers(feat.get("geometry") or {})):
                lonlat = [[float(p[0]), float(p[1])] for p in outer]
                if len(lonlat) >= 2 and lonlat[0] == lonlat[-1]:
                    lonlat = lonlat[:-1]
                if len(lonlat) < 3:
                    continue
                canvas = _canvas_ring(lonlat)
                if len(open_ring(canvas)) < 3:
                    continue
                if ring_area(canvas) < 0.05:
                    continue
                cx, cy = polygon_centroid(canvas)
                out[(adm0, level)].append(
                    {
                        "name": name,
                        "norm": folded,
                        "canvas": canvas,
                        "cx": float(cx),
                        "cy": float(cy),
                        "area": ring_area(canvas),
                        "src_n": len(lonlat),
                        "part_id": (adm0, level, feat_i, part_i),
                    }
                )
                n += 1
        print("loaded", adm0, level, "parts", n, flush=True)
    if not out:
        raise SystemExit("geoBoundaries cache missing under ~/gapeng1/scratch/geoboundaries")
    return out


def _levels(level: str) -> List[str]:
    if level == "ADM2":
        return ["ADM2", "ADM1"]
    if level == "ADM1":
        return ["ADM1", "ADM2"]
    return ["ADM1", "ADM2"]


def _source_adms(adm: str) -> Tuple[str, ...]:
    return ADM_ALIASES.get(adm, (adm,))


def _part_option(part, lv, adm, px, py, how: str):
    return {
        "canvas": part["canvas"],
        "adm": adm,
        "level": lv,
        "dist": math.hypot(part["cx"] - px, part["cy"] - py),
        "src_name": part["name"],
        "src_n": part["src_n"],
        "area": part["area"],
        "part_id": part["part_id"],
        "how": how,
    }


def match_provinces(base, geo, owners, parts, restrict: Sequence[int] = ()) -> Tuple[dict, List[dict]]:
    """Name match, then the part that contains the centroid.

    A multipolygon's tiny island can sit nearer the simplified centroid than
    the mainland. The containing part is the unit the circle was drawn on.
    """
    options = defaultdict(list)
    skipped_unknown = []
    considered = []
    allow = {int(pid) for pid in restrict}
    for pid in SCOPE_PLACEHOLDER_IDS:
        if allow and pid not in allow:
            continue
        if owners.get(str(pid)) != "ENG":
            continue
        if pid >= 950000 or _is_water(pid, base.get(pid, {})):
            continue
        g = geo.get(pid)
        if g is None:
            continue
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if meta.get(META_RING):
            continue
        considered.append(pid)
        if pid in UNKNOWN_PLACEHOLDER_IDS:
            skipped_unknown.append(
                {"id": pid, "name": base[pid]["name"], "reason": UNKNOWN_REASONS.get(pid, "unknown")}
            )
            continue
        adm = str(meta.get("adm0_a3") or "")
        level = str(meta.get("level") or "")
        pts = open_ring(g.get("points") or [])
        px, py = polygon_centroid(pts)
        prov_area = max(ring_area(pts), 1.0)
        limit = max(80.0, 1.5 * math.sqrt(prov_area / math.pi))
        named = []
        for src_adm in _source_adms(adm):
            for lv in _levels(level):
                for part in parts.get((src_adm, lv)) or []:
                    if names_match(base[pid]["name"], part["name"]):
                        named.append((lv, src_adm, part))
        chosen = []
        containers = [
            (lv, src_adm, part)
            for lv, src_adm, part in named
            if point_in_ring(px, py, part["canvas"]) and part["area"] >= 1.0
        ]
        if containers:
            preferred = [row for row in containers if row[0] == (level or "ADM1")]
            pool = preferred or containers
            pool.sort(key=lambda row: -row[2]["area"])
            chosen = [_part_option(part, lv, src_adm, px, py, "name") for lv, src_adm, part in pool[:4]]
        else:
            within = [
                (lv, src_adm, part)
                for lv, src_adm, part in named
                if math.hypot(part["cx"] - px, part["cy"] - py) <= limit and part["area"] >= 1.0
            ]
            within.sort(key=lambda row: -row[2]["area"])
            chosen = [_part_option(part, lv, src_adm, px, py, "name") for lv, src_adm, part in within[:4]]
        geometric = []
        if not chosen:
            for src_adm in _source_adms(adm):
                for lv in _levels(level):
                    for part in parts.get((src_adm, lv)) or []:
                        if not point_in_ring(px, py, part["canvas"]):
                            continue
                        ratio = part["area"] / prov_area
                        if 0.5 <= ratio <= 2.0:
                            geometric.append((lv, src_adm, part, ratio))
        if not chosen and geometric:
            geometric.sort(key=lambda row: abs(math.log(row[3])))
            chosen = [
                _part_option(part, lv, src_adm, px, py, "centroid")
                for lv, src_adm, part, _ratio in geometric[:3]
            ]
        if not chosen:
            skipped_unknown.append(
                {
                    "id": pid,
                    "name": base[pid]["name"],
                    "adm0": adm,
                    "reason": UNKNOWN_REASONS.get(pid, "no %s admin part contains the centroid" % (adm or "?")),
                }
            )
            continue
        options[pid] = chosen
    matched = {}
    used_parts = set()
    pool = []
    for pid, hits in options.items():
        for rank, opt in enumerate(hits):
            pool.append((rank, opt["dist"], pid, opt["part_id"], opt))
    pool.sort()
    claimed = set()
    for _rank, _dist, pid, part_id, opt in pool:
        if pid in claimed or part_id in used_parts:
            continue
        claimed.add(pid)
        used_parts.add(part_id)
        matched[pid] = opt
    for pid in options:
        if pid not in matched:
            skipped_unknown.append(
                {"id": pid, "name": base[pid]["name"], "reason": "admin part already used by a closer province"}
            )
    skipped_unknown.sort(key=lambda row: row["id"])
    print("matched", len(matched), "unknown", len(skipped_unknown), "open", len(considered), flush=True)
    return matched, skipped_unknown


def _ortho_pieces(pts):
    """Split an axis-aligned ring at a revisited vertex.

    A one-pixel stair pinch makes the contour touch itself. Each touch is
    two simple loops sharing that vertex. The larger loop is the district.
    """
    stack = [list(pts)]
    out = []
    while stack:
        cur = stack.pop()
        seen = {}
        split = None
        for i, p in enumerate(cur):
            key = (int(round(p[0])), int(round(p[1])))
            if key in seen:
                j = seen[key]
                split = (cur[j:i], cur[:j] + cur[i:])
                break
            seen[key] = i
        if split is None:
            if len(cur) >= 4:
                out.append(cur)
            continue
        for part in split:
            if len(part) >= 4:
                stack.append(part)
    return out


def _force_simple(pid, ring):
    """Return a strictly simple ring. Repair a pinch with the largest simple loop."""
    from gap_china2_outline import _area, _clean, covered_loops

    def _emit(pts):
        if len(pts) in (36, 72):
            a, b = pts[0], pts[1]
            mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
            pts = [pts[0], mid] + list(pts[1:])
        return [_json_pt(float(p[0]), float(p[1])) for p in pts]

    pts = open_ring(ring)
    if len(pts) >= 3 and not ring_is_raw_invalid(pts):
        return _emit(pts)
    pieces = _ortho_pieces(pts)
    good = [
        part
        for part in pieces
        if len(part) >= 4 and abs(_area(part)) > 1.0 and not ring_is_raw_invalid(part)
    ]
    if not good:
        loops = [loop for loop in covered_loops(_clean(pts)) if _area(loop) > 1.0]
        good = [loop for loop in loops if not ring_is_raw_invalid(loop)]
    if not good:
        raise RuntimeError("raw-invalid repair %s" % pid)
    best = max(good, key=lambda part: abs(_area(part)))
    print("repaired", pid, "verts", len(pts), "->", len(best), flush=True)
    return _emit(best)


def _order_preserving(old, new_set):
    kept = [n for n in old if n in new_set]
    have = set(kept)
    added = sorted(n for n in new_set if n not in have)
    return kept + added, added, [n for n in old if n not in new_set]


def _ring_hits_foreign(pid, ring, other_land, sea_masks, matched, geo) -> bool:
    """True when this outline covers another land province or a sea zone."""
    for entry in other_land:
        if overlap_px(ring, entry[1]) > 1:
            return True
    for sid, _sb, _sm in sea_masks:
        opts = open_ring(geo[sid].get("points") or [])
        if len(opts) >= 3 and overlap_px(ring, opts) > 1:
            return True
    for other, info in matched.items():
        if other == pid:
            continue
        if overlap_px(ring, info["canvas"]) > 1:
            return True
    return False


def _touches(pid, ring, rings) -> set:
    bb = integer_bounds(ring, 2)
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


def _drop_new_third_overlaps(pid, ring, took, new_rings, geo, base):
    """Remove yield pixels that newly overlap a province this notch did not target."""
    for _guard in range(4):
        blockers = []
        for oid, g in geo.items():
            if oid == pid or oid in took or oid in new_rings:
                continue
            if _is_water(oid, base.get(oid, {})):
                continue
            opts = open_ring(g.get("points") or [])
            if len(opts) < 3:
                continue
            ov = overlap_px(ring, opts)
            if ov <= 1:
                continue
            old_ov = overlap_px(geo[pid]["points"], opts)
            if ov <= max(1, old_ov):
                print("yield-overlap kept", pid, oid, "new", ov, "old", old_ov, flush=True)
                continue
            print("yield-overlap shave", pid, oid, "new", ov, "old", old_ov, flush=True)
            blockers.append(opts)
        for sid in took:
            if overlap_px(ring, new_rings[sid]) > 1:
                blockers.append(open_ring(new_rings[sid]))
        if not blockers:
            break
        bb = integer_bounds(ring, 1)
        reduced = rasterize_centers(ring, bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])
        for opts in blockers:
            ob = integer_bounds(opts, 1)
            om = rasterize_centers(opts, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
            _subtract(bb, reduced, ob, om)
        if int(reduced.sum()) < 10:
            raise RuntimeError("third-party shave emptied %s" % pid)
        ring = _ring_from_mask(reduced, bb)
    return ring


def _absorb_new_holes(new_rings, yields, geo, base):
    """Give a newly enclosed hole to the re-ringed province that touches it most.

    Restoring one admin unit can fence in a sibling district the densify bin
    dropped. That empty patch is real land with no province. It is painted
    onto the neighbouring new ring so the board does not gain a hole.
    """
    import numpy as np

    from gap_eng1_product import HOLE_PX_MAX, _hole_components, _prior_allows
    from gap_ussr_west2_product import _cluster_windows

    rings = {}
    for pid, g in geo.items():
        if pid in new_rings:
            rings[pid] = open_ring(new_rings[pid])
        elif pid in yields:
            rings[pid] = open_ring(yields[pid])
        else:
            pts = open_ring(g.get("points") or [])
            if len(pts) >= 3:
                rings[pid] = pts
    boxes = [(pid, integer_bounds(ring, 2)) for pid, ring in new_rings.items()]
    for win in _cluster_windows(boxes, 4):
        w, h = win[2] - win[0], win[3] - win[1]
        if w <= 0 or h <= 0 or w * h > 6_000_000:
            continue
        for _pass in range(3):
            occ = np.zeros((h, w), np.uint8)
            for pid, pts in rings.items():
                bb = integer_bounds(pts, 0)
                if not _bboxes_overlap(win, bb):
                    continue
                occ |= rasterize_centers(pts, win[0], win[1], w, h)
            absorbed = False
            for size, px, py, cells in _hole_components(occ, win[0], win[1]):
                if size <= HOLE_PX_MAX or _prior_allows(size, cells, (win[0], win[1])):
                    continue
                hole = np.zeros((h, w), np.uint8)
                for r, c in cells:
                    hole[r, c] = 1
                touch = np.zeros_like(hole)
                touch[1:, :] |= hole[:-1, :]
                touch[:-1, :] |= hole[1:, :]
                touch[:, 1:] |= hole[:, :-1]
                touch[:, :-1] |= hole[:, 1:]
                touch &= np.uint8(1 - hole)
                best_pid, best_n = None, 0
                best_bounds = None
                for pid in new_rings:
                    bb = integer_bounds(rings[pid], 1)
                    part = rasterize_centers(rings[pid], win[0], win[1], w, h)
                    n = int((touch & part).sum())
                    if n > best_n:
                        best_pid, best_n, best_bounds = pid, n, bb
                if best_pid is None or best_n == 0:
                    raise RuntimeError("enclosed hole %d px at (%.1f, %.1f) touches no re-ring" % (size, px, py))
                xs = [win[0] + c for _r, c in cells]
                ys = [win[1] + r for r, _c in cells]
                nb = (
                    min(best_bounds[0], min(xs)),
                    min(best_bounds[1], min(ys)),
                    max(best_bounds[2], max(xs) + 1),
                    max(best_bounds[3], max(ys) + 1),
                )
                mask = np.zeros((nb[3] - nb[1], nb[2] - nb[0]), np.uint8)
                _or_into(
                    nb,
                    mask,
                    integer_bounds(rings[best_pid], 0),
                    rasterize_centers(
                        rings[best_pid],
                        *integer_bounds(rings[best_pid], 0)[:2],
                        integer_bounds(rings[best_pid], 0)[2] - integer_bounds(rings[best_pid], 0)[0],
                        integer_bounds(rings[best_pid], 0)[3] - integer_bounds(rings[best_pid], 0)[1],
                    ),
                )
                for r, c in cells:
                    mask[win[1] + r - nb[1], win[0] + c - nb[0]] = 1
                ring = _ring_from_mask(mask, nb)
                ring = _force_simple(best_pid, ring)
                new_rings[best_pid] = ring
                rings[best_pid] = open_ring(ring)
                print("absorb", size, "px at", round(px, 1), round(py, 1), "into", best_pid, flush=True)
                absorbed = True
                break
            if not absorbed:
                break
    return new_rings


def clip_batch(matched, base, geo):
    """Return (new_rings, yields, stolen_from) for this matched subset."""
    import numpy as np

    gis_masks = {}
    for pid, info in matched.items():
        bounds = integer_bounds(info["canvas"], 2)
        mask = rasterize_centers(
            info["canvas"], bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1]
        )
        gis_masks[pid] = [bounds, mask]
    for pid in sorted(gis_masks):
        bounds, mask = gis_masks[pid]
        for other in sorted(gis_masks):
            if other >= pid:
                continue
            ob, om = gis_masks[other]
            _subtract(bounds, mask, ob, om)

    def _mask_of(pid, pts):
        bb = integer_bounds(pts, 1)
        return bb, rasterize_centers(pts, bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])

    sea_masks = []
    frozen_masks = []
    for pid, row in base.items():
        g = geo.get(pid)
        if not g:
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        bb = integer_bounds(pts, 1)
        if not any(_bboxes_overlap(bb, gis_masks[s][0]) for s in gis_masks):
            continue
        if pid in FROZEN:
            frozen_masks.append((pid, *_mask_of(pid, pts)))
            continue
        if _is_water(pid, row):
            sea_masks.append((pid, *_mask_of(pid, pts)))
    # Admin mask before the sea clip. A coarse sea polygon can cover a whole
    # district (Bandarban sits inside 950308). A single sea ring cannot be
    # punched into an interior hole, so that district keeps its admin pixels
    # and overlaps the sea the way the existing CHI coast already does.
    admin_masks = {}
    for pid in gis_masks:
        bounds, mask = gis_masks[pid]
        admin_masks[pid] = (tuple(bounds), mask.copy())
        for _sid, sb, sm in sea_masks:
            _subtract(bounds, mask, sb, sm)
        for _sid, sb, sm in frozen_masks:
            _subtract(bounds, mask, sb, sm)

    other_land = []
    for pid, row in base.items():
        if pid in matched or pid in FROZEN or _is_water(pid, row):
            continue
        g = geo.get(pid)
        if not g:
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        bb = integer_bounds(pts, 1)
        if not any(_bboxes_overlap(bb, gis_masks[s][0]) for s in gis_masks):
            continue
        other_land.append([pid, pts, bb, None])

    def other_mask(entry):
        if entry[3] is None:
            bb = entry[2]
            entry[3] = rasterize_centers(entry[1], bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])
        return entry[2], entry[3]

    final_masks = {}
    for pid in sorted(matched):
        bounds, mask = gis_masks[pid]
        old_pts = open_ring(geo[pid].get("points") or [])
        old_bounds = integer_bounds(old_pts, 2)
        ub = (
            min(bounds[0], old_bounds[0]),
            min(bounds[1], old_bounds[1]),
            max(bounds[2], old_bounds[2]),
            max(bounds[3], old_bounds[3]),
        )
        if ub != tuple(bounds):
            moved = np.zeros((ub[3] - ub[1], ub[2] - ub[0]), np.uint8)
            _or_into(ub, moved, bounds, mask)
            bounds = ub
            mask = moved
            gis_masks[pid] = [bounds, mask]
        old_m = rasterize_centers(old_pts, bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
        bulge_u = ((old_m == 1) & (mask == 0)).astype(np.uint8)
        for entry in other_land:
            ob, om = other_mask(entry)
            _subtract(bounds, bulge_u, ob, om)
        for _sid, sb, sm in sea_masks:
            _subtract(bounds, bulge_u, sb, sm)
        for _sid, sb, sm in frozen_masks:
            _subtract(bounds, bulge_u, sb, sm)
        for other in matched:
            if other == pid:
                continue
            ob, om = gis_masks[other]
            _subtract(bounds, bulge_u, ob, om)
        mask = mask | bulge_u
        if int(mask.sum()) < 1:
            ab, am = admin_masks[pid]
            restored = np.zeros_like(mask)
            _or_into(bounds, restored, ab, am)
            for _sid, sb, sm in frozen_masks:
                _subtract(bounds, restored, sb, sm)
            for other in matched:
                if other >= pid:
                    continue
                ob, om = gis_masks[other]
                _subtract(bounds, restored, ob, om)
            if int(restored.sum()) < 12:
                raise RuntimeError("province %s empty after clip" % pid)
            mask = restored
            print("coarse-sea overlap kept", pid, int(mask.sum()), flush=True)
        final_masks[pid] = (bounds, mask)

    new_rings: Dict[int, List[List[float]]] = {}
    for pid, (bounds, mask) in list(final_masks.items()):
        # A reef can cover fewer than three pixel centers. The contour tracer
        # refuses that, and a stair would invent a shape. Keep the admin
        # outline when it does not cover another province.
        ring = None
        if int(mask.sum()) < 12:
            canvas = [_json_pt(float(p[0]), float(p[1])) for p in open_ring(matched[pid]["canvas"])]
            if canvas and not self_crosses(canvas) and ring_area(canvas) > 0:
                if not _ring_hits_foreign(pid, canvas, other_land, sea_masks, matched, geo):
                    ring = canvas
        if ring is None:
            if int(mask.sum()) < 3:
                raise RuntimeError("province %s empty after clip" % pid)
            ring = _ring_from_mask(mask, bounds)
        ring = _force_simple(pid, ring)
        new_rings[pid] = ring
        painted = rasterize_centers(ring, bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
        final_masks[pid] = (bounds, painted)
        print(
            "ring",
            pid,
            base[pid]["name"],
            "verts",
            vertex_count(geo[pid]["points"]),
            "->",
            len(ring),
            "area",
            round(ring_area(geo[pid]["points"]), 1),
            "->",
            round(ring_area(ring), 1),
            "src",
            matched[pid]["src_name"],
            "dist",
            round(matched[pid]["dist"], 1),
            flush=True,
        )

    yields: Dict[int, List[List[float]]] = {}
    yield_masks = {}
    stolen_from: Dict[int, List[int]] = defaultdict(list)
    for entry in other_land:
        pid = entry[0]
        ob, om = other_mask(entry)
        reduced = om.copy()
        took = []
        for sid, (sb, sm) in final_masks.items():
            n = _subtract(ob, reduced, sb, sm)
            if n:
                took.append(sid)
        if not took:
            continue
        if int(reduced.sum()) < 10:
            raise RuntimeError("neighbour %s would vanish" % pid)
        try:
            ring = _ring_from_mask(reduced, ob)
        except RuntimeError as exc:
            raise RuntimeError("notch %s %s: %s" % (pid, base[pid]["name"], exc)) from exc
        painted = rasterize_centers(ring, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
        for _pass in range(4):
            bad = [sid for sid in took if overlap_px(ring, new_rings[sid]) > 1]
            if not bad:
                break
            stolen = np.zeros_like(reduced)
            for sid in bad:
                sb, sm = final_masks[sid]
                _or_into(ob, stolen, sb, sm)
            extra = ((painted == 1) & (reduced == 0) & (stolen == 1)).astype(np.uint8)
            if int(extra.sum()) == 0:
                detail = [(sid, overlap_px(ring, new_rings[sid])) for sid in bad]
                raise RuntimeError("notch %s still overlaps %s" % (pid, detail))
            for sid in bad:
                sb, sm = final_masks[sid]
                _subtract(sb, sm, ob, extra)
                new_rings[sid] = _ring_from_mask(sm, sb)
                final_masks[sid] = (
                    sb,
                    rasterize_centers(new_rings[sid], sb[0], sb[1], sb[2] - sb[0], sb[3] - sb[1]),
                )
            reduced = reduced | extra
            ring = _ring_from_mask(reduced, ob)
            painted = rasterize_centers(ring, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
        else:
            detail = [(sid, overlap_px(ring, new_rings[sid])) for sid in took]
            raise RuntimeError("notch %s still overlaps %s" % (pid, detail))
        others = []
        for oid, g in geo.items():
            if oid == pid or oid in took or _is_water(oid, base.get(oid, {})):
                continue
            opts = open_ring(g.get("points") or [])
            if len(opts) >= 3:
                others.append(opts)
        shaved = _shave_new_border_slivers(geo[pid]["points"], ring, others)
        if not self_crosses(shaved):
            ring = shaved
        ring = _drop_new_third_overlaps(pid, ring, took, new_rings, geo, base)
        ring = _force_simple(pid, ring)
        yields[pid] = ring
        yield_masks[pid] = (ob, rasterize_centers(ring, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1]))
        stolen_from[pid] = took
        print("yield", pid, base[pid]["name"], "for", took, "verts", vertex_count(geo[pid]["points"]), "->", len(ring), flush=True)

    new_rings = _absorb_new_holes(new_rings, yields, geo, base)
    problems = []
    land_for_check = {}
    for pid, g in geo.items():
        if _is_water(pid, base.get(pid, {})):
            continue
        if pid in new_rings:
            land_for_check[pid] = new_rings[pid]
        elif pid in yields:
            land_for_check[pid] = yields[pid]
        else:
            pts = open_ring(g.get("points") or [])
            if len(pts) >= 3:
                land_for_check[pid] = pts
    boxes = {pid: integer_bounds(pts, 0) for pid, pts in land_for_check.items()}
    for pid, ring in new_rings.items():
        for oid, other in land_for_check.items():
            if oid == pid:
                continue
            if not _bboxes_overlap(boxes[pid], boxes[oid]):
                continue
            ov = overlap_px(ring, other)
            if ov > 1:
                problems.append((ov, pid, oid))
    if problems:
        problems.sort(reverse=True)
        raise RuntimeError("OVERLAPS %s" % (problems[:12],))
    print("overlap ok", len(new_rings), "rings", len(yields), "yields", flush=True)

    from gap_china2_outline import _area, _clean, _nz_pair_area, as_points, region_loops

    def _on_grid(ring) -> bool:
        for x, y in open_ring(ring):
            if abs(x - round(x)) > 1e-4 or abs(y - round(y)) > 1e-4:
                return False
        return True

    def _poly_fix(pid, ring):
        for _guard in range(8):
            hit = None
            for oid, other in land_for_check.items():
                if oid == pid:
                    continue
                if not _bboxes_overlap(integer_bounds(ring, 0), integer_bounds(other, 0)):
                    continue
                # Grid stairs that share no pixel center have no polygon area.
                if _on_grid(ring) and _on_grid(other) and overlap_px(ring, other) <= 1:
                    continue
                area = _nz_pair_area(_clean(ring), _clean(other))
                if area > POLY_OVERLAP_MAX:
                    hit = (area, oid, other)
                    break
            if hit is None:
                return ring
            area, oid, other = hit
            loops = region_loops([ring], [other], "difference")
            if not loops:
                raise RuntimeError("poly overlap %s x %s emptied the ring (%.1f)" % (pid, oid, area))
            ring = _force_simple(pid, as_points(max(loops, key=_area), nd=4))
            land_for_check[pid] = open_ring(ring)
            print("poly-shave", pid, oid, round(area, 2), flush=True)
        raise RuntimeError("poly overlap remains on %s" % pid)

    for pid in list(new_rings):
        new_rings[pid] = _poly_fix(pid, new_rings[pid])
        land_for_check[pid] = open_ring(new_rings[pid])
    for pid in list(yields):
        yields[pid] = _poly_fix(pid, yields[pid])
        land_for_check[pid] = open_ring(yields[pid])
    for pid, ring in list(new_rings.items()) + list(yields.items()):
        if ring_is_raw_invalid(ring):
            raise RuntimeError("still raw-invalid %s" % pid)
    print("poly overlap ok", flush=True)
    return new_rings, yields, stolen_from, final_masks, yield_masks


def _garrison_borders(owners, domains, adj) -> Dict[str, List[int]]:
    owner_of = {int(k): v for k, v in owners.items()}
    water = {"sea", "strait", "lake"}
    out = {}
    for tag in GARRISON_TAGS:
        ids = []
        for pid, own in owner_of.items():
            if own != tag or pid >= 950000 or str(domains.get(pid) or "") in water:
                continue
            for nid in adj.get(str(pid), []):
                nid = int(nid)
                if nid >= 950000 or str(domains.get(nid) or "") in water:
                    continue
                other = owner_of.get(nid) or ""
                if other and other != tag:
                    ids.append(pid)
                    break
        out[tag] = ids
    return out


def _write_geometry(updates, new_rings, matched) -> None:
    raw = GEO_PATH.read_text(encoding="utf-8")
    for pid in sorted(updates, reverse=True):
        start, end = _find_object(raw, pid)
        raw = _splice_field(raw, start, end, "points", json.dumps(updates[pid], separators=(",", ":")))
        start, end = _find_object(raw, pid)
        obj, _rel = json.JSONDecoder().raw_decode(raw, start)
        meta = dict(obj.get("meta") or {})
        if pid in new_rings:
            info = matched[pid]
            meta[META_RING] = "geoBoundaries-%s-%s:%s" % (info["adm"], info["level"], info["src_name"])
            meta["vertex_n"] = len(open_ring(updates[pid]))
            meta["area"] = round(ring_area(updates[pid]), 6)
        else:
            meta[META_YIELD] = "notch"
        raw = _splice_field(raw, start, end, "meta", json.dumps(meta, separators=(",", ":")))
        anchor = obj.get("label_anchor")
        ring = updates[pid]
        if isinstance(anchor, list) and len(anchor) >= 2:
            if not _point_in(float(anchor[0]), float(anchor[1]), ring):
                cx, cy = polygon_centroid(ring)
                if not _point_in(cx, cy, ring):
                    cx, cy = _interior_point(ring)
                start, end = _find_object(raw, pid)
                raw = _splice_field(
                    raw, start, end, "label_anchor", json.dumps([round(cx, 4), round(cy, 4)], separators=(",", ":"))
                )
                print("anchor moved", pid, flush=True)
    check = json.loads(raw)
    if len(check["provinces"]) != 3596:
        raise RuntimeError("written count %s" % len(check["provinces"]))
    GEO_PATH.write_text(raw, encoding="utf-8")
    print("geometry written", len(updates), flush=True)


def _write_adjacency(adj, adj_changes) -> None:
    if not adj_changes:
        print("adjacency unchanged", flush=True)
        return
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
            raise RuntimeError("adjacency key missing %s" % pid)
        end = adj_raw.find("]", at)
        if end < 0:
            raise RuntimeError("adjacency list %s" % pid)
        body = ",\n".join("      %d" % n for n in adj[str(pid)])
        repl = '\n    "%d": [\n%s\n    ]' % (pid, body)
        adj_raw = adj_raw[:at] + repl + adj_raw[end + 1 :]
    json.loads(adj_raw)
    ADJ_PATH.write_text(adj_raw, encoding="utf-8")
    print("adjacency written", sorted(changed_ids), flush=True)


def _batch_ids(geo, adm0: str, id_filter: Sequence[int]):
    """None means every in-scope placeholder. A list limits match and clip."""
    if not adm0 and not id_filter:
        return None
    allow = {int(pid) for pid in id_filter}
    ids = []
    for pid in SCOPE_PLACEHOLDER_IDS:
        if allow and pid not in allow:
            continue
        if adm0:
            board_adm = str((geo[pid].get("meta") or {}).get("adm0_a3") or "")
            aliases = _source_adms(board_adm)
            if adm0 != board_adm and adm0 not in aliases and board_adm not in _source_adms(adm0):
                continue
        ids.append(pid)
    return ids


def build(apply: bool, adm0: str, limit: int, id_filter: Sequence[int], match_only: bool) -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    base_rows = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    base = {int(p["id"]): p for p in base_rows}
    geo_doc = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    domains = {pid: row.get("domain") for pid, row in base.items()}
    if len(base) != 3596 or len(geo_doc["provinces"]) != 3596:
        print("refuse: province count", len(base), len(geo_doc["provinces"]))
        return 2
    adj_doc_now = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj_now = {k: [int(n) for n in v] for k, v in adj_doc_now["adjacency"].items()}
    before_path = EVIDENCE / "garrison_border_before.json"
    if not before_path.is_file():
        before_path.write_text(
            json.dumps(_garrison_borders(owners, domains, adj_now)) + "\n", encoding="utf-8"
        )
        print("wrote", before_path, flush=True)
    restrict = _batch_ids(geo, adm0, id_filter)
    load_only: List[str] = []
    if restrict is not None:
        for pid in restrict:
            board_adm = str((geo[pid].get("meta") or {}).get("adm0_a3") or "")
            load_only.extend(_source_adms(board_adm))
    parts = load_parts(load_only)
    matched, unknown = match_provinces(base, geo, owners, parts, restrict or ())
    full_pass = restrict is None
    if full_pass:
        (EVIDENCE / "unknown.json").write_text(
            json.dumps({"rows": unknown}, indent=2) + "\n", encoding="utf-8"
        )
    if match_only:
        slim = []
        for pid, info in sorted(matched.items()):
            slim.append(
                {
                    "id": pid,
                    "name": base[pid]["name"],
                    "how": info["how"],
                    "adm": info["adm"],
                    "level": info["level"],
                    "src_name": info["src_name"],
                    "src_n": info["src_n"],
                    "area": round(float(info["area"]), 1),
                    "dist": round(float(info["dist"]), 2),
                }
            )
        if full_pass:
            (EVIDENCE / "matches.json").write_text(
                json.dumps({"count": len(slim), "rows": slim}, indent=2) + "\n", encoding="utf-8"
            )
        print("match-only: geometry not written")
        return 0
    if adm0:
        matched = {
            pid: info
            for pid, info in matched.items()
            if info["adm"] == adm0 or str((geo[pid].get("meta") or {}).get("adm0_a3") or "") == adm0
        }
    if id_filter:
        want = set(int(i) for i in id_filter)
        matched = {pid: info for pid, info in matched.items() if pid in want}
    ids = sorted(matched)
    if limit > 0:
        ids = ids[:limit]
        matched = {pid: matched[pid] for pid in ids}
    print("batch", len(matched), flush=True)
    if not matched:
        print("nothing to do")
        return 0
    new_rings, yields, stolen_from, _fm, _ym = clip_batch(matched, base, geo)
    updates = {}
    updates.update(new_rings)
    updates.update(yields)

    adj_doc = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj = {k: [int(n) for n in v] for k, v in adj_doc["adjacency"].items()}
    old_rings = {}
    new_ring_map = {}
    for pid, g in geo.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            old_rings[pid] = pts
            new_ring_map[pid] = pts
    for pid, ring in updates.items():
        new_ring_map[pid] = open_ring(ring)
    adj_changes = []
    for pid in sorted(updates):
        old_list = list(adj.get(str(pid), []))
        before_touch = _touches(pid, old_rings[pid], old_rings)
        after_touch = _touches(pid, new_ring_map[pid], new_ring_map)
        if not after_touch and not old_list:
            print("refuse: zero neighbours", pid)
            return 2
        gained = after_touch - before_touch
        lost = before_touch - after_touch
        new_set = (set(old_list) - lost) | gained
        if not new_set:
            print("refuse: zero neighbours", pid)
            return 2
        updated, added, dropped = _order_preserving(old_list, new_set)
        if added or dropped:
            adj_changes.append({"id": pid, "added": added, "dropped": dropped, "name": base[pid]["name"]})
            adj[str(pid)] = updated
            for oid in dropped:
                key = str(oid)
                adj[key] = [n for n in adj.get(key, []) if n != pid]
            for oid in added:
                key = str(oid)
                cur = list(adj.get(key, []))
                if pid not in cur:
                    adj[key] = cur + [pid]
            print("adj", pid, "add", added, "drop", dropped, flush=True)
    for pid in updates:
        for nid in adj[str(pid)]:
            if pid not in adj.get(str(nid), []):
                print("refuse: asymmetric", pid, nid)
                return 2
    # A real outline can pull away from a coarse neighbour on every side.
    # Keep one old link so that province is not left with an empty list.
    for oid_s, nbs in list(adj.items()):
        if nbs:
            continue
        oid = int(oid_s)
        restorers = [row for row in adj_changes if oid in row["dropped"]]
        if not restorers:
            continue
        pid = restorers[0]["id"]
        adj[oid_s] = [pid]
        if oid not in adj[str(pid)]:
            adj[str(pid)].append(oid)
        row = restorers[0]
        row["dropped"] = [n for n in row["dropped"] if n != oid]
        print("restore-link", oid, "keeps", pid, flush=True)
    adj_changes[:] = [row for row in adj_changes if row["added"] or row["dropped"]]

    rows = []
    for pid, ring in sorted(new_rings.items()):
        rows.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "role": "rering",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(ring)),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(ring), 2),
                "source": "geoBoundaries-%s-%s:%s" % (matched[pid]["adm"], matched[pid]["level"], matched[pid]["src_name"]),
                "centroid_shift_px": round(matched[pid]["dist"], 2),
                "adm0": matched[pid]["adm"],
            }
        )
    for pid, ring in sorted(yields.items()):
        rows.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "role": "yield",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(ring)),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(ring), 2),
                "stole_for": stolen_from[pid],
            }
        )
    table_path = EVIDENCE / "rering_table.json"
    prior = {"rows": []}
    if table_path.is_file():
        prior = json.loads(table_path.read_text(encoding="utf-8"))
    by_id = {int(row["id"]): row for row in prior.get("rows") or [] if row.get("role") == "rering" or True}
    for row in rows:
        by_id[int(row["id"])] = row
    table_path.write_text(json.dumps({"rows": [by_id[k] for k in sorted(by_id)]}, indent=2) + "\n", encoding="utf-8")
    (EVIDENCE / "adjacency.json").write_text(json.dumps({"changes": adj_changes}, indent=2) + "\n", encoding="utf-8")
    # Merge adjacency changes across batches.
    adj_all = EVIDENCE / "adjacency_all.json"
    prev_changes = []
    if adj_all.is_file():
        prev_changes = json.loads(adj_all.read_text(encoding="utf-8")).get("changes") or []
    seen = {int(row["id"]) for row in adj_changes}
    merged_changes = [row for row in prev_changes if int(row["id"]) not in seen] + adj_changes
    adj_all.write_text(json.dumps({"changes": merged_changes}, indent=2) + "\n", encoding="utf-8")
    patched = []
    for g in geo_doc["provinces"]:
        pid = int(g["id"])
        if pid not in updates:
            patched.append(g)
            continue
        g2 = dict(g)
        g2["points"] = updates[pid]
        meta = dict(g.get("meta") or {})
        if pid in new_rings:
            meta[META_RING] = "batch"
        g2["meta"] = meta
        patched.append(g2)
    # Yields may keep an overlap the old ring already had. New rings must tile.
    audit_problems = audit_changed(patched, domains, adj, sorted(new_rings))
    if audit_problems:
        print("AUDIT", audit_problems)
        return 2
    print("audit ok", flush=True)
    print("evidence", EVIDENCE, "changes", len(adj_changes), flush=True)
    if not apply:
        print("dry-run: geometry not written")
        return 0
    _write_geometry(updates, new_rings, matched)
    _write_adjacency(adj, adj_changes)
    borders = _garrison_borders(owners, domains, adj)
    (EVIDENCE / "garrison_border_after.json").write_text(json.dumps(borders) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--match-only", action="store_true")
    ap.add_argument("--adm0", default="")
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--ids", default="", help="comma-separated province ids")
    args = ap.parse_args()
    id_filter = [int(x) for x in args.ids.split(",") if x.strip()]
    return build(args.apply, args.adm0.strip().upper(), args.limit, id_filter, args.match_only)


if __name__ == "__main__":
    raise SystemExit(main())
