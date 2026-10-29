#!/usr/bin/env python3
"""Replace SOV 1936 36-vertex placeholder rings with geoBoundaries rings.

Source GeoJSON is the same gbOpen simplified set densify_row_geoboundaries.py
downloads (not committed; cache is gitignored). Numpy only, no shapely.

  python3 tools/map_generation/scripts/apply_gap_ussr_west2.py
  python3 tools/map_generation/scripts/apply_gap_ussr_west2.py --apply

Matching is exact on the normalized admin name. A hit whose centroid is more
than 40 px from the current ring is rejected. Baikonur lease 902132 has no
admin polygon and is left unchanged.

New rings win overlapping land pixels (neighbours are notched). Sea zones
(id >= 950000) keep their pixels. Old placeholder pixels that covered no
other province stay with the province so a densify bulge cannot open a hole.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_ussr_west2_product import (  # noqa: E402
    HOLE_PX_MAX,
    META_RING,
    META_YIELD,
    UNKNOWN_PLACEHOLDER_IDS,
    audit_board,
    integer_bounds,
    is_placeholder_ring,
    largest_component,
    open_ring,
    overlap_px,
    point_in_ring,
    rasterize_centers,
    ring_area,
    ring_bbox,
    trace_mask,
    vertex_count,
)
from ne_full_geometry_align import lonlat_to_canvas, polygon_centroid  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
GEO_PATH = BOARD / "provinces_geometry.json"
ADJ_PATH = BOARD / "province_adjacency.json"
SOURCE_DIRS = (
    Path.home() / "gapussrw2" / "scratch" / "geoboundaries",
    ROOT / "tools" / "map_generation" / "data" / "cache" / "geoboundaries",
)
ADM_LEVEL = {
    "RUS": "ADM1",
    "AZE": "ADM2",
    "GEO": "ADM2",
    "ARM": "ADM2",
    "KGZ": "ADM2",
}
CENTROID_MAX_PX = 40.0
RDP_EPS = 0.45


def _norm(name: str) -> str:
    text = name.lower().replace("’", "'").replace("`", "'")
    text = re.sub(r"\s+area$", "", text)
    text = re.sub(r"\s+district$", "", text)
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def _largest_lonlat_ring(geom: dict):
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates")
    if not coords:
        return None
    cands = []
    if gtype == "Polygon":
        cands = [coords[0]] if coords else []
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                cands.append(poly[0])
    if not cands:
        return None

    def area(ring):
        acc = 0.0
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i][0], ring[i][1]
            x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
            acc += x1 * y2 - x2 * y1
        return abs(acc) * 0.5

    outer = max(cands, key=area)
    ring = [[float(p[0]), float(p[1])] for p in outer]
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    return ring if len(ring) >= 3 else None


def _rdp(points: Sequence[Sequence[float]], eps: float) -> List[List[float]]:
    """Douglas-Peucker. Iterative so a 20k-point coast does not recurse."""
    pts = [list(p) for p in points]
    n = len(pts)
    if n < 3:
        return pts
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        den = math.hypot(dx, dy)
        best_i = -1
        best_d = eps
        for i in range(a + 1, b):
            px, py = pts[i]
            if den < 1e-12:
                dist = math.hypot(px - ax, py - ay)
            else:
                dist = abs(dy * px - dx * py + bx * ay - by * ax) / den
            if dist > best_d:
                best_d = dist
                best_i = i
        if best_i >= 0:
            keep[best_i] = True
            stack.append((a, best_i))
            stack.append((best_i, b))
    return [pts[i] for i in range(n) if keep[i]]


def _load_sources() -> Dict[Tuple[str, str], List[List[float]]]:
    src = None
    for folder in SOURCE_DIRS:
        if (folder / "geoBoundaries-RUS-ADM1_simplified.geojson").is_file():
            src = folder
            break
    if src is None:
        raise SystemExit("geoBoundaries cache missing under ~/gapussrw2/scratch/geoboundaries")
    out: Dict[Tuple[str, str], List[List[float]]] = {}
    for adm, level in ADM_LEVEL.items():
        path = src / ("geoBoundaries-%s-%s_simplified.geojson" % (adm, level))
        doc = json.loads(path.read_text(encoding="utf-8"))
        for feat in doc.get("features") or []:
            props = feat.get("properties") if isinstance(feat.get("properties"), dict) else {}
            name = str(props.get("shapeName") or props.get("name") or "")
            ring = _largest_lonlat_ring(feat.get("geometry") or {})
            if not ring:
                continue
            out[(adm, _norm(name))] = ring
    return out


def _canvas_ring(lonlat: Sequence[Sequence[float]]) -> List[List[float]]:
    simplified = _rdp(lonlat, 0.02) if len(lonlat) > 4000 else lonlat
    # 0.02 degrees is a coarse pre-pass; the canvas RDP below is the real tolerance.
    canvas = [[*lonlat_to_canvas(float(lon), float(lat))] for lon, lat in simplified]
    if len(canvas) > 800:
        canvas = _rdp(canvas, RDP_EPS)
    return canvas


def _is_water(pid: int, base_row: dict) -> bool:
    if pid >= 950000:
        return True
    return str(base_row.get("domain") or "") in ("sea", "strait", "lake")


def _bboxes_overlap(a, b) -> bool:
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def _subtract(dst_bounds, dst, src_bounds, src) -> int:
    """Clear dst pixels that are set in src. Returns cleared count."""
    dx0, dy0, dx1, dy1 = dst_bounds
    sx0, sy0, sx1, sy1 = src_bounds
    ix0, iy0 = max(dx0, sx0), max(dy0, sy0)
    ix1, iy1 = min(dx1, sx1), min(dy1, sy1)
    if ix0 >= ix1 or iy0 >= iy1:
        return 0
    sub_d = dst[iy0 - dy0 : iy1 - dy0, ix0 - dx0 : ix1 - dx0]
    sub_s = src[iy0 - sy0 : iy1 - sy0, ix0 - sx0 : ix1 - sx0]
    both = (sub_d == 1) & (sub_s == 1)
    n = int(both.sum())
    if n:
        sub_d[both] = 0
    return n


def _or_into(dst_bounds, dst, src_bounds, src) -> None:
    dx0, dy0, dx1, dy1 = dst_bounds
    sx0, sy0, sx1, sy1 = src_bounds
    ix0, iy0 = max(dx0, sx0), max(dy0, sy0)
    ix1, iy1 = min(dx1, sx1), min(dy1, sy1)
    if ix0 >= ix1 or iy0 >= iy1:
        return
    sub_d = dst[iy0 - dy0 : iy1 - dy0, ix0 - dx0 : ix1 - dx0]
    sub_s = src[iy0 - sy0 : iy1 - sy0, ix0 - sx0 : ix1 - sx0]
    sub_d |= sub_s


def _mask_hole_px(mask) -> int:
    from gap_ussr_west2_product import enclosed_hole_px

    return enclosed_hole_px(mask)


def _json_pt(x: float, y: float):
    if float(x).is_integer() and float(y).is_integer():
        return [int(x), int(y)]
    return [round(float(x), 4), round(float(y), 4)]


def _ring_from_mask(mask, bounds) -> List[List[float]]:
    """Exterior of the largest component.

    A single ring cannot punch interior holes. Quantization leaves a few
    empty pixels inside the coast; those are absorbed when the total is
    within the hole budget and the ring misses none of the component.
    """
    import numpy as np

    comp, kept, dropped = largest_component(mask)
    if kept < 3:
        raise RuntimeError("empty component")
    if dropped > HOLE_PX_MAX:
        rest = ((mask == 1) & (comp == 0)).astype(np.uint8)
        _rest_comp, other, _rest_drop = largest_component(rest)
        # Several slits may sum past the budget. Each piece must still be
        # small enough that dropping it cannot open a hole over the budget.
        if other > HOLE_PX_MAX:
            raise RuntimeError("dropped component %d px" % other)
    ring = trace_mask(comp, bounds[0], bounds[1])
    if len(ring) < 3:
        raise RuntimeError("trace failed")
    # Avoid the placeholder vertex counts. The extra point is the midpoint
    # of an existing edge, so the filled pixels stay the same.
    if len(ring) in (36, 72):
        a = ring[0]
        b = ring[1]
        ring = [a, ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)] + ring[1:]
    back = rasterize_centers(ring, bounds[0], bounds[1], mask.shape[1], mask.shape[0])
    missing = int(np.logical_and(back == 0, comp == 1).sum())
    extra = int(np.logical_and(back == 1, comp == 0).sum())
    if missing != 0 or extra > HOLE_PX_MAX:
        raise RuntimeError("trace missing %d extra %d kept %d dropped %d" % (missing, extra, kept, dropped))
    return [_json_pt(x, y) for x, y in ring]


def _shave_new_border_slivers(old_ring, ring, others):
    """Drop contour stairs that enter a neighbour the old ring did not cover.

    A pixel contour follows cell edges, so it can bulge a fraction of a pixel
    into the next province. That bulge is new area. Coarse overlaps that the
    old ring already had are left in place.
    """
    from gap_china2_outline import _area, _nz_pair_area, as_points, region_loops

    cur = open_ring(ring)
    old = open_ring(old_ring)

    def _probes(pts):
        for x, y in pts:
            yield x, y
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            yield (x1 + x2) * 0.5, (y1 + y2) * 0.5

    for other in others:
        other = open_ring(other)
        if len(other) < 3 or len(cur) < 3:
            continue
        cb = ring_bbox(cur)
        ob = ring_bbox(other)
        if cb[2] < ob[0] or ob[2] < cb[0] or cb[3] < ob[1] or ob[3] < cb[1]:
            continue
        fresh = False
        for x, y in _probes(cur):
            if point_in_ring(x, y, other) and not point_in_ring(x, y, old):
                fresh = True
                break
        if not fresh:
            continue
        if _nz_pair_area(old, other) > 1.0:
            continue
        if _nz_pair_area(cur, other) <= 1.0:
            continue
        loops = region_loops([cur], [other], "difference")
        if not loops:
            raise RuntimeError("shave removed the ring")
        best = max(loops, key=_area)
        cur = open_ring(as_points(best, nd=4))
        if len(cur) in (36, 72):
            a, b = cur[0], cur[1]
            mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
            cur = [a, mid] + list(cur[1:])
    return [_json_pt(x, y) for x, y in cur]


def _box_gap(a, b) -> float:
    """Separation of two xyxy boxes. 0 when they overlap or touch."""
    dx = 0.0
    if a[2] < b[0]:
        dx = b[0] - a[2]
    elif b[2] < a[0]:
        dx = a[0] - b[2]
    dy = 0.0
    if a[3] < b[1]:
        dy = b[1] - a[3]
    elif b[3] < a[1]:
        dy = a[1] - b[3]
    if dx == 0.0 and dy == 0.0:
        return 0.0
    return math.hypot(dx, dy)


def _mask_touches_ring(bounds, mask, ring) -> bool:
    """True when ring pixel-centers overlap the mask or 4-touch it."""
    import numpy as np

    minx, miny, maxx, maxy = ring_bbox(ring)
    ix0 = max(bounds[0], int(math.floor(minx)) - 1)
    iy0 = max(bounds[1], int(math.floor(miny)) - 1)
    ix1 = min(bounds[2], int(math.ceil(maxx)) + 1)
    iy1 = min(bounds[3], int(math.ceil(maxy)) + 1)
    if ix0 >= ix1 or iy0 >= iy1:
        return False
    h, w = iy1 - iy0, ix1 - ix0
    part = np.zeros((h, w), np.uint8)
    _or_into((ix0, iy0, ix1, iy1), part, bounds, mask)
    other = rasterize_centers(ring, ix0, iy0, w, h)
    if np.any(part & other):
        return True
    if h > 1 and (np.any(part[1:, :] & other[:-1, :]) or np.any(part[:-1, :] & other[1:, :])):
        return True
    if w > 1 and (np.any(part[:, 1:] & other[:, :-1]) or np.any(part[:, :-1] & other[:, 1:])):
        return True
    return False


def _splice_field(raw: str, obj_start: int, obj_end: int, field: str, value_json: str) -> str:
    chunk = raw[obj_start:obj_end]
    token = '"%s":' % field
    at = chunk.find(token)
    if at < 0:
        raise RuntimeError("missing %s" % field)
    val_at = at + len(token)
    opener = chunk[val_at]
    if opener not in "[{":
        raise RuntimeError("field %s not a structure" % field)
    close = "]" if opener == "[" else "}"
    depth = 0
    k = val_at
    while k < len(chunk):
        ch = chunk[k]
        if ch == opener:
            depth += 1
        elif ch == close:
            depth -= 1
            if depth == 0:
                k += 1
                break
        k += 1
    else:
        raise RuntimeError("unclosed %s" % field)
    new_chunk = chunk[:val_at] + value_json + chunk[k:]
    return raw[:obj_start] + new_chunk + raw[obj_end:]


def _find_object(raw: str, pid: int) -> Tuple[int, int]:
    token = '"id":%d' % pid
    at = raw.find(token)
    if at < 0 or raw.find(token, at + 1) >= 0:
        raise RuntimeError("id %s not unique" % pid)
    start = raw.rfind("{", 0, at)
    dec = json.JSONDecoder()
    _obj, end = dec.raw_decode(raw, start)
    return start, end


def _match(owners, base, geo, sources):
    matched = {}
    unknown = []
    for key, tag in owners.items():
        if tag != "SOV":
            continue
        pid = int(key)
        g = geo[pid]
        pts = g.get("points") or []
        if not is_placeholder_ring(pts):
            continue
        if pid in UNKNOWN_PLACEHOLDER_IDS:
            unknown.append({"id": pid, "name": base[pid]["name"], "reason": "no admin polygon for the lease"})
            continue
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        adm = str(meta.get("adm0_a3") or "")
        name = str(base[pid]["name"])
        lonlat = sources.get((adm, _norm(name)))
        if lonlat is None:
            unknown.append({"id": pid, "name": name, "reason": "no exact %s name" % adm})
            continue
        canvas = _canvas_ring(lonlat)
        cx, cy = polygon_centroid(canvas)
        px, py = polygon_centroid(open_ring(pts))
        dist = math.hypot(cx - px, cy - py)
        if dist > CENTROID_MAX_PX:
            unknown.append({"id": pid, "name": name, "reason": "centroid %.1f px" % dist})
            continue
        matched[pid] = {
            "canvas": canvas,
            "adm": adm,
            "level": str(meta.get("level") or ADM_LEVEL.get(adm, "")),
            "dist": dist,
            "src_n": len(lonlat),
        }
    return matched, unknown


def build(apply: bool) -> int:
    import numpy as np

    base_rows = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    base = {int(p["id"]): p for p in base_rows}
    geo_doc = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    print("provinces", len(base))
    sources = _load_sources()
    matched, unknown = _match(owners, base, geo, sources)
    print("matched", len(matched), "unknown", unknown)
    if len(matched) < 53:
        print("refuse: expected 53 sourced placeholders")
        return 2
    if any(row["id"] != 902132 for row in unknown):
        print("refuse: unexpected unknown", unknown)
        return 2

    # Masks of the resolved GIS rings, then old exclusive bulges.
    gis_masks = {}
    for pid, info in matched.items():
        bounds = integer_bounds(info["canvas"], 2)
        mask = rasterize_centers(info["canvas"], bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
        gis_masks[pid] = [bounds, mask]
    for pid in sorted(gis_masks):
        bounds, mask = gis_masks[pid]
        for other in sorted(gis_masks):
            if other >= pid:
                continue
            ob, om = gis_masks[other]
            _subtract(bounds, mask, ob, om)

    sea_masks = []
    for pid, row in base.items():
        if not _is_water(pid, row):
            continue
        g = geo.get(pid)
        if not g:
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        bb = integer_bounds(pts, 1)
        # Only seas that meet a new ring.
        if not any(_bboxes_overlap(bb, gis_masks[s][0]) for s in gis_masks):
            continue
        sea_masks.append((pid, bb, rasterize_centers(pts, bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])))
    for pid in gis_masks:
        bounds, mask = gis_masks[pid]
        for _sid, sb, sm in sea_masks:
            _subtract(bounds, mask, sb, sm)

    # Non-new land that overlaps a GIS mask. Cached so bulge pixels can avoid them.
    other_land = []
    for pid, row in base.items():
        if pid in matched or _is_water(pid, row):
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
        # Expand the working grid to cover the old ring too.
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
        # Pixels the old circle covered that no other province and no sea owns.
        # Dropping them would open a hole beside the real admin polygon.
        bulge_u = ((old_m == 1) & (mask == 0)).astype(np.uint8)
        for entry in other_land:
            ob, om = other_mask(entry)
            _subtract(bounds, bulge_u, ob, om)
        for _sid, sb, sm in sea_masks:
            _subtract(bounds, bulge_u, sb, sm)
        for other in matched:
            if other == pid:
                continue
            ob, om = gis_masks[other]
            _subtract(bounds, bulge_u, ob, om)
        mask = mask | bulge_u
        hole = _mask_hole_px(mask)
        if hole > HOLE_PX_MAX:
            raise RuntimeError("province %s mask hole %d" % (pid, hole))
        final_masks[pid] = (bounds, mask)

    new_rings: Dict[int, List[List[float]]] = {}
    for pid, (bounds, mask) in list(final_masks.items()):
        ring = _ring_from_mask(mask, bounds)
        new_rings[pid] = ring
        # The stored ring fills quantization holes. Notch neighbours against
        # that fill so the written polygon is what the overlap test sees.
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
        )

    # Notch neighbours that still contain a pixel of a new ring.
    yields: Dict[int, List[List[float]]] = {}
    yield_masks: Dict[int, tuple] = {}
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
        hole = _mask_hole_px(reduced)
        if hole > HOLE_PX_MAX:
            raise RuntimeError("neighbour %s notch hole %d" % (pid, hole))
        try:
            ring = _ring_from_mask(reduced, ob)
        except RuntimeError as exc:
            _c0, _k0, orig_drop = largest_component(om)
            raise RuntimeError(
                "%s %s orig_drop=%s reduced=%s took=%s: %s" % (pid, base[pid]["name"], orig_drop, int(reduced.sum()), took, exc)
            ) from exc
        painted = rasterize_centers(ring, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
        # The exterior contour fills tiny holes. If those pixels belong to a
        # new ring, give them back to this neighbour and drop them from the new ring.
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
        ring = _shave_new_border_slivers(geo[pid]["points"], ring, others)
        painted = rasterize_centers(ring, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
        yields[pid] = ring
        yield_masks[pid] = (ob, painted)
        stolen_from[pid] = took
        print("yield", pid, base[pid]["name"], "for", took, "verts", vertex_count(geo[pid]["points"]), "->", len(ring))

    # Pairwise overlap among new rings and against every other land ring.
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
        print("overlap-check", pid, flush=True)
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
        print("OVERLAPS", problems[:20])
        return 2
    print("overlap ok", len(new_rings), "rings", len(yields), "yields")

    evidence = []
    for pid, ring in sorted(new_rings.items()):
        evidence.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "role": "rering",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(ring)),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(ring), 2),
                "source": "geoBoundaries-%s-%s" % (matched[pid]["adm"], matched[pid]["level"]),
                "centroid_shift_px": round(matched[pid]["dist"], 2),
            }
        )
    for pid, ring in sorted(yields.items()):
        evidence.append(
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
    ev_path = Path.home() / "gapussrw2" / "evidence" / "rering_table.json"
    ev_path.parent.mkdir(parents=True, exist_ok=True)
    ev_path.write_text(json.dumps({"unknown": unknown, "rows": evidence, "province_count": len(base)}, indent=2) + "\n", encoding="utf-8")
    print("wrote", ev_path, flush=True)

    updates = {}
    updates.update(new_rings)
    updates.update(yields)
    changed_masks = {}
    changed_masks.update(final_masks)
    changed_masks.update(yield_masks)
    adj_doc = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj = {k: [int(n) for n in v] for k, v in adj_doc["adjacency"].items()}
    rings_now = {}
    for pid, g in geo.items():
        if pid in updates:
            rings_now[pid] = open_ring(updates[pid])
        else:
            pts = open_ring(g.get("points") or [])
            if len(pts) >= 3:
                rings_now[pid] = pts
    boxes = {pid: integer_bounds(pts, 0) for pid, pts in rings_now.items()}
    changed = set(updates)
    for pid in sorted(changed):
        old = set(adj.get(str(pid), []))
        final = set()
        bb = boxes[pid]
        mb, mm = changed_masks[pid]
        for oid in old:
            if oid not in boxes:
                continue
            if _box_gap(bb, boxes[oid]) <= 20.0:
                final.add(oid)
        for oid in rings_now:
            if oid == pid or oid in final:
                continue
            if _box_gap(bb, boxes[oid]) > 2.0:
                continue
            if _mask_touches_ring(mb, mm, rings_now[oid]):
                final.add(oid)
        if not final:
            raise RuntimeError("zero neighbours for %s" % pid)
        dropped = old - final
        added = final - old
        adj[str(pid)] = sorted(final)
        for oid in dropped:
            key = str(oid)
            if key in adj and pid in adj[key]:
                adj[key] = [n for n in adj[key] if n != pid]
        for oid in added:
            key = str(oid)
            cur = set(adj.get(key, []))
            cur.add(pid)
            adj[key] = sorted(cur)
        if dropped or added:
            print("adj", pid, "drop", sorted(dropped), "add", sorted(added), flush=True)
    for pid in changed:
        for nid in adj[str(pid)]:
            if pid not in adj.get(str(nid), []):
                raise RuntimeError("asymmetric %s -> %s" % (pid, nid))
    print("adjacency planned", flush=True)

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
            meta[META_RING] = "geoBoundaries-%s-%s" % (matched[pid]["adm"], matched[pid]["level"])
        else:
            meta[META_YIELD] = "notch"
        g2["meta"] = meta
        patched.append(g2)
    domains = {i: base[i].get("domain") for i in base}
    print("audit", flush=True)
    audit_problems = audit_board(patched, domains, adj)
    if audit_problems:
        print("AUDIT", audit_problems)
        return 2
    print("audit ok", flush=True)

    if not apply:
        print("dry-run: geometry not written")
        return 0

    raw = GEO_PATH.read_text(encoding="utf-8")
    # Splice from the end of the file backward so earlier offsets stay valid.
    for pid in sorted(updates, reverse=True):
        start, end = _find_object(raw, pid)
        ring = updates[pid]
        points_json = json.dumps(ring, separators=(",", ":"))
        raw = _splice_field(raw, start, end, "points", points_json)
        start, end = _find_object(raw, pid)
        obj, _rel = json.JSONDecoder().raw_decode(raw, start)
        meta = dict(obj.get("meta") or {})
        if pid in new_rings:
            meta[META_RING] = "geoBoundaries-%s-%s" % (matched[pid]["adm"], matched[pid]["level"])
        else:
            meta[META_YIELD] = "notch"
        raw = _splice_field(raw, start, end, "meta", json.dumps(meta, separators=(",", ":")))
        anchor = obj.get("label_anchor")
        if isinstance(anchor, list) and len(anchor) >= 2:
            if not _point_in(float(anchor[0]), float(anchor[1]), ring):
                cx, cy = polygon_centroid(ring)
                if not _point_in(cx, cy, ring):
                    cx, cy = _interior_point(ring)
                anchor_json = json.dumps([cx, cy], separators=(",", ":"))
                start, end = _find_object(raw, pid)
                raw = _splice_field(raw, start, end, "label_anchor", anchor_json)
                print("anchor moved", pid)
    GEO_PATH.write_text(raw, encoding="utf-8")
    print("geometry written", flush=True)

    adj_doc["adjacency"] = {k: adj[k] for k in adj_doc["adjacency"].keys()}
    missing_keys = [pid for pid in changed if str(pid) not in adj_doc["adjacency"]]
    if missing_keys:
        raise RuntimeError("adjacency missing keys %s" % missing_keys)
    ADJ_PATH.write_text(json.dumps(adj_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("adjacency written", flush=True)
    return 0


def _point_in(x, y, ring) -> bool:
    from gap_ussr_west2_product import point_in_ring

    return point_in_ring(x, y, ring)


def _interior_point(ring):
    pts = open_ring(ring)
    # Scan a small grid around the vertex centroid.
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    if _point_in(cx, cy, pts):
        return cx, cy
    minx, miny, maxx, maxy = ring_bbox(pts)
    step = max(1.0, min(maxx - minx, maxy - miny) / 20.0)
    y = miny + step
    while y < maxy:
        x = minx + step
        while x < maxx:
            if _point_in(x, y, pts):
                return x, y
            x += step
        y += step
    return cx, cy


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    return build(args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
