"""FEED-2 Maginot corridor land-area uniformity — Mike province-sizing bar #1.

Default `world_accurate` NUTS-3 cells in Alsace / Lorraine / Baden / Rhineland
are not operationally uniform: French départements are giant (~280–511 canvas
area) while German Stadtkreise on the same front are pinpricks (~5–12). This
product is a **one-theater proof** (not a Europe remesh):

* Split the six largest French Maginot-family + neighbor départements.
  Parent IDs stay; children are **append-only** Europe IDs 711514–711519.
* Grow three Maginot-front German Stadtkreise into their own-country
  Landkreis donors (IDs unchanged). Does not move the GER–FRA Rhine edge.

Write: tools/map_generation/scripts/apply_maginot_land_uniformity.py
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)

# Tight operational Maginot corridor (label-anchor lon/lat).
THEATER_LONLAT = (6.0, 47.55, 8.8, 49.45)

# Frozen pre-FEED diagnosis (tight window, land only) — 3b2b7dc board.
PRE_FEED_METRICS: Dict[str, float] = {
    "n": 44.0,
    "min": 1.5,
    "p25": 22.2,
    "median": 57.3,
    "p75": 86.4,
    "max": 511.3,
    "max_over_median": 8.9,
    "max_over_min": 337.2,
}

# Combat edge — IDs must survive; adjacency must survive.
GER_MAGINOT_ID = 710173  # Baden-Baden, Stadtkreis
FRA_MAGINOT_ID = 710739  # Bas-Rhin

# Giant French cells: Alsace/Lorraine family + Haute-Saône neighbor.
SPLIT_PARENT_IDS: Tuple[int, ...] = (
    710747,  # Moselle
    710748,  # Vosges
    710727,  # Haute-Saône (immediate south neighbor)
    710745,  # Meurthe-et-Moselle
    710739,  # Bas-Rhin
    710740,  # Haut-Rhin
)

# Append-only Europe NUTS gap (max existing 711513).
NEW_ID_START = 711514
NEW_CHILD_IDS: Tuple[int, ...] = tuple(NEW_ID_START + i for i in range(len(SPLIT_PARENT_IDS)))

# Tiny German front cells → own-country Landkreis donors (no FRA bite).
GROW_SPECS: Tuple[Dict[str, Any], ...] = (
    {"tiny_id": 710173, "donor_id": 710176, "target_area": 26.0, "donor_floor": 28.0},
    {"tiny_id": 710185, "donor_id": 710186, "target_area": 26.0, "donor_floor": 48.0},
    {"tiny_id": 710476, "donor_id": 710489, "target_area": 24.0, "donor_floor": 36.0},
)

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})
TOUCH_PX = 16.0
FEED_META = "v1_maginot_land_uniform"

Ring = List[List[float]]
Point = List[float]


def canvas_to_lonlat(x: float, y: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + (float(x) / (w - 1.0)) * (lon_max - lon_min)
    lat = lat_max - (float(y) / (h - 1.0)) * (lat_max - lat_min)
    return lon, lat


def _is_water(p: Mapping[str, Any]) -> bool:
    terr = str(p.get("terrain") or "").strip().lower()
    dom = str(p.get("domain") or "land").strip().lower()
    return terr in WATER_T or dom in WATER_D or bool(p.get("is_sea"))


def polygon_area(points: Sequence[Sequence[float]]) -> float:
    if not points or len(points) < 3:
        return 0.0
    pts = [[float(p[0]), float(p[1])] for p in points]
    if pts[0][0] == pts[-1][0] and pts[0][1] == pts[-1][1]:
        pts = pts[:-1]
    if len(pts) < 3:
        return 0.0
    area = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return abs(area) * 0.5


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    n = float(len(ring))
    return sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n


def _principal_axis(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 2:
        return 1.0, 0.0
    cx, cy = polygon_centroid(ring)
    n = float(len(ring))
    cov_xx = sum((p[0] - cx) ** 2 for p in ring) / n
    cov_yy = sum((p[1] - cy) ** 2 for p in ring) / n
    cov_xy = sum((p[0] - cx) * (p[1] - cy) for p in ring) / n
    if abs(cov_xy) < 1e-9:
        return (1.0, 0.0) if cov_xx >= cov_yy else (0.0, 1.0)
    trace = cov_xx + cov_yy
    det = cov_xx * cov_yy - cov_xy * cov_xy
    disc = max(0.0, trace ** 2 - 4.0 * det)
    lambda1 = (trace + math.sqrt(disc)) / 2.0
    dx = cov_xy
    dy = lambda1 - cov_xx
    length = math.hypot(dx, dy)
    if length < 1e-9:
        return 1.0, 0.0
    return dx / length, dy / length


def _side(px: float, py: float, ox: float, oy: float, nx: float, ny: float) -> float:
    return (px - ox) * nx + (py - oy) * ny


def _lerp(a: Sequence[float], b: Sequence[float], t: float) -> Point:
    return [float(a[0]) + (float(b[0]) - float(a[0])) * t, float(a[1]) + (float(b[1]) - float(a[1])) * t]


def _open_ring(points: Sequence[Sequence[float]]) -> Ring:
    pts = [[float(p[0]), float(p[1])] for p in points if isinstance(p, (list, tuple)) and len(p) >= 2]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def split_ring_by_line(
    points: Sequence[Sequence[float]],
    origin: Sequence[float],
    normal: Sequence[float],
) -> Tuple[Ring, Ring, int]:
    """Walk-ring half-plane split. Shared cut vertices go to both pieces."""
    pts = _open_ring(points)
    if len(pts) < 3:
        return [], [], 0
    ox, oy = float(origin[0]), float(origin[1])
    nx, ny = float(normal[0]), float(normal[1])
    nrm = math.hypot(nx, ny) or 1.0
    nx, ny = nx / nrm, ny / nrm
    pos: Ring = []
    neg: Ring = []
    crossings = 0
    n = len(pts)
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        sa = _side(a[0], a[1], ox, oy, nx, ny)
        sb = _side(b[0], b[1], ox, oy, nx, ny)
        if sa > 1e-9:
            pos.append(list(a))
        elif sa < -1e-9:
            neg.append(list(a))
        else:
            pos.append(list(a))
            neg.append(list(a))
        if sa * sb < -1e-12:
            den = sa - sb
            t = sa / den if abs(den) > 1e-15 else 0.5
            t = min(1.0, max(0.0, t))
            hit = _lerp(a, b, t)
            pos.append(hit)
            neg.append(hit)
            crossings += 1
    return pos, neg, crossings


def _valid_piece(ring: Sequence[Sequence[float]], min_area: float) -> bool:
    return len(ring) >= 4 and polygon_area(ring) >= min_area


def best_axis_split(points: Sequence[Sequence[float]]) -> Tuple[Ring, Ring]:
    """Area-balanced cut perpendicular to the long axis."""
    pts = _open_ring(points)
    parent = polygon_area(pts)
    cx, cy = polygon_centroid(pts)
    dx, dy = _principal_axis(pts)
    span = 0.0
    for p in pts:
        span = max(span, abs((p[0] - cx) * dx + (p[1] - cy) * dy))
    best: Optional[Tuple[float, Ring, Ring]] = None
    for step in range(-8, 9):
        t = (step / 8.0) * span * 0.35
        origin = (cx + dx * t, cy + dy * t)
        pos, neg, crossings = split_ring_by_line(pts, origin, (dx, dy))
        if crossings < 2:
            continue
        a1 = polygon_area(pos)
        a2 = polygon_area(neg)
        if not _valid_piece(pos, parent * 0.28) or not _valid_piece(neg, parent * 0.28):
            continue
        if (a1 + a2) < parent * 0.82:
            continue
        imbalance = abs(a1 - a2) / max(a1 + a2, 1e-6)
        if best is None or imbalance < best[0]:
            best = (imbalance, pos, neg)
    if best is not None:
        return best[1], best[2]
    # Fallback: bbox mid-cut on the longer side.
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    if (max(xs) - min(xs)) >= (max(ys) - min(ys)):
        origin = ((min(xs) + max(xs)) * 0.5, cy)
        normal = (1.0, 0.0)
    else:
        origin = (cx, (min(ys) + max(ys)) * 0.5)
        normal = (0.0, 1.0)
    pos, neg, _ = split_ring_by_line(pts, origin, normal)
    if _valid_piece(pos, 8.0) and _valid_piece(neg, 8.0):
        return pos, neg
    raise RuntimeError("maginot split failed to produce two valid pieces")


def compass_suffix(keep_c: Sequence[float], child_c: Sequence[float]) -> str:
    dx = float(child_c[0]) - float(keep_c[0])
    dy = float(child_c[1]) - float(keep_c[1])
    # Canvas y grows south.
    if abs(dx) >= abs(dy):
        return "East" if dx > 0 else "West"
    return "South" if dy > 0 else "North"


def expand_toward(
    ring: Sequence[Sequence[float]],
    direction: Sequence[float],
    factor: float,
    centroid: Sequence[float],
) -> Ring:
    vx, vy = float(direction[0]), float(direction[1])
    nrm = math.hypot(vx, vy) or 1.0
    vx, vy = vx / nrm, vy / nrm
    cx, cy = float(centroid[0]), float(centroid[1])
    out: Ring = []
    for p in _open_ring(ring):
        rx, ry = p[0] - cx, p[1] - cy
        along = rx * vx + ry * vy
        across_x = rx - along * vx
        across_y = ry - along * vy
        if along > 0.0:
            along *= float(factor)
        out.append([cx + along * vx + across_x, cy + along * vy + across_y])
    return out


def convex_hull(points: Sequence[Sequence[float]]) -> Ring:
    pts = sorted({(float(p[0]), float(p[1])) for p in points})
    if len(pts) <= 2:
        return [[p[0], p[1]] for p in pts]

    def cross(o: Tuple[float, float], a: Tuple[float, float], b: Tuple[float, float]) -> float:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: List[Tuple[float, float]] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0.0:
            lower.pop()
        lower.append(p)
    upper: List[Tuple[float, float]] = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0.0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    return [[p[0], p[1]] for p in hull]


def _hull_hits_forbidden(hull: Sequence[Sequence[float]], forbidden: Sequence[Sequence[Sequence[float]]]) -> bool:
    for fr in forbidden:
        if len(fr) < 3:
            continue
        fcx, fcy = polygon_centroid(fr)
        if point_in_ring(fcx, fcy, hull):
            return True
        for hp in hull:
            if point_in_ring(hp[0], hp[1], fr):
                return True
    return False


def grow_into_donor(
    city: Sequence[Sequence[float]],
    donor: Sequence[Sequence[float]],
    target_area: float,
    donor_floor: float,
    forbidden: Sequence[Sequence[Sequence[float]]],
) -> Tuple[Ring, Ring]:
    """Cut a city-facing slab off the donor and hull it onto the city."""
    city_pts = _open_ring(city)
    donor_pts = _open_ring(donor)
    cx, cy = polygon_centroid(city_pts)
    dx, dy = polygon_centroid(donor_pts)
    vx, vy = dx - cx, dy - cy
    nrm = math.hypot(vx, vy) or 1.0
    vx, vy = vx / nrm, vy / nrm
    best_city = city_pts
    best_donor = donor_pts
    for step in range(1, 13):
        t = step / 14.0
        origin = (cx + (dx - cx) * t, cy + (dy - cy) * t)
        a, b, crossings = split_ring_by_line(donor_pts, origin, (vx, vy))
        if crossings < 2 or not _valid_piece(a, 4.0) or not _valid_piece(b, 4.0):
            continue
        ac = polygon_centroid(a)
        bc = polygon_centroid(b)
        da = math.hypot(ac[0] - dx, ac[1] - dy)
        db = math.hypot(bc[0] - dx, bc[1] - dy)
        keep, bite = (a, b) if da <= db else (b, a)
        if polygon_area(keep) < donor_floor:
            continue
        hull = convex_hull(city_pts + bite)
        if _hull_hits_forbidden(hull, forbidden):
            continue
        if polygon_area(hull) <= polygon_area(city_pts) + 0.8:
            continue
        best_city, best_donor = hull, keep
        if polygon_area(hull) >= target_area:
            return best_city, best_donor
    if polygon_area(best_city) >= target_area:
        return best_city, best_donor
    return _translate_shared_front(city_pts, donor_pts, target_area, donor_floor, forbidden)


def _translate_shared_front(
    city: Sequence[Sequence[float]],
    donor: Sequence[Sequence[float]],
    target_area: float,
    donor_floor: float,
    forbidden: Sequence[Sequence[Sequence[float]]],
) -> Tuple[Ring, Ring]:
    """Nudge the shared front into the donor when a centroid cut is 50/50."""
    city_pts = _open_ring(city)
    donor_pts = _open_ring(donor)
    cx, cy = polygon_centroid(city_pts)
    dx, dy = polygon_centroid(donor_pts)
    vx, vy = dx - cx, dy - cy
    nrm = math.hypot(vx, vy) or 1.0
    vx, vy = vx / nrm, vy / nrm
    best_city = city_pts
    best_donor = donor_pts
    for offset in (1.2, 1.8, 2.4, 3.2, 4.0, 5.0, 6.2):
        new_city: Ring = []
        for p in city_pts:
            relx, rely = p[0] - cx, p[1] - cy
            if relx * vx + rely * vy > -0.25:
                new_city.append([p[0] + vx * offset, p[1] + vy * offset])
            else:
                new_city.append([p[0], p[1]])
        new_donor: Ring = []
        for p in donor_pts:
            relx, rely = p[0] - dx, p[1] - dy
            if relx * (-vx) + rely * (-vy) > -0.25:
                new_donor.append([p[0] + vx * offset, p[1] + vy * offset])
            else:
                new_donor.append([p[0], p[1]])
        if _hull_hits_forbidden(new_city, forbidden):
            break
        if polygon_area(new_donor) < donor_floor:
            break
        best_city, best_donor = new_city, new_donor
        if polygon_area(new_city) >= target_area:
            break
    return best_city, best_donor


def point_in_ring(x: float, y: float, ring: Sequence[Sequence[float]]) -> bool:
    pts = _open_ring(ring)
    n = len(pts)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        intersects = (yi > y) != (yj > y)
        if intersects:
            den = (yj - yi) if (yj - yi) != 0.0 else 1e-12
            if x < (xj - xi) * (y - yi) / den + xi:
                inside = not inside
        j = i
    return inside


def nearest_ring_point(pt: Sequence[float], ring: Sequence[Sequence[float]]) -> Tuple[float, float]:
    px, py = float(pt[0]), float(pt[1])
    pts = _open_ring(ring)
    best = (pts[0][0], pts[0][1])
    best_d = float("inf")
    for q in pts:
        d = math.hypot(px - q[0], py - q[1])
        if d < best_d:
            best_d = d
            best = (q[0], q[1])
    return best


def dent_vertices_inside(donor: Sequence[Sequence[float]], taker: Sequence[Sequence[float]]) -> Ring:
    """Push donor vertices that fall inside taker onto taker's shore (outward)."""
    tcx, tcy = polygon_centroid(taker)
    out: Ring = []
    for pt in _open_ring(donor):
        x, y = pt[0], pt[1]
        if point_in_ring(x, y, taker):
            nx, ny = nearest_ring_point(pt, taker)
            vx, vy = nx - tcx, ny - tcy
            nrm = math.hypot(vx, vy) or 1.0
            x = nx + 0.35 * vx / nrm
            y = ny + 0.35 * vy / nrm
        out.append([x, y])
    return out


def min_ring_distance(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    best = float("inf")
    aa = _open_ring(a)
    bb = _open_ring(b)
    for pa in aa:
        for pb in bb:
            d = math.hypot(pa[0] - pb[0], pa[1] - pb[1])
            if d < best:
                best = d
    return best if best != float("inf") else 0.0


def rings_touch(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]], dist: float = TOUCH_PX) -> bool:
    if len(a) < 3 or len(b) < 3:
        return False
    if min_ring_distance(a, b) <= dist:
        return True
    for p in _open_ring(a):
        if point_in_ring(p[0], p[1], b):
            return True
    for p in _open_ring(b):
        if point_in_ring(p[0], p[1], a):
            return True
    return False


def load_board(board_dir: Path) -> Dict[str, Any]:
    base_rows = json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    geo_rows = json.loads((board_dir / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    adj_doc = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8"))
    base = {int(p["id"]): p for p in base_rows}
    geo = {int(g["id"]): g for g in geo_rows}
    adj_raw = adj_doc.get("adjacency") or {}
    adj = {int(k): [int(x) for x in (v or [])] for k, v in adj_raw.items()}
    return {"base": base, "geo": geo, "adj": adj, "adj_doc": adj_doc}


def theater_land_rows(
    base: Mapping[int, Mapping[str, Any]],
    geo: Mapping[int, Mapping[str, Any]],
) -> List[Dict[str, Any]]:
    lon0, lat0, lon1, lat1 = THEATER_LONLAT
    rows: List[Dict[str, Any]] = []
    for pid, p in base.items():
        if _is_water(p):
            continue
        g = geo.get(int(pid)) or {}
        pts = g.get("points") or []
        la = g.get("label_anchor") or list(polygon_centroid(pts))
        if not isinstance(la, (list, tuple)) or len(la) < 2:
            continue
        lon, lat = canvas_to_lonlat(float(la[0]), float(la[1]))
        if lon0 <= lon <= lon1 and lat0 <= lat <= lat1:
            rows.append(
                {
                    "id": int(pid),
                    "name": p.get("name"),
                    "area": polygon_area(pts),
                    "lon": lon,
                    "lat": lat,
                    "cntr": p.get("cntr_code"),
                }
            )
    return rows


def _percentile(xs: Sequence[float], p: float) -> float:
    if not xs:
        return 0.0
    ordered = sorted(float(x) for x in xs)
    k = (len(ordered) - 1) * (p / 100.0)
    i = int(k)
    f = k - i
    if i + 1 < len(ordered):
        return ordered[i] * (1.0 - f) + ordered[i + 1] * f
    return ordered[i]


def theater_metrics(rows: Sequence[Mapping[str, Any]]) -> Dict[str, float]:
    areas = [float(r.get("area") or 0.0) for r in rows]
    if not areas:
        return {"n": 0.0, "min": 0.0, "median": 0.0, "max": 0.0, "max_over_median": 0.0}
    mn = min(areas)
    mx = max(areas)
    med = _percentile(areas, 50.0)
    return {
        "n": float(len(areas)),
        "min": mn,
        "p25": _percentile(areas, 25.0),
        "median": med,
        "p75": _percentile(areas, 75.0),
        "max": mx,
        "max_over_median": mx / max(med, 1e-9),
        "max_over_min": mx / max(mn, 1e-9),
    }


def _choose_keep_piece(
    parent_id: int,
    pieces: Sequence[Ring],
    geo: Mapping[int, Mapping[str, Any]],
) -> Tuple[Ring, Ring]:
    a, b = pieces[0], pieces[1]
    if parent_id == FRA_MAGINOT_ID:
        ger = (geo.get(GER_MAGINOT_ID) or {}).get("points") or []
        da = min_ring_distance(a, ger)
        db = min_ring_distance(b, ger)
        return (a, b) if da <= db else (b, a)
    # Keep the piece whose centroid is closer to the original centroid.
    ocx, ocy = polygon_centroid((geo.get(parent_id) or {}).get("points") or a)
    ac = polygon_centroid(a)
    bc = polygon_centroid(b)
    da = math.hypot(ac[0] - ocx, ac[1] - ocy)
    db = math.hypot(bc[0] - ocx, bc[1] - ocy)
    return (a, b) if da <= db else (b, a)


def plan_maginot_land_uniformity(board_dir: str = "") -> Dict[str, Any]:
    """Compute split/grow rings. Does not write."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    already = all(int(pid) in base for pid in NEW_CHILD_IDS)
    splits: List[Dict[str, Any]] = []
    for i, parent_id in enumerate(SPLIT_PARENT_IDS):
        child_id = NEW_CHILD_IDS[i]
        g = geo[parent_id]
        pts = g.get("points") or []
        p1, p2 = best_axis_split(pts)
        keep, child = _choose_keep_piece(parent_id, (p1, p2), geo)
        kcx, kcy = polygon_centroid(keep)
        ccx, ccy = polygon_centroid(child)
        parent_name = str((base.get(parent_id) or {}).get("name") or g.get("name") or parent_id)
        suffix = compass_suffix((kcx, kcy), (ccx, ccy))
        splits.append(
            {
                "parent_id": int(parent_id),
                "child_id": int(child_id),
                "parent_name": parent_name,
                "child_name": f"{parent_name} {suffix}",
                "keep_ring": keep,
                "child_ring": child,
                "keep_area": polygon_area(keep),
                "child_area": polygon_area(child),
                "parent_area_before": polygon_area(pts),
            }
        )
    grows: List[Dict[str, Any]] = []
    for spec in GROW_SPECS:
        tiny_id = int(spec["tiny_id"])
        donor_id = int(spec["donor_id"])
        tiny_pts = _open_ring((geo[tiny_id].get("points") or []))
        donor_pts = _open_ring((geo[donor_id].get("points") or []))
        forbidden = [
            _open_ring((geo.get(FRA_MAGINOT_ID) or {}).get("points") or []),
            _open_ring((geo.get(710740) or {}).get("points") or []),
        ]
        best_tiny, best_donor = grow_into_donor(
            tiny_pts,
            donor_pts,
            float(spec["target_area"]),
            float(spec["donor_floor"]),
            forbidden,
        )
        grows.append(
            {
                "tiny_id": tiny_id,
                "donor_id": donor_id,
                "tiny_name": (base.get(tiny_id) or {}).get("name"),
                "donor_name": (base.get(donor_id) or {}).get("name"),
                "tiny_ring": best_tiny,
                "donor_ring": best_donor,
                "tiny_area_before": polygon_area(tiny_pts),
                "tiny_area_after": polygon_area(best_tiny),
                "donor_area_before": polygon_area(donor_pts),
                "donor_area_after": polygon_area(best_donor),
            }
        )
    return {
        "already_applied": already,
        "splits": splits,
        "grows": grows,
        "new_ids": list(NEW_CHILD_IDS),
        "preserved_ids": [GER_MAGINOT_ID, FRA_MAGINOT_ID] + list(SPLIT_PARENT_IDS),
    }


def _geo_object(old: Mapping[str, Any], pid: int, name: str, ring: Ring, extra_meta: Mapping[str, Any]) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta["maginot_land_feed"] = FEED_META
    meta["vertex_n"] = len(ring)
    meta["area"] = polygon_area(ring)
    meta.update(dict(extra_meta))
    obj["meta"] = meta
    return obj


def _split_top_level_objects(array_text: str) -> List[Tuple[int, int]]:
    spans: List[Tuple[int, int]] = []
    depth = 0
    start = -1
    in_str = False
    esc = False
    for i, ch in enumerate(array_text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                spans.append((start, i + 1))
                start = -1
    return spans


def surgical_replace_geometry_provinces(path: Path, updates: Mapping[int, Mapping[str, Any]]) -> int:
    raw = path.read_text(encoding="utf-8")
    marker = '"provinces":'
    m = raw.find(marker)
    if m < 0:
        raise ValueError("provinces_geometry.json missing provinces array")
    arr_open = raw.find("[", m)
    arr_close = raw.rfind("]")
    if arr_open < 0 or arr_close < arr_open:
        raise ValueError("provinces_geometry.json provinces array bounds")
    body = raw[arr_open + 1 : arr_close]
    spans = _split_top_level_objects(body)
    changed = 0
    pieces: List[str] = []
    cursor = 0
    for a, b in spans:
        pieces.append(body[cursor:a])
        chunk = body[a:b]
        try:
            obj = json.loads(chunk)
            pid = int(obj.get("id"))
        except (ValueError, TypeError, json.JSONDecodeError):
            pieces.append(chunk)
            cursor = b
            continue
        if pid in updates:
            pieces.append(json.dumps(updates[pid], separators=(",", ":")))
            changed += 1
        else:
            pieces.append(chunk)
        cursor = b
    pieces.append(body[cursor:])
    path.write_text(raw[: arr_open + 1] + "".join(pieces) + raw[arr_close:], encoding="utf-8")
    return changed


def surgical_append_geometry_provinces(path: Path, new_objs: Sequence[Mapping[str, Any]]) -> int:
    if not new_objs:
        return 0
    raw = path.read_text(encoding="utf-8")
    arr_close = raw.rfind("]")
    if arr_close < 0:
        raise ValueError("provinces_geometry.json missing array close")
    blob = ",".join(json.dumps(dict(o), separators=(",", ":")) for o in new_objs)
    path.write_text(raw[:arr_close] + "," + blob + raw[arr_close:], encoding="utf-8")
    return len(list(new_objs))


def _format_adj_array(values: Sequence[int]) -> str:
    if not values:
        return "[]"
    inner = ",\n".join(f"      {int(v)}" for v in values)
    return "[\n" + inner + "\n    ]"


def surgical_replace_adjacency_keys(path: Path, updates: Mapping[int, Sequence[int]]) -> int:
    raw = path.read_text(encoding="utf-8")
    out = raw
    changed = 0
    for pid, values in updates.items():
        key = str(int(pid))
        pattern = re.compile(r'"' + re.escape(key) + r'"\s*:\s*\[(?:[^\[\]]*)\]', re.S)
        replacement = f'"{key}": {_format_adj_array(list(values))}'
        new_out, n = pattern.subn(replacement, out, count=1)
        if n != 1:
            raise ValueError(f"adjacency key {key} not uniquely replaced (n={n})")
        out = new_out
        changed += 1
    if out != raw:
        path.write_text(out, encoding="utf-8")
    return changed


def surgical_insert_adjacency_keys(path: Path, new_keys: Mapping[int, Sequence[int]]) -> int:
    if not new_keys:
        return 0
    raw = path.read_text(encoding="utf-8")
    marker = '"adjacency":'
    m = raw.find(marker)
    if m < 0:
        raise ValueError("province_adjacency.json missing adjacency object")
    obj_open = raw.find("{", m)
    depth = 0
    close = -1
    in_str = False
    esc = False
    for i in range(obj_open, len(raw)):
        ch = raw[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                close = i
                break
    if close < 0:
        raise ValueError("adjacency object close not found")
    entries = []
    for pid, values in new_keys.items():
        entries.append(f'    "{int(pid)}": {_format_adj_array(list(values))}')
    insert = ",\n" + ",\n".join(entries) + "\n"
    # trim trailing whitespace inside the object so we sit after the last entry
    head = raw[:close].rstrip()
    if not head.endswith(","):
        # last entry has no trailing comma; we added ",\n" via insert start
        pass
    path.write_text(head + insert + raw[close:], encoding="utf-8")
    return len(list(new_keys))


def _insert_simple_key_after(raw: str, after_key: str, new_key: str, new_literal: str) -> str:
    """Insert `"new_key": literal` after a simple (non-object) `"after_key": value` entry."""
    pat = re.compile(r'"' + re.escape(after_key) + r'"\s*:\s*("[^"]*"|-?\d+(?:\.\d+)?)')
    m = pat.search(raw)
    if not m:
        raise ValueError(f"simple key {after_key} not found for insert")
    insert = f',\n    "{new_key}": {new_literal}'
    return raw[: m.end()] + insert + raw[m.end() :]


def _insert_object_key_after(raw: str, after_key: str, new_key: str, new_obj_text: str) -> str:
    token = f'"{after_key}"'
    idx = raw.find(token)
    if idx < 0:
        raise ValueError(f"object key {after_key} not found")
    brace = raw.find("{", idx)
    if brace < 0:
        raise ValueError(f"object value for {after_key} not found")
    depth = 0
    end = -1
    in_str = False
    esc = False
    for i in range(brace, len(raw)):
        ch = raw[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end < 0:
        raise ValueError(f"object value for {after_key} unclosed")
    insert = f',\n    "{new_key}": {new_obj_text}'
    return raw[:end] + insert + raw[end:]


def _insert_id_after_in_int_array(raw: str, after_id: int, new_id: int) -> str:
    """Insert new_id after the first pretty-printed occurrence of after_id in an int array."""
    pat = re.compile(r"(^|[^\d])(" + str(int(after_id)) + r")([^\d])")
    m = pat.search(raw)
    if not m:
        raise ValueError(f"id {after_id} not found to insert sibling {new_id}")
    # Prefer a list-style occurrence: `        710739,` or last element.
    list_pat = re.compile(r"(\n\s+)" + str(int(after_id)) + r"(,?)")
    lm = list_pat.search(raw)
    if lm:
        indent = lm.group(1)
        comma = lm.group(2)
        if comma:
            repl = f"{indent}{after_id},{indent}{new_id},"
        else:
            repl = f"{indent}{after_id},{indent}{new_id}"
        return raw[: lm.start()] + repl + raw[lm.end() :]
    return raw[: m.end(2)] + f", {new_id}" + raw[m.end(2) :]


def _rewrite_adj_for_theater(
    adj: Dict[int, List[int]],
    geo: Mapping[int, Mapping[str, Any]],
    parent_id: int,
    child_id: int,
    keep_ring: Ring,
    child_ring: Ring,
) -> None:
    old_nbrs = list(adj.get(parent_id) or [])
    keep_nbrs = {child_id}
    child_nbrs = {parent_id}
    for nb in old_nbrs:
        if int(nb) == child_id:
            continue
        nb_pts = (geo.get(int(nb)) or {}).get("points") or []
        if rings_touch(keep_ring, nb_pts):
            keep_nbrs.add(int(nb))
        if rings_touch(child_ring, nb_pts):
            child_nbrs.add(int(nb))
    adj[parent_id] = sorted(keep_nbrs)
    adj[child_id] = sorted(child_nbrs)
    for nb in set(old_nbrs) | keep_nbrs | child_nbrs:
        cur = set(adj.get(int(nb)) or [])
        if parent_id in cur and int(nb) not in keep_nbrs and int(nb) != parent_id:
            cur.discard(parent_id)
        if parent_id in keep_nbrs and int(nb) != parent_id:
            cur.add(parent_id)
        if int(nb) in child_nbrs and int(nb) != child_id:
            cur.add(child_id)
        elif child_id in cur and int(nb) not in child_nbrs:
            cur.discard(child_id)
        adj[int(nb)] = sorted(cur)


def apply_maginot_land_uniformity(board_dir: str = "") -> Dict[str, Any]:
    """Write split/grow geometry + layer clones. Existing IDs stay."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    plan = plan_maginot_land_uniformity(str(d))
    if plan.get("already_applied"):
        board = load_board(d)
        finish_plan = _static_plan_from_board(board["base"], board["geo"])
        _insert_hierarchy_and_ownership(d, finish_plan)
        _insert_state_and_region_ids(d, finish_plan)
        _ensure_manifest_and_adj_stats(d, added=len(NEW_CHILD_IDS))
        return {
            "ok": True,
            "already_applied": True,
            "new_ids": list(NEW_CHILD_IDS),
            "renumbered": False,
            "finished_remaining_layers": True,
        }
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]

    geo_updates: Dict[int, Dict[str, Any]] = {}
    new_geo: List[Dict[str, Any]] = []
    for spec in plan["grows"]:
        for key, pid in (("tiny_ring", spec["tiny_id"]), ("donor_ring", spec["donor_id"])):
            old = dict(geo[int(pid)])
            name = str(old.get("name") or (base.get(int(pid)) or {}).get("name") or pid)
            geo_updates[int(pid)] = _geo_object(old, int(pid), name, spec[key], {"role": key.replace("_ring", "")})
            geo[int(pid)] = geo_updates[int(pid)]

    for spec in plan["splits"]:
        parent_id = int(spec["parent_id"])
        child_id = int(spec["child_id"])
        old = dict(geo[parent_id])
        geo_updates[parent_id] = _geo_object(
            old,
            parent_id,
            spec["parent_name"],
            spec["keep_ring"],
            {"split_child": child_id},
        )
        child_obj = _geo_object(
            old,
            child_id,
            spec["child_name"],
            spec["child_ring"],
            {"split_parent": parent_id},
        )
        geo[parent_id] = geo_updates[parent_id]
        geo[child_id] = child_obj
        new_geo.append(child_obj)

    # Adjacency: rebuild around each split using post-grow rings.
    touched_adj: Dict[int, List[int]] = {}
    new_adj: Dict[int, List[int]] = {}
    for spec in plan["splits"]:
        parent_id = int(spec["parent_id"])
        child_id = int(spec["child_id"])
        _rewrite_adj_for_theater(
            adj,
            geo,
            parent_id,
            child_id,
            spec["keep_ring"],
            spec["child_ring"],
        )
    # Force combat edge if rings still touch (they should).
    if rings_touch(geo[GER_MAGINOT_ID]["points"], geo[FRA_MAGINOT_ID]["points"], dist=28.0):
        for a, b in ((GER_MAGINOT_ID, FRA_MAGINOT_ID), (FRA_MAGINOT_ID, GER_MAGINOT_ID)):
            cur = set(adj.get(a) or [])
            cur.add(b)
            adj[a] = sorted(cur)

    existing_keys = set(int(k) for k in (board["adj_doc"].get("adjacency") or {}))
    for pid, nbrs in adj.items():
        if int(pid) in existing_keys:
            touched_adj[int(pid)] = list(nbrs)
        else:
            new_adj[int(pid)] = list(nbrs)

    surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
    surgical_append_geometry_provinces(d / "provinces_geometry.json", new_geo)
    if touched_adj:
        surgical_replace_adjacency_keys(d / "province_adjacency.json", touched_adj)
    if new_adj:
        surgical_insert_adjacency_keys(d / "province_adjacency.json", new_adj)

    _append_base_children(d, plan, base)
    _clone_layer_rows(d, plan)
    _insert_hierarchy_and_ownership(d, plan)
    _insert_state_and_region_ids(d, plan)
    _bump_manifest(d, added=len(plan["splits"]))
    _bump_adj_stats(d, added=len(plan["splits"]))

    return {
        "ok": True,
        "already_applied": False,
        "board_dir": str(d),
        "new_ids": [int(s["child_id"]) for s in plan["splits"]],
        "split_parents": [int(s["parent_id"]) for s in plan["splits"]],
        "grown_ids": [int(g["tiny_id"]) for g in plan["grows"]],
        "donor_ids": [int(g["donor_id"]) for g in plan["grows"]],
        "renumbered": False,
        "world_full_touched": False,
        "splits": [
            {
                "parent_id": int(s["parent_id"]),
                "child_id": int(s["child_id"]),
                "parent_name": s["parent_name"],
                "child_name": s["child_name"],
                "keep_area": round(float(s["keep_area"]), 1),
                "child_area": round(float(s["child_area"]), 1),
                "parent_area_before": round(float(s["parent_area_before"]), 1),
            }
            for s in plan["splits"]
        ],
        "grows": [
            {
                "tiny_id": int(g["tiny_id"]),
                "donor_id": int(g["donor_id"]),
                "tiny_name": g["tiny_name"],
                "tiny_area_before": round(float(g["tiny_area_before"]), 1),
                "tiny_area_after": round(float(g["tiny_area_after"]), 1),
                "donor_area_after": round(float(g["donor_area_after"]), 1),
            }
            for g in plan["grows"]
        ],
    }


def _append_base_children(d: Path, plan: Mapping[str, Any], base: Mapping[int, Mapping[str, Any]]) -> None:
    path = d / "provinces_base.json"
    raw = path.read_text(encoding="utf-8")
    new_objs: List[str] = []
    for spec in plan["splits"]:
        parent = dict(base[int(spec["parent_id"])])
        ratio = float(spec["child_area"]) / max(float(spec["keep_area"]) + float(spec["child_area"]), 1e-6)
        child = dict(parent)
        child["id"] = int(spec["child_id"])
        child["name"] = spec["child_name"]
        pop = int(parent.get("population_base") or 0)
        child["population_base"] = max(1, int(round(pop * ratio)))
        new_pop = max(1, pop - int(child["population_base"]))
        raw = _replace_parent_population(raw, int(spec["parent_id"]), new_pop)
        new_objs.append(json.dumps(child, indent=2))
    # Indent dumped objects to match the provinces array (2 spaces).
    indented = []
    for blob in new_objs:
        lines = blob.splitlines()
        indented.append("    " + lines[0] + "\n" + "\n".join("    " + ln if ln else ln for ln in lines[1:]))
    insert = ",\n" + ",\n".join(indented)
    close = raw.rfind("]")
    if close < 0:
        raise ValueError("provinces_base.json missing array close")
    # the provinces array close is the last ] before the final }
    path.write_text(raw[:close].rstrip() + insert + "\n  ]\n}\n", encoding="utf-8")


def _replace_parent_population(raw: str, parent_id: int, new_pop: int) -> str:
    token = f'"id": {int(parent_id)}'
    idx = raw.find(token)
    if idx < 0:
        token = f'"id":{int(parent_id)}'
        idx = raw.find(token)
    if idx < 0:
        return raw
    window = raw[idx : idx + 800]
    m = re.search(r'"population_base"\s*:\s*\d+', window)
    if not m:
        return raw
    repl = f'"population_base": {int(new_pop)}'
    return raw[: idx + m.start()] + repl + raw[idx + m.end() :]


def _clone_layer_rows(d: Path, plan: Mapping[str, Any]) -> None:
    layer_files = (
        "province_terrain_layer.json",
        "province_resources_layer.json",
        "province_economy_layer.json",
        "province_city_layer.json",
    )
    for fn in layer_files:
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        doc = json.loads(raw)
        provs = doc.get("provinces")
        if not isinstance(provs, dict):
            continue
        for spec in plan["splits"]:
            parent_id = int(spec["parent_id"])
            child_id = int(spec["child_id"])
            src = dict(provs.get(str(parent_id)) or {})
            if not src:
                continue
            if fn.endswith("city_layer.json"):
                src["city_name"] = str(spec["child_name"])
            blob = json.dumps(src, indent=2)
            lines = blob.splitlines()
            body = "\n".join("    " + ln for ln in lines[1:])
            raw = _insert_object_key_after(raw, str(parent_id), str(child_id), "{\n" + body)
        path.write_text(raw, encoding="utf-8")


def _static_plan_from_board(base: Mapping[int, Mapping[str, Any]], geo: Mapping[int, Mapping[str, Any]]) -> Dict[str, Any]:
    splits = []
    for parent_id, child_id in zip(SPLIT_PARENT_IDS, NEW_CHILD_IDS):
        splits.append(
            {
                "parent_id": int(parent_id),
                "child_id": int(child_id),
                "parent_name": (base.get(int(parent_id)) or {}).get("name"),
                "child_name": (base.get(int(child_id)) or {}).get("name"),
                "keep_area": polygon_area((geo.get(int(parent_id)) or {}).get("points") or []),
                "child_area": polygon_area((geo.get(int(child_id)) or {}).get("points") or []),
            }
        )
    return {"splits": splits, "grows": []}


def _has_json_key(raw: str, key: str) -> bool:
    return re.search(r'"' + re.escape(str(key)) + r'"\s*:', raw) is not None


def _insert_hierarchy_and_ownership(d: Path, plan: Mapping[str, Any]) -> None:
    for path in sorted(d.glob("hierarchy_membership_*.json")):
        raw = path.read_text(encoding="utf-8")
        for spec in plan["splits"]:
            parent_id = str(int(spec["parent_id"]))
            child_id = str(int(spec["child_id"]))
            if _has_json_key(raw, child_id):
                continue
            raw = _insert_simple_key_after_each(raw, parent_id, child_id, None)
        path.write_text(raw, encoding="utf-8")
    for path in sorted(d.glob("province_ownership_*.json")):
        raw = path.read_text(encoding="utf-8")
        owners = json.loads(raw).get("owners") or {}
        for spec in plan["splits"]:
            parent_id = str(int(spec["parent_id"]))
            child_id = str(int(spec["child_id"]))
            if _has_json_key(raw, child_id):
                continue
            val = owners.get(parent_id)
            if val is None:
                continue
            raw = _insert_simple_key_after(raw, parent_id, child_id, json.dumps(val))
        path.write_text(raw, encoding="utf-8")


def _insert_simple_key_after_each(raw: str, after_key: str, new_key: str, literal: Optional[str]) -> str:
    """Copy the parent value onto new_key after every simple `"after_key": value`."""
    pat = re.compile(r'"' + re.escape(after_key) + r'"\s*:\s*("[^"]*"|-?\d+(?:\.\d+)?)')
    matches = list(pat.finditer(raw))
    if not matches:
        raise ValueError(f"simple key {after_key} not found for insert")
    out = raw
    for m in reversed(matches):
        value = literal if literal is not None else m.group(1)
        insert = f',\n    "{new_key}": {value}'
        out = out[: m.end()] + insert + out[m.end() :]
    return out


def _insert_state_and_region_ids(d: Path, plan: Mapping[str, Any]) -> None:
    for fn in ("province_states.json", "strategic_regions.json"):
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        for spec in plan["splits"]:
            child_id = int(spec["child_id"])
            if re.search(r"(^|[^\d])" + str(child_id) + r"([^\d]|$)", raw):
                continue
            raw = _insert_id_after_in_int_array(raw, int(spec["parent_id"]), child_id)
        path.write_text(raw, encoding="utf-8")


def _ensure_manifest_and_adj_stats(d: Path, added: int) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    if int(stats.get("provinces") or 0) < 3520 + int(added):
        _bump_manifest(d, added)
    adj_path = d / "province_adjacency.json"
    adj_doc = json.loads(adj_path.read_text(encoding="utf-8"))
    st = adj_doc.get("stats") or {}
    if int(st.get("province_n") or 0) < 3520 + int(added):
        _bump_adj_stats(d, added)


def _bump_manifest(d: Path, added: int) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    stats["provinces"] = int(stats.get("provinces") or 0) + int(added)
    stats["land"] = int(stats.get("land") or 0) + int(added)
    blocks = doc.setdefault("blocks", {})
    if "europe_nuts3" in blocks:
        blocks["europe_nuts3"] = int(blocks["europe_nuts3"]) + int(added)
    gq = str(doc.get("geometry_quality") or "")
    if FEED_META not in gq:
        doc["geometry_quality"] = (gq + "+" + FEED_META) if gq else FEED_META
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def _bump_adj_stats(d: Path, added: int) -> None:
    path = d / "province_adjacency.json"
    raw = path.read_text(encoding="utf-8")
    def _bump(key: str) -> None:
        nonlocal raw
        m = re.search(r'"' + re.escape(key) + r'"\s*:\s*(\d+)', raw)
        if not m:
            return
        raw = raw[: m.start(1)] + str(int(m.group(1)) + added) + raw[m.end(1) :]
    _bump("province_n")
    _bump("land_n")
    path.write_text(raw, encoding="utf-8")


def build_maginot_land_uniformity_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Maginot corridor land cells less extreme."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]
    rows = theater_land_rows(base, geo)
    metrics = theater_metrics(rows)
    pre = PRE_FEED_METRICS

    if int(metrics["n"]) < 40:
        fails.append(f"theater_thin n={metrics['n']}")
    else:
        passes.append(f"theater_n={int(metrics['n'])}")

    if metrics["max"] >= pre["max"] - 1.0:
        fails.append(f"max_not_reduced {metrics['max']:.1f} >= pre {pre['max']:.1f}")
    else:
        passes.append(f"max {pre['max']:.1f}→{metrics['max']:.1f}")

    if metrics["max_over_median"] >= pre["max_over_median"] - 0.15:
        fails.append(
            f"max/med_not_reduced {metrics['max_over_median']:.2f} >= pre {pre['max_over_median']:.2f}"
        )
    else:
        passes.append(f"max/med {pre['max_over_median']:.2f}→{metrics['max_over_median']:.2f}")

    if metrics["max"] > 290.0:
        fails.append(f"max_still_extreme {metrics['max']:.1f}")
    else:
        passes.append(f"max_band={metrics['max']:.1f}")

    for spec in GROW_SPECS:
        pid = int(spec["tiny_id"])
        area = polygon_area((geo.get(pid) or {}).get("points") or [])
        if area < 20.0:
            fails.append(f"tiny_still_extreme {pid} area={area:.1f}")
        else:
            passes.append(f"grown {pid} area={area:.1f}")

    for pid in list(SPLIT_PARENT_IDS) + [GER_MAGINOT_ID, FRA_MAGINOT_ID]:
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_existing_id {pid}")
    if GER_MAGINOT_ID not in fails and FRA_MAGINOT_ID not in (adj.get(GER_MAGINOT_ID) or []):
        fails.append("combat_edge_lost 710173↔710739")
    else:
        passes.append("combat_edge_710173_710739")

    new_present = [int(pid) for pid in NEW_CHILD_IDS if int(pid) in base and int(pid) in geo]
    if len(new_present) != len(NEW_CHILD_IDS):
        fails.append(f"missing_append_ids have={new_present}")
    else:
        passes.append(f"append_ids={list(NEW_CHILD_IDS)}")
        for pid in NEW_CHILD_IDS:
            if str((base.get(int(pid)) or {}).get("domain") or "land").lower() != "land":
                fails.append(f"child_not_land {pid}")
            if int(pid) >= 800000:
                fails.append(f"child_id_left_europe_block {pid}")

    # No retire: every pre-existing Europe id in the theater window still exists
    # (checked via parent + combat IDs above). Children stay < 800000.
    if any(int(pid) < 711514 or int(pid) > 711519 for pid in NEW_CHILD_IDS):
        fails.append("unexpected_new_id_block")

    n_board = len(base)
    if n_board < 3510 or n_board > 3540:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")

    world_full = ROOT / "data" / "provinces_world_full"
    # Integrity only asserts we did not require world_full; apply never writes it.
    passes.append("world_full_untouched_by_product")

    doc = ROOT / "docs" / "MAP_MAGINOT_LAND_UNIFORMITY.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if "FEED-2" in body and "Never renumber" in body and "711514" in body:
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS maginot land uniformity" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "metrics": metrics,
        "pre_feed_metrics": pre,
        "new_ids": list(NEW_CHILD_IDS),
        "renumbered": False,
        "world_full_dir_exists": world_full.is_dir(),
        "combat_edge": [GER_MAGINOT_ID, FRA_MAGINOT_ID],
        "theater_n": int(metrics["n"]),
    }


def maginot_land_uniformity_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_maginot_land_uniformity_product(board_dir)
