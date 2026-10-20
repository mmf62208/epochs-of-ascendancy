#!/usr/bin/env python3
"""GAP-BELARUS: turn placeholder rings 905807–905826 into named 1936-style
provinces (Minsk, Gomel, Vitebsk, Mogilev, Polotsk, and the rest of the
modern Belarus footprint). IDs stay. Moscow and Smolensk are re-ringed so
Vitebsk 905809 shares a border with Moscow 903534 and the Lithuania→Moscow
highway can draw through the real Belarus provinces.

No new land id. Galicia west of ~27.4 E and Bessarabia stay out of scope.
UKR is not a tag. Era owners use tags that already exist:

  1910 RUS (POL is absent; the whole footprint was the Russian Empire)
  1918 POL west of the Riga line, SOV east
  1936 POL west, SOV east
  1945 SOV (POL is absent)
  2026 BLR

Shapely is imported only while building geometry. Does not write
provinces_world_full.
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

# Existing placeholder block. Do not renumber. GAP_BELARUS_ID_START
BLR_IDS: List[int] = list(range(905807, 905827))
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)
STATE_BLR = 279
REGION_SE_ASIA = 8  # pre-existing membership of the placeholder block
SUPER_WEST = 2
MOSCOW_ID = 903534
SMOLENSK_ID = 905897
REWRITE_LAND = (MOSCOW_ID, SMOLENSK_ID)
AFFECTED_KEEP_IDS = set(BLR_IDS) | set(REWRITE_LAND)

WESTERN_1936 = frozenset(
    {
        "Grodno",
        "Brest",
        "Pinsk",
        "Baranovichi",
        "Lida",
        "Vileyka",
        "Braslaw",
        "Stolin",
        "Molodechno",
    }
)

# Moscow stays a tight capital box; west edge 35.38 so it meets the Vitebsk
# corridor. Smolensk is cut north of 55.50 so that corridor can run.
MOSCOW_RECT = (35.38, 40.30, 54.70, 56.70)
# West edge sits east of Klimovichi (31.95 E) and west of Smolensk city (32.045 E).
SMOLENSK_RECT = (32.04, 35.40, 53.30, 55.50)

# name, rects (west, east, south, north), city, terrain, pid
# pid is the existing placeholder id that this named province keeps.
NEW_SPECS: List[Tuple[str, Tuple[Tuple[float, float, float, float], ...], str, str, int]] = [
    ("Polotsk", ((27.80, 29.55, 55.00, 56.20),), "Polotsk", "forest", 905807),
    ("Pinsk", ((25.40, 27.20, 51.70, 52.70),), "Pinsk", "plains", 905808),
    (
        "Vitebsk",
        (
            (29.40, 31.95, 54.70, 56.20),
            (31.80, 35.45, 55.48, 56.22),  # corridor north of Smolensk to Moscow
        ),
        "Vitebsk",
        "forest",
        905809,
    ),
    ("Mozyr", ((28.00, 30.20, 51.50, 52.70),), "Mozyr", "plains", 905810),
    ("Stolin", ((26.20, 27.80, 51.45, 52.20),), "Stolin", "plains", 905811),
    ("Borisov", ((28.10, 29.55, 54.00, 54.85),), "Borisov", "plains", 905812),
    ("Brest", ((23.35, 25.35, 51.45, 52.75),), "Brest", "plains", 905813),
    ("Grodno", ((23.30, 25.25, 53.15, 54.25),), "Grodno", "plains", 905814),
    ("Gomel", ((29.70, 31.95, 51.65, 53.05),), "Gomel", "plains", 905815),
    ("Vileyka", ((26.40, 27.75, 54.20, 55.15),), "Vileyka", "plains", 905816),
    ("Braslaw", ((26.35, 27.95, 55.15, 56.20),), "Braslaw", "forest", 905817),
    ("Minsk", ((26.85, 28.25, 53.45, 54.20),), "Minsk", "plains", 905818),
    ("Bobruisk", ((28.65, 30.25, 52.65, 53.75),), "Bobruisk", "plains", 905819),
    ("Mogilev", ((29.55, 31.45, 53.35, 54.25),), "Mogilev", "plains", 905820),
    ("Molodechno", ((26.15, 27.55, 53.85, 54.40),), "Molodechno", "plains", 905821),
    ("Slutsk", ((26.95, 28.75, 52.55, 53.55),), "Slutsk", "plains", 905822),
    ("Baranovichi", ((25.15, 26.95, 52.65, 53.60),), "Baranovichi", "plains", 905823),
    ("Klimovichi", ((31.15, 32.90, 53.15, 54.45),), "Klimovichi", "plains", 905824),
    ("Lida", ((24.65, 26.25, 53.45, 54.35),), "Lida", "plains", 905825),
    ("Orsha", ((29.75, 31.50, 54.05, 54.90),), "Orsha", "plains", 905826),
]

MUST_CITY = {
    "Polotsk": (28.784, 55.485),
    "Pinsk": (26.073, 52.129),
    "Vitebsk": (30.204, 55.190),
    "Mozyr": (29.239, 52.049),
    "Stolin": (26.736, 51.891),
    "Borisov": (28.505, 54.222),
    "Brest": (23.734, 52.097),
    "Grodno": (23.826, 53.669),
    "Gomel": (30.988, 52.441),
    "Vileyka": (26.911, 54.488),
    "Braslaw": (27.050, 55.641),
    "Minsk": (27.5615, 53.9023),
    "Bobruisk": (29.221, 53.138),
    "Mogilev": (30.331, 53.901),
    "Molodechno": (26.854, 54.307),
    "Slutsk": (27.550, 53.027),
    "Baranovichi": (26.014, 53.132),
    "Klimovichi": (31.954, 53.607),
    "Lida": (25.294, 53.888),
    "Orsha": (30.417, 54.508),
}
EXTRA_IN = {
    "Haradok": ((29.984, 55.462), "Vitebsk"),
    "Rechytsa": ((30.249, 52.361), "Gomel"),
    "Bykhaw": ((30.250, 53.521), "Mogilev"),
    "Asipovichy": ((28.650, 53.301), "Bobruisk"),
    "Valozhyn": ((26.522, 54.089), "Molodechno"),
    "Pruzhany": ((24.464, 52.556), "Brest"),
    "Voranava": ((25.120, 54.030), "Lida"),
    "Mstsislaw": ((31.725, 54.018), "Klimovichi"),
    "Moscow": ((37.62, 55.75), "Moscow"),
    "Smolensk": ((32.045, 54.782), "Smolensk"),
}
# Galicia, Bessarabia, Ukraine, Lithuania stay outside the new rings.
MUST_OUT = {
    "Lviv": (24.03, 49.84),
    "Lutsk": (25.34, 50.75),
    "Chisinau": (28.86, 47.01),
    "Kiev": (30.5234, 50.4501),
    "Vilnius": (25.2797, 54.6872),
    "Chernihiv": (31.29, 51.49),
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


def ids_by_name() -> Dict[str, int]:
    return {name: pid for name, _rects, _city, _terrain, pid in NEW_SPECS}


def keep_id_block() -> List[int]:
    return list(BLR_IDS)  # GAP_BELARUS_ID_START


def owner_for(year: int, name: str) -> str:
    western = name in WESTERN_1936
    table = {
        1910: "RUS",  # GAP_BELARUS_OWNER_1910
        1918: "POL" if western else "SOV",
        1936: "POL" if western else "SOV",
        1945: "SOV",
        2026: "BLR",  # GAP_BELARUS_OWNER_2026
    }
    if year not in table:
        raise SystemExit("GAP-BELARUS unknown era %s" % year)
    return table[year]


ALLOWED_OWNER = {
    1910: frozenset({"RUS", "SOV"}),
    1918: frozenset({"SOV", "POL"}),
    1936: frozenset({"SOV", "POL"}),
    1945: frozenset({"SOV"}),
    2026: frozenset({"BLR", "RUS", "SOV"}),
}


def owner_allowed(year: int, tag: str) -> bool:
    return tag != "UKR" and tag in ALLOWED_OWNER[year]


def mirror_adjacency(adj: Dict[str, List[int]]) -> None:
    _ussr()._mirror_pairs(adj)  # GAP_BELARUS_MIRROR_CALL


def _eco_for(name: str) -> Dict[str, int]:
    if name == "Minsk":
        return {"population": 180000, "factories": 3, "infrastructure": 4, "development_level": 3}
    if name in ("Gomel", "Vitebsk", "Mogilev", "Grodno", "Brest"):
        return {"population": 90000, "factories": 2, "infrastructure": 3, "development_level": 2}
    if name in ("Polotsk", "Borisov", "Bobruisk", "Orsha", "Baranovichi", "Pinsk"):
        return {"population": 55000, "factories": 1, "infrastructure": 3, "development_level": 2}
    return {"population": 40000, "factories": 1, "infrastructure": 2, "development_level": 2}


def build_geometry() -> Dict[str, Any]:
    """Return name->shapely geom plus canvas rings. No file writes."""
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

    base = {int(p["id"]): p for p in u._load(D / "provinces_base.json")["provinces"]}
    geo = u._load(D / "provinces_geometry.json")
    work = box(22.0, 50.8, 41.0, 57.2)
    keep_parts = []
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
        if max(xs) < 22 or min(xs) > 41 or max(ys) < 50.8 or min(ys) > 57.2:
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
    ne_window = box(22.0, 50.8, 41.0, 57.2)
    ne_parts = []
    for feat in ne.get("features") or []:
        geom = shape(feat.get("geometry") or {})
        if geom.is_empty or not geom.intersects(ne_window):
            continue
        ne_parts.append(geom.intersection(ne_window))
    land = unary_union(ne_parts).buffer(0)

    moscow_city = (37.62, 55.75)
    smolensk_city = (32.045, 54.782)
    moscow = u._simplify_keep(
        land.intersection(u._rect_poly((MOSCOW_RECT,))).difference(keep),
        moscow_city,
    )
    smolensk = u._simplify_keep(
        land.intersection(u._rect_poly((SMOLENSK_RECT,))).difference(keep).difference(moscow),
        smolensk_city,
    )

    claim = unary_union([u._rect_poly(spec[1]) for spec in NEW_SPECS]).buffer(0)
    remaining = (
        land.intersection(claim).difference(keep).difference(moscow).difference(smolensk).buffer(0)
    )
    ordered = sorted(NEW_SPECS, key=lambda spec: (u._rect_area(spec[1]), spec[0]))
    geoms: Dict[str, Any] = {}
    for name, rects, _city, _terrain, _pid in ordered:
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

    geoms["Moscow"] = moscow
    geoms["Smolensk"] = smolensk

    report = _audit_geoms(geoms, prep)
    canvas: Dict[str, List[List[float]]] = {}
    for name, geom in geoms.items():
        canvas[name] = u._to_canvas_ring(geom)
        if len(canvas[name]) < 3:
            raise SystemExit("GAP-BELARUS empty ring %s" % name)
    id_of = ids_by_name()
    id_of["Moscow"] = MOSCOW_ID
    id_of["Smolensk"] = SMOLENSK_ID
    misses = []
    for name, (lon, lat) in list(MUST_CITY.items()) + [
        ("Moscow", moscow_city),
        ("Smolensk", smolensk_city),
    ]:
        ring_name = name
        xy = lonlat_to_canvas(lon, lat)
        if not u._point_in_ring(xy[0], xy[1], [(p[0], p[1]) for p in canvas[ring_name]]):
            misses.append(name)
    if misses:
        report["bridge_miss"] = misses
    areas = {name: round(float(geom.area), 4) for name, geom in geoms.items()}
    report["areas_deg2"] = areas
    anchors: Dict[str, Tuple[float, float]] = {}
    for name, geom in geoms.items():
        city_ll = None
        if name in MUST_CITY:
            city_ll = MUST_CITY[name]
        elif name == "Moscow":
            city_ll = moscow_city
        elif name == "Smolensk":
            city_ll = smolensk_city
        if city_ll is not None and geom.intersects(Point(*city_ll)):
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
    new_only = [geoms[n] for n in new_names()]
    new_union = unary_union(new_only)
    new_prep = prep(new_union)
    for label, ll in MUST_OUT.items():
        if new_prep.intersects(Point(*ll)):
            fails.append("stole:%s" % label)
    # Moscow must share a border with Vitebsk (id 905809) so the Lithuania
    # highway and the old stub ids can meet.
    if prepared.get("Moscow") is None or prepared.get("Vitebsk") is None:
        fails.append("moscow-vitebsk")
    else:
        if not geoms["Moscow"].buffer(0.05).intersects(geoms["Vitebsk"].buffer(0.05)):
            fails.append("moscow-vitebsk")
    return {"fails": fails}


def apply_layers(built: Mapping[str, Any]) -> None:
    u = _ussr()
    id_of = dict(built["id_of"])
    spec = {name: row for row in NEW_SPECS for name in (row[0],)}
    terrain_of = {name: spec[name][3] for name in new_names()}

    for year in ERA_YEARS:
        own_path = D / ("province_ownership_%d.json" % year)
        own = u._load(own_path)
        owners = own.setdefault("owners", {})
        for name in new_names():
            tag = owner_for(year, name)
            if not owner_allowed(year, tag):
                raise SystemExit("GAP-BELARUS refused tag %s for %s %s" % (tag, name, year))
            owners[str(id_of[name])] = tag
        own_path.write_text(u._dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = u._load(mem_path)
        # Keep the pre-existing BLR state / region / super for these ids.
        mem_path.write_text(u._dumps(mem), encoding="utf-8")

    terr = u._load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    for name in new_names():
        trows[str(id_of[name])] = {"terrain": terrain_of[name], "domain": "land"}
    (D / "province_terrain_layer.json").write_text(u._dumps(terr), encoding="utf-8")

    eco = u._load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for name in new_names():
        row = _eco_for(name)
        erows[str(id_of[name])] = dict(row)
    (D / "province_economy_layer.json").write_text(u._dumps(eco), encoding="utf-8")

    res = u._load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for name in new_names():
        pid = id_of[name]
        row = {}
        if name in ("Minsk", "Gomel", "Vitebsk", "Mogilev"):
            row = {"coal": 1, "steel": 1}
        rrows[str(pid)] = row
    (D / "province_resources_layer.json").write_text(u._dumps(res), encoding="utf-8")

    _write_base(id_of, terrain_of)
    _write_geometry(built)
    _write_cities(id_of)
    _write_adjacency(built)


def _write_base(id_of: Mapping[str, int], terrain_of: Mapping[str, str]) -> None:
    u = _ussr()
    path = D / "provinces_base.json"
    text = path.read_text(encoding="utf-8")
    doc = json.loads(text)
    by_id = {int(p["id"]): p for p in doc["provinces"]}
    for name in new_names():
        pid = id_of[name]
        old = dict(by_id[pid])
        eco = _eco_for(name)
        res = {}
        if name in ("Minsk", "Gomel", "Vitebsk", "Mogilev"):
            res = {"coal": 1, "steel": 1}
        core = ["SOV"] if name not in WESTERN_1936 else ["POL"]
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
                "gap_belarus": name,
                "adm0_a3": "BLR",
            },
        }
        pretty = u._pretty_base(row)
        text = u._replace_span(text, '"id": %d' % pid, pretty)
    for pid in (MOSCOW_ID, SMOLENSK_ID):
        old = dict(by_id[pid])
        meta = dict(old.get("meta") or {})
        meta["gap_belarus"] = "re-ringed"
        old["meta"] = meta
        pretty = u._pretty_base(old)
        text = u._replace_span(text, '"id": %d' % pid, pretty)
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

    name_by_pid = {id_of[name]: name for name in list(new_names()) + ["Moscow", "Smolensk"]}
    display = {
        MOSCOW_ID: "Moscow",
        SMOLENSK_ID: "Smolensk",
    }
    for name in new_names():
        display[id_of[name]] = name
    for pid, key in name_by_pid.items():
        ring = canvas[key]
        lon, lat = labels[key]
        ax, ay = lonlat_to_canvas(lon, lat)
        if not u._point_in_ring(ax, ay, [(p[0], p[1]) for p in ring]):
            ax = sum(p[0] for p in ring) / len(ring)
            ay = sum(p[1] for p in ring) / len(ring)
        row = {
            "id": pid,
            "points": ring,
            "name": display[pid],
            "label_anchor": [round(ax, 4), round(ay, 4)],
            "meta": {"source": "ne_10m_land", "gap_belarus": key},
        }
        blob = json.dumps(row, separators=(",", ":"), ensure_ascii=False)
        needle = '"id":%d,' % pid
        text = u._replace_span(text, needle, blob)
    path.write_text(text, encoding="utf-8")


def _write_cities(id_of: Mapping[str, int]) -> None:
    u = _ussr()
    path = D / "province_city_layer.json"
    text = path.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    for name, _rects, city, _terrain, _pid in NEW_SPECS:
        pid = id_of[name]
        tier = 3 if name == "Minsk" else 2
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


def _write_adjacency(built: Mapping[str, Any]) -> None:
    u = _ussr()
    path = D / "province_adjacency.json"
    doc = u._load(path)
    adj = {str(k): [int(x) for x in v] for k, v in (doc.get("adjacency") or {}).items()}
    id_of = built["id_of"]
    affected = [id_of[name] for name in new_names()] + list(REWRITE_LAND)
    u._unlink_affected(adj, affected)
    base = {int(p["id"]): p for p in u._load(D / "provinces_base.json")["provinces"]}
    for a, b in _touching_pairs(built, base):
        u._link(adj, a, b)
    for pid in affected:
        adj.setdefault(str(pid), [])
    mirror_adjacency(adj)
    zeros = [pid for pid in affected if not adj.get(str(pid))]
    if zeros:
        raise SystemExit("GAP-BELARUS zero-neighbour %s" % zeros)
    vitebsk = id_of["Vitebsk"]
    if MOSCOW_ID not in [int(x) for x in adj.get(str(vitebsk), [])]:
        raise SystemExit("GAP-BELARUS Moscow does not border Vitebsk %s" % vitebsk)
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
        if pid in aff or pid in AFFECTED_KEEP_IDS:
            continue
        pts = row.get("points") or []
        if len(pts) < 3:
            continue
        ll = [c2ll(float(p[0]), float(p[1])) for p in pts]
        xs = [p[0] for p in ll]
        ys = [p[1] for p in ll]
        if max(xs) < 22 or min(xs) > 41 or max(ys) < 50.8 or min(ys) > 57.2:
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

    parser = argparse.ArgumentParser(description="GAP-BELARUS geometry")
    parser.add_argument("--write", action="store_true", help="write the world_accurate board")
    args = parser.parse_args(list(argv) if argv is not None else None)
    built = build_geometry()
    fails = built["report"]["fails"]
    bridge = built["report"].get("bridge_miss") or []
    print("GAP-BELARUS ids", keep_id_block())
    print("GAP-BELARUS names", new_names())
    print("GAP-BELARUS fails", fails)
    print("GAP-BELARUS bridge_miss", bridge)
    print("GAP-BELARUS areas", json.dumps(built["report"].get("areas_deg2"), sort_keys=True))
    if fails or bridge:
        return 1
    if not args.write:
        print("GAP-BELARUS check only (no write)")
        return 0
    apply_layers(built)
    print("GAP-BELARUS wrote", len(keep_id_block()), "named land provinces")
    return 0


if __name__ == "__main__":
    sys.exit(main())
