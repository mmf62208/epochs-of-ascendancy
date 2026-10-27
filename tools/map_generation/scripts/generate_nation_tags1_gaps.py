#!/usr/bin/env python3
"""Append NATION-TAGS-1 gap provinces and set Poland's 1945 owners.

Append-only ids 906000–906020 (moved off 905849–905869). Does not renumber
world_full or any other world_accurate id. Idempotent: if the gaps and the
1945 Poland owners are already in place, it exits 0 without rewriting the board.

  python3 tools/map_generation/scripts/generate_nation_tags1_gaps.py --dry-run
  python3 tools/map_generation/scripts/generate_nation_tags1_gaps.py
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "tools" / "map_generation" / "lib"
sys.path.insert(0, str(LIB))

from nation_tags1_product import (  # noqa: E402
    BOARD,
    BOARD_N_AFTER,
    CATALOG_PATH,
    ERA_YEARS,
    FLAG_DIR,
    GAPS,
    GAP_N,
    LAND_N_AFTER,
    NEW_TAGS,
    PRIOR_MAX_LAND_ID,
    TAGS,
    GapSpec,
    audit,
    catalog_document,
)
from ne_full_geometry_align import (  # noqa: E402
    DEFAULT_NE_LAND,
    load_ne_land_features,
    lonlat_to_canvas,
    rasterize_land_mask,
    sample_mask,
)

TOUCH_PX = 18.0
NEAR_PX = 20.0
MAX_STRETCH_DEG = 4.0

Point = Tuple[float, float]
RectLL = Tuple[float, float, float, float]  # lon0, lat0, lon1, lat1


def _dump(obj) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _point_in_poly(x: float, y: float, pts: Sequence[Point]) -> bool:
    n = len(pts)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-18) + xi):
            inside = not inside
        j = i
    return inside


def _orient(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
    return (by - ay) * (cx - bx) - (bx - ax) * (cy - by)


def _proper_cross(a: Point, b: Point, c: Point, d: Point, eps: float = 1e-6) -> bool:
    o1 = _orient(a[0], a[1], b[0], b[1], c[0], c[1])
    o2 = _orient(a[0], a[1], b[0], b[1], d[0], d[1])
    o3 = _orient(c[0], c[1], d[0], d[1], a[0], a[1])
    o4 = _orient(c[0], c[1], d[0], d[1], b[0], b[1])
    if abs(o1) < eps or abs(o2) < eps or abs(o3) < eps or abs(o4) < eps:
        return False
    return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0)


class Obstacle:
    def __init__(self, pid: int, pts: List[Point]) -> None:
        self.pid = pid
        self.pts = pts
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        self.xmin, self.xmax = min(xs), max(xs)
        self.ymin, self.ymax = min(ys), max(ys)

    def bbox_hits(self, x0: float, y0: float, x1: float, y1: float, pad: float = 1.0) -> bool:
        return not (self.xmax < x0 - pad or self.xmin > x1 + pad or self.ymax < y0 - pad or self.ymin > y1 + pad)


def _rect_canvas(rect: RectLL) -> Tuple[float, float, float, float]:
    lon0, lat0, lon1, lat1 = rect
    x_w, y_s = lonlat_to_canvas(lon0, lat0)
    x_e, y_n = lonlat_to_canvas(lon1, lat1)
    return min(x_w, x_e), min(y_n, y_s), max(x_w, x_e), max(y_n, y_s)


def _samples(rect: RectLL, step: float = 0.06) -> List[Point]:
    lon0, lat0, lon1, lat1 = rect
    pts: List[Point] = []
    lat = lat0 + step * 0.5
    while lat < lat1:
        lon = lon0 + step * 0.5
        while lon < lon1:
            pts.append(lonlat_to_canvas(lon, lat))
            lon += step
        lat += step
    return pts


def _corners(box: Tuple[float, float, float, float]) -> List[Point]:
    x0, y0, x1, y1 = box
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def _edges(corners: Sequence[Point]) -> List[Tuple[Point, Point]]:
    return [(corners[i], corners[(i + 1) % len(corners)]) for i in range(len(corners))]


def overlaps(rect: RectLL, obstacles: Sequence[Obstacle], eps: float = 0.6) -> bool:
    x0, y0, x1, y1 = _rect_canvas(rect)
    if x1 - x0 < 1.0 or y1 - y0 < 1.0:
        return True
    samples = _samples(rect)
    corners = _corners((x0, y0, x1, y1))
    edges = _edges(corners)
    for ob in obstacles:
        if not ob.bbox_hits(x0, y0, x1, y1, pad=0.5):
            continue
        for vx, vy in ob.pts:
            if x0 + eps < vx < x1 - eps and y0 + eps < vy < y1 - eps:
                return True
        for sx, sy in samples:
            if _point_in_poly(sx, sy, ob.pts):
                return True
        for cx, cy in corners:
            if _point_in_poly(cx, cy, ob.pts):
                return True
        # Edge crossings. Skip edges whose bbox misses the rect.
        for i in range(len(ob.pts)):
            a = ob.pts[i]
            b = ob.pts[(i + 1) % len(ob.pts)]
            if max(a[0], b[0]) < x0 or min(a[0], b[0]) > x1:
                continue
            if max(a[1], b[1]) < y0 or min(a[1], b[1]) > y1:
                continue
            for e0, e1 in edges:
                if _proper_cross(a, b, e0, e1):
                    return True
    return False


def _dist_point_rect(px: float, py: float, box: Tuple[float, float, float, float]) -> float:
    x0, y0, x1, y1 = box
    dx = 0.0 if x0 <= px <= x1 else (x0 - px if px < x0 else px - x1)
    dy = 0.0 if y0 <= py <= y1 else (y0 - py if py < y0 else py - y1)
    return (dx * dx + dy * dy) ** 0.5


def _facing_side(tx: float, ty: float, box: Tuple[float, float, float, float]) -> str:
    x0, y0, x1, y1 = box
    if tx < x0:
        return "west"
    if tx > x1:
        return "east"
    if ty < y0:
        return "north"
    if ty > y1:
        return "south"
    return "east"


def _expand(rect: RectLL, side: str, deg: float) -> RectLL:
    lon0, lat0, lon1, lat1 = rect
    if side == "west":
        lon0 -= deg
    elif side == "east":
        lon1 += deg
    elif side == "north":
        lat1 += deg
    else:
        lat0 -= deg
    return lon0, lat0, lon1, lat1


def _stretch(rect: RectLL, target: Point, obstacles: Sequence[Obstacle], city_lon: float, city_lat: float) -> RectLL:
    best = rect
    box = _rect_canvas(best)
    if _dist_point_rect(target[0], target[1], box) <= TOUCH_PX:
        return best
    side = _facing_side(target[0], target[1], box)
    for _ in range(int(MAX_STRETCH_DEG / 0.04) + 1):
        trial = _expand(best, side, 0.04)
        lon0, lat0, lon1, lat1 = trial
        if (lon1 - city_lon) > MAX_STRETCH_DEG or (city_lon - lon0) > MAX_STRETCH_DEG:
            break
        if (lat1 - city_lat) > MAX_STRETCH_DEG or (city_lat - lat0) > MAX_STRETCH_DEG:
            break
        if overlaps(trial, obstacles):
            break
        best = trial
        if _dist_point_rect(target[0], target[1], _rect_canvas(best)) <= TOUCH_PX:
            break
    return best


def _land_anchor(rect: RectLL, city_lon: float, city_lat: float, mask) -> Optional[List[float]]:
    cx, cy = lonlat_to_canvas(city_lon, city_lat)
    lon0, lat0, lon1, lat1 = rect
    if lon0 < city_lon < lon1 and lat0 < city_lat < lat1 and sample_mask(mask, cx, cy):
        return [round(cx, 4), round(cy, 4)]
    best = None
    best_d = 1e18
    lat = lat0
    while lat <= lat1 + 1e-9:
        lon = lon0
        while lon <= lon1 + 1e-9:
            if lon0 <= lon <= lon1 and lat0 <= lat <= lat1:
                x, y = lonlat_to_canvas(lon, lat)
                if sample_mask(mask, x, y):
                    d = (lon - city_lon) ** 2 + (lat - city_lat) ** 2
                    if d < best_d:
                        best_d = d
                        best = [round(x, 4), round(y, 4)]
            lon += 0.04
        lat += 0.04
    return best


def _overlaps_poly(pts: Sequence[Point], obstacles: Sequence[Obstacle]) -> bool:
    if len(pts) < 3:
        return True
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    samples: List[Point] = [(cx, cy)]
    for px, py in pts:
        samples.append(((px + cx) * 0.5, (py + cy) * 0.5))
        samples.append((px * 0.75 + cx * 0.25, py * 0.75 + cy * 0.25))
    edges = [(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts))]
    for ob in obstacles:
        if not ob.bbox_hits(x0, y0, x1, y1, pad=0.5):
            continue
        for vx, vy in ob.pts:
            if _point_in_poly(vx, vy, pts):
                return True
        for sx, sy in samples:
            if _point_in_poly(sx, sy, ob.pts):
                return True
        for i in range(len(ob.pts)):
            a = ob.pts[i]
            b = ob.pts[(i + 1) % len(ob.pts)]
            if max(a[0], b[0]) < x0 or min(a[0], b[0]) > x1:
                continue
            if max(a[1], b[1]) < y0 or min(a[1], b[1]) > y1:
                continue
            for e0, e1 in edges:
                if _proper_cross(a, b, e0, e1):
                    return True
    return False


def _nearest_edge(city_lon: float, city_lat: float, obstacles: Sequence[Obstacle]) -> Optional[Tuple[float, Point, int]]:
    x, y = lonlat_to_canvas(city_lon, city_lat)
    best: Optional[Tuple[float, Point, int]] = None
    for pad in (40.0, 120.0, 400.0):
        for ob in obstacles:
            if not ob.bbox_hits(x, y, x, y, pad=pad):
                continue
            for i in range(len(ob.pts)):
                ax, ay = ob.pts[i]
                bx, by = ob.pts[(i + 1) % len(ob.pts)]
                vx, vy = bx - ax, by - ay
                length2 = vx * vx + vy * vy or 1e-9
                t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / length2))
                px, py = ax + t * vx, ay + t * vy
                dist = ((px - x) ** 2 + (py - y) ** 2) ** 0.5
                if best is None or dist < best[0]:
                    best = (dist, (px, py), ob.pid)
        if best is not None and best[0] < pad:
            break
    return best


def _anchor_in_poly(pts: Sequence[Point], city_lon: float, city_lat: float, mask) -> Optional[List[float]]:
    cx, cy = lonlat_to_canvas(city_lon, city_lat)
    if _point_in_poly(cx, cy, pts) and sample_mask(mask, cx, cy):
        return [round(cx, 4), round(cy, 4)]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    # Canvas step ~4px. Search the triangle bbox for NE land inside the ring.
    step = 4.0
    y = min(ys)
    best = None
    best_d = 1e18
    while y <= max(ys):
        x = min(xs)
        while x <= max(xs):
            if _point_in_poly(x, y, pts) and sample_mask(mask, x, y):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if d < best_d:
                    best_d = d
                    best = [round(x, 4), round(y, 4)]
            x += step
        y += step
    return best


def _escape_triangle(spec: GapSpec, obstacles: Sequence[Obstacle], mask) -> Optional[dict]:
    """Wedge away from a province edge that sits on the city. The city stays inside."""
    info = _nearest_edge(spec.lon, spec.lat, obstacles)
    if info is None:
        return None
    dist, closest, near_pid = info
    x, y = lonlat_to_canvas(spec.lon, spec.lat)
    dx, dy = closest[0] - x, closest[1] - y
    norm = (dx * dx + dy * dy) ** 0.5 or 1.0
    ux, uy = dx / norm, dy / norm
    fx, fy = -ux, -uy
    sx, sy = -uy, ux
    for depth in (6.0, 10.0, 14.0, 20.0, 28.0):
        for half_w in (1.2, 2.5, 4.5):
            for margin in (0.15, 0.3, 0.5):
                if margin >= dist - 0.12:
                    continue
                poly = [
                    (x + ux * margin, y + uy * margin),
                    (x + fx * depth + sx * half_w, y + fy * depth + sy * half_w),
                    (x + fx * depth - sx * half_w, y + fy * depth - sy * half_w),
                ]
                if not _point_in_poly(x, y, poly):
                    continue
                if _overlaps_poly(poly, obstacles):
                    continue
                anchor = _anchor_in_poly(poly, spec.lon, spec.lat, mask)
                if anchor is None:
                    continue
                ring = [[round(px, 4), round(py, 4)] for px, py in poly]
                return {
                    "spec": spec,
                    "points": ring,
                    "anchor": anchor,
                    "touch_px": max(0.0, dist - margin),
                    "near_pid": near_pid,
                    "target": closest,
                    "rank": (0, dist, depth),
                }
    return None


def _nearest_vertices(city_lon: float, city_lat: float, obstacles: Sequence[Obstacle], k: int = 4) -> List[Tuple[float, Point, int]]:
    x, y = lonlat_to_canvas(city_lon, city_lat)
    found: List[Tuple[float, Point, int]] = []
    for pad in (80.0, 160.0, 400.0, 1200.0):
        found = []
        for ob in obstacles:
            if not ob.bbox_hits(x, y, x, y, pad=pad):
                continue
            best_d = 1e18
            best_p = ob.pts[0]
            for px, py in ob.pts:
                d = (px - x) ** 2 + (py - y) ** 2
                if d < best_d:
                    best_d = d
                    best_p = (px, py)
            found.append((best_d ** 0.5, best_p, ob.pid))
        found.sort(key=lambda row: row[0])
        if found and found[0][0] < pad:
            break
    return found[:k]


def _ring_points(rect: RectLL, target: Optional[Point]) -> List[List[float]]:
    x0, y0, x1, y1 = _rect_canvas(rect)
    pts: List[Point] = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    if target is not None:
        tx, ty = target
        side = _facing_side(tx, ty, (x0, y0, x1, y1))
        if side == "east":
            bump = (x1, min(max(ty, y0), y1))
            pts.insert(2, bump)
        elif side == "west":
            bump = (x0, min(max(ty, y0), y1))
            pts.insert(4, bump)
        elif side == "north":
            bump = (min(max(tx, x0), x1), y0)
            pts.insert(1, bump)
        else:
            bump = (min(max(tx, x0), x1), y1)
            pts.insert(3, bump)
    out = []
    for px, py in pts:
        out.append([round(px, 4), round(py, 4)])
    # Drop a bump that landed on a corner.
    dedup: List[List[float]] = []
    for p in out:
        if not dedup or p != dedup[-1]:
            dedup.append(p)
    if len(dedup) >= 2 and dedup[0] == dedup[-1]:
        dedup = dedup[:-1]
    return dedup


def _load_obstacles(geo_rows: Sequence[dict]) -> List[Obstacle]:
    out: List[Obstacle] = []
    for g in geo_rows:
        pts = g.get("points") or []
        if len(pts) < 3:
            continue
        out.append(Obstacle(int(g["id"]), [(float(p[0]), float(p[1])) for p in pts]))
    return out


def fit_gaps(geo_rows: Sequence[dict], mask) -> List[dict]:
    obstacles = _load_obstacles(geo_rows)
    placed: List[dict] = []
    sizes = ((0.05, 0.04), (0.08, 0.06), (0.16, 0.12), (0.24, 0.18), (0.34, 0.26), (0.48, 0.36))
    extras = [(0.0, 0.0, 0.0, 0.0)]
    for step in (0.2, 0.45, 0.8):
        extras.extend(
            (
                (step, 0.0, 0.0, 0.0),
                (0.0, step, 0.0, 0.0),
                (0.0, 0.0, step, 0.0),
                (0.0, 0.0, 0.0, step),
            )
        )
    for spec in GAPS:
        targets = _nearest_vertices(spec.lon, spec.lat, obstacles, k=4)
        if not targets:
            raise SystemExit("no neighbor vertex for %s" % spec.name)
        best = None
        for hw, hh in sizes:
            for west, south, east, north in extras:
                rect = (
                    spec.lon - hw - west,
                    spec.lat - hh - south,
                    spec.lon + hw + east,
                    spec.lat + hh + north,
                )
                if overlaps(rect, obstacles):
                    continue
                anchor = _land_anchor(rect, spec.lon, spec.lat, mask)
                if anchor is None:
                    continue
                for dist0, tgt, pid in targets[:3]:
                    stretched = _stretch(rect, tgt, obstacles, spec.lon, spec.lat)
                    if overlaps(stretched, obstacles):
                        continue
                    anchor2 = _land_anchor(stretched, spec.lon, spec.lat, mask)
                    if anchor2 is None:
                        continue
                    box = _rect_canvas(stretched)
                    dist = _dist_point_rect(tgt[0], tgt[1], box)
                    area = (stretched[2] - stretched[0]) * (stretched[3] - stretched[1])
                    rank = (0 if dist <= NEAR_PX else 1, dist, area)
                    row = {
                        "spec": spec,
                        "rect": stretched,
                        "anchor": anchor2,
                        "touch_px": dist,
                        "near_pid": pid,
                        "target": tgt,
                        "rank": rank,
                    }
                    if best is None or rank < best["rank"]:
                        best = row
                    if dist <= TOUCH_PX and area < 0.2:
                        break
                if best is not None and best["touch_px"] <= TOUCH_PX and best["rank"][2] < 0.2:
                    break
            if best is not None and best["touch_px"] <= TOUCH_PX:
                break
        if best is None:
            escaped = _escape_triangle(spec, obstacles, mask)
            if escaped is None:
                raise SystemExit("could not place %s (%s) without overlap" % (spec.pid, spec.name))
            obstacles.append(Obstacle(spec.pid, [(p[0], p[1]) for p in escaped["points"]]))
            placed.append(escaped)
            print(
                "fit %s %s wedge touch=%.1fpx near=%s anchor=%s"
                % (spec.pid, spec.name, escaped["touch_px"], escaped["near_pid"], escaped["anchor"])
            )
            continue
        ring = _ring_points(best["rect"], best["target"])
        cx, cy = lonlat_to_canvas(spec.lon, spec.lat)
        if not _point_in_poly(cx, cy, [(p[0], p[1]) for p in ring]):
            raise SystemExit("%s ring missed its city" % spec.pid)
        obstacles.append(Obstacle(spec.pid, [(p[0], p[1]) for p in ring]))
        best["points"] = ring
        placed.append(best)
        print(
            "fit %s %s touch=%.1fpx near=%s anchor=%s"
            % (spec.pid, spec.name, best["touch_px"], best["near_pid"], best["anchor"])
        )
    return placed


def _neighbors(placed: Sequence[dict], obstacles: Sequence[Obstacle]) -> Dict[int, List[int]]:
    by_id = {ob.pid: ob for ob in obstacles}
    out: Dict[int, List[int]] = {}
    for row in placed:
        spec: GapSpec = row["spec"]
        me = by_id[spec.pid]
        samples: List[Point] = list(me.pts)
        # Edge samples so a long side still counts as a near-vertex touch.
        for i in range(len(me.pts)):
            ax, ay = me.pts[i]
            bx, by = me.pts[(i + 1) % len(me.pts)]
            steps = max(1, int((((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5) / 8.0))
            for s in range(1, steps):
                t = s / steps
                samples.append((ax + (bx - ax) * t, ay + (by - ay) * t))
        nbrs = set()
        for ob in obstacles:
            if ob.pid == spec.pid:
                continue
            if not ob.bbox_hits(me.xmin, me.ymin, me.xmax, me.ymax, pad=NEAR_PX + 1.0):
                continue
            hit = False
            for sx, sy in samples:
                if sx < ob.xmin - NEAR_PX or sx > ob.xmax + NEAR_PX or sy < ob.ymin - NEAR_PX or sy > ob.ymax + NEAR_PX:
                    continue
                for px, py in ob.pts:
                    if (px - sx) ** 2 + (py - sy) ** 2 <= NEAR_PX * NEAR_PX:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                nbrs.add(ob.pid)
        if not nbrs:
            nbrs.add(int(row["near_pid"]))
        out[spec.pid] = sorted(nbrs)
    return out


def _prove_adjacency_roundtrip(path: Path) -> None:
    raw = path.read_text(encoding="utf-8")
    fixed = _fix_adj_tail(_dump(json.loads(raw)))
    if fixed != raw:
        raise SystemExit("adjacency dump is not brace-stable; refusing to rewrite")


def _fix_adj_tail(text: str) -> str:
    suffix = "  }\n}\n"
    if text.endswith(suffix):
        return text[: -len(suffix)] + "}\n}\n"
    return text


def _already_applied(base_ids: set, owners_1945: dict, base_rows: Sequence[dict]) -> bool:
    if any(g.pid not in base_ids for g in GAPS):
        return False
    pl = [int(p["id"]) for p in base_rows if str(p.get("cntr_code") or "").upper() == "PL"]
    return all(owners_1945.get(str(pid)) == "POL" for pid in pl)


def _write_flags() -> None:
    from PIL import Image, ImageDraw

    FLAG_DIR.mkdir(parents=True, exist_ok=True)
    ignore = FLAG_DIR / ".gdignore"
    if not ignore.is_file():
        ignore.write_text("# Placeholder flags. Not imported as Godot resources.\n", encoding="utf-8")

    def save(name: str, img: Image.Image) -> None:
        img.save(FLAG_DIR / name, format="PNG")

    ukr = Image.new("RGB", (48, 32), "#005BBB")
    draw = ImageDraw.Draw(ukr)
    draw.rectangle((0, 16, 48, 32), fill="#FFD500")
    save("ukr.png", ukr)

    mda = Image.new("RGB", (48, 32), "#003DA5")
    draw = ImageDraw.Draw(mda)
    draw.rectangle((16, 0, 32, 32), fill="#FFD100")
    draw.rectangle((32, 0, 48, 32), fill="#CC0000")
    save("mda.png", mda)

    prc = Image.new("RGB", (48, 32), "#DE2910")
    draw = ImageDraw.Draw(prc)
    draw.rectangle((4, 4, 16, 14), fill="#FFDE00")
    save("prc.png", prc)

    man = Image.new("RGB", (48, 32), "#FFDE00")
    draw = ImageDraw.Draw(man)
    draw.rectangle((0, 0, 16, 14), fill="#C8102E")
    save("man.png", man)


def _base_row(spec: GapSpec) -> dict:
    owner_1936 = spec.owner(1936)
    lon_span = 0.4
    lat_span = 0.3
    area = abs(lon_span * lat_span) * (111.0 ** 2) * 0.7
    return {
        "id": spec.pid,
        "name": spec.name,
        "terrain": "plains",
        "domain": "land",
        "core_for_tags": [owner_1936] if owner_1936 not in NEW_TAGS else [],
        "natural_resources": {},
        "population_base": 0,
        "meta": {
            "source": "nation_tags1",
            "adm0_a3": spec.adm0,
            "admin": spec.adm0,
            "level": "GAP",
            "area": round(area, 1),
        },
    }


def _format_base_row(row: dict) -> str:
    body = json.dumps(row, indent=2, ensure_ascii=False)
    return "\n".join("    " + line for line in body.split("\n"))


def _append_base(raw: str, rows: Sequence[dict]) -> str:
    suffix = "\n  ]\n}\n"
    if not raw.endswith(suffix):
        raise SystemExit("provinces_base.json tail is not the expected array close")
    block = ",\n" + ",\n".join(_format_base_row(r) for r in rows)
    return raw[: -len(suffix)] + block + suffix


def _append_geometry(raw: str, placed: Sequence[dict]) -> str:
    j = raw.rfind('],"meta":')
    if j < 0 or raw[j] != "]":
        raise SystemExit("geometry junction not found")
    chunks = []
    for row in placed:
        spec: GapSpec = row["spec"]
        obj = {
            "id": spec.pid,
            "points": row["points"],
            "label_anchor": row["anchor"],
            "meta": {"source": "nation_tags1", "adm0_a3": spec.adm0, "level": "GAP"},
        }
        chunks.append(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))
    return raw[:j] + "," + ",".join(chunks) + raw[j:]


def _append_cities(raw: str, specs: Sequence[GapSpec]) -> str:
    needle = '\n  },\n  "meta": {\n    "source": "polish_capital_layers_v1_4"'
    idx = raw.find(needle)
    if idx < 0:
        raise SystemExit("city layer meta junction not found")
    parts = []
    for spec in specs:
        parts.append(
            '    "%s": {\n      "city_name": %s,\n      "tier": 2\n    }'
            % (spec.pid, json.dumps(spec.name, ensure_ascii=False))
        )
    return raw[:idx] + ",\n" + ",\n".join(parts) + raw[idx:]


def _insert_state_ids(raw: str, state_id: int, pids: Sequence[int]) -> str:
    marker = '"id": %s,' % state_id
    i = raw.find(marker)
    if i < 0:
        raise SystemExit("state %s not found" % state_id)
    j = raw.find('"province_ids": [', i)
    k = raw.find("\n      ]", j)
    if j < 0 or k < 0:
        raise SystemExit("state %s province_ids close not found" % state_id)
    window = raw[j:k]
    add = [pid for pid in pids if str(pid) not in window]
    if not add:
        return raw
    extra = "".join(",\n        %s" % pid for pid in add)
    return raw[:k] + extra + raw[k:]


def _backup(paths: Sequence[Path], dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for p in paths:
        target = dest / p.name
        # Membership files share no name collision; prefix with parent-relative.
        rel = p.relative_to(BOARD) if str(p).startswith(str(BOARD)) else Path(p.name)
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)


def _restore(dest: Path) -> None:
    for p in dest.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(dest)
        shutil.copy2(p, BOARD / rel)


def apply_board(placed: Sequence[dict]) -> None:
    base_path = BOARD / "provinces_base.json"
    geo_path = BOARD / "provinces_geometry.json"
    adj_path = BOARD / "province_adjacency.json"
    city_path = BOARD / "province_city_layer.json"
    state_path = BOARD / "province_states.json"
    region_path = BOARD / "strategic_regions.json"
    scaffold_path = BOARD / "hierarchy_scaffold.json"
    manifest_path = BOARD / "manifest_world_accurate.json"
    own_paths = [BOARD / ("province_ownership_%s.json" % y) for y in ERA_YEARS]
    mem_paths = [BOARD / ("hierarchy_membership_%s.json" % y) for y in ERA_YEARS]
    layer_paths = [
        BOARD / "province_terrain_layer.json",
        BOARD / "province_economy_layer.json",
        BOARD / "province_resources_layer.json",
    ]
    touched = [
        base_path,
        geo_path,
        adj_path,
        city_path,
        state_path,
        region_path,
        scaffold_path,
        manifest_path,
        *own_paths,
        *mem_paths,
        *layer_paths,
    ]
    backup = Path("/tmp/nation_tags1_apply_backup")
    _backup(touched, backup)
    try:
        _prove_adjacency_roundtrip(adj_path)
        base_raw = base_path.read_text(encoding="utf-8")
        rows = [_base_row(row["spec"]) for row in placed]
        base_path.write_text(_append_base(base_raw, rows), encoding="utf-8")

        geo_raw = geo_path.read_text(encoding="utf-8")
        geo_path.write_text(_append_geometry(geo_raw, placed), encoding="utf-8")

        city_raw = city_path.read_text(encoding="utf-8")
        city_path.write_text(_append_cities(city_raw, [row["spec"] for row in placed]), encoding="utf-8")

        state_raw = state_path.read_text(encoding="utf-8")
        by_state: Dict[int, List[int]] = {}
        for row in placed:
            by_state.setdefault(row["spec"].state_id, []).append(row["spec"].pid)
        for sid, pids in by_state.items():
            state_raw = _insert_state_ids(state_raw, sid, pids)
        json.loads(state_raw)
        state_path.write_text(state_raw, encoding="utf-8")

        regions = _load(region_path)
        by_region: Dict[int, List[int]] = {}
        for row in placed:
            by_region.setdefault(row["spec"].region_id, []).append(row["spec"].pid)
        for region in regions["regions"]:
            extra = by_region.get(int(region["id"]))
            if not extra:
                continue
            have = set(int(x) for x in region["province_ids"])
            for pid in extra:
                if pid not in have:
                    region["province_ids"].append(pid)
            if "province_count" in region:
                region["province_count"] = int(region["province_count"]) + len(extra)
        region_path.write_text(_dump(regions), encoding="utf-8")

        geo_rows = _load(geo_path)["provinces"]
        obstacles = _load_obstacles(geo_rows)
        nbrs = _neighbors(placed, obstacles)
        adj_doc = _load(adj_path)
        adjacency = adj_doc["adjacency"]
        for pid, links in nbrs.items():
            adjacency[str(pid)] = links
            for other in links:
                key = str(other)
                cur = adjacency.get(key)
                if cur is None:
                    adjacency[key] = [pid]
                elif pid not in [int(x) for x in cur]:
                    cur.append(pid)
        adj_doc["stats"]["province_n"] = int(adj_doc["stats"]["province_n"]) + GAP_N
        adj_doc["stats"]["land_n"] = int(adj_doc["stats"]["land_n"]) + GAP_N
        adj_path.write_text(_fix_adj_tail(_dump(adj_doc)), encoding="utf-8")

        base_rows = _load(base_path)["provinces"]
        pl_ids = {str(int(p["id"])) for p in base_rows if str(p.get("cntr_code") or "").upper() == "PL"}
        for year, path in zip(ERA_YEARS, own_paths):
            doc = _load(path)
            owners = doc["owners"]
            if year == 1945:
                for pid in pl_ids:
                    owners[pid] = "POL"
            for row in placed:
                spec = row["spec"]
                owners[str(spec.pid)] = spec.owner(year)
            path.write_text(_dump(doc), encoding="utf-8")

        for path in mem_paths:
            doc = _load(path)
            for row in placed:
                spec = row["spec"]
                key = str(spec.pid)
                doc["province_to_region"][key] = spec.region_id
                doc["province_to_state"][key] = spec.state_id
                doc["province_to_super_region"][key] = spec.super_id
            path.write_text(_dump(doc), encoding="utf-8")

        scaffold = _load(scaffold_path)
        for row in placed:
            spec = row["spec"]
            key = str(spec.pid)
            scaffold["province_to_region"][key] = spec.region_id
            scaffold["province_to_state"][key] = spec.state_id
            scaffold["province_to_super_region"][key] = spec.super_id
        if int(scaffold.get("province_n") or 0) != 3520 or int(scaffold.get("land_n") or 0) != 3180:
            raise SystemExit("refusing to rewrite scaffold scalars")
        scaffold_path.write_text(_dump(scaffold), encoding="utf-8")

        terrain = _load(layer_paths[0])
        economy = _load(layer_paths[1])
        resources = _load(layer_paths[2])
        for row in placed:
            key = str(row["spec"].pid)
            terrain["provinces"][key] = {"terrain": "plains", "domain": "land"}
            economy["provinces"][key] = {
                "population": 0,
                "factories": 0,
                "infrastructure": 1,
                "development_level": 1,
            }
            resources["provinces"][key] = {"coal": 0, "steel": 0}
        layer_paths[0].write_text(_dump(terrain), encoding="utf-8")
        layer_paths[1].write_text(_dump(economy), encoding="utf-8")
        layer_paths[2].write_text(_dump(resources), encoding="utf-8")

        manifest_raw = manifest_path.read_text(encoding="utf-8")
        if "v1_nation_tags1_gaps" not in manifest_raw:
            manifest_raw = manifest_raw.replace('"provinces": 3536', '"provinces": %s' % BOARD_N_AFTER, 1)
            manifest_raw = manifest_raw.replace(
                '"land": 3196',
                '"land": %s' % LAND_N_AFTER,
                1,
            )
            manifest_raw = manifest_raw.replace(
                "v1_se_england_shire_land_uniform",
                "v1_se_england_shire_land_uniform+v1_nation_tags1_gaps",
                1,
            )
            json.loads(manifest_raw)
            manifest_path.write_text(manifest_raw, encoding="utf-8")

        CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        CATALOG_PATH.write_text(_dump(catalog_document()), encoding="utf-8")
        _write_flags()

        base_ids = {int(p["id"]) for p in _load(base_path)["provinces"]}
        if PRIOR_MAX_LAND_ID not in base_ids or len(base_ids) != BOARD_N_AFTER:
            raise SystemExit("board count after append is %s" % len(base_ids))
        report = audit(BOARD)
        if not report["ok"]:
            raise SystemExit("audit failed after write:\n" + "\n".join(report["failures"]))
    except BaseException:
        _restore(backup)
        raise
    shutil.rmtree(backup, ignore_errors=True)
    print("applied %s gap provinces; board %s" % (GAP_N, BOARD_N_AFTER))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    base_rows = _load(BOARD / "provinces_base.json")["provinces"]
    base_ids = {int(p["id"]) for p in base_rows}
    owners_1945 = _load(BOARD / "province_ownership_1945.json")["owners"]
    if _already_applied(base_ids, owners_1945, base_rows):
        print("nation-tags-1 already applied")
        report = audit(BOARD)
        if not report["ok"]:
            print("\n".join(report["failures"]))
            return 1
        return 0
    if any(g.pid in base_ids for g in GAPS):
        raise SystemExit("partial gap ids already present; refusing to append")
    print("loading Natural Earth land mask")
    mask = rasterize_land_mask(load_ne_land_features(Path(DEFAULT_NE_LAND)), width=2048, height=1024)
    geo_rows = _load(BOARD / "provinces_geometry.json")["provinces"]
    # Cities must still be holes. A covered city would renumber nothing but paint over land.
    obstacles = _load_obstacles(geo_rows)
    for spec in GAPS:
        x, y = lonlat_to_canvas(spec.lon, spec.lat)
        for ob in obstacles:
            if not ob.bbox_hits(x, y, x, y, pad=0.0):
                continue
            if _point_in_poly(x, y, ob.pts):
                raise SystemExit("%s %s is already inside %s" % (spec.pid, spec.name, ob.pid))
    placed = fit_gaps(geo_rows, mask)
    if len(placed) != GAP_N:
        raise SystemExit("placed %s" % len(placed))
    if args.dry_run:
        print("dry-run ok, %s rings" % len(placed))
        return 0
    apply_board(placed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
