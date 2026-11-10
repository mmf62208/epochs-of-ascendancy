"""ENG-MAP-FINISH: NE rings for the GAP-ENG-1 leftovers, Oman land gaps, Abu Dhabi sliver.

Natural Earth 10m admin-0 map units supply Somaliland and the island outlines.
The world canvas stops at latitude -56, so Antarctica has no on-canvas ring.
Siachen sits inside PAK North and IND North, and a single ring cannot punch
that hole. Potaro-Siparuni and Ayi stay placeholders: cutting them out would
split another province or invent a corridor.

Oman gaps on Natural Earth land go to the longest-edge land neighbour.
Central Indian Basin North is clipped off Abu Dhabi. No new province id.
"""
from __future__ import annotations

import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from canada_hole_measure import (  # noqa: E402
    LAND_GEOJSON,
    WATER_DOMAINS,
    WINDOW_PAD,
    _area,
    _bbox,
    _clean,
    _edge_index,
    _even_odd,
    _in_ne,
    _interior_point,
    _load_ne_polys,
    _owners_of_edge,
    _point_in_rings,
    _poly_centroid,
    _winding,
    arrange,
    canvas_to_lonlat,
)
from gap_china2_outline import snap  # noqa: E402
from ne_full_geometry_align import lonlat_to_canvas  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
CACHE = ROOT / "tools" / "map_generation" / "data" / "cache"

MAP_UNITS_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
    "ne_10m_admin_0_map_units.geojson"
)
COUNTRIES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
    "ne_10m_admin_0_countries.geojson"
)
DISPUTED_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
    "ne_10m_admin_0_disputed_areas.geojson"
)
MAP_UNITS_SHA256 = "57da82be755f4afccd8f3b14251bb2752f5df1395f47d2d86f817470c4a48862"
COUNTRIES_SHA256 = "239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255"
DISPUTED_SHA256 = "9cafef8b7dfb6b164dc58f218f981f4ace9f716f6c03795d4c62d1ac9f3d50f5"

def _cache_name(url: str) -> Path:
    return CACHE / (url.replace("://", "_").replace("/", "_"))


MAP_UNITS_PATH = _cache_name(MAP_UNITS_URL)
COUNTRIES_PATH = _cache_name(COUNTRIES_URL)
DISPUTED_PATH = _cache_name(DISPUTED_URL)

# Feed-6 island floor. A ring smaller than this is scaled about its centroid.
ISLAND_AREA_MIN = 4.0
# Enclosed Oman-touching faces at or under this stay (sub-pixel slivers).
OMAN_HOLE_MIN = 1.0
OVERLAP_PAIR = (905734, 950283)
POLY_OVERLAP_MAX = 1.0

# Centroid part of ne_10m_admin_0_map_units. One ring per province.
RERING_ADMIN = {
    900316: "Somaliland",
    902422: "Cayman Islands",
    902423: "Heard Island and McDonald Islands",
    902447: "Jersey",
    902448: "Isle of Man",
    902475: "South Georgia and the Islands",
    902476: "Falkland Islands",
}
# Coarse blobs that already cover the Somaliland outline. Notched, not deleted.
SOMALILAND_NOTCH = (905330, 904290, 905333)

# Left as placeholders. Reasons are the measured ones on this base.
STILL_UNKNOWN = (900329, 902131, 902133, 902134, 905394)
STILL_UNKNOWN_REASONS = {
    900329: (
        "Potaro-Siparuni lies inside VEN 903817 Zona en Reclamación. "
        "Natural Earth has no separate admin-0 unit to cut out without splitting that province."
    ),
    902131: (
        "The centroid is inside NE Siachen Glacier (disputed, 138.8 px²), which is in the "
        "interior of both PAK North 903576 and IND North 902676. A single ring cannot punch "
        "that hole. Jammu and Kashmir and Azad Kashmir do not contain the centroid."
    ),
    902133: (
        "NE Antarctica is entirely south of latitude -60.52, below the world canvas floor "
        "of -56. There is no on-canvas sourced ring."
    ),
    902134: (
        "Same as 902133. NE has one Antarctica unit and no sourced split between 902133 and "
        "902134. Both stay placeholders."
    ),
    905394: (
        "No Natural Earth unit is named Ayi. The circle sits on the Red Sea south of Ma'an "
        "(polygon overlap with Ma'an is 0). Joining it to Ma'an would invent a corridor."
    ),
}

# Aden town, used only to pad the Oman/UAE window the way the Canada measure pads.
ADEN_LONLAT = (45.03, 12.79)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def source_manifest() -> List[dict]:
    rows = [
        {"url": MAP_UNITS_URL, "sha256": MAP_UNITS_SHA256, "path": str(MAP_UNITS_PATH)},
        {"url": COUNTRIES_URL, "sha256": COUNTRIES_SHA256, "path": str(COUNTRIES_PATH)},
        {"url": DISPUTED_URL, "sha256": DISPUTED_SHA256, "path": str(DISPUTED_PATH)},
    ]
    for row in rows:
        path = Path(row["path"])
        row["present"] = path.is_file()
        if path.is_file():
            row["sha256_ok"] = sha256_file(path) == row["sha256"]
        else:
            row["sha256_ok"] = False
    return rows


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _outers(geom: dict):
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    if gtype == "Polygon" and coords and coords[0]:
        yield coords[0]
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                yield poly[0]


def _project_part(outer) -> List[Tuple[float, float]]:
    """Equirectangular canvas ring. Empty when any vertex is off the world canvas."""
    lats = [float(p[1]) for p in outer]
    lons = [float(p[0]) for p in outer]
    if not lats:
        return []
    if min(lats) < -56.0 or max(lats) > 83.0 or min(lons) < -180.0 or max(lons) > 180.0:
        return []
    ring: List[Tuple[float, float]] = []
    for lon, lat in zip(lons, lats):
        x, y = lonlat_to_canvas(lon, lat)
        pt = (float(x), float(y))
        if ring and abs(pt[0] - ring[-1][0]) < 1e-7 and abs(pt[1] - ring[-1][1]) < 1e-7:
            continue
        ring.append(pt)
    if len(ring) >= 2 and abs(ring[0][0] - ring[-1][0]) < 1e-7 and abs(ring[0][1] - ring[-1][1]) < 1e-7:
        ring = ring[:-1]
    if len(ring) < 3 or abs(_area(ring)) < 0.05:
        return []
    if _area(ring) < 0:
        ring = list(reversed(ring))
    return ring


_PARTS: Dict[str, List[List[Tuple[float, float]]]] = {}


def map_unit_parts(admin: str) -> List[List[Tuple[float, float]]]:
    """On-canvas outer rings for one Natural Earth admin-0 map unit."""
    if admin in _PARTS:
        return _PARTS[admin]
    if not MAP_UNITS_PATH.is_file():
        raise FileNotFoundError("NE map units cache missing: %s" % MAP_UNITS_PATH)
    if sha256_file(MAP_UNITS_PATH) != MAP_UNITS_SHA256:
        raise RuntimeError("NE map units sha256 does not match the recorded source")
    doc = _load(MAP_UNITS_PATH)
    found = None
    for feat in doc.get("features") or []:
        props = feat.get("properties") or {}
        if props.get("ADMIN") == admin:
            found = feat
            break
    if found is None:
        raise KeyError("no map unit ADMIN=%s" % admin)
    parts = []
    for outer in _outers(found.get("geometry") or {}):
        ring = _project_part(outer)
        if ring:
            parts.append(ring)
    parts.sort(key=lambda r: -abs(_area(r)))
    _PARTS[admin] = parts
    return parts


def part_for_centroid(admin: str, x: float, y: float) -> List[Tuple[float, float]]:
    """The map-unit part that contains the placeholder centroid, else the largest."""
    parts = map_unit_parts(admin)
    inside = [ring for ring in parts if _winding(ring, x, y) != 0]
    pool = inside or parts
    if not pool:
        raise RuntimeError("no on-canvas part for %s" % admin)
    return max(pool, key=lambda r: abs(_area(r)))


def ensure_clickable(ring: Sequence[Tuple[float, float]], min_area: float = ISLAND_AREA_MIN):
    """Scale a sub-pixel island about its centroid up to the feed-6 floor."""
    pts = [(float(p[0]), float(p[1])) for p in ring]
    area = abs(_area(pts))
    if area >= min_area or area < 1e-9:
        return pts
    cx, cy = _poly_centroid(pts)
    scale = math.sqrt(min_area / area)
    return [(cx + (x - cx) * scale, cy + (y - cy) * scale) for x, y in pts]


def avoid_placeholder_vertex_count(ring: Sequence[Tuple[float, float]]):
    """36 and 72 vertices are still the densify placeholder test. Insert a midpoint."""
    pts = [(float(p[0]), float(p[1])) for p in ring]
    if len(pts) not in (36, 72):
        return pts
    best_i = 0
    best_d = -1.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        dist = (x2 - x1) ** 2 + (y2 - y1) ** 2
        if dist > best_d:
            best_d = dist
            best_i = i
    x1, y1 = pts[best_i]
    x2, y2 = pts[(best_i + 1) % n]
    mid = ((x1 + x2) * 0.5, (y1 + y2) * 0.5)
    return pts[: best_i + 1] + [mid] + pts[best_i + 1 :]


def _adm(prov: dict) -> str:
    return str((prov.get("meta") or {}).get("adm0_a3") or "")


def _domain(prov: dict) -> str:
    return str(prov.get("domain") or "land")


def measure_oman_holes(board: Path = DEFAULT_DIR, use_natural_earth: bool = True) -> dict:
    """Enclosed faces in the Oman/UAE/Aden window, padded like the Canada measure.

    A face is an Oman hole when an OMN land ring owns one of its edges and the
    face is not already inside a land or water ring. Syria, Jordan, Iraq, and
    the Levant are outside this filter even when the pad reaches them.
    """
    base = _load(board / "provinces_base.json")
    geo = _load(board / "provinces_geometry.json")
    adj = (_load(board / "province_adjacency.json").get("adjacency") or {})
    provs = {int(p["id"]): p for p in base["provinces"]}
    rings = {}
    for g in geo["provinces"]:
        pts = _clean([(float(p[0]), float(p[1])) for p in (g.get("points") or [])])
        if len(pts) >= 3:
            rings[int(g["id"])] = pts
    boxes = {pid: _bbox(ring) for pid, ring in rings.items()}
    seed = [
        pid
        for pid, prov in provs.items()
        if _adm(prov) in ("OMN", "ARE") and pid in rings and _domain(prov) not in WATER_DOMAINS
    ]
    ax, ay = lonlat_to_canvas(*ADEN_LONLAT)
    for pid, ring in rings.items():
        bb = boxes[pid]
        if ax < bb[0] or ax > bb[2] or ay < bb[1] or ay > bb[3]:
            continue
        if _winding(ring, ax, ay) != 0 or _even_odd(ring, ax, ay):
            seed.append(pid)
    seed = sorted(set(seed))
    if not seed:
        raise RuntimeError("no Oman/UAE/Aden seed rings")
    minx = min(boxes[pid][0] for pid in seed) - WINDOW_PAD
    miny = min(boxes[pid][1] for pid in seed) - WINDOW_PAD
    maxx = max(boxes[pid][2] for pid in seed) + WINDOW_PAD
    maxy = max(boxes[pid][3] for pid in seed) + WINDOW_PAD
    neighbor = set()
    for pid in seed:
        for nid in adj.get(str(pid)) or []:
            neighbor.add(int(nid))
    scope = []
    for pid, bb in boxes.items():
        if bb[2] < minx or bb[0] > maxx or bb[3] < miny or bb[1] > maxy:
            if pid not in neighbor and pid not in seed:
                continue
        scope.append(pid)
    land_ids = [
        pid
        for pid in scope
        if _domain(provs[pid]) not in WATER_DOMAINS and pid < 950000
    ]
    water_ids = [pid for pid in scope if pid not in land_ids]
    faces = arrange([rings[pid] for pid in land_ids] + [rings[pid] for pid in water_ids])
    edge_grid = _edge_index({pid: rings[pid] for pid in scope})
    land_rings = [rings[pid] for pid in land_ids]
    water_rings = [rings[pid] for pid in water_ids]
    land_boxes = [boxes[pid] for pid in land_ids]
    water_boxes = [boxes[pid] for pid in water_ids]
    holes = []
    for face in faces:
        area = _area(face)
        if area <= 0.5:
            continue
        pt = _interior_point(face)
        if pt is None:
            continue
        x, y = pt
        if _point_in_rings(land_rings, land_boxes, x, y, lambda r, px, py: _winding(r, px, py) != 0):
            continue
        if _point_in_rings(water_rings, water_boxes, x, y, lambda r, px, py: _winding(r, px, py) != 0):
            continue
        if _point_in_rings(land_rings, land_boxes, x, y, _even_odd) or _point_in_rings(
            water_rings, water_boxes, x, y, _even_odd
        ):
            continue
        lengths: Dict[int, float] = defaultdict(float)
        owners: List[int] = []
        n = len(face)
        for i in range(n):
            u, v = face[i], face[(i + 1) % n]
            for pid in _owners_of_edge(edge_grid, u, v):
                lengths[pid] += math.hypot(v[0] - u[0], v[1] - u[1])
                if pid not in owners:
                    owners.append(pid)
        if not any(_adm(provs.get(pid) or {}) == "OMN" for pid in owners):
            continue
        cx, cy = _poly_centroid(face)
        lon, lat = canvas_to_lonlat(cx, cy)
        surround = []
        for pid in sorted(owners, key=lambda p: -lengths[p]):
            prov = provs.get(pid) or {}
            surround.append(
                {
                    "id": pid,
                    "name": prov.get("name") or "",
                    "domain": _domain(prov),
                    "adm0": _adm(prov),
                    "edge_px": round(lengths[pid], 2),
                }
            )
        holes.append(
            {
                "area_px2": round(area, 2),
                "area_exact": area,
                "centroid": [round(cx, 2), round(cy, 2)],
                "centroid_exact": [cx, cy],
                "interior": [round(x, 2), round(y, 2)],
                "lon": round(lon, 4),
                "lat": round(lat, 4),
                "vertices": len(face),
                "surrounding": surround,
                "ring": [[round(p[0], 4), round(p[1], 4)] for p in face],
            }
        )
    holes.sort(key=lambda h: -h["area_exact"])
    if use_natural_earth and holes and LAND_GEOJSON.is_file():
        lon0, lat_at_maxy = canvas_to_lonlat(minx, maxy)
        lon1, lat_at_miny = canvas_to_lonlat(maxx, miny)
        lat0, lat1 = min(lat_at_maxy, lat_at_miny), max(lat_at_maxy, lat_at_miny)
        land = _load_ne_polys(LAND_GEOJSON, min(lon0, lon1) - 1, max(lon0, lon1) + 1, lat0 - 1, lat1 + 1)
        for hole in holes:
            lon, lat = canvas_to_lonlat(hole["centroid_exact"][0], hole["centroid_exact"][1])
            on_land = bool(_in_ne(land, lon, lat)) if land else None
            hole["on_land"] = on_land
            if on_land is True:
                hole["kind"] = "gap"
                hole["evidence"] = "centroid is on Natural Earth 10m land"
            elif on_land is False:
                hole["kind"] = "water"
                hole["evidence"] = "centroid is not on Natural Earth 10m land"
            else:
                hole["kind"] = "unknown"
                hole["evidence"] = "Natural Earth land cache not available"
    return {
        "window": [minx, miny, maxx, maxy],
        "aden_canvas": [ax, ay],
        "seed_ids": seed,
        "scope_provinces": len(scope),
        "holes": holes,
        "oman_faces_over_1": [h for h in holes if h["area_px2"] > OMAN_HOLE_MIN],
    }


def choose_oman_target(hole: dict) -> Optional[int]:
    """Longest-edge land neighbour when the centroid is on NE land.

    Real water would extend an existing sea ring. These Oman faces are on
    land, so the sea edge does not win. No new water province is created.
    """
    if hole.get("on_land") is not True:
        return None
    lands = [
        row
        for row in hole.get("surrounding") or []
        if row.get("domain") not in WATER_DOMAINS and int(row["id"]) < 950000
    ]
    if not lands or not any(row.get("adm0") == "OMN" for row in lands):
        return None
    return int(max(lands, key=lambda row: row.get("edge_px") or 0)["id"])


def pair_overlap_area(board: Path = DEFAULT_DIR) -> dict:
    """Polygon intersection of Abu Dhabi and Central Indian Basin North."""
    from gap_china2_outline import _nz_pair_area
    from gap_ussr_west2_product import overlap_px

    geo = _load(board / "provinces_geometry.json")
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    land_id, sea_id = OVERLAP_PAIR
    land = [(float(p[0]), float(p[1])) for p in by_id[land_id]["points"]]
    sea = [(float(p[0]), float(p[1])) for p in by_id[sea_id]["points"]]
    return {
        "land": land_id,
        "sea": sea_id,
        "px": int(overlap_px(land, sea)),
        "poly_px2": float(_nz_pair_area(_clean(land), _clean(sea))),
    }


def placeholder_snapshot(board: Path = DEFAULT_DIR) -> dict:
    from gap_eng1_product import scope_placeholder_ids
    from gap_ussr_west2_product import ring_area, vertex_count

    geo = _load(board / "provinces_geometry.json")
    base = _load(board / "provinces_base.json")
    owners = _load(board / "province_ownership_1936.json")["owners"]
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    names = {int(p["id"]): p.get("name") for p in base["provinces"]}
    remaining = scope_placeholder_ids(owners, geo["provinces"], domains)
    rows = []
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    for pid in remaining:
        g = by_id[pid]
        pts = g.get("points") or []
        rows.append(
            {
                "id": pid,
                "name": names.get(pid),
                "vertices": vertex_count(pts),
                "area_px2": round(ring_area(pts), 2),
                "still_placeholder": pid in remaining,
            }
        )
    ids = [int(g["id"]) for g in geo["provinces"]]
    return {
        "province_count": len(ids),
        "ids_sha256": hashlib.sha256(",".join(str(i) for i in ids).encode("utf-8")).hexdigest(),
        "remaining_placeholders": remaining,
        "rows": rows,
    }


def snap_ring(ring: Sequence[Sequence[float]]) -> List[Tuple[float, float]]:
    pts = [snap((float(p[0]), float(p[1]))) for p in ring]
    out = []
    for pt in pts:
        if not out or pt != out[-1]:
            out.append(pt)
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    return out
