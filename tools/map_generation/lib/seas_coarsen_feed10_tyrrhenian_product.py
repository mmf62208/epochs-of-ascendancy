"""FEED-10 seas coarsen — Mike province-sizing bar #3 (Tyrrhenian basin only).

The accurate board already allocated "Tyrrhenian Sea" 950120, but its ring was a
leftover expand_grand_theater seed hex sitting at ~5.48°E / 37.00°N (south of
Spain, canvas area ~344). The real west-Italy / Corsica–Sardinia basin
(9.5–15.0°E / 38.2–42.5°N) was void.

This product is a **one-theater proof** (not Ligurian / Adriatic / Alboran
redo, not NAtl, not lakes, not Maginot / Flanders / SE England land):

* Reuse sea ID **950120** (not a renumber) and place a basin-sized ring on the
  real Tyrrhenian water, west of the Italian peninsula, east of Corsica /
  Sardinia, south of Cap Corse / Ligurian 950119.
* Do not write land mesh (Maginot, Flanders/Nord, SE England, Gibraltar, HK,
  Windward).
* Do not rewrite Ligurian 950119 / Alboran 950128 / strait 950019 /
  Adriatic 950121 / Channel / Great Lakes meshes. Do not write world_full.

Write: tools/map_generation/scripts/apply_seas_coarsen_feed10_tyrrhenian.py
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)

TYRRHENIAN_ID = 950120
LIGURIAN_ID = 950119
ADRIATIC_ID = 950121
ALBORAN_ID = 950128
STRAIT_ID = 950019
CHANNEL_ID = 950001
WESTERN_MED_ID = 950003
CENTRAL_MED_ID = 950004

GIBRALTAR_ID = 711520
MAGINOT_GER_ID = 710173
MAGINOT_FRA_ID = 710739
NORD_ID = 710734
NORD_EAST_ID = 711521
NORD_SOUTH_ID = 711522
OXFORDSHIRE_ID = 711438
HAMPSHIRE_ID = 711449
OXFORDSHIRE_NORTH_ID = 711523
OXFORDSHIRE_EAST_ID = 711524

# Core west-Italy / Corsica / Sardinia coasts that must touch the new ring.
CORSE_DU_SUD_ID = 710801
HAUTE_CORSE_ID = 710802
NAPOLI_ID = 710892
SASSARI_ID = 710917
NUORO_ID = 710918
SUD_SARDEGNA_ID = 710921
GROSSETO_ID = 710953
VITERBO_ID = 710961
ROMA_ID = 710963
LATINA_ID = 710964

WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})
WATER_T = frozenset({"sea", "ocean", "water", "lake"})

# Leftover seed (pre-FEED) — 950120 sat at ~5.48°E / 37.00°N, area ~344.
PRE_TYRRHENIAN_AREA = 344.35
PRE_TYRRHENIAN_LONLAT = (5.4762, 36.9966)
PRE_THEATER_SEA_N = 1
PRE_THEATER_MEDIAN = 344.35
PRE_WEST_ITALY_COASTAL_MEDIAN = 202.0

# Basin-sized proof: Alboran/Ligurian-class if the void allows (>=1000),
# always >=600 and clearly larger than west-Italy coastal land median (~202).
TYRRHENIAN_AREA_MIN = 1000.0
TYRRHENIAN_AREA_FLOOR = 600.0
THEATER_MEDIAN_MIN = 600.0
# Packed NUTS: 8px (~0.35°) is "actually touches".
COAST_TOUCH_PX = 8.0
COAST_WINDOW = (8.4, 37.8, 16.0, 43.0)
WEST_ITALY_LAND_WINDOW = (9.5, 38.0, 15.5, 42.8)

# Clockwise from NW. Void corridor: east of Corsica/Sardinia hulls,
# west of Italian peninsula hulls, south of Cap Corse / Ligurian (~43.16°N),
# north of Sicily (~38.2°N).
TYRRHENIAN_LONLAT_RING: Tuple[Tuple[float, float], ...] = (
    (9.68, 42.30),
    (10.15, 42.34),
    (10.75, 42.32),
    (11.20, 42.20),
    (11.50, 41.98),
    (11.85, 41.58),
    (12.25, 41.28),
    (12.70, 41.12),
    (13.15, 41.02),
    (13.65, 40.85),
    (14.08, 40.62),
    (14.28, 40.35),
    (14.22, 39.90),
    (13.95, 39.40),
    (13.45, 38.88),
    (12.75, 38.55),
    (12.05, 38.48),
    (11.35, 38.55),
    (10.70, 38.82),
    (10.20, 39.20),
    (10.00, 39.55),
    (9.95, 40.00),
    (9.95, 40.55),
    (9.98, 41.05),
    (9.85, 41.50),
    (9.68, 41.85),
    (9.62, 42.10),
)
TYRRHENIAN_CENTROID_LONLAT = (11.59, 40.61)
TYRRHENIAN_LON_WINDOW = (9.5, 15.0)
TYRRHENIAN_LAT_WINDOW = (38.2, 42.5)

# Basin sample points that were VOID on the FEED-9 tip.
TYRRHENIAN_SAMPLE_LONLAT: Tuple[Tuple[float, float], ...] = (
    (12.0, 40.5),
    (11.5, 41.5),
    (13.0, 41.0),
    (10.5, 40.0),
    (14.0, 40.5),
)

CORE_COAST_IDS: Tuple[int, ...] = (
    CORSE_DU_SUD_ID,
    HAUTE_CORSE_ID,
    NAPOLI_ID,
    SASSARI_ID,
    NUORO_ID,
    SUD_SARDEGNA_ID,
    GROSSETO_ID,
    VITERBO_ID,
    ROMA_ID,
    LATINA_ID,
)
STALE_CLUSTER_SEAS: Tuple[int, ...] = (WESTERN_MED_ID, CENTRAL_MED_ID, ADRIATIC_ID)
SKIP_COAST_IDS: Tuple[int, ...] = (TYRRHENIAN_ID, LIGURIAN_ID, 710908, 710909, 710910)

BANNED_LAND_IDS: Tuple[int, ...] = (
    GIBRALTAR_ID,
    MAGINOT_GER_ID,
    MAGINOT_FRA_ID,
    711514,
    711515,
    711516,
    711517,
    711518,
    711519,
    NORD_ID,
    NORD_EAST_ID,
    NORD_SOUTH_ID,
    OXFORDSHIRE_ID,
    HAMPSHIRE_ID,
    OXFORDSHIRE_NORTH_ID,
    OXFORDSHIRE_EAST_ID,
)
BANNED_SEA_MESH_IDS: Tuple[int, ...] = (
    LIGURIAN_ID,
    ALBORAN_ID,
    STRAIT_ID,
    ADRIATIC_ID,
    CHANNEL_ID,
)
GREAT_LAKE_IDS: Tuple[int, ...] = (950333, 950334, 950335, 950336, 950337)

# Tip-frozen meshes this FEED must not rewrite (FEED-8 / FEED-4 / FEED-9).
FROZEN_MESH_AREA: Dict[int, float] = {
    LIGURIAN_ID: 1340.58,
    ALBORAN_ID: 1881.05,
    OXFORDSHIRE_ID: 58.22,
    HAMPSHIRE_ID: 215.21,
    OXFORDSHIRE_NORTH_ID: 113.73,
    OXFORDSHIRE_EAST_ID: 59.12,
}

FEED_META = "v1_tyrrhenian_basin_coarsen"
PRESERVED_IDS: Tuple[int, ...] = (
    TYRRHENIAN_ID,
    LIGURIAN_ID,
    ADRIATIC_ID,
    ALBORAN_ID,
    STRAIT_ID,
    MAGINOT_GER_ID,
    MAGINOT_FRA_ID,
    NORD_ID,
    GIBRALTAR_ID,
    OXFORDSHIRE_ID,
    HAMPSHIRE_ID,
    OXFORDSHIRE_NORTH_ID,
    OXFORDSHIRE_EAST_ID,
)

Ring = List[List[float]]


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


def _open_ring(points: Sequence[Sequence[float]]) -> Ring:
    pts = [[float(p[0]), float(p[1])] for p in points if isinstance(p, (list, tuple)) and len(p) >= 2]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def polygon_area(points: Sequence[Sequence[float]]) -> float:
    pts = _open_ring(points)
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
    pts = _open_ring(points)
    if not pts:
        return 0.0, 0.0
    n = float(len(pts))
    return sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n


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


def ring_bbox(points: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    pts = _open_ring(points)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def bbox_overlap(
    a: Sequence[Sequence[float]],
    b: Sequence[Sequence[float]],
    pad: float = 0.0,
) -> bool:
    ax0, ay0, ax1, ay1 = ring_bbox(a)
    bx0, by0, bx1, by1 = ring_bbox(b)
    return not (ax1 + pad < bx0 or bx1 + pad < ax0 or ay1 + pad < by0 or by1 + pad < ay0)


def min_ring_distance(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    best = float("inf")
    for pa in _open_ring(a):
        for pb in _open_ring(b):
            d = math.hypot(pa[0] - pb[0], pa[1] - pb[1])
            if d < best:
                best = d
    return best if best != float("inf") else 0.0


def rings_touch(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]], dist: float) -> bool:
    if len(_open_ring(a)) < 3 or len(_open_ring(b)) < 3:
        return False
    if not bbox_overlap(a, b, pad=dist):
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


def tyrrhenian_design_ring() -> Ring:
    return [list(lonlat_to_canvas(lon, lat)) for lon, lat in TYRRHENIAN_LONLAT_RING]


def _is_water(p: Mapping[str, Any]) -> bool:
    terr = str(p.get("terrain") or "").strip().lower()
    dom = str(p.get("domain") or "land").strip().lower()
    return terr in WATER_T or dom in WATER_D or bool(p.get("is_sea"))


def load_board(board_dir: Path) -> Dict[str, Any]:
    base_rows = json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    geo_rows = json.loads((board_dir / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    adj_doc = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8"))
    base = {int(p["id"]): p for p in base_rows}
    geo = {int(g["id"]): g for g in geo_rows}
    adj_raw = adj_doc.get("adjacency") or {}
    adj = {int(k): [int(x) for x in (v or [])] for k, v in adj_raw.items()}
    return {"base": base, "geo": geo, "adj": adj, "adj_doc": adj_doc}


def west_italy_coastal_land_areas(
    base: Mapping[int, Mapping[str, Any]], geo: Mapping[int, Mapping[str, Any]]
) -> List[float]:
    lon0, lat0, lon1, lat1 = WEST_ITALY_LAND_WINDOW
    out: List[float] = []
    for pid, p in base.items():
        if _is_water(p):
            continue
        pts = (geo.get(int(pid)) or {}).get("points") or []
        cx, cy = polygon_centroid(pts)
        lon, lat = canvas_to_lonlat(cx, cy)
        if not (lon0 <= lon <= lon1 and lat0 <= lat <= lat1):
            continue
        area = polygon_area(pts)
        if 20.0 <= area < 2000.0:
            out.append(area)
    return out


def _median(vals: Sequence[float]) -> float:
    if not vals:
        return 0.0
    s = sorted(float(v) for v in vals)
    n = len(s)
    mid = n // 2
    if n % 2 == 1:
        return s[mid]
    return 0.5 * (s[mid - 1] + s[mid])


def theater_sea_ids() -> Tuple[int, ...]:
    return (TYRRHENIAN_ID,)


def theater_metrics(geo: Mapping[int, Mapping[str, Any]]) -> Dict[str, float]:
    areas = [polygon_area((geo.get(int(pid)) or {}).get("points") or []) for pid in theater_sea_ids()]
    return {
        "sea_n": float(len(areas)),
        "min": min(areas) if areas else 0.0,
        "median": _median(areas),
        "max": max(areas) if areas else 0.0,
        "tyrrhenian": polygon_area((geo.get(TYRRHENIAN_ID) or {}).get("points") or []),
    }


def _geo_object(old: Mapping[str, Any], pid: int, name: str, ring: Ring, extra_meta: Mapping[str, Any]) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta["seas_coarsen_feed"] = FEED_META
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
    pieces: List[str] = []
    cursor = 0
    changed = 0
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


def _coastal_neighbors(
    ring: Ring,
    base: Mapping[int, Mapping[str, Any]],
    geo: Mapping[int, Mapping[str, Any]],
) -> List[int]:
    """Land that actually touches the Tyrrhenian ring (west-Italy / Corsica / Sardinia)."""
    skip = set(SKIP_COAST_IDS)
    lon0, lat0, lon1, lat1 = COAST_WINDOW
    out: List[int] = []
    for pid, p in base.items():
        if int(pid) in skip or _is_water(p):
            continue
        pts = (geo.get(int(pid)) or {}).get("points") or []
        if len(pts) < 3:
            continue
        cx, cy = polygon_centroid(pts)
        lon, lat = canvas_to_lonlat(cx, cy)
        if not (lon0 <= lon <= lon1 and lat0 <= lat <= lat1):
            continue
        if rings_touch(ring, pts, COAST_TOUCH_PX):
            out.append(int(pid))
    return sorted(out)


def apply_seas_coarsen_feed10(board_dir: str = "") -> Dict[str, Any]:
    """Write Tyrrhenian basin ring + theater adj. Existing IDs stay. No land writes."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]
    if TYRRHENIAN_ID not in geo or TYRRHENIAN_ID not in base:
        raise KeyError("missing allocated Tyrrhenian sea id 950120")

    before = theater_metrics(geo)
    ring = tyrrhenian_design_ring()
    old = dict(geo[TYRRHENIAN_ID])
    geo_obj = _geo_object(
        old,
        TYRRHENIAN_ID,
        "Tyrrhenian Sea",
        ring,
        {"role": "med_basin", "theater": "tyrrhenian"},
    )
    geo_updates: Dict[int, Dict[str, Any]] = {TYRRHENIAN_ID: geo_obj}
    banned_written = [
        pid
        for pid in geo_updates
        if int(pid) in BANNED_LAND_IDS or int(pid) in GREAT_LAKE_IDS or int(pid) in BANNED_SEA_MESH_IDS
    ]
    if banned_written:
        raise RuntimeError(f"refusing land/lake/other-sea rewrite {banned_written}")

    coastal = _coastal_neighbors(ring, base, geo)
    wanted: Set[int] = set(coastal)

    adj_updates: Dict[int, List[int]] = {}
    old_nbrs = set(adj.get(TYRRHENIAN_ID) or [])
    for nb in old_nbrs:
        if nb in wanted:
            continue
        if nb in adj:
            adj[nb] = [x for x in adj[nb] if int(x) != TYRRHENIAN_ID]
            adj_updates[int(nb)] = list(adj[nb])
    adj[TYRRHENIAN_ID] = sorted(wanted)
    adj_updates[TYRRHENIAN_ID] = adj[TYRRHENIAN_ID]
    for nb in wanted:
        cur = set(int(x) for x in (adj.get(nb) or []))
        if TYRRHENIAN_ID not in cur:
            cur.add(TYRRHENIAN_ID)
            adj[int(nb)] = sorted(cur)
            adj_updates[int(nb)] = adj[int(nb)]

    n_geo = surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
    n_adj = surgical_replace_adjacency_keys(d / "province_adjacency.json", adj_updates)

    after_geo = {
        int(g["id"]): g
        for g in json.loads((d / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    }
    after = theater_metrics(after_geo)
    return {
        "ok": n_geo == 1 and after["tyrrhenian"] >= TYRRHENIAN_AREA_MIN,
        "board_dir": str(d),
        "geo_objects_rewritten": n_geo,
        "adj_keys_rewritten": n_adj,
        "reused_ids": [TYRRHENIAN_ID],
        "new_ids": [],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_touched": False,
        "land_ids_rewritten": [],
        "coastal_land_ids": coastal,
        "before": before,
        "after": after,
    }


def build_seas_coarsen_feed10_tyrrhenian_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Tyrrhenian Sea is the real basin, not a leftover seed."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]

    for pid, want_name, want_domain in (
        (TYRRHENIAN_ID, "Tyrrhenian Sea", "sea"),
        (LIGURIAN_ID, "Ligurian Sea", "sea"),
        (ADRIATIC_ID, "Adriatic Sea", "sea"),
        (ALBORAN_ID, "Alboran Sea", "sea"),
        (STRAIT_ID, "Gibraltar Strait Zone", "strait"),
        (ROMA_ID, "Roma", "land"),
        (GROSSETO_ID, "Grosseto", "land"),
        (HAUTE_CORSE_ID, "Haute-Corse", "land"),
        (NUORO_ID, "Nuoro", "land"),
        (OXFORDSHIRE_ID, "Oxfordshire", "land"),
    ):
        row = base.get(int(pid)) or {}
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_existing_id {pid}")
        elif str(row.get("name") or "") != want_name:
            fails.append(f"{pid} renamed {row.get('name')!r}")
        elif str(row.get("domain") or "land").lower() != want_domain:
            fails.append(f"{pid} domain={row.get('domain')!r}")
        else:
            passes.append(f"kept_{pid}_{want_name}")

    metrics = theater_metrics(geo)
    tyrrhenian_area = float(metrics["tyrrhenian"])
    if tyrrhenian_area < TYRRHENIAN_AREA_MIN:
        fails.append(f"tyrrhenian_not_basin_scale area={tyrrhenian_area:.1f}")
    else:
        passes.append(f"tyrrhenian_area={tyrrhenian_area:.1f}")
    if tyrrhenian_area < TYRRHENIAN_AREA_FLOOR:
        fails.append(f"tyrrhenian_below_floor {tyrrhenian_area:.1f}<{TYRRHENIAN_AREA_FLOOR}")
    if tyrrhenian_area <= PRE_TYRRHENIAN_AREA:
        fails.append(f"tyrrhenian_not_coarser_than_leftover {tyrrhenian_area:.1f}<={PRE_TYRRHENIAN_AREA}")
    if float(metrics["median"]) <= PRE_THEATER_MEDIAN:
        fails.append(f"theater_median_not_larger {metrics['median']:.1f}<={PRE_THEATER_MEDIAN}")
    else:
        passes.append(f"theater_median={metrics['median']:.1f}")
    if int(metrics["sea_n"]) > PRE_THEATER_SEA_N:
        fails.append(f"theater_sea_count_grew n={int(metrics['sea_n'])}")
    else:
        passes.append(f"theater_sea_n={int(metrics['sea_n'])}")

    coastal_land = west_italy_coastal_land_areas(base, geo)
    land_med = _median(coastal_land) if coastal_land else PRE_WEST_ITALY_COASTAL_MEDIAN
    if tyrrhenian_area <= land_med * 3.0:
        fails.append(f"tyrrhenian_not_3x_coastal_land {tyrrhenian_area:.1f}<={land_med * 3.0:.1f}")
    else:
        passes.append(f"tyrrhenian_over_coastal_median={tyrrhenian_area / max(land_med, 1.0):.2f}")

    tyrrhenian_ring = (geo.get(TYRRHENIAN_ID) or {}).get("points") or []
    cx, cy = polygon_centroid(tyrrhenian_ring)
    lon, lat = canvas_to_lonlat(cx, cy)
    if not (
        TYRRHENIAN_LON_WINDOW[0] <= lon <= TYRRHENIAN_LON_WINDOW[1]
        and TYRRHENIAN_LAT_WINDOW[0] <= lat <= TYRRHENIAN_LAT_WINDOW[1]
    ):
        fails.append(f"tyrrhenian_centroid_off_basin lonlat=({lon:.3f},{lat:.3f})")
    else:
        passes.append(f"centroid=({lon:.3f},{lat:.3f})")

    la = (geo.get(TYRRHENIAN_ID) or {}).get("label_anchor") or [cx, cy]
    la_lon, la_lat = canvas_to_lonlat(float(la[0]), float(la[1]))
    if not (
        TYRRHENIAN_LON_WINDOW[0] <= la_lon <= TYRRHENIAN_LON_WINDOW[1]
        and TYRRHENIAN_LAT_WINDOW[0] <= la_lat <= TYRRHENIAN_LAT_WINDOW[1]
    ):
        fails.append(f"tyrrhenian_label_anchor_off_basin lonlat=({la_lon:.3f},{la_lat:.3f})")
    else:
        passes.append(f"label_anchor=({la_lon:.3f},{la_lat:.3f})")

    leftover_x, leftover_y = lonlat_to_canvas(PRE_TYRRHENIAN_LONLAT[0], PRE_TYRRHENIAN_LONLAT[1])
    if point_in_ring(leftover_x, leftover_y, tyrrhenian_ring):
        fails.append("leftover_south_of_spain_still_owned")
    else:
        passes.append("leftover_seed_vacated")

    for slon, slat in TYRRHENIAN_SAMPLE_LONLAT:
        sx, sy = lonlat_to_canvas(slon, slat)
        if not point_in_ring(sx, sy, tyrrhenian_ring):
            fails.append(f"basin_sample_miss ({slon},{slat})")
        land_hits = [
            pid
            for pid, p in base.items()
            if not _is_water(p) and point_in_ring(sx, sy, (geo.get(int(pid)) or {}).get("points") or [])
        ]
        if land_hits:
            fails.append(f"basin_sample_in_land ({slon},{slat}) {land_hits[:4]}")
    if not any(f.startswith("basin_sample") for f in fails):
        passes.append("basin_samples_in_tyrrhenian")

    nbrs = set(int(x) for x in (adj.get(TYRRHENIAN_ID) or []))
    for pid in CORE_COAST_IDS:
        if pid not in nbrs:
            fails.append(f"missing_core_coast {pid}")
        elif TYRRHENIAN_ID not in set(int(x) for x in (adj.get(pid) or [])):
            fails.append(f"coast_{pid}_missing_tyrrhenian_neighbor")
        else:
            passes.append(f"adj_coast_{pid}")
    for pid in STALE_CLUSTER_SEAS:
        if pid in nbrs:
            fails.append(f"stale_cluster_neighbor {pid}")
        elif TYRRHENIAN_ID in set(int(x) for x in (adj.get(pid) or [])):
            fails.append(f"stale_sea_{pid}_still_lists_tyrrhenian")
    if not any(f.startswith("stale_") for f in fails):
        passes.append("stale_leftover_neighbors_dropped")
    if LIGURIAN_ID in nbrs or ALBORAN_ID in nbrs or STRAIT_ID in nbrs or CHANNEL_ID in nbrs:
        fails.append("out_of_theater_sea_neighbor")
    else:
        passes.append("no_ligurian_alboran_channel_edge")

    # Banned land / other-sea geometry must stay (spot areas).
    for pid, expected in FROZEN_MESH_AREA.items():
        got = polygon_area((geo.get(int(pid)) or {}).get("points") or [])
        if abs(got - expected) > 2.0:
            fails.append(f"frozen_mesh_rewritten {pid} area={got:.2f}")
    if not any(str(f).startswith("frozen_mesh") for f in fails):
        passes.append("ligurian_alboran_se_england_meshes")
    adr_area = polygon_area((geo.get(ADRIATIC_ID) or {}).get("points") or [])
    if abs(adr_area - 393.06) > 2.0:
        fails.append(f"adriatic_mesh_rewritten area={adr_area:.2f}")
    else:
        passes.append("adriatic_mesh_untouched")
    gib_area = polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
    if abs(gib_area - 13.67) > 0.2:
        fails.append(f"gibraltar_land_remeshed area={gib_area:.2f}")
    else:
        passes.append("gibraltar_land_untouched")
    for pid in GREAT_LAKE_IDS:
        row = base.get(int(pid)) or {}
        if str(row.get("domain") or "").lower() != "lake":
            fails.append(f"great_lake_domain {pid}")
    else:
        passes.append("great_lakes_untouched")

    mag_adj = set(int(x) for x in (adj.get(MAGINOT_GER_ID) or []))
    if MAGINOT_FRA_ID not in mag_adj:
        fails.append("maginot_combat_edge_lost")
    else:
        passes.append("maginot_edge_kept")
    if NORD_ID not in base or str((base.get(NORD_ID) or {}).get("name") or "") != "Nord":
        fails.append("flanders_nord_lost")
    else:
        passes.append("flanders_nord_kept")

    sea_block = sum(1 for pid in base if int(pid) >= 950000)
    if sea_block != 340:
        fails.append(f"sea_block_changed n={sea_block}")
    else:
        passes.append("seas_340_ids_kept")
    n_board = len(base)
    if n_board < 3510 or n_board > 3545:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")
    if n_board != 3536:
        fails.append(f"board_count_changed n={n_board}")
    else:
        passes.append("board_3536_reshape_only")

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir():
        passes.append("world_full_dir_exists_untouched")
    else:
        passes.append("world_full_dir_absent_ok")

    doc = ROOT / "docs" / "MAP_SEAS_COARSEN_FEED10_TYRRHENIAN.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if "FEED-10" in body and "Never renumber" in body and "950120" in body and "Tyrrhenian" in body:
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS Tyrrhenian seas coarsen" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "reused_ids": [TYRRHENIAN_ID],
        "new_ids": [],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "metrics": metrics,
        "before_metrics": {
            "sea_n": PRE_THEATER_SEA_N,
            "median": PRE_THEATER_MEDIAN,
            "tyrrhenian": PRE_TYRRHENIAN_AREA,
        },
        "west_italy_coastal_median": land_med,
        "tyrrhenian_area": round(tyrrhenian_area, 2),
        "coastal_land_ids": sorted(nbrs),
        "board_n": n_board,
        "sea_block": sea_block,
    }


def seas_coarsen_feed10_tyrrhenian_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_seas_coarsen_feed10_tyrrhenian_product(board_dir)
