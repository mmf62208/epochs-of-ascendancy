#!/usr/bin/env python3
"""GAP-USSR-WEST: fill the 1936 UkrSSR holes, re-ring Moscow and Leningrad,
tile the Black Sea onto 950006 / 950123 / 950124.

The Ink sketch is missing. Boxes are a deterministic stand-in for the named
oblasts in the brief, plus three RSFSR-west fills (Smolensk, Kursk, Tula).
Belarus, the Caucasus, Galicia west of ~27.4 E, and Bessarabia are not
claimed. UKR is not a tag in any era file. New-province owners:

  1910 RUS (the tag is present; UKR is not)
  1918 SOV (UKR and RUS are both absent; SOV is the parent owner)
  1936 SOV
  1945 SOV
  2026 RUS (UKR is absent; BLR is Belarus, which this slice does not fill)

No new sea id. Azov is entirely inside Black Sea East 950123.
Shapely is imported only while building geometry. The unit test does not
need it. Does not write provinces_world_full.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gap_ussr_west_parent_blobs.json"
NE_LAND = (
    ROOT
    / "tools"
    / "map_generation"
    / "data"
    / "cache"
    / "map_tiles"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_land.geojson"
)

NEW_ID_START = 905889  # GAP_USSR_NEW_ID
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)
STATE_RUS = 388
REGION_MOSCOW = 5
SUPER_EAST = 3
REWRITE_LAND = (903492, 903493, 903532, 903534)
SEA_WEST = 950124
SEA_CENTRAL = 950006
SEA_EAST = 950123
SEA_IDS = (SEA_WEST, SEA_CENTRAL, SEA_EAST)
AFFECTED_KEEP_IDS = set(REWRITE_LAND) | set(SEA_IDS)

# Parent totals at the stale-pins tip, before this slice splits them.
PARENT_492 = {"population": 4783021, "factories": 27, "coal": 27, "steel": 54, "oil": 27}
PARENT_493 = {"population": 4401621, "factories": 22, "coal": 22, "steel": 44, "oil": 22}
MOSCOW_ECO = {
    "population": 2000000,
    "factories": 8,
    "infrastructure": 7,
    "development_level": 4,
    "industrial_hub": True,
}
LENINGRAD_ECO = {
    "population": 800000,
    "factories": 5,
    "infrastructure": 5,
    "development_level": 3,
    "industrial_hub": True,
}
MOSCOW_RES = {"coal": 1, "steel": 2, "oil": 1}
LENINGRAD_RES = {"coal": 1, "steel": 2, "oil": 1}

# year -> tag. UKR is never emitted.
def owner_for(year: int) -> str:
    table = {
        1910: "RUS",  # GAP_USSR_OWNER_1910
        1918: "SOV",  # GAP_USSR_OWNER_1918
        1936: "SOV",
        1945: "SOV",
        2026: "RUS",  # GAP_USSR_OWNER_2026
    }
    if year not in table:
        raise SystemExit("GAP-USSR unknown era %s" % year)
    return table[year]


ALLOWED_OWNER = {
    1910: frozenset({"RUS", "SOV"}),
    1918: frozenset({"SOV"}),
    1936: frozenset({"SOV"}),
    1945: frozenset({"SOV"}),
    2026: frozenset({"RUS", "BLR", "SOV"}),
}


def owner_allowed(year: int, tag: str) -> bool:
    return tag != "UKR" and tag in ALLOWED_OWNER[year]


# name, rects (west, east, south, north), city, terrain
# ID order is this list. Rects are the brief's oblasts, not an Ink sketch.
NEW_SPECS: List[Tuple[str, Tuple[Tuple[float, float, float, float], ...], str, str]] = [
    ("Kiev", ((28.30, 32.80, 49.15, 51.15),), "Kiev", "plains"),
    ("Vinnytsia", ((27.40, 30.20, 48.05, 49.95),), "Vinnytsia", "plains"),
    ("Chernihiv", ((30.20, 35.20, 50.50, 52.25),), "Chernihiv", "forest"),
    ("Kharkiv", ((32.70, 38.30, 48.90, 50.55),), "Kharkiv", "plains"),
    ("Dnipropetrovsk", ((32.30, 37.10, 46.25, 49.20),), "Dnipropetrovsk", "plains"),
    ("Odessa", ((29.90, 33.70, 45.40, 47.90),), "Odessa", "plains"),
    (
        "Donetsk",
        ((36.50, 38.75, 46.80, 49.10), (38.15, 40.05, 47.90, 49.60)),
        "Donetsk",
        "plains",
    ),
    ("Crimean ASSR", ((32.40, 36.75, 44.35, 46.25),), "Simferopol", "plains"),
    ("Smolensk", ((31.90, 35.40, 53.30, 56.10),), "Smolensk", "forest"),
    ("Kursk", ((32.40, 39.20, 50.40, 53.70),), "Kursk", "forest"),
    ("Tula", ((34.70, 39.90, 53.40, 54.90),), "Tula", "forest"),
]

MOSCOW_RECT = (35.50, 40.30, 54.70, 56.70)
LENINGRAD_RECT = (27.80, 35.50, 58.45, 61.30)
# Black Sea partition. Azov is applied before the lon cuts so it stays one zone.
AZOV_RECT = (34.70, 39.45, 45.15, 47.35)
SEA_WINDOW = (27.45, 41.15, 41.95, 47.35)  # west, south, east, north
SEA_WEST_MAX = 33.15
SEA_EAST_MIN = 36.60

MUST_CITY = {
    "Kiev": (30.5234, 50.4501),
    "Vinnytsia": (28.48, 49.23),
    "Chernihiv": (31.29, 51.49),
    "Kharkiv": (36.23, 49.99),
    "Dnipropetrovsk": (35.05, 48.46),
    "Odessa": (30.73, 46.48),
    "Donetsk": (37.80, 48.00),
    "Crimean ASSR": (34.10, 44.95),
    "Smolensk": (32.05, 54.78),
    "Kursk": (36.19, 51.74),
    "Tula": (37.62, 54.20),
}
EXTRA_IN = {
    # Sevastopol's harbour point is water on the 10m land mask.
    "Sevastopol": ((33.60, 44.70), "Crimean ASSR"),
    "Zhytomyr": ((28.66, 50.25), "Kiev"),
    "Mykolaiv": ((32.00, 46.97), "Odessa"),
    "Zaporizhzhia": ((35.14, 47.84), "Dnipropetrovsk"),
    "Mariupol": ((37.54, 47.10), "Donetsk"),
    "Luhansk": ((39.31, 48.57), "Donetsk"),
    "Bryansk": ((34.37, 53.25), "Kursk"),
    "Orel": ((36.07, 52.97), "Kursk"),
    "Kaluga": ((36.26, 54.51), "Tula"),
    "Poltava": ((34.55, 49.59), "Kharkiv"),
    "Sumy": ((34.80, 50.91), "Chernihiv"),
    "Moscow": ((37.62, 55.75), "Moscow"),
    "Leningrad": ((30.31, 59.93), "Leningrad oblast"),
    "Rostov": ((39.70, 47.22), "RUS West"),
    "Petrozavodsk": ((34.35, 61.78), "RUS West"),
}
# These stay outside the new oblasts. Belarus and Galicia are out of scope.
MUST_OUT = {
    "Minsk": (27.56, 53.90),
    "Lviv": (24.03, 49.84),
    "Chisinau": (28.86, 47.01),
    "Gomel": (31.00, 52.43),
    "Vitebsk": (30.20, 55.19),
    "Lutsk": (25.34, 50.75),
}


def new_names() -> List[str]:
    return [row[0] for row in NEW_SPECS]


def new_id_block() -> List[int]:
    return list(range(NEW_ID_START, NEW_ID_START + len(NEW_SPECS)))


def ids_by_name() -> Dict[str, int]:
    return {name: pid for name, pid in zip(new_names(), new_id_block())}


def mirror_adjacency(adj: Dict[str, List[int]]) -> None:
    _mirror_pairs(adj)  # GAP_USSR_MIRROR_CALL


def _mirror_pairs(adj: Dict[str, List[int]]) -> None:
    pending: List[Tuple[str, int]] = []
    for src, nbs in adj.items():
        for dst in nbs:
            key = str(int(dst))
            if int(src) not in [int(x) for x in adj.get(key, [])]:
                pending.append((key, int(src)))
    for key, dst in pending:
        adj.setdefault(key, []).append(dst)
    for key in adj:
        adj[key] = sorted(set(int(x) for x in adj[key]))


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _dumps(doc: Any) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _rect_area(rects: Sequence[Tuple[float, float, float, float]]) -> float:
    return sum(max(0.0, e - w) * max(0.0, n - s) for w, e, s, n in rects)


def _ring_area(ring: Sequence[Tuple[float, float]]) -> float:
    if len(ring) < 3:
        return 0.0
    acc = 0.0
    for i, p in enumerate(ring):
        q = ring[(i + 1) % len(ring)]
        acc += p[0] * q[1] - q[0] * p[1]
    return acc / 2.0


def _open_ring(ring: Sequence[Tuple[float, float]]) -> List[Tuple[float, float]]:
    out = [(float(p[0]), float(p[1])) for p in ring]
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    return out


def _ensure_ccw(ring: Sequence[Tuple[float, float]]) -> List[Tuple[float, float]]:
    out = _open_ring(ring)
    if _ring_area(out) < 0:
        out.reverse()
    return out


def bridge_rings(rings: Sequence[Sequence[Tuple[float, float]]]) -> List[Tuple[float, float]]:
    parts = [_ensure_ccw(r) for r in rings if len(_open_ring(r)) >= 3]
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
    return [(round(p[0], 4), round(p[1], 4)) for p in _open_ring(acc)]


def _snap_land_anchor(geom, lon: float, lat: float) -> Tuple[float, float]:
    """Move a coastal city anchor onto the coarse NE land mask, staying inside geom.

    map_accuracy_qc samples label_anchor on a 2048x1024 mask. Odessa's harbour
    point falls in a water pixel there even though the province ring is land.
    """
    from shapely.geometry import Point

    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import (
        DEFAULT_NE_LAND,
        load_ne_land_features,
        rasterize_land_mask,
        sample_mask,
        lonlat_to_canvas,
    )

    if not hasattr(_snap_land_anchor, "_mask"):
        _snap_land_anchor._mask = rasterize_land_mask(
            load_ne_land_features(DEFAULT_NE_LAND), width=2048, height=1024
        )
    mask = _snap_land_anchor._mask

    def ok(x: float, y: float) -> bool:
        if not geom.intersects(Point(x, y)):
            return False
        cx, cy = lonlat_to_canvas(x, y)
        return bool(sample_mask(mask, cx, cy))

    if ok(lon, lat):
        return (lon, lat)
    for step in (0.05, 0.1, 0.2, 0.4):
        for dlat in (0.0, step, -step, 2 * step, -2 * step):
            for dlon in (0.0, -step, step, -2 * step, 2 * step):
                if ok(lon + dlon, lat + dlat):
                    return (lon + dlon, lat + dlat)
    return (lon, lat)


def _point_in_ring(x: float, y: float, ring: Sequence[Tuple[float, float]]) -> bool:
    pts = _open_ring(ring)
    n = len(pts)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            den = (yj - yi) if (yj - yi) != 0.0 else 1e-12
            if x < (xj - xi) * (y - yi) / den + xi:
                inside = not inside
        j = i
    return inside


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


def _split_int(total: int, weights: Mapping[str, float]) -> Dict[str, int]:
    denom = sum(weights.values()) or 1.0
    raw = {k: total * float(w) / denom for k, w in weights.items()}
    out = {k: int(v) for k, v in raw.items()}
    rem = int(total) - sum(out.values())
    order = sorted(raw, key=lambda k: -(raw[k] - out[k]))
    for key in order:
        if rem <= 0:
            break
        out[key] += 1
        rem -= 1
    return out


def _as_polys(geom) -> list:
    from shapely.geometry import GeometryCollection, MultiPolygon, Polygon

    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [] if geom.area <= 0 else [geom]
    if isinstance(geom, (MultiPolygon, GeometryCollection)):
        out = []
        for g in geom.geoms:
            out.extend(_as_polys(g))
        return out
    return []


def _rect_poly(rects: Sequence[Tuple[float, float, float, float]]):
    from shapely.geometry import box
    from shapely.ops import unary_union

    return unary_union([box(w, s, e, n) for w, e, s, n in rects])


def _clean(geom, min_area: float):
    from shapely.ops import unary_union

    parts = [p for p in _as_polys(geom) if p.area >= min_area]
    if not parts:
        parts = _as_polys(geom)
        parts.sort(key=lambda p: -p.area)
        parts = parts[:1]
    if not parts:
        return geom
    return unary_union(parts)


def _simplify_keep(geom, city_ll: Optional[Tuple[float, float]]):
    from shapely.geometry import Point

    geom = geom.buffer(0)
    if geom.is_empty:
        return geom
    city = Point(*city_ll) if city_ll else None
    for tol in (0.02, 0.01, 0.0):
        trial = geom if tol == 0.0 else geom.simplify(tol, preserve_topology=True)
        trial = trial.buffer(0)
        if city is None or trial.contains(city) or trial.intersects(city):
            # Drop dust, but never the part that holds the city.
            kept = []
            for part in _as_polys(trial):
                if part.area >= 0.012 or (city is not None and part.intersects(city)):
                    kept.append(part)
            if not kept:
                return trial
            from shapely.ops import unary_union

            merged = unary_union(kept).buffer(0)
            if city is None or merged.intersects(city):
                return merged
    return geom


def _to_canvas_ring(geom) -> List[List[float]]:
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import lonlat_to_canvas

    parts = []
    for poly in _as_polys(geom):
        coords = list(poly.exterior.coords)
        if len(coords) >= 2 and coords[0] == coords[-1]:
            coords = coords[:-1]
        if len(coords) < 3:
            continue
        parts.append([lonlat_to_canvas(float(x), float(y)) for x, y in coords])
    bridged = bridge_rings(parts)
    return [[p[0], p[1]] for p in bridged]


def _canvas_to_lonlat(x: float, y: float) -> Tuple[float, float]:
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS

    lon_min, _lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + float(x) / (w - 1.0) * (lon_max - lon_min)
    lat = lat_max - float(y) / (h - 1.0) * (lat_max - lon_min and (lat_max - WORLD_BBOX[1]))
    return lon, lat


def build_geometry() -> Dict[str, Any]:
    """Return name->shapely geom plus sea geoms and a text report. No file writes."""
    from shapely.geometry import Point, Polygon, box, shape
    from shapely.ops import unary_union
    from shapely.prepared import prep

    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS, lonlat_to_canvas

    def c2ll(x: float, y: float) -> Tuple[float, float]:
        lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
        w, h = WORLD_CANVAS
        lon = lon_min + float(x) / (w - 1.0) * (lon_max - lon_min)
        lat = lat_max - float(y) / (h - 1.0) * (lat_max - lat_min)
        return lon, lat

    if not FIXTURE.is_file():
        raise SystemExit("missing parent fixture %s" % FIXTURE)
    fixture = _load(FIXTURE)
    parent = {}
    for key, ring in (fixture.get("rings") or {}).items():
        ll = [c2ll(float(p[0]), float(p[1])) for p in ring]
        if ll[0] != ll[-1]:
            ll = ll + [ll[0]]
        poly = Polygon(ll)
        if not poly.is_valid:
            poly = poly.buffer(0)
        parent[int(key)] = poly

    base = {int(p["id"]): p for p in _load(D / "provinces_base.json")["provinces"]}
    geo = _load(D / "provinces_geometry.json")
    work = box(20.0, 40.0, 66.0, 66.0)
    keep_parts = []
    sea_keep = []
    for row in geo["provinces"]:
        pid = int(row["id"])
        if pid in AFFECTED_KEEP_IDS:
            continue
        pts = row.get("points") or []
        if len(pts) < 3:
            continue
        ll = [c2ll(float(p[0]), float(p[1])) for p in pts]
        xs = [p[0] for p in ll]
        ys = [p[1] for p in ll]
        if max(xs) < 20 or min(xs) > 66 or max(ys) < 40 or min(ys) > 66:
            continue
        if ll[0] != ll[-1]:
            ll = ll + [ll[0]]
        poly = Polygon(ll)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty or not poly.intersects(work):
            continue
        domain = str((base.get(pid) or {}).get("domain") or "")
        if domain == "land":
            keep_parts.append(poly)
        elif pid >= 950000:
            sea_keep.append(poly)
    keep = unary_union(keep_parts).buffer(0) if keep_parts else Polygon()
    other_sea = unary_union(sea_keep).buffer(0) if sea_keep else Polygon()

    ne = _load(NE_LAND)
    ne_window = box(20.0, 40.0, 66.0, 66.0)
    ne_parts = []
    for feat in ne.get("features") or []:
        geom = shape(feat.get("geometry") or {})
        if geom.is_empty or not geom.intersects(ne_window):
            continue
        ne_parts.append(geom.intersection(ne_window))
    land = unary_union(ne_parts).buffer(0)

    moscow_city = MUST_CITY and (37.62, 55.75)
    len_city = (30.31, 59.93)
    moscow = _simplify_keep(
        land.intersection(_rect_poly((MOSCOW_RECT,))).difference(keep),
        moscow_city,
    )
    leningrad = _simplify_keep(
        land.intersection(_rect_poly((LENINGRAD_RECT,))).difference(keep),
        len_city,
    )
    spec_by = {name: spec for spec in NEW_SPECS for name in (spec[0],)}
    ordered = sorted(NEW_SPECS, key=lambda spec: (_rect_area(spec[1]), spec[0]))
    claim = unary_union([_rect_poly(spec[1]) for spec in NEW_SPECS]).buffer(0)
    remaining = land.intersection(claim).difference(keep).difference(moscow).difference(leningrad).buffer(0)
    geoms: Dict[str, Any] = {}
    for name, rects, _city, _terrain in ordered:
        piece = remaining.intersection(_rect_poly(rects)).buffer(0)
        city = MUST_CITY[name]
        piece = _simplify_keep(piece, city)
        geoms[name] = piece
        remaining = remaining.difference(piece).buffer(0)
    # Anything left inside the claim rects joins the nearest named centroid.
    if not remaining.is_empty and remaining.area > 0.01:
        centres = {}
        for name, geom in geoms.items():
            if geom.is_empty:
                centres[name] = Point(*MUST_CITY[name])
            else:
                centres[name] = geom.representative_point()
        for part in _as_polys(remaining):
            if part.area < 0.008:
                continue
            pt = part.representative_point()
            best = min(centres, key=lambda n: pt.distance(centres[n]))
            geoms[best] = geoms[best].union(part).buffer(0)

    donor492 = parent[903492].intersection(land).difference(keep).buffer(0)
    donor493 = parent[903493].intersection(land).difference(keep).buffer(0)
    painted = unary_union([geoms[n] for n in geoms] + [moscow, leningrad]).buffer(0)
    rus492 = _clean(donor492.difference(painted), 0.05)
    rus493 = _clean(donor493.difference(painted), 0.03)
    geoms["Moscow"] = moscow
    geoms["Leningrad oblast"] = leningrad
    geoms["RUS West"] = rus492
    geoms["RUS West North"] = rus493

    sea_box = box(* (SEA_WINDOW[0], SEA_WINDOW[1], SEA_WINDOW[2], SEA_WINDOW[3]))
    water = sea_box.difference(land).difference(other_sea).buffer(0)
    # Pull zones off any land ring we are about to ship, including KEEP.
    land_cover = unary_union(
        [g for g in list(geoms.values()) if not g.is_empty] + ([keep] if not keep.is_empty else [])
    ).buffer(0)
    water = water.difference(land_cover).buffer(0)
    azov = box(*AZOV_RECT)
    west_box = box(SEA_WINDOW[0], SEA_WINDOW[1], SEA_WEST_MAX, SEA_WINDOW[3])
    cent_box = box(SEA_WEST_MAX, SEA_WINDOW[1], SEA_EAST_MIN, SEA_WINDOW[3])
    azov_water = water.intersection(azov)
    rest = water.difference(azov)
    sea_west = _clean(rest.intersection(west_box), 0.01)
    sea_cent = _clean(rest.intersection(cent_box).difference(azov), 0.01)
    sea_east = _clean(water.difference(sea_west).difference(sea_cent), 0.01)

    report = _audit_geoms(geoms, sea_west, sea_cent, sea_east, prep)
    canvas: Dict[str, List[List[float]]] = {}
    for name, geom in list(geoms.items()) + [
        ("Black Sea West", sea_west),
        ("Black Sea Zone", sea_cent),
        ("Black Sea East", sea_east),
    ]:
        canvas[name] = _to_canvas_ring(geom)
        if len(canvas[name]) < 3:
            raise SystemExit("GAP-USSR empty ring %s" % name)
    # City anchors must survive the single-ring bridge.
    id_of = ids_by_name()
    id_of.update({
        "Moscow": 903534,
        "Leningrad oblast": 903532,
        "RUS West": 903492,
        "RUS West North": 903493,
    })
    misses = []
    for name, (lon, lat) in list(MUST_CITY.items()) + [("Moscow", (37.62, 55.75)), ("Leningrad oblast", (30.31, 59.93))]:
        key = name if name in canvas else ("Leningrad oblast" if name.startswith("Leningrad") else name)
        ring_name = name if name in ("Moscow", "Leningrad oblast") or name in MUST_CITY else name
        if name in MUST_CITY:
            ring_name = name
        xy = lonlat_to_canvas(lon, lat)
        if not _point_in_ring(xy[0], xy[1], [(p[0], p[1]) for p in canvas[ring_name]]):
            misses.append(name)
    if misses:
        report["bridge_miss"] = misses
    areas = {name: round(float(geom.area), 4) for name, geom in geoms.items()}
    report["areas_deg2"] = areas
    report["sea_areas"] = {
        "west": round(float(sea_west.area), 4),
        "central": round(float(sea_cent.area), 4),
        "east": round(float(sea_east.area), 4),
    }
    anchors: Dict[str, Tuple[float, float]] = {}
    for name, geom in list(geoms.items()) + [
        ("Black Sea West", sea_west),
        ("Black Sea Zone", sea_cent),
        ("Black Sea East", sea_east),
    ]:
        city_ll = None
        if name in MUST_CITY:
            city_ll = MUST_CITY[name]
        elif name == "Moscow":
            city_ll = (37.62, 55.75)
        elif name == "Leningrad oblast":
            city_ll = (30.31, 59.93)
        if city_ll is not None and geom.intersects(Point(*city_ll)):
            anchors[name] = _snap_land_anchor(geom, city_ll[0], city_ll[1])
        else:
            rp = geom.representative_point()
            anchors[name] = _snap_land_anchor(geom, float(rp.x), float(rp.y))
    return {
        "geoms": geoms,
        "canvas": canvas,
        "anchors": anchors,
        "sea": {SEA_WEST: sea_west, SEA_CENTRAL: sea_cent, SEA_EAST: sea_east},
        "donor492": donor492,
        "donor493": donor493,
        "report": report,
        "id_of": id_of,
    }


def _audit_geoms(geoms, sea_west, sea_cent, sea_east, prep) -> dict:
    from shapely.geometry import Point

    fails = []
    prepared = {name: prep(geom) for name, geom in geoms.items() if not geom.is_empty}
    for name, ll in MUST_CITY.items():
        hit = prepared.get(name)
        if hit is None or not hit.intersects(Point(*ll)):
            fails.append("city:%s" % name)
    prepared["Moscow"] = prepared.get("Moscow")
    for label, (ll, expect) in EXTRA_IN.items():
        if expect == "RUS West":
            # Rostov stays on the southern blob; Petrozavodsk on the northern one.
            choices = ("RUS West", "RUS West North")
            ok = any(
                prepared.get(n) is not None and prepared[n].intersects(Point(*ll)) for n in choices
            )
            if label == "Rostov":
                ok = prepared.get("RUS West") is not None and prepared["RUS West"].intersects(Point(*ll))
                ok = ok and not any(
                    prepared.get(n) is not None and prepared[n].intersects(Point(*ll))
                    for n in new_names()
                )
            if label == "Petrozavodsk":
                ok = prepared.get("RUS West North") is not None and prepared["RUS West North"].intersects(Point(*ll))
            if not ok:
                fails.append("extra:%s" % label)
            continue
        geom_name = expect
        if expect == "Leningrad oblast":
            geom_name = "Leningrad oblast"
        hit = prepared.get(geom_name)
        if hit is None or not hit.intersects(Point(*ll)):
            fails.append("extra:%s" % label)
    new_only = [geoms[n] for n in new_names()]
    from shapely.ops import unary_union

    new_union = unary_union(new_only)
    new_prep = prep(new_union)
    for label, ll in MUST_OUT.items():
        if new_prep.intersects(Point(*ll)):
            fails.append("stole:%s" % label)
    # Taganrog stays out of Donetsk.
    if prepared.get("Donetsk") is not None and prepared["Donetsk"].intersects(Point(38.90, 47.24)):
        fails.append("stole:Taganrog")
    sea_prep = {
        "west": prep(sea_west),
        "central": prep(sea_cent),
        "east": prep(sea_east),
    }
    bs = Point(34.0, 43.6)
    if not any(p.intersects(bs) for p in sea_prep.values()):
        fails.append("sea:black")
    az = Point(36.8, 46.2)
    if not sea_prep["east"].intersects(az):
        fails.append("sea:azov")
    if sea_prep["west"].intersects(az) or sea_prep["central"].intersects(az):
        fails.append("sea:azov-split")
    return {"fails": fails}


def _shares(built: Mapping[str, Any]) -> Dict[str, Dict[str, int]]:
    geoms = built["geoms"]
    donor492 = built["donor492"]
    donor493 = built["donor493"]
    names = list(new_names()) + ["Moscow", "Leningrad oblast", "RUS West", "RUS West North"]
    w492 = {}
    w493 = {}
    for name in names:
        geom = geoms[name]
        w492[name] = float(geom.intersection(donor492).area) if not geom.is_empty else 0.0
        w493[name] = float(geom.intersection(donor493).area) if not geom.is_empty else 0.0
    # The parent remainder is the recipient for whatever the donors did not give away.
    pop492 = _split_int(PARENT_492["population"], w492)
    fac492 = _split_int(PARENT_492["factories"], w492)
    coal = _split_int(PARENT_492["coal"], w492)
    steel = _split_int(PARENT_492["steel"], w492)
    oil = _split_int(PARENT_492["oil"], w492)
    pop493 = _split_int(PARENT_493["population"], w493)
    fac493 = _split_int(PARENT_493["factories"], w493)
    coal493 = _split_int(PARENT_493["coal"], w493)
    steel493 = _split_int(PARENT_493["steel"], w493)
    oil493 = _split_int(PARENT_493["oil"], w493)
    out: Dict[str, Dict[str, int]] = {}
    for name in names:
        out[name] = {
            "population": pop492[name] + pop493[name],
            "factories": fac492[name] + fac493[name],
            "coal": coal[name] + coal493[name],
            "steel": steel[name] + steel493[name],
            "oil": oil[name] + oil493[name],
        }
    for name in new_names():
        if out[name]["population"] < 20000:
            out[name]["population"] = 40000 + (ids_by_name()[name] % 5) * 5000
        if out[name]["factories"] < 1:
            out[name]["factories"] = 1
    # Capitals keep their hub totals and add only the sliver carved off a parent.
    out["Moscow"]["population"] += MOSCOW_ECO["population"]
    out["Moscow"]["factories"] += MOSCOW_ECO["factories"]
    out["Leningrad oblast"]["population"] += LENINGRAD_ECO["population"]
    out["Leningrad oblast"]["factories"] += LENINGRAD_ECO["factories"]
    out["Moscow"]["coal"] += MOSCOW_RES["coal"]
    out["Moscow"]["steel"] += MOSCOW_RES["steel"]
    out["Moscow"]["oil"] += MOSCOW_RES["oil"]
    out["Leningrad oblast"]["coal"] += LENINGRAD_RES["coal"]
    out["Leningrad oblast"]["steel"] += LENINGRAD_RES["steel"]
    out["Leningrad oblast"]["oil"] += LENINGRAD_RES["oil"]
    return out


def _link(adj: Dict[str, List[int]], a: int, b: int) -> None:
    if a == b or a <= 0 or b <= 0:
        return
    for src, dst in ((a, b), (b, a)):
        nbs = [int(x) for x in adj.setdefault(str(src), [])]
        if dst not in nbs:
            nbs.append(dst)
        adj[str(src)] = nbs


def _unlink_affected(adj: Dict[str, List[int]], affected: Iterable[int]) -> None:
    aff = {int(x) for x in affected}
    for pid in aff:
        adj[str(pid)] = []
    for key in list(adj):
        adj[key] = [int(x) for x in adj[key] if int(x) not in aff]


def _touching_pairs(built: Mapping[str, Any], base: Mapping[int, dict]) -> List[Tuple[int, int]]:
    from shapely.geometry import Polygon
    from shapely.strtree import STRtree

    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS

    def c2ll(x: float, y: float) -> Tuple[float, float]:
        lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
        w, h = WORLD_CANVAS
        lon = lon_min + float(x) / (w - 1.0) * (lon_max - lon_min)
        lat = lat_max - float(y) / (h - 1.0) * (lat_max - lat_min)
        return lon, lat

    id_of = built["id_of"]
    sea_names = {
        SEA_WEST: "Black Sea West",
        SEA_CENTRAL: "Black Sea Zone",
        SEA_EAST: "Black Sea East",
    }
    # Rebuild sea geoms from the returned sea dict.
    owned: List[Tuple[int, Any]] = []
    for name, geom in built["geoms"].items():
        owned.append((id_of[name], geom))
    for pid, geom in built["sea"].items():
        owned.append((pid, geom))
    aff = {pid for pid, _g in owned}
    geo = _load(D / "provinces_geometry.json")
    others_geom = []
    others_id = []
    for row in geo["provinces"]:
        pid = int(row["id"])
        if pid in aff or pid in AFFECTED_KEEP_IDS:
            continue
        pts = row.get("points") or []
        if len(pts) < 3:
            continue
        ll = [c2ll(float(p[0]), float(p[1])) for p in pts]
        xs = [p[0] for p in ll]
        ys = [p[1] for p in ll]
        if max(xs) < 20 or min(xs) > 66 or max(ys) < 40 or min(ys) > 66:
            continue
        if ll[0] != ll[-1]:
            ll = ll + [ll[0]]
        poly = Polygon(ll)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            continue
        others_geom.append(poly.buffer(0.04))
        others_id.append(pid)
    tree = STRtree(others_geom) if others_geom else None
    pairs = []
    buffered = [(pid, geom.buffer(0.04)) for pid, geom in owned if not geom.is_empty]
    for i, (pid, geom) in enumerate(buffered):
        for oid, other in buffered[i + 1 :]:
            if geom.intersects(other):
                pairs.append((pid, oid))
        if tree is None:
            continue
        hits = tree.query(geom, predicate="intersects")
        for hit in hits:
            pairs.append((pid, others_id[int(hit)]))
    _ = sea_names
    _ = base
    return pairs


def apply_layers(built: Mapping[str, Any]) -> None:
    id_of = dict(built["id_of"])
    # Two geometries share the display name "RUS West"; ids come from id_of.
    shares = _shares(built)
    new_ids = [id_of[name] for name in new_names()]
    spec = {name: row for row in NEW_SPECS for name in (row[0],)}

    for year in ERA_YEARS:
        tag = owner_for(year)
        if not owner_allowed(year, tag):
            raise SystemExit("GAP-USSR refused tag %s for %s" % (tag, year))
        own_path = D / ("province_ownership_%d.json" % year)
        own = _load(own_path)
        owners = own.setdefault("owners", {})
        for pid in new_ids:
            owners[str(pid)] = tag
        own_path.write_text(_dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = _load(mem_path)
        reg = mem.setdefault("province_to_region", {})
        st = mem.setdefault("province_to_state", {})
        sup = mem.setdefault("province_to_super_region", {})
        for pid in new_ids:
            reg[str(pid)] = REGION_MOSCOW
            st[str(pid)] = STATE_RUS
            sup[str(pid)] = SUPER_EAST
        mem_path.write_text(_dumps(mem), encoding="utf-8")

    terrain_of = {name: spec[name][3] for name in new_names()}
    terr = _load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    for name in new_names():
        trows[str(id_of[name])] = {"terrain": terrain_of[name], "domain": "land"}
    (D / "province_terrain_layer.json").write_text(_dumps(terr), encoding="utf-8")

    eco = _load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for name in new_names():
        row = shares[name]
        erows[str(id_of[name])] = {
            "population": int(row["population"]),
            "factories": int(row["factories"]),
            "infrastructure": 3 if name in ("Donetsk", "Kiev", "Kharkiv") else 2,
            "development_level": 2,
        }
    erows["903492"] = {
        "population": int(shares["RUS West"]["population"]),
        "factories": int(shares["RUS West"]["factories"]),
        "infrastructure": 3,
        "development_level": 2,
    }
    erows["903493"] = {
        "population": int(shares["RUS West North"]["population"]),
        "factories": int(shares["RUS West North"]["factories"]),
        "infrastructure": 3,
        "development_level": 2,
    }
    erows["903534"] = dict(MOSCOW_ECO)
    erows["903534"]["population"] = int(shares["Moscow"]["population"])
    erows["903534"]["factories"] = int(shares["Moscow"]["factories"])
    erows["903532"] = dict(LENINGRAD_ECO)
    erows["903532"]["population"] = int(shares["Leningrad oblast"]["population"])
    erows["903532"]["factories"] = int(shares["Leningrad oblast"]["factories"])
    (D / "province_economy_layer.json").write_text(_dumps(eco), encoding="utf-8")

    res = _load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for name in list(new_names()) + ["RUS West", "RUS West North", "Moscow", "Leningrad oblast"]:
        pid = id_of[name]
        row = {}
        for key in ("coal", "steel", "oil"):
            if int(shares[name][key]) > 0:
                row[key] = int(shares[name][key])
        rrows[str(pid)] = row
    (D / "province_resources_layer.json").write_text(_dumps(res), encoding="utf-8")

    regions = _load(D / "strategic_regions.json")
    for region in regions.get("regions") or []:
        if int(region.get("id") or 0) == REGION_MOSCOW:
            rids = [int(x) for x in region.get("province_ids") or []]
            for pid in new_ids:
                if pid not in rids:
                    rids.append(pid)
            region["province_ids"] = rids
            region["province_count"] = len(rids)
    (D / "strategic_regions.json").write_text(_dumps(regions), encoding="utf-8")

    scaffold = _load(D / "hierarchy_scaffold.json")
    for pid in new_ids:
        scaffold.setdefault("province_to_region", {})[str(pid)] = REGION_MOSCOW
        scaffold.setdefault("province_to_state", {})[str(pid)] = STATE_RUS
        scaffold.setdefault("province_to_super_region", {})[str(pid)] = SUPER_EAST
    scaffold["province_n"] = len(scaffold["province_to_region"])
    scaffold["land_n"] = sum(
        1 for v in scaffold["province_to_state"].values() if int(v or 0) > 0
    )
    (D / "hierarchy_scaffold.json").write_text(_dumps(scaffold), encoding="utf-8")

    _write_base(id_of, terrain_of, shares)
    _write_geometry(built)
    _write_cities(id_of)
    _write_state(new_ids)
    _write_adjacency(built)


def _write_base(id_of: Mapping[str, int], terrain_of: Mapping[str, str], shares) -> None:
    path = D / "provinces_base.json"
    text = path.read_text(encoding="utf-8")
    doc = json.loads(text)
    by_id = {int(p["id"]): p for p in doc["provinces"]}
    rows = []
    for name in new_names():
        pid = id_of[name]
        res = {}
        for key in ("coal", "steel", "oil"):
            if int(shares[name][key]) > 0:
                res[key] = int(shares[name][key])
        rows.append(
            {
                "id": pid,
                "name": name,
                "terrain": terrain_of[name],
                "domain": "land",
                "core_for_tags": ["SOV"],
                "natural_resources": res,
                "population_base": int(shares[name]["population"]),
                "meta": {
                    "source": "ne_10m_land",
                    "gap_ussr_west": name,
                    "adm0_a3": "SUN",
                },
            }
        )
    for name, pid in (("RUS West", 903492), ("RUS West North", 903493)):
        old = dict(by_id[pid])
        old["population_base"] = int(shares[name]["population"])
        res = dict(old.get("natural_resources") or {})
        for key in ("coal", "steel", "oil"):
            if int(shares[name][key]) > 0:
                res[key] = int(shares[name][key])
            elif key in res:
                res.pop(key, None)
        old["natural_resources"] = res
        meta = dict(old.get("meta") or {})
        meta["gap_ussr_west"] = "shrunk"
        old["meta"] = meta
        rows.append(old)
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
    path.write_text(text, encoding="utf-8")


def _write_geometry(built: Mapping[str, Any]) -> None:
    path = D / "provinces_geometry.json"
    text = path.read_text(encoding="utf-8")
    id_of = built["id_of"]
    canvas = built["canvas"]
    labels = built["anchors"]
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import lonlat_to_canvas

    name_by_pid = {
        id_of["Kiev"]: "Kiev",
        id_of["Vinnytsia"]: "Vinnytsia",
        id_of["Chernihiv"]: "Chernihiv",
        id_of["Kharkiv"]: "Kharkiv",
        id_of["Dnipropetrovsk"]: "Dnipropetrovsk",
        id_of["Odessa"]: "Odessa",
        id_of["Donetsk"]: "Donetsk",
        id_of["Crimean ASSR"]: "Crimean ASSR",
        id_of["Smolensk"]: "Smolensk",
        id_of["Kursk"]: "Kursk",
        id_of["Tula"]: "Tula",
        903534: "Moscow",
        903532: "Leningrad oblast",
        903492: "RUS West",
        903493: "RUS West North",
        SEA_WEST: "Black Sea West",
        SEA_CENTRAL: "Black Sea Zone",
        SEA_EAST: "Black Sea East",
    }
    # Preserve the on-disk display names of the two RUS West blobs and the seas.
    display = dict(name_by_pid)
    display[903492] = "RUS West"
    display[903493] = "RUS West"
    display[SEA_WEST] = "Black Sea West"
    display[SEA_CENTRAL] = "Black Sea Zone"
    display[SEA_EAST] = "Black Sea East"
    decoder = json.JSONDecoder()
    for pid, key in name_by_pid.items():
        ring = canvas[key]
        lon, lat = labels[key]
        ax, ay = lonlat_to_canvas(lon, lat)
        if not _point_in_ring(ax, ay, [(p[0], p[1]) for p in ring]):
            # Representative point of the ring (average) if the city anchor
            # sits on a simplified coast. Cities are audited separately.
            ax = sum(p[0] for p in ring) / len(ring)
            ay = sum(p[1] for p in ring) / len(ring)
        row = {
            "id": pid,
            "points": ring,
            "name": display[pid],
            "label_anchor": [round(ax, 4), round(ay, 4)],
            "meta": {"source": "ne_10m_land", "gap_ussr_west": key},
        }
        blob = json.dumps(row, separators=(",", ":"), ensure_ascii=False)
        needle = '"id":%d,' % pid
        if needle in text:
            text = _replace_span(text, needle, blob)
            continue
        array_at = text.find("[")
        _array, array_end = decoder.raw_decode(text, array_at)
        text = text[: array_end - 1] + "," + blob + text[array_end - 1 :]
    path.write_text(text, encoding="utf-8")


def _write_cities(id_of: Mapping[str, int]) -> None:
    path = D / "province_city_layer.json"
    text = path.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    for name, _rects, city, _terrain in NEW_SPECS:
        pid = id_of[name]
        block = '    "%d": {\n      "city_name": "%s",\n      "tier": 2\n    }' % (pid, city)
        key = '"%d":' % pid
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
    path.write_text(text, encoding="utf-8")


def _write_state(new_ids: Sequence[int]) -> None:
    path = D / "province_states.json"
    text = path.read_text(encoding="utf-8")
    needle = '"id": %d,' % STATE_RUS
    start, end = _span(text, needle)
    state = json.loads(text[start:end])
    sids = [int(x) for x in state.get("province_ids") or []]
    for pid in new_ids:
        if pid not in sids:
            sids.append(pid)
    state["province_ids"] = sids
    path.write_text(text[:start] + _pretty_base(state) + text[end:], encoding="utf-8")


def _write_adjacency(built: Mapping[str, Any]) -> None:
    path = D / "province_adjacency.json"
    doc = _load(path)
    adj = {str(k): [int(x) for x in v] for k, v in (doc.get("adjacency") or {}).items()}
    id_of = built["id_of"]
    affected = [id_of[name] for name in new_names()] + list(REWRITE_LAND) + list(SEA_IDS)
    _unlink_affected(adj, affected)
    base = {int(p["id"]): p for p in _load(D / "provinces_base.json")["provinces"]}
    for a, b in _touching_pairs(built, base):
        _link(adj, a, b)
    for pid in affected:
        adj.setdefault(str(pid), [])
    mirror_adjacency(adj)
    zeros = [pid for pid in affected if not adj.get(str(pid))]
    if zeros:
        raise SystemExit("GAP-USSR zero-neighbour %s" % zeros)
    doc["adjacency"] = {k: adj[k] for k in adj}
    base_now = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    land_n = sum(1 for p in base_now["provinces"] if str(p.get("domain") or "") == "land")
    stats["province_n"] = len(base_now["provinces"])
    stats["land_n"] = land_n
    stats["water_n"] = len(base_now["provinces"]) - land_n
    path.write_text(_dumps(doc), encoding="utf-8")
    _refresh_adj_v3()


def _refresh_adj_v3() -> None:
    script = ROOT / "tools" / "map_generation" / "scripts" / "generate_adj_v3_rhineland.py"
    import importlib.util

    spec = importlib.util.spec_from_file_location("adjv3_from_ussr", script)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load ADJ-V3 generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.main([]) != 0:
        raise SystemExit("ADJ-V3 refresh failed")


def main(argv: Optional[Sequence[str]] = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="GAP-USSR-WEST geometry")
    parser.add_argument("--write", action="store_true", help="write the world_accurate board")
    args = parser.parse_args(list(argv) if argv is not None else None)
    built = build_geometry()
    fails = built["report"]["fails"]
    bridge = built["report"].get("bridge_miss") or []
    print("GAP-USSR ids", new_id_block())
    print("GAP-USSR fails", fails)
    print("GAP-USSR bridge_miss", bridge)
    print("GAP-USSR areas", json.dumps(built["report"].get("areas_deg2"), sort_keys=True))
    print("GAP-USSR seas", json.dumps(built["report"].get("sea_areas"), sort_keys=True))
    if fails or bridge:
        return 1
    if not args.write:
        print("GAP-USSR check only (no write)")
        return 0
    apply_layers(built)
    print("GAP-USSR wrote", len(new_id_block()), "new land provinces")
    return 0


if __name__ == "__main__":
    sys.exit(main())
