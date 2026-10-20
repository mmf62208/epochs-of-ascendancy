#!/usr/bin/env python3
"""GAP-WEST-UKR: fill Galicia / Volhynia west of ~27.4 E and Bessarabia.

New land ids 905900–905908 (next free after GAP-USSR-WEST). Named 1936-style
provinces: Lviv, Lutsk, Stanislawow, Tarnopol, Rovno, Drohobych, Kovel,
Chernivtsi, Chisinau. UKR is not a tag. Era owners use tags that exist:

  Galicia / Volhynia (Lviv, Lutsk, Stanislawow, Tarnopol, Rovno, Drohobych, Kovel)
    1910 AUS for Austrian Galicia (Lviv, Stanislawow, Tarnopol, Drohobych);
         RUS for Russian Volhynia (Lutsk, Rovno, Kovel)
    1918 POL
    1936 POL
    1945 SOV (POL is absent)
    2026 RUS (UKR is absent)

  Chernivtsi (Bukovina) / Chisinau (Bessarabia)
    1910 AUS (Chernivtsi) / RUS (Chisinau)
    1918 ROM
    1936 ROM
    1945 SOV
    2026 RUS (Chernivtsi; UKR absent) / ROM (Chisinau; MDA absent, matches
         the existing Moldova placeholder rows)

Does not write provinces_world_full.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

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

NEW_ID_START = 905900  # GAP_WEST_UKR_NEW_ID
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)
STATE_RUS = 388
STATE_MDA = 357
REGION_MOSCOW = 5
REGION_SE_ASIA = 8
SUPER_EAST = 3
SUPER_WEST = 2

GALICIA_VOLHYNIA = frozenset(
    {"Lviv", "Lutsk", "Stanislawow", "Tarnopol", "Rovno", "Drohobych", "Kovel"}
)
AUSTRIAN_1910 = frozenset({"Lviv", "Stanislawow", "Tarnopol", "Drohobych", "Chernivtsi"})
ROM_1936 = frozenset({"Chisinau", "Chernivtsi"})

# name, rects (west, east, south, north), city, terrain
NEW_SPECS: List[Tuple[str, Tuple[Tuple[float, float, float, float], ...], str, str]] = [
    ("Lviv", ((23.20, 25.20, 49.40, 50.35),), "Lviv", "plains"),
    ("Lutsk", ((24.70, 26.50, 50.40, 51.35),), "Lutsk", "plains"),
    ("Stanislawow", ((23.70, 25.90, 48.15, 49.45),), "Stanislawow", "plains"),
    ("Tarnopol", ((25.15, 27.40, 48.85, 50.25),), "Tarnopol", "plains"),
    ("Chisinau", ((28.35, 29.25, 46.65, 47.35),), "Chisinau", "plains"),
    ("Rovno", ((25.90, 27.45, 50.15, 51.25),), "Rovno", "plains"),
    ("Drohobych", ((22.55, 23.90, 48.85, 49.70),), "Drohobych", "plains"),
    ("Kovel", ((24.15, 25.90, 51.00, 51.90),), "Kovel", "plains"),
    ("Chernivtsi", ((25.15, 26.90, 47.85, 48.75),), "Chernivtsi", "plains"),
]

MUST_CITY = {
    "Lviv": (24.0297, 49.8397),
    "Lutsk": (25.3424, 50.7472),
    "Stanislawow": (24.7111, 48.9226),
    "Tarnopol": (25.5948, 49.5535),
    "Chisinau": (28.8575, 47.0105),
    "Rovno": (26.2516, 50.6199),
    "Drohobych": (23.5056, 49.3499),
    "Kovel": (24.7470, 51.2150),
    "Chernivtsi": (25.9350, 48.2920),
}
EXTRA_IN = {
    "Cernauti": ((25.935, 48.292), "Chernivtsi"),
    "Ivano-Frankivsk": ((24.711, 48.923), "Stanislawow"),
}
MUST_OUT = {
    "Kiev": (30.5234, 50.4501),
    "Vinnytsia": (28.48, 49.23),
    "Minsk": (27.5615, 53.9023),
    "Brest": (23.734, 52.097),
    "Pinsk": (26.073, 52.129),
    "Odessa": (30.73, 46.48),
    "Warsaw": (21.0122, 52.2297),
}


def _ussr():
    path = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_ussr_west.py"
    spec = importlib.util.spec_from_file_location("gap_ussr_west_helpers", path)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load GAP-USSR-WEST helpers")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def new_names() -> List[str]:
    return [row[0] for row in NEW_SPECS]


def new_id_block() -> List[int]:
    return list(range(NEW_ID_START, NEW_ID_START + len(NEW_SPECS)))


def ids_by_name() -> Dict[str, int]:
    return {name: pid for name, pid in zip(new_names(), new_id_block())}


def owner_for(year: int, name: str) -> str:
    if year == 1910:  # GAP_WEST_UKR_OWNER_1910
        if name in AUSTRIAN_1910:
            return "AUS"
        return "RUS"
    if year in (1918, 1936):
        return "ROM" if name in ROM_1936 else "POL"
    if year == 1945:
        return "SOV"
    if year == 2026:  # GAP_WEST_UKR_OWNER_2026
        return "ROM" if name == "Chisinau" else "RUS"
    raise SystemExit("GAP-WEST-UKR unknown era %s" % year)


ALLOWED_OWNER = {
    1910: frozenset({"AUS", "RUS", "SOV", "ROM"}),
    1918: frozenset({"POL", "ROM", "SOV", "AUS"}),
    1936: frozenset({"POL", "ROM", "SOV"}),
    1945: frozenset({"SOV", "ROM"}),
    2026: frozenset({"RUS", "ROM", "POL", "BLR"}),
}


def owner_allowed(year: int, tag: str) -> bool:
    return tag != "UKR" and tag in ALLOWED_OWNER[year]


def mirror_adjacency(adj: Dict[str, List[int]]) -> None:
    _ussr()._mirror_pairs(adj)  # GAP_WEST_UKR_MIRROR_CALL


def state_for(name: str) -> int:
    return STATE_MDA if name == "Chisinau" else STATE_RUS


def region_for(name: str) -> int:
    return REGION_SE_ASIA if name == "Chisinau" else REGION_MOSCOW


def super_for(name: str) -> int:
    return SUPER_WEST if name == "Chisinau" else SUPER_EAST


def _eco_for(name: str) -> Dict[str, int]:
    if name == "Lviv":
        return {"population": 160000, "factories": 3, "infrastructure": 4, "development_level": 3}
    if name == "Chisinau":
        return {"population": 90000, "factories": 2, "infrastructure": 3, "development_level": 2}
    if name in ("Lutsk", "Stanislawow", "Tarnopol", "Chernivtsi"):
        return {"population": 70000, "factories": 1, "infrastructure": 3, "development_level": 2}
    return {"population": 45000, "factories": 1, "infrastructure": 2, "development_level": 2}


def build_geometry() -> Dict[str, Any]:
    from shapely.geometry import Point, Polygon, box, shape
    from shapely.ops import unary_union
    from shapely.prepared import prep

    u = _ussr()
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS, lonlat_to_canvas

    def c2ll(x: float, y: float) -> Tuple[float, float]:
        lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
        w, h = WORLD_CANVAS
        lon = lon_min + float(x) / (w - 1.0) * (lon_max - lon_min)
        lat = lat_max - float(y) / (h - 1.0) * (lat_max - lat_min)
        return lon, lat

    new_ids = set(new_id_block())
    base = {int(p["id"]): p for p in u._load(D / "provinces_base.json")["provinces"]}
    geo = u._load(D / "provinces_geometry.json")
    work = box(21.5, 45.8, 31.0, 53.0)
    keep_parts = []
    for row in geo["provinces"]:
        pid = int(row["id"])
        if pid in new_ids:
            continue
        pts = row.get("points") or []
        if len(pts) < 3:
            continue
        ll = [c2ll(float(p[0]), float(p[1])) for p in pts]
        xs = [p[0] for p in ll]
        ys = [p[1] for p in ll]
        if max(xs) < 21.5 or min(xs) > 31.0 or max(ys) < 45.8 or min(ys) > 53.0:
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
    keep = unary_union(keep_parts).buffer(0) if keep_parts else Polygon()

    ne = u._load(NE_LAND)
    ne_window = box(21.5, 45.8, 31.0, 53.0)
    ne_parts = []
    for feat in ne.get("features") or []:
        geom = shape(feat.get("geometry") or {})
        if geom.is_empty or not geom.intersects(ne_window):
            continue
        ne_parts.append(geom.intersection(ne_window))
    land = unary_union(ne_parts).buffer(0)

    claim = unary_union([u._rect_poly(spec[1]) for spec in NEW_SPECS]).buffer(0)
    remaining = land.intersection(claim).difference(keep).buffer(0)
    ordered = sorted(NEW_SPECS, key=lambda spec: (u._rect_area(spec[1]), spec[0]))
    geoms: Dict[str, Any] = {}
    for name, rects, _city, _terrain in ordered:
        piece = remaining.intersection(u._rect_poly(rects)).buffer(0)
        city = MUST_CITY[name]
        piece = u._simplify_keep(piece, city)
        geoms[name] = piece
        remaining = remaining.difference(piece).buffer(0)
    if not remaining.is_empty and remaining.area > 0.01:
        centres = {}
        for name, geom in geoms.items():
            if geom.is_empty:
                centres[name] = Point(*MUST_CITY[name])
            else:
                centres[name] = geom.representative_point()
        for part in u._as_polys(remaining):
            if part.area < 0.008:
                continue
            pt = part.representative_point()
            best = min(centres, key=lambda n: pt.distance(centres[n]))
            geoms[best] = geoms[best].union(part).buffer(0)

    report = _audit_geoms(geoms, prep)
    canvas: Dict[str, List[List[float]]] = {}
    for name, geom in geoms.items():
        canvas[name] = u._to_canvas_ring(geom)
        if len(canvas[name]) < 3:
            raise SystemExit("GAP-WEST-UKR empty ring %s" % name)
    id_of = ids_by_name()
    misses = []
    for name, (lon, lat) in MUST_CITY.items():
        xy = lonlat_to_canvas(lon, lat)
        if not u._point_in_ring(xy[0], xy[1], [(p[0], p[1]) for p in canvas[name]]):
            misses.append(name)
    if misses:
        report["bridge_miss"] = misses
    report["areas_deg2"] = {name: round(float(geom.area), 4) for name, geom in geoms.items()}
    anchors: Dict[str, Tuple[float, float]] = {}
    for name, geom in geoms.items():
        city_ll = MUST_CITY[name]
        if geom.intersects(Point(*city_ll)):
            anchors[name] = u._snap_land_anchor(geom, city_ll[0], city_ll[1])
        else:
            rp = geom.representative_point()
            anchors[name] = u._snap_land_anchor(geom, float(rp.x), float(rp.y))
    return {
        "geoms": geoms,
        "canvas": canvas,
        "anchors": anchors,
        "report": report,
        "id_of": id_of,
    }


def _audit_geoms(geoms, prep) -> dict:
    from shapely.geometry import Point
    from shapely.ops import unary_union

    fails = []
    prepared = {name: prep(geom) for name, geom in geoms.items() if not geom.is_empty}
    for name, ll in MUST_CITY.items():
        hit = prepared.get(name)
        if hit is None or not hit.intersects(Point(*ll)):
            fails.append("city:%s" % name)
    for label, (ll, expect) in EXTRA_IN.items():
        hit = prepared.get(expect)
        if hit is None or not hit.intersects(Point(*ll)):
            fails.append("extra:%s" % label)
    new_union = unary_union([geoms[n] for n in new_names()])
    new_prep = prep(new_union)
    for label, ll in MUST_OUT.items():
        if new_prep.intersects(Point(*ll)):
            fails.append("stole:%s" % label)
    # East of 27.4 E is Vinnytsia / Kiev land; Tarnopol may kiss 27.4 but
    # must not take Vinnytsia city.
    return {"fails": fails}


def apply_layers(built: Mapping[str, Any]) -> None:
    u = _ussr()
    id_of = dict(built["id_of"])
    spec = {name: row for row in NEW_SPECS for name in (row[0],)}
    terrain_of = {name: spec[name][3] for name in new_names()}
    new_ids = [id_of[name] for name in new_names()]

    for year in ERA_YEARS:
        own_path = D / ("province_ownership_%d.json" % year)
        own = u._load(own_path)
        owners = own.setdefault("owners", {})
        for name in new_names():
            tag = owner_for(year, name)
            if not owner_allowed(year, tag):
                raise SystemExit("GAP-WEST-UKR refused tag %s for %s %s" % (tag, name, year))
            owners[str(id_of[name])] = tag
        own_path.write_text(u._dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = u._load(mem_path)
        reg = mem.setdefault("province_to_region", {})
        st = mem.setdefault("province_to_state", {})
        sup = mem.setdefault("province_to_super_region", {})
        for name in new_names():
            pid = id_of[name]
            reg[str(pid)] = region_for(name)
            st[str(pid)] = state_for(name)
            sup[str(pid)] = super_for(name)
        mem_path.write_text(u._dumps(mem), encoding="utf-8")

    terr = u._load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    for name in new_names():
        trows[str(id_of[name])] = {"terrain": terrain_of[name], "domain": "land"}
    (D / "province_terrain_layer.json").write_text(u._dumps(terr), encoding="utf-8")

    eco = u._load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for name in new_names():
        erows[str(id_of[name])] = dict(_eco_for(name))
    (D / "province_economy_layer.json").write_text(u._dumps(eco), encoding="utf-8")

    res = u._load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for name in new_names():
        row = {"coal": 1} if name in ("Lviv", "Drohobych") else {}
        rrows[str(id_of[name])] = row
    (D / "province_resources_layer.json").write_text(u._dumps(res), encoding="utf-8")

    regions = u._load(D / "strategic_regions.json")
    for region in regions.get("regions") or []:
        rid = int(region.get("id") or 0)
        rids = [int(x) for x in region.get("province_ids") or []]
        for name in new_names():
            if region_for(name) != rid:
                continue
            pid = id_of[name]
            if pid not in rids:
                rids.append(pid)
        region["province_ids"] = rids
        region["province_count"] = len(rids)
    (D / "strategic_regions.json").write_text(u._dumps(regions), encoding="utf-8")

    scaffold = u._load(D / "hierarchy_scaffold.json")
    for name in new_names():
        pid = id_of[name]
        scaffold.setdefault("province_to_region", {})[str(pid)] = region_for(name)
        scaffold.setdefault("province_to_state", {})[str(pid)] = state_for(name)
        scaffold.setdefault("province_to_super_region", {})[str(pid)] = super_for(name)
    scaffold["province_n"] = len(scaffold["province_to_region"])
    scaffold["land_n"] = sum(1 for v in scaffold["province_to_state"].values() if int(v or 0) > 0)
    (D / "hierarchy_scaffold.json").write_text(u._dumps(scaffold), encoding="utf-8")

    _write_base(id_of, terrain_of)
    _write_geometry(built)
    _write_cities(id_of)
    _write_states(id_of)
    _write_adjacency(built)


def _write_base(id_of: Mapping[str, int], terrain_of: Mapping[str, str]) -> None:
    u = _ussr()
    path = D / "provinces_base.json"
    text = path.read_text(encoding="utf-8")
    for name in new_names():
        pid = id_of[name]
        eco = _eco_for(name)
        res = {"coal": 1} if name in ("Lviv", "Drohobych") else {}
        core = ["ROM"] if name in ROM_1936 else ["POL"]
        row = {
            "id": pid,
            "name": name,
            "terrain": terrain_of[name],
            "domain": "land",
            "core_for_tags": core,
            "natural_resources": res,
            "population_base": int(eco["population"]),
            "meta": {
                "source": "ne_10m_land",
                "gap_west_ukr": name,
                "adm0_a3": "ROM" if name in ROM_1936 else "POL",
            },
        }
        pretty = u._pretty_base(row)
        needle = '"id": %d' % pid
        if needle in text:
            text = u._replace_span(text, needle, pretty)
            continue
        close = text.rfind("\n  ]\n}")
        if close < 0:
            raise SystemExit("provinces_base.json has no array close")
        text = text[:close] + ",\n" + pretty + text[close:]
    path.write_text(text, encoding="utf-8")


def _write_geometry(built: Mapping[str, Any]) -> None:
    u = _ussr()
    path = D / "provinces_geometry.json"
    text = path.read_text(encoding="utf-8")
    id_of = built["id_of"]
    canvas = built["canvas"]
    labels = built["anchors"]
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import lonlat_to_canvas

    decoder = json.JSONDecoder()
    for name in new_names():
        pid = id_of[name]
        ring = canvas[name]
        lon, lat = labels[name]
        ax, ay = lonlat_to_canvas(lon, lat)
        if not u._point_in_ring(ax, ay, [(p[0], p[1]) for p in ring]):
            ax = sum(p[0] for p in ring) / len(ring)
            ay = sum(p[1] for p in ring) / len(ring)
        row = {
            "id": pid,
            "points": ring,
            "name": name,
            "label_anchor": [round(ax, 4), round(ay, 4)],
            "meta": {"source": "ne_10m_land", "gap_west_ukr": name},
        }
        blob = json.dumps(row, separators=(",", ":"), ensure_ascii=False)
        needle = '"id":%d,' % pid
        if needle in text:
            text = u._replace_span(text, needle, blob)
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
        tier = 3 if name == "Lviv" else 2
        block = '    "%d": {\n      "city_name": "%s",\n      "tier": %d\n    }' % (pid, city, tier)
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


def _write_states(id_of: Mapping[str, int]) -> None:
    u = _ussr()
    path = D / "province_states.json"
    text = path.read_text(encoding="utf-8")
    by_state: Dict[int, List[int]] = {}
    for name in new_names():
        by_state.setdefault(state_for(name), []).append(id_of[name])
    for sid, pids in by_state.items():
        needle = '"id": %d,' % sid
        start, end = u._span(text, needle)
        state = json.loads(text[start:end])
        sids = [int(x) for x in state.get("province_ids") or []]
        for pid in pids:
            if pid not in sids:
                sids.append(pid)
        state["province_ids"] = sids
        text = text[:start] + u._pretty_base(state) + text[end:]
    path.write_text(text, encoding="utf-8")


def _write_adjacency(built: Mapping[str, Any]) -> None:
    u = _ussr()
    path = D / "province_adjacency.json"
    doc = u._load(path)
    adj = {str(k): [int(x) for x in v] for k, v in (doc.get("adjacency") or {}).items()}
    id_of = built["id_of"]
    affected = [id_of[name] for name in new_names()]
    u._unlink_affected(adj, affected)
    base = {int(p["id"]): p for p in u._load(D / "provinces_base.json")["provinces"]}
    for a, b in _touching_pairs(built, base):
        u._link(adj, a, b)
    for pid in affected:
        adj.setdefault(str(pid), [])
    mirror_adjacency(adj)
    zeros = [pid for pid in affected if not adj.get(str(pid))]
    if zeros:
        raise SystemExit("GAP-WEST-UKR zero-neighbour %s" % zeros)
    doc["adjacency"] = {k: adj[k] for k in adj}
    base_now = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    land_n = sum(1 for p in base_now["provinces"] if str(p.get("domain") or "") == "land")
    stats["province_n"] = len(base_now["provinces"])
    stats["land_n"] = land_n
    stats["water_n"] = len(base_now["provinces"]) - land_n
    path.write_text(u._dumps(doc), encoding="utf-8")
    u._refresh_adj_v3()


def _touching_pairs(built: Mapping[str, Any], base: Mapping[int, dict]) -> List[Tuple[int, int]]:
    from shapely.geometry import Polygon
    from shapely.strtree import STRtree

    u = _ussr()
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
    from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS

    def c2ll(x: float, y: float) -> Tuple[float, float]:
        lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
        w, h = WORLD_CANVAS
        lon = lon_min + float(x) / (w - 1.0) * (lon_max - lon_min)
        lat = lat_max - float(y) / (h - 1.0) * (lat_max - lat_min)
        return lon, lat

    id_of = built["id_of"]
    owned: List[Tuple[int, Any]] = []
    for name, geom in built["geoms"].items():
        owned.append((id_of[name], geom))
    aff = {pid for pid, _g in owned}
    geo = u._load(D / "provinces_geometry.json")
    others_geom = []
    others_id = []
    for row in geo["provinces"]:
        pid = int(row["id"])
        if pid in aff:
            continue
        pts = row.get("points") or []
        if len(pts) < 3:
            continue
        ll = [c2ll(float(p[0]), float(p[1])) for p in pts]
        xs = [p[0] for p in ll]
        ys = [p[1] for p in ll]
        if max(xs) < 21.5 or min(xs) > 31.0 or max(ys) < 45.8 or min(ys) > 53.0:
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
    _ = base
    return pairs


def main(argv: Optional[Sequence[str]] = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="GAP-WEST-UKR geometry")
    parser.add_argument("--write", action="store_true", help="write the world_accurate board")
    args = parser.parse_args(list(argv) if argv is not None else None)
    built = build_geometry()
    fails = built["report"]["fails"]
    bridge = built["report"].get("bridge_miss") or []
    print("GAP-WEST-UKR ids", new_id_block())
    print("GAP-WEST-UKR names", new_names())
    print("GAP-WEST-UKR fails", fails)
    print("GAP-WEST-UKR bridge_miss", bridge)
    print("GAP-WEST-UKR areas", json.dumps(built["report"].get("areas_deg2"), sort_keys=True))
    if fails or bridge:
        return 1
    if not args.write:
        print("GAP-WEST-UKR check only (no write)")
        return 0
    apply_layers(built)
    print("GAP-WEST-UKR wrote", len(new_id_block()), "new land provinces")
    return 0


if __name__ == "__main__":
    sys.exit(main())
