"""FEED-3 Gibraltar island-scale land key — Mike province-sizing bar #2.

The accurate board already has a sea/strait cell named "Gibraltar Strait Zone"
(950019). Cadiz (710671) and Ceuta (710679) are mainland land. The rock itself
is a void just south of Cadiz's isthmus tip. This product is a **one-theater
proof** (not HK, not other keys, not seas coarsening):

* Append Europe ID **711520** "Gibraltar" as a dedicated island-scale land cell
  covering the rock, readable like Malta / Gozo (not Cadiz-sized).
* Dent Cadiz vertices that fall inside that ring (Cadiz ID stays).
* Wire adjacency: Gibraltar ↔ Cadiz (isthmus) and Gibraltar ↔ 950019 (strait).
* Do not add Ceuta as a land neighbor (across-water). Do not write world_full.

Write: tools/map_generation/scripts/apply_gibraltar_island_land.py
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

GIBRALTAR_ID = 711520
CADIZ_ID = 710671
CEUTA_ID = 710679
STRAIT_ID = 950019

# Rock / town WGS84. Island-key ring is Malta-like (readable), not 6.8 km² real.
ROCK_LONLAT = (-5.3536, 36.1408)
# Clockwise from NW. Covers the rock + Cadiz isthmus tip (verts at ~36.152°N).
GIBRALTAR_LONLAT_RING: Tuple[Tuple[float, float], ...] = (
    (-5.46, 36.200),
    (-5.28, 36.200),
    (-5.26, 36.145),
    (-5.30, 36.090),
    (-5.40, 36.085),
    (-5.48, 36.140),
)

ISLAND_AREA_MIN = 4.0
ISLAND_AREA_MAX = 25.0
CADIZ_AREA_FLOOR = 400.0
ROCK_LON_WINDOW = (-5.70, -5.10)
ROCK_LAT_WINDOW = (35.95, 36.30)

FEED_META = "v1_gibraltar_island_land"
PRESERVED_IDS: Tuple[int, ...] = (CADIZ_ID, CEUTA_ID, STRAIT_ID)

Ring = List[List[float]]
Point = List[float]


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
    """Legacy outward dent. Prefer clip_isthmus_from_donor for Cadiz."""
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


def clip_isthmus_from_donor(donor: Sequence[Sequence[float]], taker: Sequence[Sequence[float]]) -> Ring:
    """Cut the donor spike that sits inside taker; share taker's north shore.

    Cadiz's southern verts at the Gibraltar isthmus are a local spike. A latitude
    mid-cut would also drop Cape Trafalgar. Replace only the inside run with
    Gibraltar's two northernmost verts, nudged toward Cadiz so the rock is not
    still inside Cadiz.
    """
    pts = _open_ring(donor)
    taker_pts = _open_ring(taker)
    if len(pts) < 4 or len(taker_pts) < 3:
        return pts
    tcx, tcy = polygon_centroid(taker_pts)
    taker_covers_rock = point_in_ring(tcx, tcy, pts)
    inside = []
    for p in pts:
        if point_in_ring(p[0], p[1], taker_pts):
            inside.append(True)
        elif taker_covers_rock and min_ring_distance([p], taker_pts) <= 4.0:
            inside.append(True)
        else:
            inside.append(False)
    if not any(inside):
        return pts
    idxs = [i for i, flag in enumerate(inside) if flag]
    # Require a single non-wrapping run so Trafalgar (outside) stays.
    if idxs[0] == 0 and idxs[-1] == len(pts) - 1:
        return dent_vertices_inside(pts, taker_pts)
    i0, i1 = idxs[0], idxs[-1]
    if any(not inside[i] for i in range(i0, i1 + 1)):
        return dent_vertices_inside(pts, taker_pts)
    by_north = sorted(taker_pts, key=lambda p: p[1])
    north_a, north_b = by_north[0], by_north[1]
    prev_pt = pts[(i0 - 1) % len(pts)]
    d_a = math.hypot(north_a[0] - prev_pt[0], north_a[1] - prev_pt[1])
    d_b = math.hypot(north_b[0] - prev_pt[0], north_b[1] - prev_pt[1])
    first, second = (north_a, north_b) if d_a <= d_b else (north_b, north_a)
    dcx, dcy = polygon_centroid(pts)
    def _nudge(p: Sequence[float]) -> Point:
        vx, vy = dcx - float(p[0]), dcy - float(p[1])
        nrm = math.hypot(vx, vy) or 1.0
        return [float(p[0]) + 0.40 * vx / nrm, float(p[1]) + 0.40 * vy / nrm]

    return pts[:i0] + [_nudge(first), _nudge(second)] + pts[i1 + 1 :]


def min_ring_distance(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> float:
    best = float("inf")
    for pa in _open_ring(a):
        for pb in _open_ring(b):
            d = math.hypot(pa[0] - pb[0], pa[1] - pb[1])
            if d < best:
                best = d
    return best if best != float("inf") else 0.0


def gibraltar_design_ring() -> Ring:
    return [list(lonlat_to_canvas(lon, lat)) for lon, lat in GIBRALTAR_LONLAT_RING]


def load_board(board_dir: Path) -> Dict[str, Any]:
    base_rows = json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    geo_rows = json.loads((board_dir / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    adj_doc = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8"))
    base = {int(p["id"]): p for p in base_rows}
    geo = {int(g["id"]): g for g in geo_rows}
    adj_raw = adj_doc.get("adjacency") or {}
    adj = {int(k): [int(x) for x in (v or [])] for k, v in adj_raw.items()}
    return {"base": base, "geo": geo, "adj": adj, "adj_doc": adj_doc}


def _geo_object(old: Mapping[str, Any], pid: int, name: str, ring: Ring, extra_meta: Mapping[str, Any]) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta["gibraltar_land_feed"] = FEED_META
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
    head = raw[:close].rstrip()
    path.write_text(head + insert + raw[close:], encoding="utf-8")
    return len(list(new_keys))


def _has_json_key(raw: str, key: str) -> bool:
    return re.search(r'"' + re.escape(str(key)) + r'"\s*:', raw) is not None


def _insert_simple_key_after(raw: str, after_key: str, new_key: str, new_literal: str) -> str:
    pat = re.compile(r'"' + re.escape(after_key) + r'"\s*:\s*("[^"]*"|-?\d+(?:\.\d+)?)')
    m = pat.search(raw)
    if not m:
        raise ValueError(f"simple key {after_key} not found for insert")
    insert = f',\n    "{new_key}": {new_literal}'
    return raw[: m.end()] + insert + raw[m.end() :]


def _insert_simple_key_after_each(raw: str, after_key: str, new_key: str, literal: Optional[str]) -> str:
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
    pat = re.compile(r"(^|[^\d])(" + str(int(after_id)) + r")([^\d])")
    m = pat.search(raw)
    if not m:
        raise ValueError(f"id {after_id} not found to insert sibling {new_id}")
    return raw[: m.end(2)] + f", {new_id}" + raw[m.end(2) :]


def plan_gibraltar_island_land(board_dir: str = "") -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    already = int(GIBRALTAR_ID) in base and int(GIBRALTAR_ID) in geo
    rock_ring = gibraltar_design_ring()
    cadiz_stored = _open_ring((geo.get(CADIZ_ID) or {}).get("points") or [])
    # Always clip from the designed rock ring against current Cadiz. If this
    # apply already ran, Cadiz may already be clipped — clipping again is a no-op
    # when no verts remain inside Gibraltar.
    cadiz_new = clip_isthmus_from_donor(cadiz_stored, rock_ring) if cadiz_stored else []
    if already:
        stored_rock = _open_ring((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
        if stored_rock:
            rock_ring = stored_rock
            # Re-clip stored Cadiz against the stored/design ring (refresh).
            cadiz_new = clip_isthmus_from_donor(cadiz_stored, rock_ring)
    return {
        "already_applied": already,
        "gibraltar_id": GIBRALTAR_ID,
        "cadiz_id": CADIZ_ID,
        "ceuta_id": CEUTA_ID,
        "strait_id": STRAIT_ID,
        "gibraltar_ring": rock_ring,
        "cadiz_ring": cadiz_new,
        "cadiz_area_before": polygon_area(cadiz_stored),
        "cadiz_area_after": polygon_area(cadiz_new),
        "gibraltar_area": polygon_area(rock_ring),
        "new_ids": [GIBRALTAR_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "cadiz_name": str((base.get(CADIZ_ID) or {}).get("name") or "Cádiz"),
        "strait_name": str((base.get(STRAIT_ID) or {}).get("name") or "Gibraltar Strait Zone"),
    }


def apply_gibraltar_island_land(board_dir: str = "") -> Dict[str, Any]:
    """Write Gibraltar land + Cadiz dent. Existing IDs stay."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    plan = plan_gibraltar_island_land(str(d))
    already = bool(plan.get("already_applied"))
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]

    cadiz_old = dict(geo[CADIZ_ID])
    rock_ring: Ring = plan["gibraltar_ring"]
    cadiz_ring: Ring = plan["cadiz_ring"]
    geo_updates = {
        CADIZ_ID: _geo_object(
            cadiz_old,
            CADIZ_ID,
            str(cadiz_old.get("name") or (base.get(CADIZ_ID) or {}).get("name") or "Cádiz"),
            cadiz_ring,
            {"split_child": GIBRALTAR_ID, "role": "donor_isthmus"},
        )
    }
    child_obj = _geo_object(
        cadiz_old,
        GIBRALTAR_ID,
        "Gibraltar",
        rock_ring,
        {
            "split_parent": CADIZ_ID,
            "role": "island_key",
            "nuts_id": "GI001",
            "cntr_code": "UK",
        },
    )
    geo[CADIZ_ID] = geo_updates[CADIZ_ID]
    geo[GIBRALTAR_ID] = child_obj

    cadiz_nbrs = set(adj.get(CADIZ_ID) or [])
    cadiz_nbrs.add(GIBRALTAR_ID)
    adj[CADIZ_ID] = sorted(cadiz_nbrs)
    strait_nbrs = set(adj.get(STRAIT_ID) or [])
    strait_nbrs.add(GIBRALTAR_ID)
    adj[STRAIT_ID] = sorted(strait_nbrs)
    # Isthmus + strait only. Do not land-bridge Ceuta across the water.
    adj[GIBRALTAR_ID] = sorted({CADIZ_ID, STRAIT_ID})

    if already:
        geo_updates[GIBRALTAR_ID] = child_obj
        surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {CADIZ_ID: adj[CADIZ_ID], STRAIT_ID: adj[STRAIT_ID], GIBRALTAR_ID: adj[GIBRALTAR_ID]},
        )
    else:
        surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
        surgical_append_geometry_provinces(d / "provinces_geometry.json", [child_obj])
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {CADIZ_ID: adj[CADIZ_ID], STRAIT_ID: adj[STRAIT_ID]},
        )
        surgical_insert_adjacency_keys(d / "province_adjacency.json", {GIBRALTAR_ID: adj[GIBRALTAR_ID]})

    _append_base_gibraltar(d, base)
    _clone_layer_rows(d)
    _insert_hierarchy_and_ownership(d)
    _insert_state_and_region_ids(d)
    if not already:
        _bump_manifest(d)
        _bump_adj_stats(d)

    return {
        "ok": True,
        "already_applied": already,
        "board_dir": str(d),
        "new_ids": [GIBRALTAR_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_touched": False,
        "gibraltar_area": round(float(plan["gibraltar_area"]), 2),
        "cadiz_area_before": round(float(plan["cadiz_area_before"]), 1),
        "cadiz_area_after": round(float(plan["cadiz_area_after"]), 1),
    }


def _append_base_gibraltar(d: Path, base: Mapping[int, Mapping[str, Any]]) -> None:
    path = d / "provinces_base.json"
    raw = path.read_text(encoding="utf-8")
    if re.search(r'"id":\s*' + str(GIBRALTAR_ID), raw):
        return
    parent = dict(base[CADIZ_ID])
    child = dict(parent)
    child["id"] = GIBRALTAR_ID
    child["name"] = "Gibraltar"
    child["terrain"] = "mountains"
    child["domain"] = "land"
    child["theater"] = "europe_core"
    child["strategic_region_hint"] = "Iberia"
    child["population_base"] = 20000
    child["nuts_id"] = "GI001"
    child["cntr_code"] = "UK"
    child["core_for_tags"] = ["ENG"]
    child["island_class"] = "island"
    child["facility_tier"] = 2
    child["special_features"] = ["fortress", "naval_base"]
    blob = json.dumps(child, indent=2)
    lines = blob.splitlines()
    indented = "    " + lines[0] + "\n" + "\n".join("    " + ln if ln else ln for ln in lines[1:])
    close = raw.rfind("]")
    if close < 0:
        raise ValueError("provinces_base.json missing array close")
    path.write_text(raw[:close].rstrip() + ",\n" + indented + "\n  ]\n}\n", encoding="utf-8")


def _clone_layer_rows(d: Path) -> None:
    layer_files = (
        "province_terrain_layer.json",
        "province_resources_layer.json",
        "province_economy_layer.json",
        "province_city_layer.json",
    )
    overlays: Dict[str, Dict[str, Any]] = {
        "province_terrain_layer.json": {"terrain": "mountains", "domain": "land"},
        "province_resources_layer.json": {},
        "province_economy_layer.json": {
            "population": 20000,
            "factories": 1,
            "infrastructure": 5,
            "development_level": 2,
        },
        "province_city_layer.json": {"city_name": "Gibraltar", "tier": 2},
    }
    for fn in layer_files:
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(GIBRALTAR_ID)):
            continue
        src = overlays[fn]
        blob = json.dumps(src, indent=2)
        lines = blob.splitlines()
        if len(lines) <= 1:
            obj_text = blob
        else:
            body = "\n".join("    " + ln for ln in lines[1:])
            obj_text = "{\n" + body
        raw = _insert_object_key_after(raw, str(CADIZ_ID), str(GIBRALTAR_ID), obj_text)
        path.write_text(raw, encoding="utf-8")


def _insert_hierarchy_and_ownership(d: Path) -> None:
    for path in sorted(d.glob("hierarchy_membership_*.json")):
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(GIBRALTAR_ID)):
            continue
        raw = _insert_simple_key_after_each(raw, str(CADIZ_ID), str(GIBRALTAR_ID), None)
        path.write_text(raw, encoding="utf-8")
    for path in sorted(d.glob("province_ownership_*.json")):
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(GIBRALTAR_ID)):
            continue
        # British rock 1713–present; do not clone SPA from Cadiz.
        raw = _insert_simple_key_after(raw, str(CADIZ_ID), str(GIBRALTAR_ID), '"ENG"')
        path.write_text(raw, encoding="utf-8")


def _insert_state_and_region_ids(d: Path) -> None:
    for fn in ("province_states.json", "strategic_regions.json"):
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        if re.search(r"(^|[^\d])" + str(GIBRALTAR_ID) + r"([^\d]|$)", raw):
            continue
        raw = _insert_id_after_in_int_array(raw, CADIZ_ID, GIBRALTAR_ID)
        path.write_text(raw, encoding="utf-8")


def _ensure_manifest_and_adj_stats(d: Path) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    if int(stats.get("provinces") or 0) < 3527:
        _bump_manifest(d)
    adj_path = d / "province_adjacency.json"
    adj_doc = json.loads(adj_path.read_text(encoding="utf-8"))
    st = adj_doc.get("stats") or {}
    if int(st.get("province_n") or 0) < 3527:
        _bump_adj_stats(d)


def _bump_manifest(d: Path) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    stats["provinces"] = int(stats.get("provinces") or 0) + 1
    stats["land"] = int(stats.get("land") or 0) + 1
    blocks = doc.setdefault("blocks", {})
    if "europe_nuts3" in blocks:
        blocks["europe_nuts3"] = int(blocks["europe_nuts3"]) + 1
    gq = str(doc.get("geometry_quality") or "")
    if FEED_META not in gq:
        doc["geometry_quality"] = (gq + "+" + FEED_META) if gq else FEED_META
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def _bump_adj_stats(d: Path) -> None:
    path = d / "province_adjacency.json"
    raw = path.read_text(encoding="utf-8")

    def _bump(key: str) -> None:
        nonlocal raw
        m = re.search(r'"' + re.escape(key) + r'"\s*:\s*(\d+)', raw)
        if not m:
            return
        raw = raw[: m.start(1)] + str(int(m.group(1)) + 1) + raw[m.end(1) :]

    _bump("province_n")
    _bump("land_n")
    path.write_text(raw, encoding="utf-8")


def _land_named_gibraltar(base: Mapping[int, Mapping[str, Any]]) -> List[int]:
    hits: List[int] = []
    for pid, p in base.items():
        name = str(p.get("name") or "").strip().lower()
        if name == "gibraltar" and str(p.get("domain") or "land").lower() == "land":
            hits.append(int(pid))
    return hits


def build_gibraltar_island_land_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Gibraltar is a dedicated island-scale land key."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]

    for pid, want_name in (
        (CADIZ_ID, "Cádiz"),
        (CEUTA_ID, "Ceuta"),
        (STRAIT_ID, "Gibraltar Strait Zone"),
    ):
        row = base.get(int(pid)) or {}
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_existing_id {pid}")
        elif str(row.get("name") or "") != want_name:
            fails.append(f"{pid} renamed {row.get('name')!r}")
        else:
            passes.append(f"kept_{pid}_{want_name}")

    strait = base.get(STRAIT_ID) or {}
    if str(strait.get("domain") or "").lower() != "strait":
        fails.append("strait_domain_changed")
    else:
        passes.append("strait_950019_still_sea")

    if GIBRALTAR_ID not in base or GIBRALTAR_ID not in geo:
        fails.append("missing_append_id 711520")
    else:
        passes.append("append_id=711520")
        gbase = base[GIBRALTAR_ID]
        if str(gbase.get("name") or "") != "Gibraltar":
            fails.append(f"gibraltar_name={gbase.get('name')!r}")
        if str(gbase.get("domain") or "").lower() != "land":
            fails.append(f"gibraltar_not_land domain={gbase.get('domain')}")
        if int(GIBRALTAR_ID) >= 800000 or int(GIBRALTAR_ID) < 711520:
            fails.append(f"gibraltar_id_left_europe_append_gap {GIBRALTAR_ID}")
        area = polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
        if area < ISLAND_AREA_MIN or area > ISLAND_AREA_MAX:
            fails.append(f"gibraltar_not_island_scale area={area:.2f}")
        else:
            passes.append(f"gibraltar_area={area:.2f}")
        cadiz_area = polygon_area((geo.get(CADIZ_ID) or {}).get("points") or [])
        if cadiz_area < CADIZ_AREA_FLOOR:
            fails.append(f"cadiz_shrunk_too_far area={cadiz_area:.1f}")
        if area >= cadiz_area:
            fails.append("gibraltar_not_smaller_than_cadiz")
        cx, cy = polygon_centroid((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
        lon, lat = canvas_to_lonlat(cx, cy)
        if not (ROCK_LON_WINDOW[0] <= lon <= ROCK_LON_WINDOW[1] and ROCK_LAT_WINDOW[0] <= lat <= ROCK_LAT_WINDOW[1]):
            fails.append(f"gibraltar_centroid_off_rock lonlat=({lon:.3f},{lat:.3f})")
        else:
            passes.append(f"centroid=({lon:.3f},{lat:.3f})")
        rx, ry = lonlat_to_canvas(ROCK_LONLAT[0], ROCK_LONLAT[1])
        if not point_in_ring(rx, ry, (geo.get(GIBRALTAR_ID) or {}).get("points") or []):
            fails.append("rock_wgs84_not_inside_gibraltar")
        else:
            passes.append("rock_inside_gibraltar")
        # Rock must not still be Cadiz / Ceuta / strait-only.
        if point_in_ring(rx, ry, (geo.get(CADIZ_ID) or {}).get("points") or []):
            fails.append("rock_still_inside_cadiz")
        nbrs = set(int(x) for x in (adj.get(GIBRALTAR_ID) or []))
        if CADIZ_ID not in nbrs:
            fails.append("gibraltar_not_adjacent_cadiz")
        else:
            passes.append("adj_cadiz")
        if STRAIT_ID not in nbrs:
            fails.append("gibraltar_not_adjacent_strait")
        else:
            passes.append("adj_strait")
        if CEUTA_ID in nbrs:
            fails.append("gibraltar_land_bridged_ceuta")
        if CADIZ_ID not in set(int(x) for x in (adj.get(GIBRALTAR_ID) or [])):
            pass
        if GIBRALTAR_ID not in set(int(x) for x in (adj.get(CADIZ_ID) or [])):
            fails.append("cadiz_missing_gibraltar_neighbor")

    named = _land_named_gibraltar(base)
    if named != [GIBRALTAR_ID] and GIBRALTAR_ID in base:
        if not named:
            fails.append("no_land_named_gibraltar")
        elif named != [GIBRALTAR_ID]:
            fails.append(f"unexpected_gibraltar_land_ids {named}")
    elif named == [GIBRALTAR_ID]:
        passes.append("one_land_gibraltar")

    # Later FEEDs may append a dedicated HK land key. FEED-3 must not reuse
    # the Gibraltar ID for it.
    hk = [
        int(pid)
        for pid, p in base.items()
        if "hong kong" in str(p.get("name") or "").lower() and str(p.get("domain") or "land").lower() == "land"
    ]
    if GIBRALTAR_ID in hk:
        fails.append(f"gibraltar_id_named_hong_kong {hk}")
    else:
        passes.append("gibraltar_id_not_hk")

    sea_n = sum(1 for p in base.values() if str(p.get("domain") or "").lower() in ("sea", "strait", "ocean"))
    # Lakes are domain=lake; seas+straits stay the 340-cell water block plus lakes.
    sea_block = sum(1 for pid in base if int(pid) >= 950000)
    if sea_block != 340:
        fails.append(f"sea_block_changed n={sea_block}")
    else:
        passes.append("seas_340_unchanged")

    n_board = len(base)
    if n_board < 3510 or n_board > 3545:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")

    own_path = d / "province_ownership_1936.json"
    if own_path.is_file():
        owners = json.loads(own_path.read_text(encoding="utf-8")).get("owners") or {}
        if str(owners.get(str(GIBRALTAR_ID)) or "") != "ENG":
            fails.append(f"gibraltar_owner_1936={owners.get(str(GIBRALTAR_ID))!r}")
        else:
            passes.append("owner_1936_ENG")
        if str(owners.get(str(CADIZ_ID)) or "") != "SPA":
            fails.append("cadiz_owner_changed")

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir():
        wf_ids = {
            int(p["id"])
            for p in json.loads((world_full / "provinces_base.json").read_text(encoding="utf-8")).get("provinces") or []
        }
        if GIBRALTAR_ID in wf_ids:
            fails.append("world_full_received_711520")
        else:
            passes.append("world_full_untouched")
    else:
        passes.append("world_full_dir_absent_ok")

    doc = ROOT / "docs" / "MAP_GIBRALTAR_ISLAND_LAND.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if "FEED-3" in body and "Never renumber" in body and "711520" in body and "950019" in body:
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS gibraltar island-scale land" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "new_ids": [GIBRALTAR_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_dir_exists": world_full.is_dir(),
        "gibraltar_area": round(polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or []), 2),
        "sea_n": sea_n,
        "board_n": n_board,
    }


def gibraltar_island_land_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_gibraltar_island_land_product(board_dir)
