#!/usr/bin/env python3
"""GAP-HAWAII: keep 800094 as Oahu and append the other islands plus a sea.

Geometry is Natural Earth 10m land already in the repo
(tools/map_generation/data/cache/map_tiles/...ne_10m_land.geojson).
Admin-1 is not in the repo. The eight main-island rings in that file are
grouped by longitude:

  lon < -158.6            Kauai and Niihau          905849
  -158.6 <= lon < -157.4  Oahu                      800094 (kept)
  -157.4 <= lon < -156.0  Maui, Molokai, Lanai, Kahoolawe  905850
  lon >= -156.0           Hawaii (Big Island)       905851

The board stores one open ring per province. A multi-island group is one
ring with a there-and-back bridge so the islets stay in the polygon and the
bridge adds no area. The label anchor is the largest island's area centroid
so the NE land check still samples land.

Hawaiian Waters 950340 is a 150 km rectangle around the chain. Its ocean
exit is the nearest existing sea by bbox gap. Marquesas 902396 and Kiribati
902397 are not inside that buffer; they are left unlinked (UNKNOWN).

County ids are the in-repo tiger pilot rows (read-only):
  802984 Honolulu 15003 -> 800094
  800842 Kauai 15007 -> 905849
  800094 Maui 15009 and 802156 Kalawao 15005 -> 905850
  800841 Hawaii 15001 -> 905851

Reserved and unused: 905852-905888, 950341-950342.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple

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

OAHU = 800094
KAUAI = 905849
MAUI = 905850
HAWAII = 905851
WATERS = 950340
LAND_IDS = (KAUAI, MAUI, HAWAII)
NEW_IDS = (KAUAI, MAUI, HAWAII, WATERS)
# GAP_HAWAII_ERAS
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)

# Parent economy / coal at the ADJ-V3 tip, before this split. Re-read from
# these constants so a second run does not split the already-split values.
PARENT_POP = 103439
PARENT_COAL = 5
PARENT_FACTORIES = 10
PARENT_INFRA = 3
PARENT_DEV = 2

# County id -> (geoid, name, playable island). From provinces_pilot_us_tiger.
COUNTY_TO_ISLAND = {
    802984: ("15003", "Honolulu", OAHU),
    800842: ("15007", "Kauai", KAUAI),
    800094: ("15009", "Maui", MAUI),
    802156: ("15005", "Kalawao", MAUI),
    800841: ("15001", "Hawaii", HAWAII),
}

W_PX = 8192.0
H_PX = 4096.0
BUFFER_KM = 150.0
KM_PER_DEG = 111.32

Point = Tuple[float, float]
Ring = List[Point]


def emit_existing_id(pid: int) -> int:
    return int(pid)  # GAP_HAWAII_PID identity


def extra_bogus_links() -> Tuple[Tuple[int, int], ...]:
    return ()  # GAP_HAWAII_BOGUS


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _dumps(doc: Any) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _lonlat_to_canvas(lon: float, lat: float) -> Point:
    x = (lon - (-180.0)) / 360.0 * W_PX
    y = (lat - 83.0) / (-139.0) * H_PX
    return (round(x, 6), round(y, 6))


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
    if abs(acc_a) < 1e-12:
        return (
            sum(p[0] for p in ring) / n,
            sum(p[1] for p in ring) / n,
        )
    return (cx / (3.0 * acc_a), cy / (3.0 * acc_a))


def _area_m2(ring: Sequence[Point]) -> float:
    if not ring:
        return 0.0
    lat0 = sum(p[1] for p in ring) / len(ring)
    mx = KM_PER_DEG * 1000.0 * math.cos(math.radians(lat0))
    my = KM_PER_DEG * 1000.0
    pts = [(p[0] * mx, p[1] * my) for p in ring]
    return abs(_ring_area(pts))


def _ensure_ccw(ring: Sequence[Point]) -> List[Point]:
    out = [(float(p[0]), float(p[1])) for p in ring]
    if out and out[0] == out[-1]:
        out = out[:-1]
    if _ring_area(out) < 0:
        out.reverse()
    return out


def bridge_rings(rings: Sequence[Sequence[Point]]) -> List[Point]:
    """One open ring. Extra islands join by a there-and-back bridge."""
    parts = [_ensure_ccw(r) for r in rings if len(r) >= 3]
    parts.sort(key=lambda r: (-abs(_ring_area(r)), r[0][0], r[0][1]))
    if not parts:
        return []
    acc = list(parts[0])
    for nxt in parts[1:]:
        best = None
        bi = bj = 0
        for i, p in enumerate(acc):
            for j, q in enumerate(nxt):
                dist = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
                if best is None or dist < best:
                    best = dist
                    bi, bj = i, j
        rotated = nxt[bj:] + nxt[:bj]
        acc = acc[: bi + 1] + rotated + [rotated[0], acc[bi]] + acc[bi + 1 :]
    if acc and acc[0] == acc[-1]:
        acc = acc[:-1]
    return [(round(p[0], 6), round(p[1], 6)) for p in acc]


def _exterior_rings(geom: Mapping[str, Any]) -> List[Ring]:
    kind = geom.get("type")
    coords = geom.get("coordinates") or []
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


def _group_for(lon: float, lat: float) -> int:
    if not (-161.5 <= lon <= -154.0 and 18.0 <= lat <= 23.5):
        return 0
    if lon < -158.6:
        return KAUAI
    if lon < -157.4:
        return OAHU
    if lon < -156.0:
        return MAUI
    return HAWAII


def load_island_groups(path: Path = NE_LAND) -> Dict[int, List[Ring]]:
    doc = _load(path)
    groups: Dict[int, List[Ring]] = {OAHU: [], KAUAI: [], MAUI: [], HAWAII: []}
    for feat in doc.get("features") or []:
        for ring in _exterior_rings(feat.get("geometry") or {}):
            if len(ring) < 4:
                continue
            lon = sum(p[0] for p in ring) / len(ring)
            lat = sum(p[1] for p in ring) / len(ring)
            gid = _group_for(lon, lat)
            if gid:
                groups[gid].append([(float(p[0]), float(p[1])) for p in ring])
    missing = [str(pid) for pid, rings in groups.items() if not rings]
    if missing:
        raise SystemExit("NE land is missing Hawaii group(s): %s" % ",".join(missing))
    return groups


def _split_int(total: int, weights: Mapping[int, float]) -> Dict[int, int]:
    keys = sorted(weights)
    scale = sum(weights.values())
    if scale <= 0:
        raise SystemExit("Hawaii area is zero")
    raw = {k: total * weights[k] / scale for k in keys}
    floors = {k: int(math.floor(raw[k])) for k in keys}
    left = total - sum(floors.values())
    order = sorted(keys, key=lambda k: (-(raw[k] - floors[k]), k))
    for key in order[:left]:
        floors[key] += 1
    return floors


def _bbox(points: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), max(xs), min(ys), max(ys)


def _gap_km(a: Tuple[float, float, float, float], b: Tuple[float, float, float, float]) -> float:
    def gap(a0: float, a1: float, b0: float, b1: float) -> float:
        if a1 < b0:
            return b0 - a1
        if b1 < a0:
            return a0 - b1
        return 0.0

    dlon = gap(a[0], a[1], b[0], b[1])
    dlat = gap(a[2], a[3], b[2], b[3])
    lat = (max(a[2], b[2]) + min(a[3], b[3])) / 2.0 if dlat == 0 else (a[2] + a[3] + b[2] + b[3]) / 4.0
    km_lon = dlon * KM_PER_DEG * math.cos(math.radians(lat))
    km_lat = dlat * KM_PER_DEG
    return math.hypot(km_lon, km_lat)


def sea_rectangle(groups: Mapping[int, Sequence[Ring]]) -> List[Point]:
    lons: List[float] = []
    lats: List[float] = []
    for rings in groups.values():
        for ring in rings:
            for lon, lat in ring:
                lons.append(lon)
                lats.append(lat)
    lat_c = (min(lats) + max(lats)) / 2.0
    dlat = BUFFER_KM / KM_PER_DEG
    dlon = BUFFER_KM / (KM_PER_DEG * math.cos(math.radians(lat_c)))
    west, east = min(lons) - dlon, max(lons) + dlon
    south, north = min(lats) - dlat, max(lats) + dlat
    corners = [(west, north), (east, north), (east, south), (west, south)]
    pts: List[Point] = []
    steps = 12
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        for step in range(steps):
            t = step / steps
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts


def _canvas_ring(lonlat: Sequence[Point]) -> List[List[float]]:
    return [[x, y] for x, y in (_lonlat_to_canvas(lon, lat) for lon, lat in lonlat)]


def build_geometry(groups: Mapping[int, Sequence[Ring]]) -> Dict[int, dict]:
    names = {
        OAHU: "Oahu",
        KAUAI: "Kauai\u2013Niihau",
        MAUI: "Maui County",
        HAWAII: "Hawaii",
    }
    out: Dict[int, dict] = {}
    for pid, rings in groups.items():
        sized = sorted(rings, key=lambda r: -_area_m2(r))
        canvas_parts = [_canvas_ring(r) for r in sized]
        bridged = bridge_rings(canvas_parts)
        anchor_ll_ring = sized[0]
        ax, ay = _area_centroid(_canvas_ring(anchor_ll_ring))
        out[pid] = {
            "id": pid,
            "points": [[p[0], p[1]] for p in bridged],
            "label_anchor": [round(ax, 6), round(ay, 6)],
            "meta": {
                "source": "ne_10m_land",
                "gap_hawaii": names[pid],
                "ne_ring_n": len(rings),
            },
            "name": names[pid],
        }
    sea_ll = sea_rectangle(groups)
    sea_xy = _canvas_ring(sea_ll)
    sx, sy = _area_centroid(sea_xy)
    out[WATERS] = {
        "id": WATERS,
        "points": sea_xy,
        "label_anchor": [round(sx, 6), round(sy, 6)],
        "meta": {
            "source": "ne_10m_land",
            "gap_hawaii": "Hawaiian Waters",
            "buffer_km": BUFFER_KM,
            "gis_ne_domain": "water",
        },
    }
    return out


def _mirror_pairs(adj: Dict[str, List[int]]) -> None:
    # GAP_HAWAII_MIRROR
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
    # One direction. _mirror_pairs writes the reverse. GAP_HAWAII_LINK
    nbs = adj.setdefault(str(int(a)), [])
    dst = int(b)
    if dst not in [int(x) for x in nbs]:
        nbs.append(dst)


def _unlink(adj: Dict[str, List[int]], a: int, b: int) -> None:
    for src, dst in ((a, b), (b, a)):
        key = str(src)
        if key in adj:
            adj[key] = [x for x in adj[key] if int(x) != dst]


def build_adjacency(
    adj: Dict[str, List[int]],
    waters_bbox: Tuple[float, float, float, float],
    other_bboxes: Mapping[int, Tuple[float, float, float, float]],
    sea_ids: Iterable[int] = (),
) -> Dict[str, Any]:
    """Replace Oahu's far links with the local chain. Returns the ocean note."""
    for pid in (OAHU, KAUAI, MAUI, HAWAII, WATERS):
        adj.setdefault(str(pid), [])
    # Drop whatever 800094 currently touches, then add the local chain.
    # The old Marquesas / Kiribati links are not inside the 150 km buffer.
    old = [int(x) for x in adj.get(str(OAHU), [])]
    for other in old:
        _unlink(adj, OAHU, other)
    for a, b in (
        (OAHU, WATERS),
        (KAUAI, WATERS),
        (MAUI, WATERS),
        (HAWAII, WATERS),
        (OAHU, KAUAI),
        (OAHU, MAUI),
    ):
        _link(adj, a, b)
    seas = set(int(pid) for pid in sea_ids)
    ranked: List[Tuple[float, int]] = []
    for pid, box in other_bboxes.items():
        if pid == WATERS or pid not in seas:
            continue
        ranked.append((_gap_km(waters_bbox, box), int(pid)))
    ranked.sort()
    nearest_id = ranked[0][1] if ranked else 0
    nearest_km = ranked[0][0] if ranked else -1.0
    if nearest_id:
        _link(adj, WATERS, nearest_id)
    for a, b in extra_bogus_links():
        _link(adj, int(a), int(b))
    # Remap only when a mutant changes emit_existing_id. Identity is a no-op.
    if any(emit_existing_id(int(k)) != int(k) for k in list(adj)):
        remapped: Dict[str, List[int]] = {}
        for key, nbs in adj.items():
            nk = str(emit_existing_id(int(key)))
            remapped.setdefault(nk, [])
            remapped[nk].extend(emit_existing_id(int(b)) for b in nbs)
        adj.clear()
        adj.update({k: sorted(set(remapped[k])) for k in remapped})
    _mirror_pairs(adj)  # GAP_HAWAII_MIRROR_CALL
    marquesas = _gap_km(waters_bbox, other_bboxes[902396]) if 902396 in other_bboxes else None
    kiribati = _gap_km(waters_bbox, other_bboxes[902397]) if 902397 in other_bboxes else None
    return {
        "nearest_sea": nearest_id,
        "nearest_sea_km": round(nearest_km, 1),
        "runner_up": ranked[1] if len(ranked) > 1 else None,
        "marquesas_902396": "UNKNOWN" if marquesas is None or marquesas > 1.0 else "adjacent",
        "marquesas_km": None if marquesas is None else round(marquesas, 1),
        "kiribati_902397": "UNKNOWN" if kiribati is None or kiribati > 1.0 else "adjacent",
        "kiribati_km": None if kiribati is None else round(kiribati, 1),
        "oahu": list(adj.get(str(OAHU)) or []),
    }


def _pretty_base(obj: Mapping[str, Any]) -> str:
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    return "\n".join("    " + line for line in text.splitlines())


def _span(text: str, needle: str) -> Tuple[int, int]:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit("missing %s" % needle)
    brace = text.rfind("{", 0, idx)
    _obj, end = json.JSONDecoder().raw_decode(text, brace)
    # The brace line's indent sits outside the object. Swallow it, or each
    # rewrite stacks another four spaces in front of '{'.
    line = text.rfind("\n", 0, brace) + 1
    if text[line:brace].strip() == "":
        return line, end
    return brace, end


def _replace_span(text: str, needle: str, new_text: str) -> str:
    start, end = _span(text, needle)
    return text[:start] + new_text + text[end:]


def _base_row_oahu(old: Mapping[str, Any]) -> dict:
    meta = dict(old.get("meta") or {})
    merge = dict(meta.get("us_merge") or {})
    merge["gap_hawaii_note"] = (
        "800094 kept as Oahu. merged_from is the pre-split county history. "
        "The old survivor geoid 15009 was Maui County."
    )
    meta["us_merge"] = merge
    meta["tiger_geoid"] = "15003"
    meta["gap_hawaii"] = "Oahu"
    row = {
        "id": OAHU,
        "name": "Oahu",
        "terrain": "plains",
        "domain": "land",
        "core_for_tags": list(old.get("core_for_tags") or []),
        "natural_resources": dict(old.get("natural_resources") or {}),
        "population_base": int(old.get("population_base") or 0),
        "meta": meta,
    }
    return row


def _base_row_land(pid: int, name: str, terrain: str, geoid: str) -> dict:
    return {
        "id": emit_existing_id(pid),
        "name": name,
        "terrain": terrain,
        "domain": "land",
        "core_for_tags": [],
        "natural_resources": {},
        "population_base": 0,
        "meta": {
            "source": "ne_10m_land",
            "statefp": "15",
            "tiger_geoid": geoid,
            "gap_hawaii": name,
            "split_from": OAHU,
        },
    }


def _base_row_sea() -> dict:
    return {
        "id": WATERS,
        "name": "Hawaiian Waters",
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
            "gap_hawaii": "Hawaiian Waters",
            "buffer_km": BUFFER_KM,
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


def _areas(groups: Mapping[int, Sequence[Ring]]) -> Dict[int, float]:
    return {pid: sum(_area_m2(r) for r in rings) for pid, rings in groups.items()}


def apply_layers(groups: Mapping[int, Sequence[Ring]], ocean: Mapping[str, Any]) -> None:
    areas = _areas(groups)
    pop = _split_int(PARENT_POP, areas)
    coal = _split_int(PARENT_COAL, areas)

    # --- round-trip JSON files ---
    for year in ERA_YEARS:
        own_path = D / ("province_ownership_%d.json" % year)
        own = _load(own_path)
        owners = own.setdefault("owners", {})
        parent = owners.get(str(OAHU), "USA")
        for pid in (OAHU, KAUAI, MAUI, HAWAII, WATERS):
            owners[str(emit_existing_id(pid))] = parent
        own_path.write_text(_dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = _load(mem_path)
        reg = mem.setdefault("province_to_region", {})
        st = mem.setdefault("province_to_state", {})
        sup = mem.setdefault("province_to_super_region", {})
        parent_region = reg.get(str(OAHU), 150)
        parent_state = st.get(str(OAHU), 222)
        parent_super = sup.get(str(OAHU), 2)
        for pid in (OAHU, KAUAI, MAUI, HAWAII):
            key = str(emit_existing_id(pid))
            reg[key] = parent_region
            st[key] = parent_state
            sup[key] = parent_super
        reg[str(WATERS)] = 10
        sup[str(WATERS)] = 4
        st.pop(str(WATERS), None)
        mem_path.write_text(_dumps(mem), encoding="utf-8")

    terr = _load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    trows[str(OAHU)] = {"terrain": "plains", "domain": "land"}
    for pid, terrain in ((KAUAI, "mountains"), (MAUI, "mountains"), (HAWAII, "mountains")):
        trows[str(pid)] = {"terrain": terrain, "domain": "land"}
    trows[str(WATERS)] = {"terrain": "sea", "domain": "sea"}
    (D / "province_terrain_layer.json").write_text(_dumps(terr), encoding="utf-8")

    eco = _load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for pid in (OAHU, KAUAI, MAUI, HAWAII):
        erows[str(pid)] = {
            "population": pop[pid],
            "factories": PARENT_FACTORIES if pid == OAHU else 0,
            "infrastructure": PARENT_INFRA,
            "development_level": PARENT_DEV,
        }
    erows[str(WATERS)] = {
        "population": 0,
        "factories": 0,
        "infrastructure": 1,
        "development_level": 0,
    }
    (D / "province_economy_layer.json").write_text(_dumps(eco), encoding="utf-8")

    res = _load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for pid in (OAHU, KAUAI, MAUI, HAWAII):
        if coal[pid]:
            rrows[str(pid)] = {"coal": coal[pid]}
        else:
            rrows[str(pid)] = {}
    rrows[str(WATERS)] = {}
    (D / "province_resources_layer.json").write_text(_dumps(res), encoding="utf-8")

    regions = _load(D / "strategic_regions.json")
    for region in regions.get("regions") or []:
        ids = region.setdefault("province_ids", [])
        if region.get("id") == 150:
            for pid in LAND_IDS:
                if pid not in ids:
                    ids.append(pid)
        if region.get("id") == 10 and WATERS not in ids:
            ids.append(WATERS)
    (D / "strategic_regions.json").write_text(_dumps(regions), encoding="utf-8")

    scaffold = _load(D / "hierarchy_scaffold.json")
    scaffold.setdefault("province_to_region", {})[str(OAHU)] = 150
    scaffold.setdefault("province_to_state", {})[str(OAHU)] = 222
    scaffold.setdefault("province_to_super_region", {})[str(OAHU)] = 2
    for pid in LAND_IDS:
        scaffold["province_to_region"][str(pid)] = 150
        scaffold["province_to_state"][str(pid)] = 222
        scaffold["province_to_super_region"][str(pid)] = 2
    scaffold["province_to_region"][str(WATERS)] = 10
    scaffold["province_to_state"][str(WATERS)] = 0
    scaffold["province_to_super_region"][str(WATERS)] = 4
    scaffold["province_n"] = len(scaffold["province_to_region"])
    scaffold["land_n"] = sum(1 for v in scaffold["province_to_state"].values() if int(v or 0) > 0)
    (D / "hierarchy_scaffold.json").write_text(_dumps(scaffold), encoding="utf-8")

    remap = _load(D / "us_county_to_playable_remap.json")
    table = remap.setdefault("remap", {})
    for county, (_geoid, _name, island) in COUNTY_TO_ISLAND.items():
        table[str(county)] = island
    # The file's cluster list is the survivor table. A separate "survivors"
    # key is not part of the schema; drop it if an earlier run added one.
    remap.pop("survivors", None)
    clusters = list(remap.get("clusters") or [])
    island_ids = {OAHU, KAUAI, MAUI, HAWAII}
    kept = [row for row in clusters if int(row.get("survivor_id") or 0) not in island_ids]
    by_island = {
        OAHU: ("Oahu", [802984]),
        KAUAI: ("Kauai\u2013Niihau", [800842]),
        MAUI: ("Maui County", [800094, 802156]),
        HAWAII: ("Hawaii", [800841]),
    }
    for pid in (OAHU, KAUAI, MAUI, HAWAII):
        name, members = by_island[pid]
        kept.append(
            {
                "survivor_id": pid,
                "state_id": 222,
                "state_name": "Hawaii",
                "name": name,
                "member_ids": members,
            }
        )
    remap["clusters"] = kept
    remap["survivors_n"] = len(kept)
    if "counties_n" in remap:
        remap["dead_n"] = int(remap["counties_n"]) - len(kept)
    (D / "us_county_to_playable_remap.json").write_text(_dumps(remap), encoding="utf-8")

    # --- surgical files ---
    base_text = (D / "provinces_base.json").read_text(encoding="utf-8")
    base_doc = json.loads(base_text)
    old_oahu = next(p for p in base_doc["provinces"] if int(p["id"]) == OAHU)
    rows = [
        _base_row_oahu(old_oahu),
        _base_row_land(KAUAI, "Kauai\u2013Niihau", "mountains", "15007"),
        _base_row_land(MAUI, "Maui County", "mountains", "15009"),
        _base_row_land(HAWAII, "Hawaii", "mountains", "15001"),
        _base_row_sea(),
    ]
    # Mutant (b) rewrites 800094. Drop a duplicate pretty row if the id moved.
    seen = set()
    unique_rows = []
    for row in rows:
        if row["id"] in seen:
            continue
        seen.add(row["id"])
        unique_rows.append(row)
    (D / "provinces_base.json").write_text(_upsert_base(base_text, unique_rows), encoding="utf-8")

    geo_text = (D / "provinces_geometry.json").read_text(encoding="utf-8")
    geos = build_geometry(groups)
    # Keep Oahu's historical merge meta on the geometry row and add the NE source.
    old_geo = json.loads(geo_text)
    old_row = next(g for g in old_geo["provinces"] if int(g["id"]) == OAHU)
    geos[OAHU]["meta"] = {
        "source": "ne_10m_land",
        "geoid": "15003",
        "us_merge": (old_row.get("meta") or {}).get("us_merge") or {},
        "gap_hawaii": "Oahu",
        "ne_ring_n": geos[OAHU]["meta"]["ne_ring_n"],
    }
    geo_rows = [geos[pid] for pid in (OAHU, KAUAI, MAUI, HAWAII, WATERS)]
    (D / "provinces_geometry.json").write_text(_upsert_geometry(geo_text, geo_rows), encoding="utf-8")

    city_path = D / "province_city_layer.json"
    city_text = city_path.read_text(encoding="utf-8")
    city_text = city_text.replace('"city_name": "Hawaii"', '"city_name": "Honolulu"', 1)
    city_path.write_text(city_text, encoding="utf-8")

    states_path = D / "province_states.json"
    states_text = states_path.read_text(encoding="utf-8")
    needle = '"id": 222,'
    start, end = _span(states_text, needle)
    state = json.loads(states_text[start:end])
    ids = list(state.get("province_ids") or [])
    for pid in LAND_IDS:
        if pid not in ids:
            ids.append(pid)
    state["province_ids"] = ids
    states_path.write_text(states_text[:start] + _pretty_base(state) + states_text[end:], encoding="utf-8")

    # Adjacency, then the ADJ-V3 renderer so the committed file stays its output.
    adj_path = D / "province_adjacency.json"
    adj_doc = _load(adj_path)
    adj = {k: [int(x) for x in v] for k, v in (adj_doc.get("adjacency") or {}).items()}
    geo_now = json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))
    lonlat_boxes: Dict[int, Tuple[float, float, float, float]] = {}
    for row in geo_now["provinces"]:
        pts = row.get("points") or []
        if not pts:
            continue
        x0, x1, y0, y1 = _bbox(pts)
        corners = (
            _canvas_to_lonlat(x0, y0),
            _canvas_to_lonlat(x1, y0),
            _canvas_to_lonlat(x0, y1),
            _canvas_to_lonlat(x1, y1),
        )
        lons = [p[0] for p in corners]
        lats = [p[1] for p in corners]
        lonlat_boxes[int(row["id"])] = (min(lons), max(lons), min(lats), max(lats))
    waters_box = lonlat_boxes[WATERS]
    base_now = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    sea_ids = [
        int(p["id"])
        for p in base_now["provinces"]
        if str(p.get("domain") or "") == "sea" and int(p["id"]) != WATERS
    ]
    sea_meta_note = build_adjacency(adj, waters_box, lonlat_boxes, sea_ids)
    for key in adj:
        adj[key] = sorted(set(int(x) for x in adj[key]))
    adj_doc["adjacency"] = {k: adj[k] for k in adj}
    # Counts follow the board. land_shared_coverage stays the ADJ-V3 value.
    stats = adj_doc.setdefault("stats", {})
    land_n = sum(
        1 for p in base_now["provinces"] if str(p.get("domain") or "") == "land"
    )
    stats["province_n"] = len(adj)
    stats["land_n"] = land_n
    stats["water_n"] = len(adj) - land_n
    # Stamp the ocean note onto the sea base row we already wrote.
    base_text = (D / "provinces_base.json").read_text(encoding="utf-8")
    start, end = _span(base_text, '"id": %d' % WATERS)
    sea = json.loads(base_text[start:end])
    sea.setdefault("meta", {})["ocean"] = {
        "nearest_sea": sea_meta_note["nearest_sea"],
        "nearest_sea_km": sea_meta_note["nearest_sea_km"],
        "marquesas_902396": sea_meta_note["marquesas_902396"],
        "marquesas_km": sea_meta_note["marquesas_km"],
        "kiribati_902397": sea_meta_note["kiribati_902397"],
        "kiribati_km": sea_meta_note["kiribati_km"],
    }
    base_text = base_text[:start] + _pretty_base(sea) + base_text[end:]
    (D / "provinces_base.json").write_text(base_text, encoding="utf-8")
    adj_path.write_text(_dumps(adj_doc), encoding="utf-8")
    return None


def refresh_adj_v3() -> None:
    script = ROOT / "tools" / "map_generation" / "scripts" / "generate_adj_v3_rhineland.py"
    import importlib.util

    spec = importlib.util.spec_from_file_location("adjv3_from_hawaii", script)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load ADJ-V3 generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.main([]) != 0:
        raise SystemExit("ADJ-V3 refresh failed")


def main() -> int:
    if not NE_LAND.is_file():
        raise SystemExit("missing NE 10m land: %s" % NE_LAND)
    groups = load_island_groups()
    # ocean is filled inside apply_layers once geometry exists
    apply_layers(groups, {})
    refresh_adj_v3()
    base = _load(D / "provinces_base.json")
    ids = {int(p["id"]) for p in base["provinces"]}
    print(
        "GAP-HAWAII n=%d oahu=%s new=%s"
        % (
            len(ids),
            next(p["name"] for p in base["provinces"] if int(p["id"]) == OAHU),
            all(pid in ids for pid in NEW_IDS),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
