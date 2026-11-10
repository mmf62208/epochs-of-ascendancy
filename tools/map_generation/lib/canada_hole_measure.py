"""Enclosed holes in Canadian land on the world_accurate board.

A hole is a bounded face of the arrangement of Canadian land rings and every
land, lake, and sea ring that meets the Canada window (id-adjacent neighbours
included). The face is a hole when its interior point lies in no ring. Area
is the shoelace of that face, in canvas px². The centroid is the area-weighted
centre. Surrounding provinces are the rings that own the face edges.

Natural Earth 10m lakes and land, when the local cache is present, say
whether that centroid is a named lake, ocean, or land. The cache is evidence
only. The hole list does not depend on it.
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from gap_china2_outline import (  # noqa: E402
    _accept_split,
    _area,
    _clean,
    _even_odd,
    _interior_point,
    _orient,
    _param,
    _seg_points,
    _winding,
    snap,
)

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
LAKES_GEOJSON = (
    ROOT
    / "tools/map_generation/data/cache"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_lakes.geojson"
)
LAND_GEOJSON = (
    ROOT
    / "tools/map_generation/data/cache/map_tiles"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_land.geojson"
)

# Same canvas as great_lakes_water_province_product / world_accurate GIS.
WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)
# Provinces this far outside the Canadian rings still close a border gap
# (the Alaska wedge sits west of Yukon).
WINDOW_PAD = 220.0
CELL = 48.0
WATER_DOMAINS = frozenset({"sea", "lake", "ocean", "strait"})


def canvas_to_lonlat(x: float, y: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + (float(x) / (w - 1.0)) * (lon_max - lon_min)
    lat = lat_max - (float(y) / (h - 1.0)) * (lat_max - lat_min)
    return lon, lat


def _bbox(ring: Sequence[Tuple[float, float]]) -> Tuple[float, float, float, float]:
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def _poly_centroid(ring: Sequence[Tuple[float, float]]) -> Tuple[float, float]:
    a = cx = cy = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        c = x1 * y2 - x2 * y1
        a += c
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    if abs(a) < 1e-12:
        return (
            sum(p[0] for p in ring) / n,
            sum(p[1] for p in ring) / n,
        )
    return cx / (3.0 * a), cy / (3.0 * a)


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _is_can(prov: dict) -> bool:
    meta = prov.get("meta") if isinstance(prov.get("meta"), dict) else {}
    return meta.get("adm0_a3") == "CAN" or meta.get("admin") == "CAN"


def _domain(prov: dict) -> str:
    return str(prov.get("domain") or "land")


def arrange(rings: Sequence[Sequence[Tuple[float, float]]]) -> List[List[Tuple[float, float]]]:
    """Bounded and unbounded faces. Same walk as gap_china2_outline._Arr, gridded."""
    clean = [_clean(r) for r in rings if len(_clean(r)) >= 3]
    segs = []
    for ring in clean:
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            if a != b:
                segs.append((a, b))
    splits = [[a, b] for a, b in segs]
    buckets = defaultdict(list)
    for i, (a, b) in enumerate(segs):
        x0, x1 = (a[0], b[0]) if a[0] <= b[0] else (b[0], a[0])
        y0, y1 = (a[1], b[1]) if a[1] <= b[1] else (b[1], a[1])
        gx0 = int(math.floor(x0 / CELL))
        gx1 = int(math.floor(x1 / CELL))
        gy0 = int(math.floor(y0 / CELL))
        gy1 = int(math.floor(y1 / CELL))
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                buckets[(gx, gy)].append(i)
    seen_pairs = set()
    for idxs in buckets.values():
        m = len(idxs)
        for ii in range(m):
            i = idxs[ii]
            a, b = segs[i]
            for jj in range(ii + 1, m):
                j = idxs[jj]
                if i > j:
                    key = (j, i)
                else:
                    key = (i, j)
                if key in seen_pairs:
                    continue
                seen_pairs.add(key)
                c, d = segs[j]
                if max(a[0], b[0]) < min(c[0], d[0]) - 1e-6:
                    continue
                if max(c[0], d[0]) < min(a[0], b[0]) - 1e-6:
                    continue
                if max(a[1], b[1]) < min(c[1], d[1]) - 1e-6:
                    continue
                if max(c[1], d[1]) < min(a[1], b[1]) - 1e-6:
                    continue
                for p in _seg_points(a, b, c, d):
                    splits[i].append(p)
                    splits[j].append(p)
    edges = set()
    for i, (a, b) in enumerate(segs):
        pts = []
        seen = set()
        for p in splits[i]:
            p = snap(p)
            if p not in seen and _accept_split(a, b, p):
                seen.add(p)
                pts.append(p)
        pts.sort(key=lambda p: _param(a, b, p))
        for u, v in zip(pts, pts[1:]):
            if u != v:
                edges.add((u, v) if u < v else (v, u))
    adj = defaultdict(list)
    for u, v in edges:
        adj[u].append((math.atan2(v[1] - u[1], v[0] - u[0]), v))
        adj[v].append((math.atan2(u[1] - v[1], u[0] - v[0]), u))
    for k in adj:
        adj[k].sort(key=lambda t: t[0])
    used = set()
    faces = []
    for u, v in list(edges):
        for a, b in ((u, v), (v, u)):
            if (a, b) in used:
                continue
            face = []
            cur, nxt = a, b
            guard = 0
            while guard < 200000:
                guard += 1
                if (cur, nxt) in used and face:
                    break
                used.add((cur, nxt))
                face.append(cur)
                outs = adj[nxt]
                rev = None
                for i, (_ang, w) in enumerate(outs):
                    if w == cur:
                        rev = i
                        break
                if rev is None or not outs:
                    break
                _ang, w = outs[(rev - 1) % len(outs)]
                cur, nxt = nxt, w
                if cur == a and nxt == b:
                    break
            else:
                continue
            if len(face) >= 3:
                faces.append(face)
    return faces


def _edge_index(rings_by_id: Dict[int, List[Tuple[float, float]]]):
    """Grid of snapped ring edges for 'which province owns this face edge'."""
    grid = defaultdict(list)
    for pid, ring in rings_by_id.items():
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            if a == b:
                continue
            x0, x1 = (a[0], b[0]) if a[0] <= b[0] else (b[0], a[0])
            y0, y1 = (a[1], b[1]) if a[1] <= b[1] else (b[1], a[1])
            gx0 = int(math.floor(x0 / CELL)) - 1
            gx1 = int(math.floor(x1 / CELL)) + 1
            gy0 = int(math.floor(y0 / CELL)) - 1
            gy1 = int(math.floor(y1 / CELL)) + 1
            rec = (pid, a, b, math.hypot(b[0] - a[0], b[1] - a[1]))
            for gx in range(gx0, gx1 + 1):
                for gy in range(gy0, gy1 + 1):
                    grid[(gx, gy)].append(rec)
    return grid


def _owners_of_edge(grid, u, v) -> List[int]:
    mx = (u[0] + v[0]) * 0.5
    my = (u[1] + v[1]) * 0.5
    gx = int(math.floor(mx / CELL))
    gy = int(math.floor(my / CELL))
    found = []
    elen = math.hypot(v[0] - u[0], v[1] - u[1])
    for pid, a, b, _ln in grid.get((gx, gy), ()):
        # Midpoint of the face edge lies on this ring edge.
        cross = abs(_orient(a, b, (mx, my)))
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        if seg < 1e-12:
            continue
        if cross > max(1e-4, 1e-3 * seg):
            continue
        t = ((mx - a[0]) * (b[0] - a[0]) + (my - a[1]) * (b[1] - a[1])) / (seg * seg)
        if -1e-4 <= t <= 1.0 + 1e-4:
            if pid not in found:
                found.append(pid)
    if not found and elen > 0:
        # A snapped split can sit a cell away. Search the neighbour cells.
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                for pid, a, b, _ln in grid.get((gx + dx, gy + dy), ()):
                    cross = abs(_orient(a, b, (mx, my)))
                    seg = math.hypot(b[0] - a[0], b[1] - a[1])
                    if seg < 1e-12 or cross > max(1e-4, 1e-3 * seg):
                        continue
                    t = ((mx - a[0]) * (b[0] - a[0]) + (my - a[1]) * (b[1] - a[1])) / (seg * seg)
                    if -1e-4 <= t <= 1.0 + 1e-4 and pid not in found:
                        found.append(pid)
    return found


def _point_in_rings(rings, boxes, x, y, pred) -> bool:
    for ring, bb in zip(rings, boxes):
        if x < bb[0] - 0.2 or x > bb[2] + 0.2 or y < bb[1] - 0.2 or y > bb[3] + 0.2:
            continue
        if pred(ring, x, y):
            return True
    return False


def _load_ne_polys(path: Path, lon0: float, lon1: float, lat0: float, lat1: float):
    """(name, bbox, exterior, holes) for features that meet the lon/lat window."""
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    out = []
    for ft in data.get("features") or []:
        geom = ft.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates") or []
        props = ft.get("properties") or {}
        name = str(props.get("name") or props.get("name_en") or "")
        polys = []
        if gtype == "Polygon":
            polys = [coords]
        elif gtype == "MultiPolygon":
            polys = coords
        else:
            continue
        for poly in polys:
            if not poly or not poly[0] or len(poly[0]) < 3:
                continue
            exterior = [(float(p[0]), float(p[1])) for p in poly[0]]
            holes = []
            for hole in poly[1:]:
                if hole and len(hole) >= 3:
                    holes.append([(float(p[0]), float(p[1])) for p in hole])
            xs = [p[0] for p in exterior]
            ys = [p[1] for p in exterior]
            bb = (min(xs), min(ys), max(xs), max(ys))
            if bb[2] < lon0 or bb[0] > lon1 or bb[3] < lat0 or bb[1] > lat1:
                continue
            out.append((name, bb, exterior, holes))
    return out


def _in_ne(polys, lon: float, lat: float) -> str:
    for name, bb, exterior, holes in polys:
        if lon < bb[0] or lon > bb[2] or lat < bb[1] or lat > bb[3]:
            continue
        if not _even_odd(exterior, lon, lat):
            continue
        if any(_even_odd(h, lon, lat) for h in holes):
            continue
        return name or "(unnamed)"
    return ""


def measure_canada_holes(board: Path = DEFAULT_DIR, use_natural_earth: bool = True) -> dict:
    """Return the BEFORE/AFTER hole table for one board directory."""
    base = _load(board / "provinces_base.json")
    geo = _load(board / "provinces_geometry.json")
    adj_doc = _load(board / "province_adjacency.json")
    provs = {int(p["id"]): p for p in base["provinces"]}
    rings_raw = {}
    for g in geo["provinces"]:
        pts = _clean([(float(p[0]), float(p[1])) for p in (g.get("points") or [])])
        if len(pts) >= 3:
            rings_raw[int(g["id"])] = pts
    can_ids = [pid for pid, p in provs.items() if _is_can(p) and pid in rings_raw]
    if not can_ids:
        raise RuntimeError("no Canadian land rings in %s" % board)
    boxes = {pid: _bbox(rings_raw[pid]) for pid in rings_raw}
    minx = min(boxes[pid][0] for pid in can_ids) - WINDOW_PAD
    miny = min(boxes[pid][1] for pid in can_ids) - WINDOW_PAD
    maxx = max(boxes[pid][2] for pid in can_ids) + WINDOW_PAD
    maxy = max(boxes[pid][3] for pid in can_ids) + WINDOW_PAD
    # Id-adjacent neighbours of Canada, even if the shared edge is a gap.
    adj = adj_doc.get("adjacency") or {}
    neighbor_ids = set()
    for pid in can_ids:
        for nid in adj.get(str(pid)) or []:
            neighbor_ids.add(int(nid))
    scope = []
    for pid, ring in rings_raw.items():
        bb = boxes[pid]
        if bb[2] < minx or bb[0] > maxx or bb[3] < miny or bb[1] > maxy:
            if pid not in neighbor_ids and pid not in can_ids:
                continue
        scope.append(pid)
    scope_set = set(scope)
    land_ids = [pid for pid in scope if _domain(provs[pid]) not in WATER_DOMAINS and pid < 950000]
    water_ids = [pid for pid in scope if pid not in land_ids]
    land_rings = [rings_raw[pid] for pid in land_ids]
    water_rings = [rings_raw[pid] for pid in water_ids]
    all_rings = land_rings + water_rings
    all_ids = land_ids + water_ids
    faces = arrange(all_rings)
    by_id = {pid: rings_raw[pid] for pid in all_ids}
    edge_grid = _edge_index(by_id)
    land_boxes = [_bbox(r) for r in land_rings]
    water_boxes = [_bbox(r) for r in water_rings]
    holes = []
    for face in faces:
        area = _area(face)
        if area <= 0.5:
            continue
        pt = _interior_point(face)
        if pt is None:
            continue
        x, y = pt
        in_land = _point_in_rings(land_rings, land_boxes, x, y, lambda r, px, py: _winding(r, px, py) != 0)
        if in_land:
            continue
        in_water = _point_in_rings(water_rings, water_boxes, x, y, lambda r, px, py: _winding(r, px, py) != 0)
        if in_water:
            continue
        # Even-odd disagreement means a self-crossing ring still covers the point.
        in_land_eo = _point_in_rings(land_rings, land_boxes, x, y, _even_odd)
        in_water_eo = _point_in_rings(water_rings, water_boxes, x, y, _even_odd)
        if in_land_eo or in_water_eo:
            continue
        owners = []
        lengths = defaultdict(float)
        n = len(face)
        for i in range(n):
            u, v = face[i], face[(i + 1) % n]
            for pid in _owners_of_edge(edge_grid, u, v):
                lengths[pid] += math.hypot(v[0] - u[0], v[1] - u[1])
                if pid not in owners:
                    owners.append(pid)
        if not any(pid in can_ids or provs.get(pid) and _is_can(provs[pid]) for pid in owners):
            # Keep a gap that touches Canada only through an id-adjacent neighbour
            # when a Canadian ring is also on the boundary. Otherwise it is not
            # a Canadian hole (a US interior gap, an ocean face).
            if not any(pid in can_ids for pid in owners):
                continue
        cx, cy = _poly_centroid(face)
        lon, lat = canvas_to_lonlat(cx, cy)
        surround = []
        for pid in sorted(owners, key=lambda p: -lengths[p]):
            p = provs.get(pid) or {}
            surround.append({
                "id": pid,
                "name": p.get("name") or "",
                "domain": _domain(p),
                "adm0": (p.get("meta") or {}).get("adm0_a3") or "",
                "edge_px": round(lengths[pid], 2),
            })
        holes.append({
            "area_px2": round(area, 1),
            "area_exact": area,
            "centroid": [round(cx, 1), round(cy, 1)],
            "centroid_exact": [cx, cy],
            "interior": [round(x, 1), round(y, 1)],
            "lon": round(lon, 4),
            "lat": round(lat, 4),
            "vertices": len(face),
            "surrounding": surround,
            "ring": [[round(p[0], 4), round(p[1], 4)] for p in face],
        })
    holes.sort(key=lambda h: -h["area_exact"])
    if use_natural_earth and holes:
        lakes = _load_ne_polys(LAKES_GEOJSON, -170.0, -40.0, 35.0, 80.0)
        land = _load_ne_polys(LAND_GEOJSON, -170.0, -40.0, 35.0, 80.0)
        for hole in holes:
            lon, lat = canvas_to_lonlat(hole["centroid_exact"][0], hole["centroid_exact"][1])
            lake = _in_ne(lakes, lon, lat) if lakes else ""
            on_land = bool(_in_ne(land, lon, lat)) if land else None
            if lake:
                kind = "water"
                evidence = "centroid inside Natural Earth 10m lake %s" % lake
            elif on_land is False:
                kind = "water"
                evidence = "centroid is not on Natural Earth 10m land (ocean or inlet)"
            elif on_land is True:
                kind = "gap"
                evidence = "centroid is on Natural Earth 10m land and in no 10m lake"
            else:
                kind = "unknown"
                evidence = "Natural Earth cache not available"
            hole["kind"] = kind
            hole["water_name"] = lake
            hole["on_land"] = on_land
            hole["evidence"] = evidence
    return {
        "board": str(board),
        "province_count": len(provs),
        "canada_land_ids": len(can_ids),
        "scope_provinces": len(scope_set),
        "holes": holes,
    }


def _ring_of_base_point(points) -> List[Tuple[float, float]]:
    return _clean([(float(p[0]), float(p[1])) for p in points])


def count_invalid_polygons(board: Path = DEFAULT_DIR) -> dict:
    """Rings Godot cannot triangulate: short, empty, or self-crossing.

    A self-crossing is a non-adjacent edge meeting, the same test as
    gap_china2_outline._self_kinds, counted once per province.
    """
    from gap_china2_outline import _self_kinds

    geo = _load(board / "provinces_geometry.json")
    bad = []
    for g in geo["provinces"]:
        ring = _ring_of_base_point(g.get("points") or [])
        if len(ring) < 3:
            bad.append({"id": int(g["id"]), "kind": "short"})
            continue
        if abs(_area(ring)) < 0.5:
            bad.append({"id": int(g["id"]), "kind": "sliver"})
            continue
        kinds = _self_kinds(ring)
        if kinds:
            bad.append({"id": int(g["id"]), "kind": kinds[0]})
    return {"count": len(bad), "ids": bad}


def count_land_sea_overlaps(board: Path = DEFAULT_DIR, min_px: int = 1) -> dict:
    """Land×sea pairs whose pixel-center overlap is at least min_px.

    Pixel centers match gap_ussr_west2 overlap_px: a shared grid edge is 0.
    """
    import sys
    lib = Path(__file__).resolve().parent
    if str(lib) not in sys.path:
        sys.path.insert(0, str(lib))
    from gap_ussr_west2_product import overlap_px, ring_bbox

    base = _load(board / "provinces_base.json")
    geo = _load(board / "provinces_geometry.json")
    provs = {int(p["id"]): p for p in base["provinces"]}
    land = []
    water = []
    for g in geo["provinces"]:
        pid = int(g["id"])
        pts = g.get("points") or []
        if len(pts) < 3:
            continue
        p = provs.get(pid) or {}
        dom = _domain(p)
        bb = ring_bbox(pts)
        if dom in WATER_DOMAINS or pid >= 950000:
            water.append((pid, pts, bb))
        else:
            land.append((pid, pts, bb))
    pairs = []
    for lpid, lpts, lbb in land:
        for wpid, wpts, wbb in water:
            if lbb[2] < wbb[0] or wbb[2] < lbb[0] or lbb[3] < wbb[1] or wbb[3] < lbb[1]:
                continue
            # Skip pairs whose boxes barely touch.
            ix = min(lbb[2], wbb[2]) - max(lbb[0], wbb[0])
            iy = min(lbb[3], wbb[3]) - max(lbb[1], wbb[1])
            if ix <= 0 or iy <= 0:
                continue
            n = overlap_px(lpts, wpts)
            if n >= min_px:
                pairs.append({"land": lpid, "water": wpid, "px": n})
    pairs.sort(key=lambda r: -r["px"])
    return {"count": len(pairs), "pairs": pairs}


def _positive(ring: Sequence[Tuple[float, float]]) -> List[Tuple[float, float]]:
    pts = _clean(ring)
    if _area(pts) < 0:
        pts = list(reversed(pts))
    return pts


def _atomic_edges(ring: Sequence[Tuple[float, float]], cuts: Sequence[Tuple[float, float]]):
    """Directed edges of a positive ring, split at cut points that lie on them."""
    edges = []
    n = len(ring)
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        if a == b:
            continue
        pts = []
        seen = set()
        for p in (a, b, *cuts):
            p = snap(p)
            if p in seen:
                continue
            if p == a or p == b or _accept_split(a, b, p):
                seen.add(p)
                pts.append(p)
        pts.sort(key=lambda p: _param(a, b, p))
        for u, v in zip(pts, pts[1:]):
            if u != v:
                edges.append((u, v))
    return edges


def merge_positive_rings(ring_a, ring_b) -> List[List[Tuple[float, float]]]:
    """Union of two rings that share boundary edges. Returns leftover loops.

    Shared boundary edges cancel. A clean absorb of a hole is one loop.
    """
    a = _positive(ring_a)
    b = _positive(ring_b)
    cuts = list(a) + list(b)
    # Proper crossings become extra cut points so partial overlaps cancel.
    for i in range(len(a)):
        a0, a1 = a[i], a[(i + 1) % len(a)]
        for j in range(len(b)):
            b0, b1 = b[j], b[(j + 1) % len(b)]
            if max(a0[0], a1[0]) < min(b0[0], b1[0]) - 1e-6:
                continue
            if max(b0[0], b1[0]) < min(a0[0], a1[0]) - 1e-6:
                continue
            if max(a0[1], a1[1]) < min(b0[1], b1[1]) - 1e-6:
                continue
            if max(b0[1], b1[1]) < min(a0[1], a1[1]) - 1e-6:
                continue
            for p in _seg_points(a0, a1, b0, b1):
                cuts.append(p)
    edges = _atomic_edges(a, cuts) + _atomic_edges(b, cuts)
    cancel = defaultdict(int)
    for u, v in edges:
        cancel[(u, v)] += 1
    # Cancel the shared border: drop min(count(u,v), count(v,u)) from each direction.
    left = {}
    seen_undirected = set()
    for u, v in list(cancel):
        und = (u, v) if (u, v) < (v, u) else (v, u)
        if und in seen_undirected:
            continue
        seen_undirected.add(und)
        c_uv = cancel.get((und[0], und[1]), 0)
        c_vu = cancel.get((und[1], und[0]), 0)
        share = min(c_uv, c_vu)
        if c_uv - share > 0:
            left[(und[0], und[1])] = c_uv - share
        if c_vu - share > 0:
            left[(und[1], und[0])] = c_vu - share
    # Chain directed edges. If a vertex has several outs, take them as separate walks.
    outs = defaultdict(list)
    for (u, v), n in left.items():
        for _ in range(n):
            outs[u].append(v)
    loops = []
    while True:
        start = None
        for u, vs in outs.items():
            if vs:
                start = u
                break
        if start is None:
            break
        loop = [start]
        cur = start
        guard = 0
        while guard < 100000:
            guard += 1
            vs = outs.get(cur) or []
            if not vs:
                break
            nxt = vs.pop()
            if not vs:
                outs.pop(cur, None)
            loop.append(nxt)
            cur = nxt
            if cur == start:
                break
        if len(loop) >= 4 and loop[0] == loop[-1]:
            loop = loop[:-1]
        if len(loop) >= 3 and abs(_area(loop)) > 0.05:
            if _area(loop) < 0:
                loop = list(reversed(loop))
            loops.append(loop)
    loops.sort(key=lambda r: -abs(_area(r)))
    return loops


def choose_absorb_target(hole: dict) -> Optional[int]:
    """Province that should absorb this hole. None if it should stay.

    Real water goes to the existing lake or sea on its border (no new id).
    A named great lake that does not share an edge cannot be extended: a
    bridge would cross land. Lake Saint Clair has no lake province, so it
    falls through to the longest bordering land edge.
    A land gap goes to the land neighbour with the longest shared edge.
    The Alaska wedge west of 141°W stays in Alaska. A gap south of the 49th
    parallel between the Pacific and Lake of the Woods stays in the US.
    On the Quebec–Vermont 45th parallel and the Quebec–Maine height of land,
    a near-tie (Canada at least 85% of the longest foreign edge) stays with
    Canada.
    """
    surround = hole.get("surrounding") or []
    waters = [s for s in surround if s.get("domain") in WATER_DOMAINS]
    lands = [s for s in surround if s.get("domain") not in WATER_DOMAINS]
    if hole.get("kind") == "water" and waters:
        name = str(hole.get("water_name") or "").lower()
        named = [s for s in waters if name and name in str(s.get("name") or "").lower()]
        pool = named or waters
        return int(max(pool, key=lambda s: s.get("edge_px") or 0)["id"])
    if not lands:
        return None
    lon = float(hole.get("lon") or 0.0)
    lat = float(hole.get("lat") or 0.0)
    if lon < -141.05:
        foreign = [s for s in lands if s.get("adm0") != "CAN"]
        if foreign:
            return int(max(foreign, key=lambda s: s.get("edge_px") or 0)["id"])
    if -125.0 < lon < -95.0 and lat < 48.95:
        foreign = [s for s in lands if s.get("adm0") != "CAN"]
        if foreign:
            return int(max(foreign, key=lambda s: s.get("edge_px") or 0)["id"])
    ranked = sorted(lands, key=lambda s: -(s.get("edge_px") or 0))
    best = ranked[0]
    # 45th parallel (Quebec–Vermont / New York) and the Maine height of land.
    # East of -71° is Maine, not the Vermont band. The St Lawrence (west of
    # about -75°) is not this frontier.
    on_vermont = 44.9 <= lat <= 45.2 and lon < -71.0
    on_maine = -71.5 <= lon <= -66.9 and 45.2 < lat <= 47.6
    if on_vermont or on_maine:
        can = [s for s in lands if s.get("adm0") == "CAN"]
        foreign = [s for s in lands if s.get("adm0") != "CAN"]
        if can and foreign:
            cbest = max(can, key=lambda s: s.get("edge_px") or 0)
            fbest = max(foreign, key=lambda s: s.get("edge_px") or 0)
            if (cbest.get("edge_px") or 0) + 1e-9 >= (fbest.get("edge_px") or 0) * 0.85:
                return int(cbest["id"])
            return int(fbest["id"])
    return int(best["id"])


def adjacency_asymmetric(board: Path = DEFAULT_DIR) -> List[Tuple[int, int]]:
    adj = _load(board / "province_adjacency.json").get("adjacency") or {}
    bad = []
    for key, nbs in adj.items():
        pid = int(key)
        for nid in nbs:
            back = adj.get(str(int(nid))) or []
            if pid not in [int(x) for x in back]:
                bad.append((pid, int(nid)))
    return bad
