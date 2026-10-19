#!/usr/bin/env python3
"""GAP-IBS: add Iwo Jima, the Bonin Islands, and Saipan, plus two seas.

Geometry is Natural Earth 10m land already in the repo. Admin-1 is not in
the repo. The islands are a few pixels wide, so each Natural Earth ring
becomes an 8 px display cell (still inside the renderer's tiny-inflation
band) centered on that ring's area centroid. A group is one open ring with
a there-and-back bridge. The label anchor is the largest ring's centroid,
which is what the NE land check samples.

Boxes (vertex-mean centroid), counted in this repo's NE file:

  140.9–141.8 E, 24.0–25.8 N   Kita-Iwo, Iwo Jima, Minami-Iwo   905852
  141.9–142.5 E, 26.4–27.9 N   Haha-jima, Chichi-jima, Mukojima 905853
  145.70–145.85 E, 15.10–15.30 N   Saipan                        905854

Nishinoshima (140.87 E, 27.25 N) is outside the Bonin box and stays unowned
by these provinces. Rota and Tinian are not Saipan and are not provinces.

950341 Volcano–Bonin Waters is the rectangle
(140.70, 147.60, 24.00, 29.50). It is subtracted from WestPac 950046 and
950048. Both parents are kept. The clip always starts from
tools/map_generation/fixtures/gap_ibs_parent_seas.json (the rings before
this slice), so a second run is a fixed point. 950342 Marianas Waters is
(144.35, 146.45, 13.72, 16.60), just north of Guam 902485.

Owners use tags that already exist. There is no occupation tag and no
Tokyo / Ogasawara / South Seas Mandate / CNMI state, so the three land
provinces sit in state 339 (JPN) and the seas follow the island they serve.
Those choices are UNKNOWN in the slice report. Populations stay 0.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"
NE_LAND = (
    ROOT
    / "tools"
    / "map_generation"
    / "data"
    / "cache"
    / "map_tiles"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_land.geojson"
)
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gap_ibs_parent_seas.json"

IWO = 905852
BONIN = 905853
SAIPAN = 905854
VOLCANO = 950341
MARIANAS = 950342
GUAM = 902485
POHNPEI = 902474
PARENTS = (950046, 950048)
LAND_IDS = (IWO, BONIN, SAIPAN)
NEW_IDS = (IWO, BONIN, SAIPAN, VOLCANO, MARIANAS)
# GAP_IBS_ERAS
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)

# year -> pid -> tag. Seas follow the island they were carved for.
OWNERS = {
    1910: {IWO: "JAP", BONIN: "JAP", SAIPAN: "GER", VOLCANO: "JAP", MARIANAS: "GER"},
    1918: {IWO: "JAP", BONIN: "JAP", SAIPAN: "JAP", VOLCANO: "JAP", MARIANAS: "JAP"},
    1936: {IWO: "JAP", BONIN: "JAP", SAIPAN: "JAP", VOLCANO: "JAP", MARIANAS: "JAP"},
    1945: {IWO: "USA", BONIN: "USA", SAIPAN: "USA", VOLCANO: "USA", MARIANAS: "USA"},
    2026: {IWO: "JAP", BONIN: "JAP", SAIPAN: "USA", VOLCANO: "JAP", MARIANAS: "USA"},
}

# One direction. _mirror_pairs writes the reverse.
LINKS = (
    (IWO, VOLCANO),
    (BONIN, VOLCANO),
    (SAIPAN, MARIANAS),
    (VOLCANO, 950046),
    (VOLCANO, 950048),
    (GUAM, MARIANAS),
)

# (west, east, south, north) in degrees.
VOLCANO_RECT = (140.70, 147.60, 24.00, 29.50)
MARIANAS_RECT = (144.35, 146.45, 13.72, 16.60)
# (west, east, south, north, pid) for the NE centroid filter.
ISLAND_BOXES = (
    (140.9, 141.8, 24.0, 25.8, IWO),
    (141.9, 142.5, 26.4, 27.9, BONIN),
    (145.70, 145.85, 15.10, 15.30, SAIPAN),
)
EXPECTED_RINGS = {IWO: 3, BONIN: 9, SAIPAN: 1}

STATE_JPN = 339
REGION_EAST_ASIA = 7
SUPER_EAST_ASIA = 3
REGION_OCEANS = 10
SUPER_OCEANS = 4

W_PX = 8192.0
H_PX = 4096.0
CELL_RADIUS_PX = 8.0
CELL_SIDES = 16
KM_PER_DEG = 111.32

Point = Tuple[float, float]
Ring = List[Point]


def emit_existing_id(pid: int) -> int:
    return int(pid)  # GAP_IBS_PID identity


def use_shrunk_parents() -> bool:
    return True  # GAP_IBS_SHRINK


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _dumps(doc: Any) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _lonlat_to_canvas(lon: float, lat: float) -> Point:
    x = (lon - (-180.0)) / 360.0 * W_PX
    y = (lat - 83.0) / (-139.0) * H_PX
    return (x, y)


def _canvas_to_lonlat(x: float, y: float) -> Point:
    lon = -180.0 + (x / W_PX) * 360.0
    lat = 83.0 + (y / H_PX) * (-139.0)
    return (lon, lat)


def _ring_area(ring: Sequence[Point]) -> float:
    area = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return area / 2.0


def _area_centroid(ring: Sequence[Point]) -> Point:
    acc_a = 0.0
    cx = 0.0
    cy = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        acc_a += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if abs(acc_a) < 1e-18:
        return (sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n)
    return (cx / (3.0 * acc_a), cy / (3.0 * acc_a))


def _area_m2(ring: Sequence[Point]) -> float:
    if not ring:
        return 0.0
    lat0 = sum(p[1] for p in ring) / len(ring)
    mx = KM_PER_DEG * 1000.0 * math.cos(math.radians(lat0))
    my = KM_PER_DEG * 1000.0
    pts = [(p[0] * mx, p[1] * my) for p in ring]
    return abs(_ring_area(pts))


def _open_ring(ring: Sequence[Point]) -> List[Point]:
    out = [(float(p[0]), float(p[1])) for p in ring]
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    return out


def _ensure_ccw(ring: Sequence[Point]) -> List[Point]:
    out = _open_ring(ring)
    if _ring_area(out) < 0:
        out.reverse()
    return out


def _dedupe(ring: Sequence[Point]) -> List[Point]:
    cleaned: List[Point] = []
    for p in ring:
        if not cleaned or abs(p[0] - cleaned[-1][0]) > 1e-9 or abs(p[1] - cleaned[-1][1]) > 1e-9:
            cleaned.append((float(p[0]), float(p[1])))
    if len(cleaned) > 1 and abs(cleaned[0][0] - cleaned[-1][0]) < 1e-9 and abs(cleaned[0][1] - cleaned[-1][1]) < 1e-9:
        cleaned.pop()
    return cleaned


def bridge_rings(rings: Sequence[Sequence[Point]]) -> List[Point]:
    """One open ring. Extra parts join by a there-and-back bridge."""
    parts = [_ensure_ccw(r) for r in rings if len(r) >= 3]
    parts.sort(key=lambda r: (-abs(_ring_area(r)), r[0][0], r[0][1]))
    if not parts:
        return []
    acc = list(parts[0])
    for nxt in parts[1:]:
        best: Optional[float] = None
        bi = bj = 0
        for i, p in enumerate(acc):
            for j, q in enumerate(nxt):
                dist = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
                if best is None or dist < best:
                    best = dist
                    bi, bj = i, j
        rotated = nxt[bj:] + nxt[:bj]
        acc = acc[: bi + 1] + rotated + [rotated[0], acc[bi]] + acc[bi + 1 :]
    return [(round(p[0], 6), round(p[1], 6)) for p in _open_ring(acc)]


def _clip_plane(
    poly: Sequence[Point],
    inside: Callable[[Point], bool],
    inter: Callable[[Point, Point], Point],
) -> List[Point]:
    if not poly:
        return []
    out: List[Point] = []
    prev = poly[-1]
    prev_in = inside(prev)
    for cur in poly:
        cur_in = inside(cur)
        if cur_in:
            if not prev_in:
                out.append(inter(prev, cur))
            out.append(cur)
        elif prev_in:
            out.append(inter(prev, cur))
        prev, prev_in = cur, cur_in
    return _dedupe(out)


def _inter_x(a: Point, b: Point, x: float) -> Point:
    den = b[0] - a[0]
    t = 0.0 if abs(den) < 1e-15 else (x - a[0]) / den
    return (x, a[1] + t * (b[1] - a[1]))


def _inter_y(a: Point, b: Point, y: float) -> Point:
    den = b[1] - a[1]
    t = 0.0 if abs(den) < 1e-15 else (y - a[1]) / den
    return (a[0] + t * (b[0] - a[0]), y)


def clip_to_rect(poly: Sequence[Point], rect: Sequence[float]) -> List[Point]:
    """Sutherland–Hodgman intersection with an axis-aligned lon/lat rect."""
    west, east, south, north = rect
    p = _clip_plane(list(poly), lambda q: q[0] >= west, lambda a, b: _inter_x(a, b, west))
    p = _clip_plane(p, lambda q: q[0] <= east, lambda a, b: _inter_x(a, b, east))
    p = _clip_plane(p, lambda q: q[1] >= south, lambda a, b: _inter_y(a, b, south))
    p = _clip_plane(p, lambda q: q[1] <= north, lambda a, b: _inter_y(a, b, north))
    return p


def outside_rect_parts(poly: Sequence[Point], rect: Sequence[float]) -> List[List[Point]]:
    """Polygon minus rect, as up to four strips. A convex window partitions the complement."""
    west, east, south, north = rect
    left = _clip_plane(list(poly), lambda q: q[0] <= west, lambda a, b: _inter_x(a, b, west))
    right = _clip_plane(list(poly), lambda q: q[0] >= east, lambda a, b: _inter_x(a, b, east))
    slab = _clip_plane(list(poly), lambda q: q[0] >= west, lambda a, b: _inter_x(a, b, west))
    slab = _clip_plane(slab, lambda q: q[0] <= east, lambda a, b: _inter_x(a, b, east))
    bottom = _clip_plane(slab, lambda q: q[1] <= south, lambda a, b: _inter_y(a, b, south))
    top = _clip_plane(slab, lambda q: q[1] >= north, lambda a, b: _inter_y(a, b, north))
    parts: List[List[Point]] = []
    for part in (left, right, bottom, top):
        if len(part) >= 3 and abs(_ring_area(part)) > 1e-8:
            parts.append(part)
    return parts


def _rect_ring(rect: Sequence[float], steps: int = 12) -> List[Point]:
    west, east, south, north = rect
    corners = [(west, north), (east, north), (east, south), (west, south)]
    pts: List[Point] = []
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        for step in range(steps):
            t = step / steps
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts


def _cell(cx: float, cy: float) -> List[Point]:
    pts: List[Point] = []
    for i in range(CELL_SIDES):
        ang = 2.0 * math.pi * i / CELL_SIDES
        pts.append((cx + CELL_RADIUS_PX * math.cos(ang), cy + CELL_RADIUS_PX * math.sin(ang)))
    return pts


def _round_ring(ring: Sequence[Point]) -> List[List[float]]:
    return [[round(p[0], 6), round(p[1], 6)] for p in ring]


def _exterior_rings(geom: Mapping[str, Any]) -> List[Ring]:
    kind = geom.get("type")
    coords = geom.get("coordinates") or []
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


def _box_for(lon: float, lat: float) -> int:
    for west, east, south, north, pid in ISLAND_BOXES:
        if west <= lon <= east and south <= lat <= north:
            return pid
    return 0


def load_island_groups(path: Path = NE_LAND) -> Dict[int, List[Ring]]:
    doc = _load(path)
    groups: Dict[int, List[Ring]] = {IWO: [], BONIN: [], SAIPAN: []}
    for feat in doc.get("features") or []:
        for ring in _exterior_rings(feat.get("geometry") or {}):
            if len(ring) < 4:
                continue
            lon = sum(p[0] for p in ring) / len(ring)
            lat = sum(p[1] for p in ring) / len(ring)
            gid = _box_for(lon, lat)
            if gid:
                groups[gid].append([(float(p[0]), float(p[1])) for p in ring])
    for pid, expect in EXPECTED_RINGS.items():
        got = len(groups[pid])
        if got != expect:
            raise SystemExit("NE ring count for %d is %d, expected %d" % (pid, got, expect))
    return groups


def _canvas_from_ll(ring: Sequence[Point]) -> List[Point]:
    return [_lonlat_to_canvas(lon, lat) for lon, lat in ring]


_LAND_MASK = None


def _snap_land_anchor(ax: float, ay: float) -> Point:
    """Move a sub-pixel centroid onto the NE mask pixel it belongs to.

    The 2048x1024 check rounds canvas coordinates. Iwo and the Bonins are
    smaller than that pixel, so the true centroid can fall in the gap beside
    a lit pixel. A snap farther than 4 canvas px is rejected.
    """
    global _LAND_MASK
    if _LAND_MASK is None:
        lib = str(ROOT / "tools" / "map_generation" / "lib")
        if lib not in sys.path:
            sys.path.insert(0, lib)
        from ne_full_geometry_align import load_ne_land_features, rasterize_land_mask

        _LAND_MASK = rasterize_land_mask(
            load_ne_land_features(NE_LAND), width=2048, height=1024
        )
    from ne_full_geometry_align import nearest_mask_pixel, sample_mask

    if sample_mask(_LAND_MASK, ax, ay):
        return (round(ax, 6), round(ay, 6))
    nx, ny = nearest_mask_pixel(_LAND_MASK, ax, ay, want_land=True, max_radius=2)
    if (nx - ax) ** 2 + (ny - ay) ** 2 > 16.0:
        return (round(ax, 6), round(ay, 6))
    return (round(nx, 6), round(ny, 6))


def build_land_geometry(groups: Mapping[int, Sequence[Ring]]) -> Dict[int, dict]:
    names = {IWO: "Iwo Jima", BONIN: "Bonin Islands", SAIPAN: "Saipan"}
    out: Dict[int, dict] = {}
    for pid, rings in groups.items():
        sized = sorted(rings, key=lambda r: -_area_m2(r))
        cells = []
        for ring in sized:
            ll = [(float(p[0]), float(p[1])) for p in ring]
            ax, ay = _area_centroid(_canvas_from_ll(ll))
            cells.append(_cell(ax, ay))
        bridged = bridge_rings(cells)
        anchor_ll = [(float(p[0]), float(p[1])) for p in sized[0]]
        ax, ay = _area_centroid(_canvas_from_ll(anchor_ll))
        sx, sy = _snap_land_anchor(ax, ay)
        out[pid] = {
            "id": pid,
            "points": _round_ring(bridged),
            "label_anchor": [sx, sy],
            "meta": {
                "source": "ne_10m_land",
                "gap_ibs": names[pid],
                "ne_ring_n": len(rings),
                "display_cell_px": CELL_RADIUS_PX,
            },
        }
    return out


def build_sea_geometry() -> Dict[int, dict]:
    names = {VOLCANO: "Volcano-Bonin Waters", MARIANAS: "Marianas Waters"}
    rects = {VOLCANO: VOLCANO_RECT, MARIANAS: MARIANAS_RECT}
    out: Dict[int, dict] = {}
    for pid, rect in rects.items():
        canvas = _ensure_ccw(_canvas_from_ll(_rect_ring(rect)))
        ax, ay = _area_centroid(canvas)
        west, east, south, north = rect
        out[pid] = {
            "id": pid,
            "points": _round_ring(canvas),
            "label_anchor": [round(ax, 6), round(ay, 6)],
            "meta": {
                "source": "ne_10m_land",
                "gap_ibs": names[pid],
                "gis_ne_domain": "water",
                "rect": [west, east, south, north],
            },
        }
    return out


def _fixture_ll() -> Dict[int, List[Point]]:
    doc = _load(FIXTURE)
    out: Dict[int, List[Point]] = {}
    for key, ring in (doc.get("rings") or {}).items():
        out[int(key)] = [_canvas_to_lonlat(float(p[0]), float(p[1])) for p in ring]
    return out


def shrunk_parent_rings() -> Dict[int, dict]:
    """Clip the fixture rings. Returns id -> {points, label_anchor, removed_deg2, kept_deg2}."""
    out: Dict[int, dict] = {}
    shrink = use_shrunk_parents()
    for pid, ring in _fixture_ll().items():
        original = abs(_ring_area(ring))
        if shrink:
            parts = outside_rect_parts(ring, VOLCANO_RECT)
            inter = clip_to_rect(ring, VOLCANO_RECT)
            removed = abs(_ring_area(inter)) if len(inter) >= 3 else 0.0
            kept = sum(abs(_ring_area(p)) for p in parts)
            if not parts:
                raise SystemExit("GAP-IBS shrink produced an empty ring for %d" % pid)
            if abs((kept + removed) - original) > 1e-4:
                raise SystemExit(
                    "GAP-IBS shrink did not conserve area for %d (kept %s removed %s original %s)"
                    % (pid, kept, removed, original)
                )
            if removed < 0.05:
                raise SystemExit("GAP-IBS shrink missed %d (removed %s)" % (pid, removed))
            canvas_parts = [_canvas_from_ll(p) for p in parts]
            canvas = bridge_rings(canvas_parts) if len(canvas_parts) > 1 else _round_ring(_ensure_ccw(canvas_parts[0]))
            if len(canvas_parts) == 1:
                canvas = [[round(p[0], 6), round(p[1], 6)] for p in _ensure_ccw(canvas_parts[0])]
        else:
            # Mutant (d): put the unshrunk fixture rings back.
            canvas = [[round(p[0], 6), round(p[1], 6)] for p in _canvas_from_ll(ring)]
            removed = 0.0
            kept = original
        anchor = _area_centroid([(float(p[0]), float(p[1])) for p in canvas])
        out[pid] = {
            "points": canvas if isinstance(canvas[0], list) else _round_ring(canvas),
            "label_anchor": [round(anchor[0], 6), round(anchor[1], 6)],
            "removed_deg2": round(removed, 6),
            "kept_deg2": round(kept, 6),
        }
    return out


def _mirror_pairs(adj: Dict[str, List[int]]) -> None:
    pending: List[Tuple[str, int]] = []
    for src, nbs in adj.items():
        for dst in nbs:
            key = str(int(dst))
            if key not in adj:
                continue
            if int(src) not in adj[key]:
                pending.append((key, int(src)))
    for key, dst in pending:
        adj[key].append(dst)
    for key in adj:
        adj[key] = sorted(set(int(x) for x in adj[key]))


def _link(adj: Dict[str, List[int]], a: int, b: int) -> None:
    nbs = adj.setdefault(str(int(a)), [])
    dst = int(b)
    if dst not in [int(x) for x in nbs]:
        nbs.append(dst)


def _unlink(adj: Dict[str, List[int]], a: int, b: int) -> None:
    for src, dst in ((a, b), (b, a)):
        key = str(src)
        if key in adj:
            adj[key] = [x for x in adj[key] if int(x) != dst]


def build_adjacency(adj: Dict[str, List[int]]) -> None:
    for pid in NEW_IDS:
        adj.setdefault(str(pid), [])
    for a, b in LINKS:
        _unlink(adj, a, b)
    for a, b in LINKS:
        _link(adj, a, b)
    if any(emit_existing_id(int(k)) != int(k) for k in list(adj)):
        remapped: Dict[str, List[int]] = {}
        for key, nbs in adj.items():
            nk = str(emit_existing_id(int(key)))
            remapped.setdefault(nk, [])
            remapped[nk].extend(emit_existing_id(int(b)) for b in nbs)
        adj.clear()
        adj.update({k: sorted(set(remapped[k])) for k in remapped})
    _mirror_pairs(adj)  # GAP_IBS_MIRROR_CALL


def _pretty_base(obj: Mapping[str, Any]) -> str:
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    return "\n".join("    " + line for line in text.splitlines())


def _span(text: str, needle: str) -> Tuple[int, int]:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit("missing %s" % needle)
    brace = text.rfind("{", 0, idx)
    _obj, end = json.JSONDecoder().raw_decode(text, brace)
    line = text.rfind("\n", 0, brace) + 1
    if text[line:brace].strip() == "":
        return line, end
    return brace, end


def _replace_span(text: str, needle: str, new_text: str) -> str:
    start, end = _span(text, needle)
    return text[:start] + new_text + text[end:]


def _base_row_land(pid: int, name: str) -> dict:
    return {
        "id": pid,
        "name": name,
        "terrain": "plains",
        "domain": "land",
        "core_for_tags": [],
        "natural_resources": {},
        "population_base": 0,
        "meta": {"source": "ne_10m_land", "gap_ibs": name},
    }


def _base_row_sea(pid: int, name: str, rect: Sequence[float]) -> dict:
    west, east, south, north = rect
    return {
        "id": pid,
        "name": name,
        "terrain": "sea",
        "core_for_tags": [],
        "natural_resources": {},
        "population_base": 0,
        "special_features": [],
        "special_levels": {},
        "domain": "sea",
        "island_class": "none",
        "facility_tier": "none",
        "theater": "sea",
        "naval_importance": 1,
        "meta": {
            "source": "ne_10m_land",
            "gap_ibs": name,
            "rect": [west, east, south, north],
        },
    }


def _upsert_base(text: str, rows: Sequence[Mapping[str, Any]]) -> str:
    for row in rows:
        pid = int(row["id"])
        needle = '"id": %d' % pid
        pretty = _pretty_base(row)
        if needle in text:
            text = _replace_span(text, needle, pretty)
            continue
        close = text.rfind("\n  ]\n}")
        if close < 0:
            raise SystemExit("provinces_base.json has no array close")
        text = text[:close] + ",\n" + pretty + text[close:]
    return text


def _compact_geo(row: Mapping[str, Any]) -> str:
    return json.dumps(row, separators=(",", ":"), ensure_ascii=False)


def _upsert_geometry(text: str, rows: Sequence[Mapping[str, Any]]) -> str:
    decoder = json.JSONDecoder()
    array_at = text.find("[")
    _array, array_end = decoder.raw_decode(text, array_at)
    for row in rows:
        pid = int(row["id"])
        needle = '"id":%d' % pid
        blob = _compact_geo(row)
        if needle in text:
            text = _replace_span(text, needle, blob)
            array_at = text.find("[")
            _array, array_end = decoder.raw_decode(text, array_at)
            continue
        text = text[: array_end - 1] + "," + blob + text[array_end - 1 :]
        array_at = text.find("[")
        _array, array_end = decoder.raw_decode(text, array_at)
    return text


def _city_block(pid: int, name: str) -> str:
    return '    "%d": {\n      "city_name": "%s",\n      "tier": 2\n    }' % (pid, name)


def _upsert_cities(text: str, rows: Sequence[Tuple[int, str]]) -> str:
    decoder = json.JSONDecoder()
    for pid, name in rows:
        key = '"%d":' % pid
        block = _city_block(pid, name)
        idx = text.find(key)
        if idx >= 0:
            brace = text.find("{", idx)
            _obj, end = decoder.raw_decode(text, brace)
            line = text.rfind("\n", 0, idx) + 1
            text = text[:line] + block + text[end:]
            continue
        marker = '\n  },\n  "meta"'
        at = text.rfind(marker)
        if at < 0 or text[at - 1] != "}":
            raise SystemExit("province_city_layer.json tail is not the expected close")
        text = text[:at] + ",\n" + block + text[at:]
    return text


def _economy() -> dict:
    return {"population": 0, "factories": 0, "infrastructure": 1, "development_level": 0}


def apply_layers(groups: Mapping[int, Sequence[Ring]]) -> None:
    for year in ERA_YEARS:
        own_path = D / ("province_ownership_%d.json" % year)
        own = _load(own_path)
        owners = own.setdefault("owners", {})
        for pid, tag in OWNERS[year].items():
            owners[str(pid)] = tag
        own_path.write_text(_dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = _load(mem_path)
        reg = mem.setdefault("province_to_region", {})
        st = mem.setdefault("province_to_state", {})
        sup = mem.setdefault("province_to_super_region", {})
        for pid in LAND_IDS:
            reg[str(pid)] = REGION_EAST_ASIA
            st[str(pid)] = STATE_JPN
            sup[str(pid)] = SUPER_EAST_ASIA
        for pid in (VOLCANO, MARIANAS):
            reg[str(pid)] = REGION_OCEANS
            sup[str(pid)] = SUPER_OCEANS
            st.pop(str(pid), None)
        mem_path.write_text(_dumps(mem), encoding="utf-8")

    terr = _load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    for pid in LAND_IDS:
        trows[str(pid)] = {"terrain": "plains", "domain": "land"}
    for pid in (VOLCANO, MARIANAS):
        trows[str(pid)] = {"terrain": "sea", "domain": "sea"}
    (D / "province_terrain_layer.json").write_text(_dumps(terr), encoding="utf-8")

    eco = _load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for pid in NEW_IDS:
        erows[str(pid)] = _economy()
    (D / "province_economy_layer.json").write_text(_dumps(eco), encoding="utf-8")

    res = _load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for pid in NEW_IDS:
        rrows[str(pid)] = {}
    (D / "province_resources_layer.json").write_text(_dumps(res), encoding="utf-8")

    regions = _load(D / "strategic_regions.json")
    for region in regions.get("regions") or []:
        ids = region.setdefault("province_ids", [])
        if region.get("id") == REGION_EAST_ASIA:
            for pid in LAND_IDS:
                if pid not in ids:
                    ids.append(pid)
        if region.get("id") == REGION_OCEANS:
            for pid in (VOLCANO, MARIANAS):
                if pid not in ids:
                    ids.append(pid)
    (D / "strategic_regions.json").write_text(_dumps(regions), encoding="utf-8")

    scaffold = _load(D / "hierarchy_scaffold.json")
    for pid in LAND_IDS:
        scaffold.setdefault("province_to_region", {})[str(pid)] = REGION_EAST_ASIA
        scaffold.setdefault("province_to_state", {})[str(pid)] = STATE_JPN
        scaffold.setdefault("province_to_super_region", {})[str(pid)] = SUPER_EAST_ASIA
    for pid in (VOLCANO, MARIANAS):
        scaffold["province_to_region"][str(pid)] = REGION_OCEANS
        scaffold["province_to_state"][str(pid)] = 0
        scaffold["province_to_super_region"][str(pid)] = SUPER_OCEANS
    scaffold["province_n"] = len(scaffold["province_to_region"])
    scaffold["land_n"] = sum(1 for v in scaffold["province_to_state"].values() if int(v or 0) > 0)
    (D / "hierarchy_scaffold.json").write_text(_dumps(scaffold), encoding="utf-8")

    base_text = (D / "provinces_base.json").read_text(encoding="utf-8")
    rows = [
        _base_row_land(IWO, "Iwo Jima"),
        _base_row_land(BONIN, "Bonin Islands"),
        _base_row_land(SAIPAN, "Saipan"),
        _base_row_sea(VOLCANO, "Volcano-Bonin Waters", VOLCANO_RECT),
        _base_row_sea(MARIANAS, "Marianas Waters", MARIANAS_RECT),
    ]
    (D / "provinces_base.json").write_text(_upsert_base(base_text, rows), encoding="utf-8")

    shrunk = shrunk_parent_rings()
    geo_text = (D / "provinces_geometry.json").read_text(encoding="utf-8")
    geo_doc = json.loads(geo_text)
    by_geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    geo_rows: List[dict] = []
    for pid in PARENTS:
        old = by_geo[pid]
        meta = dict(old.get("meta") or {})
        meta["gap_ibs_shrunk_for"] = VOLCANO
        meta["gap_ibs_removed_deg2"] = shrunk[pid]["removed_deg2"]
        geo_rows.append(
            {
                "id": pid,
                "points": shrunk[pid]["points"],
                "label_anchor": shrunk[pid]["label_anchor"],
                "meta": meta,
            }
        )
    lands = build_land_geometry(groups)
    seas = build_sea_geometry()
    for pid in NEW_IDS:
        geo_rows.append(lands[pid] if pid in lands else seas[pid])
    (D / "provinces_geometry.json").write_text(_upsert_geometry(geo_text, geo_rows), encoding="utf-8")

    city_path = D / "province_city_layer.json"
    city_text = _upsert_cities(
        city_path.read_text(encoding="utf-8"),
        ((BONIN, "Chichi-jima"), (SAIPAN, "Garapan")),
    )
    city_path.write_text(city_text, encoding="utf-8")

    states_path = D / "province_states.json"
    states_text = states_path.read_text(encoding="utf-8")
    needle = '"id": %d,' % STATE_JPN
    start, end = _span(states_text, needle)
    state = json.loads(states_text[start:end])
    ids = list(state.get("province_ids") or [])
    for pid in LAND_IDS:
        if pid not in ids:
            ids.append(pid)
    state["province_ids"] = ids
    states_path.write_text(states_text[:start] + _pretty_base(state) + states_text[end:], encoding="utf-8")

    adj_path = D / "province_adjacency.json"
    adj_doc = _load(adj_path)
    adj = {k: [int(x) for x in v] for k, v in (adj_doc.get("adjacency") or {}).items()}
    build_adjacency(adj)
    for key in list(adj):
        adj[key] = sorted(set(int(x) for x in adj[key]))
    adj_doc["adjacency"] = {k: adj[k] for k in adj}
    base_now = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    stats = adj_doc.setdefault("stats", {})
    land_n = sum(1 for p in base_now["provinces"] if str(p.get("domain") or "") == "land")
    stats["province_n"] = len(adj)
    stats["land_n"] = land_n
    stats["water_n"] = len(adj) - land_n
    adj_path.write_text(_dumps(adj_doc), encoding="utf-8")


def refresh_adj_v3() -> None:
    script = ROOT / "tools" / "map_generation" / "scripts" / "generate_adj_v3_rhineland.py"
    import importlib.util

    spec = importlib.util.spec_from_file_location("adjv3_from_ibs", script)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load ADJ-V3 generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.main([]) != 0:
        raise SystemExit("ADJ-V3 refresh failed")


def main() -> int:
    if not NE_LAND.is_file():
        raise SystemExit("missing NE 10m land: %s" % NE_LAND)
    if not FIXTURE.is_file():
        raise SystemExit("missing parent-sea fixture: %s" % FIXTURE)
    groups = load_island_groups()
    apply_layers(groups)
    refresh_adj_v3()
    base = _load(D / "provinces_base.json")
    ids = {int(p["id"]) for p in base["provinces"]}
    print(
        "GAP-IBS n=%d new=%s parents=%s"
        % (
            len(ids),
            all(pid in ids for pid in NEW_IDS),
            all(pid in ids for pid in PARENTS),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
