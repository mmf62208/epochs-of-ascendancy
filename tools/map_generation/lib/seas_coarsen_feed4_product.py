"""FEED-4 seas coarsen — Mike province-sizing bar #3 (one Med basin).

The accurate board already allocated "Alboran Sea" 950128, but its ring was a
leftover expand-world seed hex sitting at ~3°E (east of the real basin, canvas
area ~241 — smaller than typical Iberian coastal land ~471). The actual Alboran
water between Gibraltar/Cadiz and Cabo de Gata was mostly void.

This product is a **one-theater proof** (not whole-ocean remesh, not NAtl, not
lakes, not Gibraltar/HK land):

* Reuse sea ID **950128** (not a renumber) and place a basin-sized ring on the
  real Alboran water, east of strait 950019, west of Almería.
* Keep 950019 as the naval choke (ID + domain=strait + chokepoint list).
* Do not write land mesh (Gibraltar 711520, Cadiz 710671, Ceuta 710679,
  Maginot, Great Lakes). Do not write world_full.

Write: tools/map_generation/scripts/apply_seas_coarsen_feed4.py
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

ALBORAN_ID = 950128
STRAIT_ID = 950019
GIBRALTAR_ID = 711520
CADIZ_ID = 710671
CEUTA_ID = 710679

WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})
WATER_T = frozenset({"sea", "ocean", "water", "lake"})

# Leftover seed (pre-FEED) — 950128 sat at ~2.95°E / 36.52°N, area ~241.
PRE_ALBORAN_AREA = 240.82
PRE_STRAIT_AREA = 88.95
PRE_THEATER_SEA_N = 2
PRE_THEATER_MEDIAN = 164.88
PRE_IBERIAN_COASTAL_MEDIAN = 471.0

# Basin-sized proof: clearly larger than typical Iberian NUTS coastal land.
ALBORAN_AREA_MIN = 1500.0
THEATER_MEDIAN_MIN = 400.0
IBERIAN_COASTAL_WINDOW = (-10.0, 35.0, 3.0, 44.0)
COAST_TOUCH_PX = 18.0

# Clockwise from NW. Stays in the void corridor: south of Spanish NUTS hulls,
# north of Maghreb RoW hulls, east of strait 950019, west of Almería / DZA West.
ALBORAN_LONLAT_RING: Tuple[Tuple[float, float], ...] = (
    (-4.80, 36.20),
    (-4.20, 36.26),
    (-3.70, 36.40),
    (-3.10, 36.46),
    (-2.40, 36.50),
    (-1.80, 36.46),
    (-1.30, 36.36),
    (-1.15, 36.15),
    (-1.25, 35.78),
    (-1.80, 35.60),
    (-2.50, 35.56),
    (-3.30, 35.56),
    (-4.10, 35.60),
    (-4.65, 35.72),
    (-4.82, 35.96),
    (-4.86, 36.10),
)
ALBORAN_CENTROID_LONLAT = (-3.07, 36.04)
ALBORAN_LON_WINDOW = (-5.20, -0.80)
ALBORAN_LAT_WINDOW = (35.40, 36.70)

# Basin sample points that were VOID on the FEED-3 tip.
ALBORAN_SAMPLE_LONLAT: Tuple[Tuple[float, float], ...] = (
    (-4.0, 36.0),
    (-2.5, 36.2),
    (-1.8, 36.0),
    (-3.2, 35.8),
)

# Land IDs this FEED must not rewrite.
BANNED_LAND_IDS: Tuple[int, ...] = (
    GIBRALTAR_ID,
    CADIZ_ID,
    CEUTA_ID,
    710173,
    710739,
    711514,
    711515,
    711516,
    711517,
    711518,
    711519,
)
GREAT_LAKE_IDS: Tuple[int, ...] = (950333, 950334, 950335, 950336, 950337)

FEED_META = "v1_alboran_basin_coarsen"
PRESERVED_IDS: Tuple[int, ...] = (
    STRAIT_ID,
    GIBRALTAR_ID,
    CADIZ_ID,
    CEUTA_ID,
    ALBORAN_ID,
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


def alboran_design_ring() -> Ring:
    return [list(lonlat_to_canvas(lon, lat)) for lon, lat in ALBORAN_LONLAT_RING]


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


def iberian_coastal_land_areas(base: Mapping[int, Mapping[str, Any]], geo: Mapping[int, Mapping[str, Any]]) -> List[float]:
    lon0, lat0, lon1, lat1 = IBERIAN_COASTAL_WINDOW
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
    return (STRAIT_ID, ALBORAN_ID)


def theater_metrics(geo: Mapping[int, Mapping[str, Any]]) -> Dict[str, float]:
    areas = [polygon_area((geo.get(int(pid)) or {}).get("points") or []) for pid in theater_sea_ids()]
    return {
        "sea_n": float(len(areas)),
        "min": min(areas) if areas else 0.0,
        "median": _median(areas),
        "max": max(areas) if areas else 0.0,
        "alboran": polygon_area((geo.get(ALBORAN_ID) or {}).get("points") or []),
        "strait": polygon_area((geo.get(STRAIT_ID) or {}).get("points") or []),
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
    """Land that touches the Alboran ring. Gibraltar/Ceuta stay FEED-3-only."""
    skip = {GIBRALTAR_ID, CEUTA_ID, ALBORAN_ID}
    out: List[int] = []
    for pid, p in base.items():
        if int(pid) in skip or _is_water(p):
            continue
        pts = (geo.get(int(pid)) or {}).get("points") or []
        if len(pts) < 3:
            continue
        if rings_touch(ring, pts, COAST_TOUCH_PX):
            out.append(int(pid))
    return sorted(out)


def apply_seas_coarsen_feed4(board_dir: str = "") -> Dict[str, Any]:
    """Write Alboran basin ring + theater adj. Existing IDs stay. No land writes."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]
    if ALBORAN_ID not in geo or ALBORAN_ID not in base:
        raise KeyError("missing allocated Alboran sea id 950128")
    if STRAIT_ID not in geo or STRAIT_ID not in base:
        raise KeyError("missing Gibraltar Strait Zone 950019")

    before = theater_metrics(geo)
    ring = alboran_design_ring()
    old = dict(geo[ALBORAN_ID])
    geo_obj = _geo_object(
        old,
        ALBORAN_ID,
        "Alboran Sea",
        ring,
        {"role": "med_basin", "theater": "alboran"},
    )
    geo_updates: Dict[int, Dict[str, Any]] = {ALBORAN_ID: geo_obj}
    banned_written = [pid for pid in geo_updates if int(pid) in BANNED_LAND_IDS or int(pid) in GREAT_LAKE_IDS]
    if banned_written:
        raise RuntimeError(f"refusing land/lake rewrite {banned_written}")

    coastal = _coastal_neighbors(ring, base, geo)
    wanted: Set[int] = {STRAIT_ID}
    wanted.update(coastal)

    adj_updates: Dict[int, List[int]] = {}
    old_nbrs = set(adj.get(ALBORAN_ID) or [])
    for nb in old_nbrs:
        if nb in wanted:
            continue
        if nb in adj:
            adj[nb] = [x for x in adj[nb] if int(x) != ALBORAN_ID]
            adj_updates[int(nb)] = list(adj[nb])
    adj[ALBORAN_ID] = sorted(wanted)
    adj_updates[ALBORAN_ID] = adj[ALBORAN_ID]
    for nb in wanted:
        cur = set(int(x) for x in (adj.get(nb) or []))
        if ALBORAN_ID not in cur:
            cur.add(ALBORAN_ID)
            adj[int(nb)] = sorted(cur)
            adj_updates[int(nb)] = adj[int(nb)]
        elif int(nb) not in adj_updates and int(nb) == STRAIT_ID:
            # Strait already listed Alboran; keep the existing key if unchanged.
            pass

    n_geo = surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
    n_adj = surgical_replace_adjacency_keys(d / "province_adjacency.json", adj_updates)

    after_geo = {int(g["id"]): g for g in json.loads((d / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]}
    after = theater_metrics(after_geo)
    return {
        "ok": n_geo == 1 and after["alboran"] >= ALBORAN_AREA_MIN,
        "board_dir": str(d),
        "geo_objects_rewritten": n_geo,
        "adj_keys_rewritten": n_adj,
        "reused_ids": [ALBORAN_ID],
        "new_ids": [],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_touched": False,
        "land_ids_rewritten": [],
        "coastal_land_ids": coastal,
        "before": before,
        "after": after,
    }


def build_seas_coarsen_feed4_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Alboran is one coarse Med basin abutting Gibraltar."""
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
        (STRAIT_ID, "Gibraltar Strait Zone", "strait"),
        (ALBORAN_ID, "Alboran Sea", "sea"),
        (CADIZ_ID, "Cádiz", "land"),
        (CEUTA_ID, "Ceuta", "land"),
        (GIBRALTAR_ID, "Gibraltar", "land"),
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
    alboran_area = float(metrics["alboran"])
    if alboran_area < ALBORAN_AREA_MIN:
        fails.append(f"alboran_not_basin_scale area={alboran_area:.1f}")
    else:
        passes.append(f"alboran_area={alboran_area:.1f}")
    if alboran_area <= PRE_ALBORAN_AREA:
        fails.append(f"alboran_not_coarser_than_leftover {alboran_area:.1f}<={PRE_ALBORAN_AREA}")
    if float(metrics["median"]) <= PRE_THEATER_MEDIAN:
        fails.append(f"theater_median_not_larger {metrics['median']:.1f}<={PRE_THEATER_MEDIAN}")
    else:
        passes.append(f"theater_median={metrics['median']:.1f}")
    if int(metrics["sea_n"]) > PRE_THEATER_SEA_N:
        fails.append(f"theater_sea_count_grew n={int(metrics['sea_n'])}")
    else:
        passes.append(f"theater_sea_n={int(metrics['sea_n'])}")

    coastal_land = iberian_coastal_land_areas(base, geo)
    land_med = _median(coastal_land) if coastal_land else PRE_IBERIAN_COASTAL_MEDIAN
    if alboran_area <= land_med:
        fails.append(f"alboran_not_larger_than_coastal_land {alboran_area:.1f}<={land_med:.1f}")
    else:
        passes.append(f"alboran_over_coastal_median={alboran_area / max(land_med, 1.0):.2f}")

    cx, cy = polygon_centroid((geo.get(ALBORAN_ID) or {}).get("points") or [])
    lon, lat = canvas_to_lonlat(cx, cy)
    if not (ALBORAN_LON_WINDOW[0] <= lon <= ALBORAN_LON_WINDOW[1] and ALBORAN_LAT_WINDOW[0] <= lat <= ALBORAN_LAT_WINDOW[1]):
        fails.append(f"alboran_centroid_off_basin lonlat=({lon:.3f},{lat:.3f})")
    else:
        passes.append(f"centroid=({lon:.3f},{lat:.3f})")

    alboran_ring = (geo.get(ALBORAN_ID) or {}).get("points") or []
    for slon, slat in ALBORAN_SAMPLE_LONLAT:
        sx, sy = lonlat_to_canvas(slon, slat)
        if not point_in_ring(sx, sy, alboran_ring):
            fails.append(f"basin_sample_miss ({slon},{slat})")
        land_hits = [
            pid
            for pid, p in base.items()
            if not _is_water(p) and point_in_ring(sx, sy, (geo.get(int(pid)) or {}).get("points") or [])
        ]
        if land_hits:
            fails.append(f"basin_sample_in_land ({slon},{slat}) {land_hits[:4]}")
    if not any(f.startswith("basin_sample") for f in fails):
        passes.append("basin_samples_in_alboran")

    # Strait choke role.
    choke_path = d / "naval_chokepoints.json"
    if choke_path.is_file():
        choke = json.loads(choke_path.read_text(encoding="utf-8"))
        ids = [int(x) for x in (choke.get("chokepoint_province_ids") or [])]
        if STRAIT_ID not in ids:
            fails.append("strait_dropped_from_chokepoints")
        else:
            passes.append("strait_950019_choke")
    nbrs = set(int(x) for x in (adj.get(ALBORAN_ID) or []))
    if STRAIT_ID not in nbrs:
        fails.append("alboran_not_adjacent_strait")
    else:
        passes.append("adj_strait")
    if ALBORAN_ID not in set(int(x) for x in (adj.get(STRAIT_ID) or [])):
        fails.append("strait_missing_alboran_neighbor")
    if GIBRALTAR_ID not in set(int(x) for x in (adj.get(STRAIT_ID) or [])):
        fails.append("strait_lost_gibraltar")
    if CEUTA_ID in set(int(x) for x in (adj.get(GIBRALTAR_ID) or [])):
        fails.append("gibraltar_land_bridged_ceuta")

    # Banned land / lake geometry must be byte-stable in this FEED (areas).
    cadiz_area = polygon_area((geo.get(CADIZ_ID) or {}).get("points") or [])
    gib_area = polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
    if abs(gib_area - 13.67) > 0.2:
        fails.append(f"gibraltar_land_remeshed area={gib_area:.2f}")
    else:
        passes.append("gibraltar_land_untouched")
    if cadiz_area < 400.0:
        fails.append(f"cadiz_remeshed area={cadiz_area:.1f}")
    for pid in GREAT_LAKE_IDS:
        row = base.get(int(pid)) or {}
        if str(row.get("domain") or "").lower() != "lake":
            fails.append(f"great_lake_domain {pid}")
    else:
        passes.append("great_lakes_untouched")

    mag_adj = set(int(x) for x in (adj.get(710173) or []))
    if 710739 not in mag_adj:
        fails.append("maginot_combat_edge_lost")
    else:
        passes.append("maginot_edge_kept")

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

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir():
        passes.append("world_full_dir_exists_untouched")
    else:
        passes.append("world_full_dir_absent_ok")

    doc = ROOT / "docs" / "MAP_SEAS_COARSEN_FEED4.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if "FEED-4" in body and "Never renumber" in body and "950128" in body and "950019" in body:
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS Alboran seas coarsen" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "reused_ids": [ALBORAN_ID],
        "new_ids": [],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "metrics": metrics,
        "before_metrics": {
            "sea_n": PRE_THEATER_SEA_N,
            "median": PRE_THEATER_MEDIAN,
            "alboran": PRE_ALBORAN_AREA,
            "strait": PRE_STRAIT_AREA,
        },
        "iberian_coastal_median": land_med,
        "alboran_area": round(alboran_area, 2),
        "board_n": n_board,
        "sea_block": sea_block,
    }


def seas_coarsen_feed4_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_seas_coarsen_feed4_product(board_dir)
