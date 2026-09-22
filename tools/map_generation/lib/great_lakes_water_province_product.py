"""Great Lakes theater proof — Mike province-sizing bar #4.

Default `world_accurate` already allocated named lake IDs 950333–950337, but
their rings were leftover expand-world seed cells sitting over Quebec / James
Bay. The real Superior / Michigan / Huron / Erie / Ontario basins were mostly
empty (no water cell; a few US hulls nibble the edges).

This product **reuses those IDs** (not a renumber; not a whole-world remesh):
place basin-sized `domain=lake` rings on the accurate canvas, dent overlapping
land vertices off the water, and patch theater adjacency. Land IDs stay.

Write: tools/map_generation/scripts/apply_great_lakes_water_provinces.py
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

# Same canvas as ne_full_geometry_align / world_accurate GIS.
WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})

# Existing accurate-board lake IDs (world_full seas block, never renumbered).
LAKE_SUPERIOR_ID = 950333
LAKE_MICHIGAN_ID = 950334
LAKE_HURON_ID = 950335
LAKE_ERIE_ID = 950336
LAKE_ONTARIO_ID = 950337

GREAT_LAKE_IDS: Tuple[int, ...] = (
    LAKE_SUPERIOR_ID,
    LAKE_MICHIGAN_ID,
    LAKE_HURON_ID,
    LAKE_ERIE_ID,
    LAKE_ONTARIO_ID,
)

# Hydrologic neighbor graph (not KNN across Quebec).
LAKE_NEIGHBORS: Dict[int, Tuple[int, ...]] = {
    LAKE_SUPERIOR_ID: (LAKE_MICHIGAN_ID, LAKE_HURON_ID),
    LAKE_MICHIGAN_ID: (LAKE_SUPERIOR_ID, LAKE_HURON_ID),
    LAKE_HURON_ID: (LAKE_SUPERIOR_ID, LAKE_MICHIGAN_ID, LAKE_ERIE_ID),
    LAKE_ERIE_ID: (LAKE_HURON_ID, LAKE_ONTARIO_ID),
    LAKE_ONTARIO_ID: (LAKE_ERIE_ID,),
}

# Simplified WGS84 rings (lon, lat) — basin fill, not pixel shorelines.
# Order is ring order; first≠last (closer added when rasterized).
GREAT_LAKE_SPECS: Tuple[Dict[str, Any], ...] = (
    {
        "id": LAKE_SUPERIOR_ID,
        "name": "Lake Superior",
        "ring_lonlat": (
            (-92.10, 46.72),
            (-91.20, 46.78),
            (-90.05, 47.05),
            (-89.15, 47.85),
            (-88.15, 48.75),
            (-86.95, 48.85),
            (-85.70, 48.15),
            (-84.85, 46.98),
            (-84.52, 46.52),
            (-85.55, 46.52),
            (-86.70, 46.48),
            (-87.80, 46.55),
            (-89.05, 46.62),
            (-90.55, 46.52),
            (-91.85, 46.64),
        ),
        "centroid_lonlat": (-87.50, 47.70),
        "lon_window": (-92.25, -84.35),
        "lat_window": (46.35, 49.10),
        "min_bbox_area": 8000.0,
    },
    {
        "id": LAKE_MICHIGAN_ID,
        "name": "Lake Michigan",
        "ring_lonlat": (
            (-87.75, 41.62),
            (-87.10, 41.68),
            (-86.35, 41.95),
            (-86.22, 43.00),
            (-86.38, 44.05),
            (-86.50, 44.85),
            (-85.55, 45.10),
            (-85.02, 45.78),
            (-84.95, 45.88),
            (-85.85, 45.86),
            (-86.75, 45.32),
            (-87.15, 45.18),
            (-87.78, 44.95),
            (-87.92, 44.20),
            (-87.78, 43.15),
            (-87.82, 42.20),
        ),
        "centroid_lonlat": (-87.00, 44.00),
        "lon_window": (-88.15, -84.85),
        "lat_window": (41.50, 46.20),
        "min_bbox_area": 5000.0,
    },
    {
        "id": LAKE_HURON_ID,
        "name": "Lake Huron",
        "ring_lonlat": (
            (-84.75, 45.80),
            (-83.95, 45.88),
            (-83.25, 45.25),
            (-82.55, 44.05),
            (-82.42, 43.08),
            (-82.12, 43.00),
            (-81.15, 43.25),
            (-80.10, 43.85),
            (-80.00, 44.75),
            (-80.85, 45.55),
            (-81.75, 45.95),
            (-83.05, 46.18),
            (-84.05, 46.02),
            (-84.62, 45.92),
        ),
        "centroid_lonlat": (-82.50, 44.50),
        "lon_window": (-84.95, -79.55),
        "lat_window": (42.90, 46.40),
        "min_bbox_area": 5000.0,
    },
    {
        "id": LAKE_ERIE_ID,
        "name": "Lake Erie",
        "ring_lonlat": (
            (-83.48, 41.90),
            (-83.05, 41.52),
            (-81.75, 41.40),
            (-80.55, 42.12),
            (-79.10, 42.52),
            (-78.90, 42.88),
            (-80.15, 42.76),
            (-81.45, 42.55),
            (-82.65, 42.18),
            (-83.18, 42.02),
        ),
        "centroid_lonlat": (-81.20, 42.20),
        "lon_window": (-83.65, -78.75),
        "lat_window": (41.30, 43.05),
        "min_bbox_area": 2200.0,
    },
    {
        "id": LAKE_ONTARIO_ID,
        "name": "Lake Ontario",
        "ring_lonlat": (
            (-79.76, 43.25),
            (-78.85, 43.24),
            (-77.70, 43.26),
            (-76.50, 43.26),
            (-76.18, 43.55),
            (-76.22, 44.08),
            (-77.15, 44.14),
            (-78.25, 43.86),
            (-79.38, 43.66),
            (-79.82, 43.46),
        ),
        "centroid_lonlat": (-77.90, 43.70),
        "lon_window": (-79.95, -76.05),
        "lat_window": (43.10, 44.35),
        "min_bbox_area": 1400.0,
    },
)

# Theater land-ID freeze window (label_anchor lon/lat).
THEATER_LONLAT = (-93.5, 40.8, -74.5, 49.5)
COAST_TOUCH_PX = 48.0
LAND_DENT_PAD_PX = 3.0

Point = List[float]
Ring = List[Point]


def lonlat_to_canvas(lon: float, lat: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    x = (float(lon) - lon_min) / (lon_max - lon_min) * (w - 1.0)
    y = (lat_max - float(lat)) / (lat_max - lat_min) * (h - 1.0)
    return x, y


def canvas_to_lonlat(x: float, y: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + (float(x) / (w - 1.0)) * (lon_max - lon_min)
    lat = lat_max - (float(y) / (h - 1.0)) * (lat_max - lat_min)
    return lon, lat


def spec_by_id() -> Dict[int, Dict[str, Any]]:
    return {int(s["id"]): s for s in GREAT_LAKE_SPECS}


def ring_from_lonlat(ring_lonlat: Sequence[Sequence[float]]) -> Ring:
    pts: Ring = []
    for pair in ring_lonlat:
        x, y = lonlat_to_canvas(float(pair[0]), float(pair[1]))
        pts.append([float(x), float(y)])
    return pts


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    ring = list(points)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    n = float(len(ring))
    return sum(float(p[0]) for p in ring) / n, sum(float(p[1]) for p in ring) / n


def bbox_area(points: Sequence[Sequence[float]]) -> float:
    xs: List[float] = []
    ys: List[float] = []
    for p in points or []:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if len(xs) < 2:
        return 0.0
    return max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))


def ring_bbox(points: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def bbox_overlap(
    a: Sequence[Sequence[float]],
    b: Sequence[Sequence[float]],
    pad: float = 0.0,
) -> bool:
    ax0, ay0, ax1, ay1 = ring_bbox(a)
    bx0, by0, bx1, by1 = ring_bbox(b)
    return not (ax1 + pad < bx0 or bx1 + pad < ax0 or ay1 + pad < by0 or by1 + pad < ay0)


def point_in_ring(x: float, y: float, ring: Sequence[Sequence[float]]) -> bool:
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi = float(ring[i][0])
        yi = float(ring[i][1])
        xj = float(ring[j][0])
        yj = float(ring[j][1])
        intersects = (yi > y) != (yj > y)
        if intersects:
            den = (yj - yi) if (yj - yi) != 0.0 else 1e-12
            if x < (xj - xi) * (y - yi) / den + xi:
                inside = not inside
        j = i
    return inside


def _is_water(p: Mapping[str, Any]) -> bool:
    terr = str(p.get("terrain") or "").strip().lower()
    dom = str(p.get("domain") or "land").strip().lower()
    return terr in WATER_T or dom in WATER_D or bool(p.get("is_sea"))


def min_ring_distance(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    best = float("inf")
    for pa in a:
        for pb in b:
            d = math.hypot(float(pa[0]) - float(pb[0]), float(pa[1]) - float(pb[1]))
            if d < best:
                best = d
    return best if best != float("inf") else 0.0


def rings_touch(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]], dist: float) -> bool:
    if len(a) < 3 or len(b) < 3:
        return False
    if not bbox_overlap(a, b, pad=dist):
        return False
    if min_ring_distance(a, b) <= dist:
        return True
    for p in a:
        if point_in_ring(float(p[0]), float(p[1]), b):
            return True
    for p in b:
        if point_in_ring(float(p[0]), float(p[1]), a):
            return True
    return False


def nearest_ring_point(pt: Sequence[float], ring: Sequence[Sequence[float]]) -> Tuple[float, float]:
    px, py = float(pt[0]), float(pt[1])
    best = (float(ring[0][0]), float(ring[0][1]))
    best_d = float("inf")
    for q in ring:
        d = math.hypot(px - float(q[0]), py - float(q[1]))
        if d < best_d:
            best_d = d
            best = (float(q[0]), float(q[1]))
    return best


def dent_land_away_from_lakes(land_ring: Ring, lake_rings: Sequence[Ring]) -> Tuple[Ring, bool]:
    """Project land vertices that fall inside a lake onto that lake's shore."""
    if len(land_ring) < 3:
        return land_ring, False
    changed = False
    out: Ring = []
    for pt in land_ring:
        x, y = float(pt[0]), float(pt[1])
        dented = False
        for lake in lake_rings:
            if not bbox_overlap([pt], lake, pad=1.0):
                continue
            if not point_in_ring(x, y, lake):
                continue
            cx, cy = polygon_centroid(lake)
            nx, ny = nearest_ring_point(pt, lake)
            vx, vy = nx - cx, ny - cy
            nrm = math.hypot(vx, vy) or 1.0
            x = nx + LAND_DENT_PAD_PX * vx / nrm
            y = ny + LAND_DENT_PAD_PX * vy / nrm
            dented = True
            changed = True
            break
        out.append([x, y] if dented else [float(pt[0]), float(pt[1])])
    if len(out) < 3:
        return land_ring, False
    return out, changed


def load_board(board_dir: Path) -> Dict[str, Any]:
    base_rows = json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    geo_rows = json.loads((board_dir / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    adj_doc = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8"))
    base = {int(p["id"]): p for p in base_rows}
    geo = {int(g["id"]): g for g in geo_rows}
    adj_raw = adj_doc.get("adjacency") or {}
    adj: Dict[int, List[int]] = {int(k): [int(x) for x in (v or [])] for k, v in adj_raw.items()}
    return {"base": base, "geo": geo, "adj": adj, "adj_doc": adj_doc}


def theater_land_ids(base: Mapping[int, Mapping[str, Any]], geo: Mapping[int, Mapping[str, Any]]) -> List[int]:
    lon0, lat0, lon1, lat1 = THEATER_LONLAT
    x0, y1 = lonlat_to_canvas(lon0, lat0)
    x1, y0 = lonlat_to_canvas(lon1, lat1)
    x_lo, x_hi = (x0, x1) if x0 <= x1 else (x1, x0)
    y_lo, y_hi = (y0, y1) if y0 <= y1 else (y1, y0)
    out: List[int] = []
    for pid, p in base.items():
        if _is_water(p):
            continue
        g = geo.get(int(pid)) or {}
        la = g.get("label_anchor") or polygon_centroid(g.get("points") or [])
        if not isinstance(la, (list, tuple)) or len(la) < 2:
            continue
        x, y = float(la[0]), float(la[1])
        if x_lo <= x <= x_hi and y_lo <= y <= y_hi:
            out.append(int(pid))
    return sorted(out)


def planned_lake_rings() -> Dict[int, Ring]:
    return {int(s["id"]): ring_from_lonlat(s["ring_lonlat"]) for s in GREAT_LAKE_SPECS}


def _split_top_level_objects(array_text: str) -> List[Tuple[int, int]]:
    """Byte spans of top-level `{...}` objects inside a JSON array body."""
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
    """Replace only named province objects; leave the rest of the file intact."""
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


def apply_great_lakes_water_provinces(board_dir: str = "") -> Dict[str, Any]:
    """Write basin rings + theater adj patch. Does not renumber any IDs."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]
    land_before = theater_land_ids(base, geo)
    lake_rings = planned_lake_rings()
    geo_updates: Dict[int, Dict[str, Any]] = {}
    for spec in GREAT_LAKE_SPECS:
        pid = int(spec["id"])
        if pid not in geo or pid not in base:
            raise KeyError(f"missing allocated lake id {pid}")
        ring = lake_rings[pid]
        cx, cy = polygon_centroid(ring)
        old = dict(geo[pid])
        old["points"] = ring
        old["label_anchor"] = [cx, cy]
        old["name"] = str(spec["name"])
        meta = dict(old.get("meta") or {})
        meta["great_lakes_feed"] = "v1_basin_rings"
        meta["gis_ne_domain"] = "water"
        old["meta"] = meta
        geo[pid] = old
        geo_updates[pid] = old
        row = dict(base[pid])
        row["name"] = str(spec["name"])
        row["domain"] = "lake"
        row["terrain"] = "sea"
        feats = list(row.get("special_features") or [])
        if "lake" not in feats:
            feats.append("lake")
        row["special_features"] = feats
        base[pid] = row

    dented_land: List[int] = []
    lakes_only = [lake_rings[i] for i in GREAT_LAKE_IDS]
    for pid, g in list(geo.items()):
        p = base.get(int(pid)) or {}
        if _is_water(p) or int(pid) in GREAT_LAKE_IDS:
            continue
        pts = [[float(pt[0]), float(pt[1])] for pt in (g.get("points") or []) if isinstance(pt, (list, tuple)) and len(pt) >= 2]
        if len(pts) < 3:
            continue
        if not any(bbox_overlap(pts, lake, pad=2.0) for lake in lakes_only):
            continue
        new_pts, changed = dent_land_away_from_lakes(pts, lakes_only)
        if not changed:
            continue
        ng = dict(g)
        ng["points"] = new_pts
        geo[int(pid)] = ng
        geo_updates[int(pid)] = ng
        dented_land.append(int(pid))

    coastal: Dict[int, Set[int]] = {pid: set() for pid in GREAT_LAKE_IDS}
    for lake_id, lring in lake_rings.items():
        for pid, g in geo.items():
            if int(pid) in GREAT_LAKE_IDS:
                continue
            p = base.get(int(pid)) or {}
            if _is_water(p):
                continue
            pts = g.get("points") or []
            if len(pts) < 3:
                continue
            if rings_touch(lring, pts, COAST_TOUCH_PX):
                coastal[lake_id].add(int(pid))

    adj_updates: Dict[int, List[int]] = {}
    touched_land: Set[int] = set()
    for lake_id in GREAT_LAKE_IDS:
        wanted: Set[int] = set(LAKE_NEIGHBORS[lake_id])
        wanted.update(coastal[lake_id])
        old = set(adj.get(lake_id) or [])
        for nb in old:
            if nb in GREAT_LAKE_IDS:
                continue
            # drop stale Quebec-KNN land that no longer touches the basin
            if nb not in wanted:
                if nb in adj:
                    adj[nb] = [x for x in adj[nb] if x != lake_id]
                    touched_land.add(int(nb))
        adj[lake_id] = sorted(wanted)
        adj_updates[lake_id] = adj[lake_id]
        for nb in wanted:
            cur = set(adj.get(nb) or [])
            if lake_id not in cur:
                cur.add(lake_id)
                adj[nb] = sorted(cur)
                touched_land.add(int(nb))

    for pid in touched_land:
        adj_updates[int(pid)] = list(adj[int(pid)])

    n_geo = surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
    n_adj = surgical_replace_adjacency_keys(d / "province_adjacency.json", adj_updates)

    # Base names/domain already correct on tip; rewrite the five lake rows only if needed.
    base_path = d / "provinces_base.json"
    base_doc = json.loads(base_path.read_text(encoding="utf-8"))
    base_changed = False
    for row in base_doc.get("provinces") or []:
        pid = int(row.get("id") or 0)
        if pid not in spec_by_id():
            continue
        spec = spec_by_id()[pid]
        if row.get("name") != spec["name"] or row.get("domain") != "lake":
            row["name"] = spec["name"]
            row["domain"] = "lake"
            row["terrain"] = "sea"
            feats = list(row.get("special_features") or [])
            if "lake" not in feats:
                feats.append("lake")
            row["special_features"] = feats
            base_changed = True
    if base_changed:
        base_path.write_text(json.dumps(base_doc, indent=2) + "\n", encoding="utf-8")

    land_after = theater_land_ids(
        {int(p["id"]): p for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]},
        {int(g["id"]): g for g in json.loads((d / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]},
    )
    return {
        "ok": land_before == land_after and n_geo >= 5,
        "board_dir": str(d),
        "geo_objects_rewritten": n_geo,
        "adj_keys_rewritten": n_adj,
        "dented_land_ids": sorted(dented_land),
        "coastal_by_lake": {str(k): sorted(v) for k, v in coastal.items()},
        "theater_land_ids": land_after,
        "theater_land_preserved": land_before == land_after,
        "renumbered": False,
        "new_ids": [],
        "reused_ids": list(GREAT_LAKE_IDS),
    }


def build_great_lakes_water_province_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: five Great Lakes own water cells in-basin."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}

    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]
    land_ids = theater_land_ids(base, geo)

    for spec in GREAT_LAKE_SPECS:
        pid = int(spec["id"])
        p = base.get(pid)
        if p is None:
            fails.append(f"missing lake id {pid} ({spec['name']})")
            continue
        if str(p.get("name") or "") != str(spec["name"]):
            fails.append(f"{pid} name={p.get('name')!r} want {spec['name']!r}")
        if str(p.get("domain") or "").lower() != "lake":
            fails.append(f"{pid} domain={p.get('domain')!r} want lake")
        if not _is_water(p):
            fails.append(f"{pid} not water")
        g = geo.get(pid) or {}
        pts = g.get("points") or []
        if len(pts) < 8:
            fails.append(f"{pid} ring too small n={len(pts)}")
        area = bbox_area(pts)
        if area < float(spec["min_bbox_area"]):
            fails.append(f"{pid} bbox_area={area:.1f} < {spec['min_bbox_area']}")
        cx, cy = polygon_centroid(pts)
        lon, lat = canvas_to_lonlat(cx, cy)
        lon0, lon1 = spec["lon_window"]
        lat0, lat1 = spec["lat_window"]
        if not (float(lon0) <= lon <= float(lon1) and float(lat0) <= lat <= float(lat1)):
            fails.append(f"{pid} centroid lonlat=({lon:.2f},{lat:.2f}) outside basin")
        else:
            passes.append(f"{pid} {spec['name']} in-basin area={area:.0f}")

        # Exclusive water at the design centroid (not absorbed into land).
        tx, ty = lonlat_to_canvas(float(spec["centroid_lonlat"][0]), float(spec["centroid_lonlat"][1]))
        land_hits = [
            lid
            for lid in land_ids
            if point_in_ring(tx, ty, (geo.get(lid) or {}).get("points") or [])
        ]
        if land_hits:
            fails.append(f"{pid} basin centroid absorbed by land {land_hits[:6]}")
        if not point_in_ring(tx, ty, pts):
            fails.append(f"{pid} own ring misses design centroid")

        nbrs = set(adj.get(pid) or [])
        for need in LAKE_NEIGHBORS[pid]:
            if need not in nbrs:
                fails.append(f"{pid} missing lake neighbor {need}")
        land_nbrs = [n for n in nbrs if n in base and not _is_water(base[n])]
        if len(land_nbrs) < 1:
            fails.append(f"{pid} has no coastal land neighbor")
        else:
            passes.append(f"{pid} land_nbrs={len(land_nbrs)}")

    # ID stability: theater land set uses existing IDs only (no 800k/900k invent).
    weird = [pid for pid in land_ids if not (800000 <= pid < 950000)]
    if weird:
        fails.append(f"unexpected theater land ids {weird[:8]}")
    for pid in GREAT_LAKE_IDS:
        if pid not in base:
            fails.append(f"allocated lake id lost: {pid}")

    ok = not fails
    return {
        "ok": ok,
        "empty": False,
        "summary": (
            "Great Lakes own in-basin water cells"
            if ok
            else f"Great Lakes water proof failed: {fails[:6]}"
        ),
        "fails": fails,
        "passes": passes,
        "lake_ids": list(GREAT_LAKE_IDS),
        "theater_land_n": len(land_ids),
        "theater_land_ids": land_ids,
        "renumbered": False,
        "board": str(d.relative_to(ROOT) if d.is_relative_to(ROOT) else d),
    }


def great_lakes_water_province_integrity(board_dir: str = "") -> Dict[str, Any]:
    p = build_great_lakes_water_province_product(board_dir)
    return {
        "ok": bool(p.get("ok")),
        "summary": p.get("summary"),
        "lake_ids": p.get("lake_ids"),
        "theater_land_n": p.get("theater_land_n"),
        "fails": p.get("fails") or [],
    }
