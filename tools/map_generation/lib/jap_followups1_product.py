"""JAP-FOLLOWUPS-1: clip sea 950247 off Kanto/Tohoku land, re-ring Kinmen 903981.

950247 ("Scotia Sea Edge") is a 48-vertex Pacific blob whose fill covers
eastern Honshu. Land rings stay put; the sea is clipped to remaining water
and the leftover water components are joined by a 1-px corridor through
not-land (Tsugaru / coast) so a single simple ring does not open a hole.

Kinmen 903981 is re-ringed from geoBoundaries gbOpen TWN ADM1 "Kinmen"
(the county, not the 金湖鎮 township circle). CHI 902633 (Fujian South)
fully contains that island, so it is C-notched by subtracting Kinmen plus
an eastward corridor that reaches outside the CHI bbox. A single ring
cannot punch a hole; the corridor makes the difference a simple C-shape.

Jagged-coast cleanup is skipped: the home-island turning-angle metric is
already 0 at the >150° / <1 px spike definition, and simplifying would
touch shared land-land borders.
"""
from __future__ import annotations

import hashlib
import json
import math
from collections import deque
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None  # type: ignore[assignment]

from canada_hole_measure import _area, _poly_centroid, _winding, canvas_to_lonlat
from eng_finish_product import ISLAND_AREA_MIN, avoid_placeholder_vertex_count, snap_ring
from gap_china2_outline import _clean, _nz_pair_area, _self_kinds, region_loops
from gap_jap1_product import ring_is_raw_invalid
from gap_ussr_west2_product import (
    is_placeholder_ring,
    open_ring,
    overlap_px,
    point_in_ring,
    rasterize_centers,
    ring_area,
    ring_bbox,
    trace_mask,
    vertex_count,
)
from ne_full_geometry_align import lonlat_to_canvas

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
WATER_DOMAINS = frozenset({"sea", "ocean", "lake", "strait"})

SEA_ID = 950247
KINMEN_ID = 903981
CHI_FUJIAN_ID = 902633
POLY_OVERLAP_MAX = 1.0
OVERLAP_PX_MAX = 1
HOLE_PX_MAX = 10
CORRIDOR_PAD = 40
CONNECT_MIN_PX = 10
TURN_SHARP_DEG = 150.0
SPIKE_SEG_PX = 1.0

# JPN ADM1 prefectures on this board (Osaka 903986 .. Yamaguchi 904032).
HOME_ISLAND_IDS = tuple(range(903986, 904033))

# gbOpen TWN ADM1 simplified, git 9469f09, boundaryYear 2017, build Dec 12 2023.
KINMEN_ADM1_API = "https://www.geoboundaries.org/api/current/gbOpen/TWN/ADM1/"
KINMEN_ADM1_URL = (
    "https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/"
    "TWN/ADM1/geoBoundaries-TWN-ADM1_simplified.geojson"
)
KINMEN_ADM1_SHA256 = "566a25e4522f33e492489ff321900be72b30be10de7b90a3586e292f7de1afe3"
KINMEN_ADM1_RELEASE = (
    "gbOpen TWN-ADM1-90331920 boundaryYear=2017 build=2023-12-12 "
    "sourceUpdate=2023-01-19 license=ODbL-1.0 git=9469f09 shapeName=Kinmen"
)
KINMEN_SOURCE_NAME = "geoBoundaries-TWN-ADM1:Kinmen"

# Measured on 33c0722f. The test fails on that SHA via 950247 overlaps and
# the Kinmen placeholder, not via jaggedness (already 0).
JAGGEDNESS_BEFORE = {
    "definition": (
        "On JAP 1936 home-island land rings (adm0_a3=JPN, ids 903986-904032), "
        "count vertices whose heading change (angle between consecutive edge "
        "vectors) exceeds 150 degrees, and of those the subset where at least "
        "one adjacent segment is shorter than 1.0 px. Coast-only counts skip "
        "vertices whose both adjacent edges match a neighbouring land ring "
        "to 0.001 px."
    ),
    "home_island_ids": list(HOME_ISLAND_IDS),
    "verts": 4386,
    "sharp_gt150": 0,
    "coast_sharp_gt150": 0,
    "short_spikes": 0,
    "max_turn_deg": 90.0,
    "simplified": False,
    "skip_reason": (
        "Metric already 0 at >150° / <1 px; conservative simplification "
        "would rewrite shared land-land borders or drop NE land hit rate."
    ),
}

JAGGED_SIMPLIFIED = False
KINMEN_UNKNOWN = False
KINMEN_UNKNOWN_REASON = ""

Point = Tuple[float, float]
Ring = List[Point]


def _require_numpy():
    if np is None:
        raise ImportError("numpy is required for JAP-FOLLOWUPS-1")
    return np


def _load_board(board: Path = DEFAULT_DIR):
    geo = json.loads((board / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((board / "provinces_base.json").read_text(encoding="utf-8"))
    owners = json.loads((board / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    adj = json.loads((board / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    domains = {int(p["id"]): str(p.get("domain") or "land") for p in base["provinces"]}
    names = {int(p["id"]): p.get("name") for p in base["provinces"]}
    return geo, base, owners, adj, domains, names


def _is_water(pid: int, domain: str) -> bool:
    return pid >= 950000 or domain in WATER_DOMAINS


def _positive(ring: Sequence[Sequence[float]]) -> Ring:
    pts = [(float(p[0]), float(p[1])) for p in open_ring(ring)]
    if _area(pts) < 0:
        pts = list(reversed(pts))
    return pts


def poly_overlap(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    return float(_nz_pair_area(_clean(a), _clean(b)))


def turn_angle_deg(a: Sequence[float], b: Sequence[float], c: Sequence[float]) -> Tuple[float, float, float]:
    """Heading change at b. 0 = straight, 180 = reversal. Also returns |AB|, |BC|."""
    v1x, v1y = b[0] - a[0], b[1] - a[1]
    v2x, v2y = c[0] - b[0], c[1] - b[1]
    n1 = math.hypot(v1x, v1y)
    n2 = math.hypot(v2x, v2y)
    if n1 < 1e-12 or n2 < 1e-12:
        return 0.0, n1, n2
    dot = (v1x * v2x + v1y * v2y) / (n1 * n2)
    dot = max(-1.0, min(1.0, dot))
    return math.degrees(math.acos(dot)), n1, n2


def _edge_key(p, q) -> Tuple[Tuple[float, float], Tuple[float, float]]:
    a = (round(float(p[0]), 3), round(float(p[1]), 3))
    b = (round(float(q[0]), 3), round(float(q[1]), 3))
    return (a, b) if a <= b else (b, a)


def jaggedness_of_ring(points: Sequence[Sequence[float]], neighbour_land: Sequence[Sequence[Sequence[float]]]) -> dict:
    pts = open_ring(points)
    n = len(pts)
    shared = set()
    for opts in neighbour_land:
        on = len(opts)
        for i in range(on):
            shared.add(_edge_key(opts[i], opts[(i + 1) % on]))
    sharp = coast_sharp = short_spikes = 0
    max_turn = 0.0
    over120 = 0
    over90 = 0
    for i in range(n):
        a, b, c = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        ang, n1, n2 = turn_angle_deg(a, b, c)
        if ang > max_turn:
            max_turn = ang
        if ang > 90.0:
            over90 += 1
        if ang > 120.0:
            over120 += 1
        is_coast = _edge_key(a, b) not in shared and _edge_key(b, c) not in shared
        if ang > TURN_SHARP_DEG:
            sharp += 1
            if is_coast:
                coast_sharp += 1
            if min(n1, n2) < SPIKE_SEG_PX:
                short_spikes += 1
    return {
        "verts": n,
        "sharp_gt150": sharp,
        "coast_sharp_gt150": coast_sharp,
        "short_spikes": short_spikes,
        "max_turn_deg": round(max_turn, 3),
        "turn_gt90": over90,
        "turn_gt120": over120,
    }


def measure_jaggedness(board: Path = DEFAULT_DIR) -> dict:
    geo, _base, owners, _adj, domains, _names = _load_board(board)
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    land_pts = {}
    for g in geo["provinces"]:
        pid = int(g["id"])
        if _is_water(pid, domains.get(pid) or ""):
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            land_pts[pid] = pts
    tot = {
        "verts": 0,
        "sharp_gt150": 0,
        "coast_sharp_gt150": 0,
        "short_spikes": 0,
        "turn_gt90": 0,
        "turn_gt120": 0,
        "max_turn_deg": 0.0,
    }
    per = []
    for pid in HOME_ISLAND_IDS:
        g = by_id[pid]
        pts = open_ring(g.get("points") or [])
        bb = ring_bbox(pts)
        nbs = []
        for oid, opts in land_pts.items():
            if oid == pid:
                continue
            ob = ring_bbox(opts)
            if ob[2] < bb[0] - 1 or bb[2] < ob[0] - 1 or ob[3] < bb[1] - 1 or bb[3] < ob[1] - 1:
                continue
            nbs.append(opts)
        row = jaggedness_of_ring(pts, nbs)
        row["id"] = pid
        per.append(row)
        for key in ("verts", "sharp_gt150", "coast_sharp_gt150", "short_spikes", "turn_gt90", "turn_gt120"):
            tot[key] += int(row[key])
        tot["max_turn_deg"] = max(tot["max_turn_deg"], float(row["max_turn_deg"]))
    tot["max_turn_deg"] = round(tot["max_turn_deg"], 3)
    tot["definition"] = JAGGEDNESS_BEFORE["definition"]
    tot["home_island_n"] = len(HOME_ISLAND_IDS)
    tot["simplified"] = JAGGED_SIMPLIFIED
    tot["by_id_nonzero"] = [r for r in per if r["sharp_gt150"] or r["short_spikes"] or r["coast_sharp_gt150"]]
    return tot


def measure_sea_overlaps(board: Path = DEFAULT_DIR, sea_id: int = SEA_ID) -> dict:
    geo, _base, owners, adj, domains, names = _load_board(board)
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    sea = open_ring(by_id[sea_id]["points"])
    sea_bb = ring_bbox(sea)
    cx, cy = _poly_centroid(_clean(sea) if _area(_clean(sea)) else sea)
    lon, lat = canvas_to_lonlat(cx, cy)
    land_hits = []
    other_seas = []
    for g in geo["provinces"]:
        pid = int(g["id"])
        if pid == sea_id:
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        bb = ring_bbox(pts)
        if bb[2] < sea_bb[0] or sea_bb[2] < bb[0] or bb[3] < sea_bb[1] or sea_bb[3] < bb[1]:
            continue
        poly = poly_overlap(pts, sea)
        px = overlap_px(pts, sea)
        if poly <= 0.0 and px <= 0:
            continue
        rec = {
            "id": pid,
            "name": names.get(pid),
            "owner": owners.get(str(pid)),
            "domain": domains.get(pid),
            "poly_px2": round(poly, 4),
            "px": int(px),
            "area": round(ring_area(pts), 2),
            "verts": len(pts),
        }
        if _is_water(pid, domains.get(pid) or ""):
            other_seas.append(rec)
        else:
            land_hits.append(rec)
    land_hits.sort(key=lambda r: -r["poly_px2"])
    other_seas.sort(key=lambda r: -r["poly_px2"])
    kinds = _self_kinds(_clean(sea))
    return {
        "id": sea_id,
        "name": names.get(sea_id),
        "verts": len(sea),
        "area": round(ring_area(sea), 2),
        "bbox": [round(x, 4) for x in sea_bb],
        "centroid_canvas": [round(cx, 4), round(cy, 4)],
        "centroid_lonlat": [round(lon, 4), round(lat, 4)],
        "label_anchor": by_id[sea_id].get("label_anchor"),
        "raw_invalid": ring_is_raw_invalid(sea),
        "self_kinds": kinds,
        "placeholder": is_placeholder_ring(sea),
        "neighbors": list(adj.get(str(sea_id)) or []),
        "land_overlaps": land_hits,
        "other_water_overlaps": other_seas,
        "land_overlap_n_over_1": sum(1 for r in land_hits if r["poly_px2"] > POLY_OVERLAP_MAX),
    }


def measure_kinmen(board: Path = DEFAULT_DIR) -> dict:
    geo, _base, owners, adj, domains, names = _load_board(board)
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    g = by_id[KINMEN_ID]
    pts = open_ring(g.get("points") or [])
    cx, cy = _poly_centroid(_clean(pts) if pts else [(0.0, 0.0)])
    lon, lat = canvas_to_lonlat(cx, cy)
    chi = open_ring(by_id[CHI_FUJIAN_ID]["points"])
    return {
        "id": KINMEN_ID,
        "name": names.get(KINMEN_ID),
        "owner": owners.get(str(KINMEN_ID)),
        "domain": domains.get(KINMEN_ID),
        "verts": vertex_count(pts),
        "area": round(ring_area(pts), 4),
        "bbox": [round(x, 4) for x in ring_bbox(pts)],
        "centroid_canvas": [round(cx, 4), round(cy, 4)],
        "centroid_lonlat": [round(lon, 4), round(lat, 4)],
        "placeholder": is_placeholder_ring(pts),
        "raw_invalid": ring_is_raw_invalid(pts),
        "meta": g.get("meta"),
        "neighbors": list(adj.get(str(KINMEN_ID)) or []),
        "overlap_902633_poly": round(poly_overlap(pts, chi), 4),
        "overlap_902633_px": int(overlap_px(pts, chi)),
        "centroid_in_902633": point_in_ring(cx, cy, chi),
        "unknown": KINMEN_UNKNOWN,
        "unknown_reason": KINMEN_UNKNOWN_REASON,
        "source_url": KINMEN_ADM1_URL,
        "source_sha256": KINMEN_ADM1_SHA256,
        "source_release": KINMEN_ADM1_RELEASE,
    }


def measure_report(board: Path = DEFAULT_DIR) -> dict:
    sea = measure_sea_overlaps(board)
    kin = measure_kinmen(board)
    jag = measure_jaggedness(board)
    geo, _base, _owners, adj, domains, _names = _load_board(board)
    ids = [int(g["id"]) for g in geo["provinces"]]
    return {
        "sha_note": "measured on the current board files",
        "province_count": len(ids),
        "id_first": ids[0] if ids else None,
        "id_last": ids[-1] if ids else None,
        "adjacency_n": len(adj),
        "sea_950247": sea,
        "kinmen_903981": kin,
        "jaggedness": jag,
        "jaggedness_definition": JAGGEDNESS_BEFORE["definition"],
    }


def _components(mask) -> List[List[Tuple[int, int]]]:
    npy = _require_numpy()
    seen = npy.zeros_like(mask, npy.uint8)
    comps: List[List[Tuple[int, int]]] = []
    height, width = mask.shape
    for y in range(height):
        row = mask[y]
        for x in range(width):
            if not row[x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = 1
            cells: List[Tuple[int, int]] = []
            while q:
                cy, cx = q.popleft()
                cells.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = 1
                        q.append((ny, nx))
            comps.append(cells)
    comps.sort(key=len, reverse=True)
    return comps


def _nearest_pair(a: Sequence[Tuple[int, int]], b: Sequence[Tuple[int, int]]):
    best = 1e18
    pair = None
    step_a = 3 if len(a) > 3000 else 1
    step_b = 3 if len(b) > 3000 else 1
    aa = a[::step_a]
    bb = b[::step_b]
    for y1, x1 in aa:
        for y2, x2 in bb:
            d = (y1 - y2) * (y1 - y2) + (x1 - x2) * (x1 - x2)
            if d < best:
                best = d
                pair = ((y1, x1), (y2, x2))
    return math.sqrt(best), pair


def _bfs_path(walkable, start, goal, prefer=None):
    """4-connected path. Pixels in `prefer` cost 1, other walkable cost 8."""
    import heapq

    height, width = walkable.shape
    sy, sx = start
    gy, gx = goal
    inf = 10 ** 9
    dist = {(sy, sx): 0}
    prev = {(sy, sx): None}
    heap = [(0, sy, sx)]
    while heap:
        d, y, x = heapq.heappop(heap)
        if d != dist.get((y, x), inf):
            continue
        if (y, x) == (gy, gx):
            break
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if not (0 <= ny < height and 0 <= nx < width and walkable[ny, nx]):
                continue
            step = 1 if (prefer is not None and prefer[ny, nx]) else 8
            nd = d + step
            if nd < dist.get((ny, nx), inf):
                dist[(ny, nx)] = nd
                prev[(ny, nx)] = (y, x)
                heapq.heappush(heap, (nd, ny, nx))
    if (gy, gx) not in prev:
        return None
    path = []
    cur = (gy, gx)
    while cur is not None:
        path.append(cur)
        cur = prev[cur]
    path.reverse()
    return path


def _paint_path(mask, land_mask, path) -> None:
    height, width = mask.shape
    for y, x in path:
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                ny, nx = y + dy, x + dx
                if 0 <= ny < height and 0 <= nx < width and land_mask[ny, nx] == 0:
                    mask[ny, nx] = True


def _dilate(mask, radius: int):
    npy = _require_numpy()
    if radius <= 0:
        return mask.copy()
    height, width = mask.shape
    out = mask.copy()
    ys, xs = npy.nonzero(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        y0, y1 = max(0, y - radius), min(height, y + radius + 1)
        x0, x1 = max(0, x - radius), min(width, x + radius + 1)
        out[y0:y1, x0:x1] = True
    return out


def clip_sea_off_land(
    sea_ring: Sequence[Sequence[float]],
    land_rings: Sequence[Sequence[Sequence[float]]],
    all_land_in_window: Sequence[Sequence[Sequence[float]]],
) -> dict:
    """Clip sea minus land; join leftover water components through not-land."""
    npy = _require_numpy()
    sea = _positive(sea_ring)
    lands = [_positive(r) for r in land_rings if len(open_ring(r)) >= 3]
    sea_bb = ring_bbox(sea)
    minx = math.floor(sea_bb[0]) - CORRIDOR_PAD
    miny = math.floor(sea_bb[1]) - CORRIDOR_PAD
    maxx = math.ceil(sea_bb[2]) + CORRIDOR_PAD
    maxy = math.ceil(sea_bb[3]) + CORRIDOR_PAD
    width = int(maxx - minx)
    height = int(maxy - miny)
    sea_mask = rasterize_centers(sea, minx, miny, width, height)
    land_mask = npy.zeros((height, width), npy.uint8)
    for pts in all_land_in_window:
        bb = ring_bbox(pts)
        if bb[2] < minx or maxx < bb[0] or bb[3] < miny or maxy < bb[1]:
            continue
        land_mask |= rasterize_centers(pts, minx, miny, width, height)
    remain = (sea_mask == 1) & (land_mask == 0)
    comps = _components(remain)
    joined = remain.copy()
    # Stay near the original sea so a not-land BFS cannot wrap Honshu.
    # 28 px reaches Tsugaru water north of the original ymin.
    near_sea = _dilate(sea_mask == 1, 28)
    walkable = (land_mask == 0) & (near_sea | remain)
    main_cells = list(comps[0]) if comps else []
    connected = [len(c) for c in comps if len(c) >= CONNECT_MIN_PX]
    for comp in comps[1:]:
        if len(comp) < CONNECT_MIN_PX:
            continue
        _dist, pair = _nearest_pair(main_cells, comp)
        if pair is None:
            raise RuntimeError("no pair between sea water components")
        path = _bfs_path(walkable, pair[0], pair[1], prefer=remain)
        if path is None:
            raise RuntimeError("no not-land path between sea water components")
        _paint_path(joined, land_mask, path)
        main_cells.extend(comp)
        for y, x in path:
            main_cells.append((y, x))
    jcomps = _components(joined)
    if not jcomps:
        raise RuntimeError("clipped sea is empty")
    mask = npy.zeros((height, width), npy.uint8)
    for y, x in jcomps[0]:
        mask[y, x] = 1
    # A Tsugaru corridor can close a water pocket. Fill not-land holes that
    # do not touch the window border so the sea ring stays simply connected.
    empty = (mask == 0) & (land_mask == 0)
    border = npy.zeros_like(empty)
    border[0, :] = True
    border[-1, :] = True
    border[:, 0] = True
    border[:, -1] = True
    reach = empty & border
    rq = deque(list(zip(*npy.nonzero(reach))))
    seen_b = npy.zeros_like(empty, npy.uint8)
    for y, x in rq:
        seen_b[y, x] = 1
    while rq:
        y, x = rq.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and empty[ny, nx] and not seen_b[ny, nx]:
                seen_b[ny, nx] = 1
                rq.append((ny, nx))
    holes = empty & (seen_b == 0)
    if bool(holes.any()):
        mask[holes] = 1
    ring = snap_ring(trace_mask(mask, minx, miny))
    ring = [(float(p[0]), float(p[1])) for p in avoid_placeholder_vertex_count(ring)]
    if len(ring) < 8:
        raise RuntimeError("clipped sea ring too short")
    if ring_is_raw_invalid(ring):
        raise RuntimeError("clipped sea ring is self-crossing")
    leftover_small = sum(len(c) for c in comps if len(c) < CONNECT_MIN_PX)
    # Anchor: a remain pixel whose 3x3 neighbourhood is water in the joined mask.
    anchor = None
    hh, ww = mask.shape
    for y, x in jcomps[0]:
        if y <= 0 or x <= 0 or y + 1 >= hh or x + 1 >= ww:
            continue
        if int(mask[y - 1 : y + 2, x - 1 : x + 2].sum()) < 9:
            continue
        ax, ay = minx + x + 0.5, miny + y + 0.5
        if _winding(ring, ax, ay) == 0:
            continue
        if land_mask[y, x]:
            continue
        anchor = [round(ax, 4), round(ay, 4)]
        break
    if anchor is None:
        for y, x in jcomps[0]:
            ax, ay = minx + x + 0.5, miny + y + 0.5
            if _winding(ring, ax, ay) != 0:
                anchor = [round(ax, 4), round(ay, 4)]
                break
    if anchor is None:
        raise RuntimeError("clipped sea has no interior water point")
    overlaps = []
    for pts in lands:
        poly = poly_overlap(ring, pts)
        px = overlap_px(ring, pts)
        if poly > POLY_OVERLAP_MAX or px > OVERLAP_PX_MAX:
            overlaps.append({"poly": round(poly, 4), "px": int(px)})
    if overlaps:
        raise RuntimeError("clipped sea still overlaps land %s" % overlaps[:6])
    return {
        "ring": ring,
        "anchor": anchor,
        "area": round(abs(_area(ring)), 2),
        "verts": len(ring),
        "components_joined": connected,
        "small_dropped_px": leftover_small,
        "window": [minx, miny, maxx, maxy],
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


def kinmen_parts_from_geojson(path: Path, sha256: str = KINMEN_ADM1_SHA256) -> List[Ring]:
    data = path.read_bytes()
    got = hashlib.sha256(data).hexdigest()
    if got != sha256:
        raise RuntimeError("Kinmen source sha256 %s != %s" % (got, sha256))
    doc = json.loads(data.decode("utf-8"))
    feat = None
    for row in doc.get("features") or []:
        props = row.get("properties") if isinstance(row.get("properties"), dict) else {}
        if str(props.get("shapeName") or "") == "Kinmen":
            feat = row
            break
    if feat is None:
        raise RuntimeError("Kinmen feature missing in %s" % path)
    parts = []
    for outer in _outers(feat.get("geometry") or {}):
        lonlat = [[float(p[0]), float(p[1])] for p in outer]
        if len(lonlat) >= 2 and lonlat[0] == lonlat[-1]:
            lonlat = lonlat[:-1]
        canvas = snap_ring([lonlat_to_canvas(lon, lat) for lon, lat in lonlat])
        canvas = [(float(p[0]), float(p[1])) for p in avoid_placeholder_vertex_count(canvas)]
        if len(canvas) >= 3 and abs(_area(canvas)) >= 0.2:
            parts.append(_positive(canvas))
    if not parts:
        raise RuntimeError("Kinmen source produced no canvas parts")
    return parts


def kinmen_main_ring(parts: Sequence[Ring]) -> Ring:
    return max(parts, key=lambda r: abs(_area(r)))


def notch_chi_for_kinmen(chi_ring: Sequence[Sequence[float]], kinmen_ring: Sequence[Sequence[float]]) -> Ring:
    """C-notch CHI so Kinmen is no longer interior. Corridor runs east past CHI bbox."""
    chi = _positive(chi_ring)
    kin = _positive(kinmen_ring)
    kbb = ring_bbox(kin)
    cbb = ring_bbox(chi)
    _kcx, kcy = _poly_centroid(kin)
    x0 = kbb[0] - 0.5
    x1 = cbb[2] + 2.0
    y0 = kcy - 1.2
    y1 = kcy + 1.2
    corridor = _positive([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    union_loops = region_loops([kin, corridor], None, "union")
    if not union_loops:
        raise RuntimeError("Kinmen+corridor union empty")
    cut = max(union_loops, key=lambda loop: abs(_area(loop)))
    diff = region_loops([chi], [cut], "difference")
    if not diff:
        raise RuntimeError("CHI notch removed Fujian")
    kcx, kcy = _poly_centroid(kin)
    keepers = [loop for loop in diff if not point_in_ring(kcx, kcy, loop)]
    if not keepers:
        keepers = diff
    new_chi = snap_ring(max(keepers, key=lambda loop: abs(_area(loop))))
    new_chi = [(float(p[0]), float(p[1])) for p in avoid_placeholder_vertex_count(new_chi)]
    if len(new_chi) < 4:
        raise RuntimeError("notched CHI too short")
    if ring_is_raw_invalid(new_chi):
        raise RuntimeError("notched CHI is self-crossing")
    if poly_overlap(new_chi, kin) > POLY_OVERLAP_MAX:
        raise RuntimeError("notched CHI still overlaps Kinmen")
    if overlap_px(new_chi, kin) > OVERLAP_PX_MAX:
        raise RuntimeError("notched CHI still overlaps Kinmen pixels")
    return new_chi


def land_rings_overlapping_sea(geo_provinces, domains, sea_id: int = SEA_ID) -> List[Tuple[int, Ring]]:
    by_id = {int(g["id"]): g for g in geo_provinces}
    sea = open_ring(by_id[sea_id]["points"])
    sea_bb = ring_bbox(sea)
    out = []
    for g in geo_provinces:
        pid = int(g["id"])
        if pid == sea_id or _is_water(pid, domains.get(pid) or ""):
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        bb = ring_bbox(pts)
        if bb[2] < sea_bb[0] or sea_bb[2] < bb[0] or bb[3] < sea_bb[1] or sea_bb[3] < bb[1]:
            continue
        if poly_overlap(pts, sea) > 0.01:
            out.append((pid, pts))
    return out


def all_land_rings(geo_provinces, domains) -> List[Ring]:
    out = []
    for g in geo_provinces:
        pid = int(g["id"])
        if _is_water(pid, domains.get(pid) or ""):
            continue
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            out.append(pts)
    return out
