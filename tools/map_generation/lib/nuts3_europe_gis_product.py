"""Europe NUTS-3 GIS pilot product.

Ingest Eurostat GISCO NUTS-3 GeoJSON → project to EOA world canvas → simplify →
emit pilot board (IDs 710000+, no world_full renumber) with hierarchy + adjacency.
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_GEOJSON = ROOT / "data" / "gis" / "NUTS_RG_20M_2021_4326_LEVL_3.geojson"
PILOT_DIR_NAME = "provinces_pilot_europe_nuts3"
PILOT_ID_BASE = 710000
WORLD_CANVAS = (8192.0, 4096.0)

# CNTR_CODE (Eurostat) → EOA country tag
CNTR_TO_TAG = {
    "DE": "GER",
    "FR": "FRA",
    "UK": "ENG",
    "GB": "ENG",
    "IT": "ITA",
    "ES": "SPA",
    "PT": "POR",
    "NL": "NLD",
    "BE": "BEL",
    "LU": "LUX",
    "AT": "AUS",
    "CH": "SWI",
    "PL": "POL",
    "CZ": "CZE",
    "SK": "SVK",
    "HU": "HUN",
    "RO": "ROM",
    "BG": "BUL",
    "EL": "GRE",
    "GR": "GRE",
    "SE": "SWE",
    "NO": "NOR",
    "DK": "DNK",
    "FI": "FIN",
    "IE": "IRE",
    "IS": "ICE",
    "HR": "CRO",
    "SI": "SVN",
    "RS": "SER",
    "BA": "BIH",
    "ME": "MNE",
    "MK": "MKD",
    "AL": "ALB",
    "TR": "TUR",
    "CY": "CYP",
    "MT": "MLT",
    "EE": "EST",
    "LV": "LAT",
    "LT": "LIT",
    "UA": "UKR",
    "BY": "BLR",
    "MD": "MDA",
    "LI": "LIE",
}

# Strategic region by country / NUTS-1 prefix
REGION_BY_CNTR = {
    "DE": "Germany",
    "AT": "Central Europe",
    "CH": "Central Europe",
    "LI": "Central Europe",
    "FR": "France",
    "BE": "Low Countries",
    "NL": "Low Countries",
    "LU": "Low Countries",
    "UK": "British Isles",
    "GB": "British Isles",
    "IE": "British Isles",
    "IS": "Nordic",
    "SE": "Nordic",
    "NO": "Nordic",
    "DK": "Nordic",
    "FI": "Nordic",
    "EE": "Baltic Rim",
    "LV": "Baltic Rim",
    "LT": "Baltic Rim",
    "PL": "Eastern Frontiers",
    "CZ": "Central Europe",
    "SK": "Central Europe",
    "HU": "Central Europe",
    "RO": "Balkans",
    "BG": "Balkans",
    "EL": "Balkans",
    "GR": "Balkans",
    "HR": "Balkans",
    "SI": "Balkans",
    "RS": "Balkans",
    "BA": "Balkans",
    "ME": "Balkans",
    "MK": "Balkans",
    "AL": "Balkans",
    "IT": "Italy",
    "ES": "Iberia",
    "PT": "Iberia",
    "TR": "Eastern Frontiers",
    "CY": "Eastern Frontiers",
    "MT": "Western Mediterranean",
    "UA": "Eastern Frontiers",
    "BY": "Eastern Frontiers",
    "MD": "Eastern Frontiers",
}

try:
    from ne_full_geometry_align import lonlat_to_canvas, ensure_min_vertices  # type: ignore
except Exception:  # pragma: no cover
    def lonlat_to_canvas(lon: float, lat: float) -> Tuple[float, float]:  # type: ignore
        lon_min, lat_min, lon_max, lat_max = -180.0, -56.0, 180.0, 83.0
        w, h = WORLD_CANVAS
        x = (float(lon) - lon_min) / (lon_max - lon_min) * (w - 1.0)
        y = (lat_max - float(lat)) / (lat_max - lat_min) * (h - 1.0)
        return x, y

    def ensure_min_vertices(points: Sequence[Sequence[float]], min_vertices: int = 20):  # type: ignore
        return [[float(p[0]), float(p[1])] for p in points]


def _centroid(pts: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    ring = list(pts)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    return sum(float(p[0]) for p in ring) / len(ring), sum(float(p[1]) for p in ring) / len(ring)


def _poly_area(pts: Sequence[Sequence[float]]) -> float:
    ring = list(pts)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    n = len(ring)
    if n < 3:
        return 0.0
    a = 0.0
    for i in range(n):
        x0, y0 = float(ring[i][0]), float(ring[i][1])
        x1, y1 = float(ring[(i + 1) % n][0]), float(ring[(i + 1) % n][1])
        a += x0 * y1 - x1 * y0
    return abs(a) * 0.5


def _rdp(points: List[List[float]], epsilon: float) -> List[List[float]]:
    """Ramer–Douglas–Peucker simplify (open ring)."""
    if len(points) < 3 or epsilon <= 0:
        return points

    def perp_dist(p, a, b) -> float:
        ax, ay = a[0], a[1]
        bx, by = b[0], b[1]
        px, py = p[0], p[1]
        dx, dy = bx - ax, by - ay
        if dx == 0 and dy == 0:
            return math.hypot(px - ax, py - ay)
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

    def rec(pts: List[List[float]]) -> List[List[float]]:
        if len(pts) < 3:
            return pts
        a, b = pts[0], pts[-1]
        idx, dmax = 0, 0.0
        for i in range(1, len(pts) - 1):
            d = perp_dist(pts[i], a, b)
            if d > dmax:
                idx, dmax = i, d
        if dmax > epsilon:
            left = rec(pts[: idx + 1])
            right = rec(pts[idx:])
            return left[:-1] + right
        return [a, b]

    return rec(points)


def densify_ring_min(pts: Sequence[Sequence[float]], min_verts: int = 20) -> List[List[float]]:
    """Subdivide longest edges until min_verts (canvas space)."""
    ring = [[float(p[0]), float(p[1])] for p in pts]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    guard = 0
    while len(ring) < min_verts and guard < 50_000:
        guard += 1
        best_i, best_len = 0, -1.0
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d > best_len:
                best_len, best_i = d, i
        a, b = ring[best_i], ring[(best_i + 1) % n]
        mid = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
        ring.insert(best_i + 1, mid)
    return ring


def simplify_ring(pts: Sequence[Sequence[float]], max_verts: int = 48, epsilon: float = 1.2, min_verts: int = 20) -> List[List[float]]:
    ring = [[float(p[0]), float(p[1])] for p in pts]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    out = ring
    if len(out) > max_verts:
        out = _rdp(ring, epsilon)
        eps = epsilon
        guard = 0
        while len(out) > max_verts and guard < 12:
            guard += 1
            eps *= 1.5
            out = _rdp(ring, eps)
    if len(out) < 3:
        out = ring[: max(3, min(len(ring), max_verts))]
    # Floor then optional densify for map/combat visibility
    if len(out) < min_verts:
        out = densify_ring_min(out, min_verts=min_verts)
    else:
        try:
            out = ensure_min_vertices(out, min_vertices=min_verts)
        except Exception:
            out = densify_ring_min(out, min_verts=min_verts)
    return out

def _largest_ring_from_geometry(geom: Dict[str, Any]) -> List[List[float]]:
    """Extract largest exterior ring from Polygon / MultiPolygon (lon/lat)."""
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates")
    candidates: List[List[List[float]]] = []
    if gtype == "Polygon" and isinstance(coords, list) and coords:
        ring = coords[0]
        if isinstance(ring, list):
            candidates.append([[float(p[0]), float(p[1])] for p in ring if len(p) >= 2])
    elif gtype == "MultiPolygon" and isinstance(coords, list):
        for poly in coords:
            if isinstance(poly, list) and poly:
                ring = poly[0]
                if isinstance(ring, list):
                    candidates.append([[float(p[0]), float(p[1])] for p in ring if len(p) >= 2])
    if not candidates:
        return []
    # pick by lon/lat area proxy
    best = max(candidates, key=lambda r: _poly_area(r))
    return best


def project_ring_lonlat(ring_ll: Sequence[Sequence[float]]) -> List[List[float]]:
    out: List[List[float]] = []
    for p in ring_ll:
        x, y = lonlat_to_canvas(float(p[0]), float(p[1]))
        out.append([x, y])
    return out


def load_nuts3_features(geojson_path: Path = DEFAULT_GEOJSON) -> List[Dict[str, Any]]:
    path = Path(geojson_path)
    if not path.is_file():
        raise FileNotFoundError("NUTS-3 GeoJSON missing: %s" % path)
    data = json.loads(path.read_text(encoding="utf-8"))
    feats = data.get("features") or []
    out: List[Dict[str, Any]] = []
    for f in feats:
        if not isinstance(f, dict):
            continue
        props = f.get("properties") or {}
        if int(props.get("LEVL_CODE") or 3) != 3:
            continue
        geom = f.get("geometry") or {}
        ring_ll = _largest_ring_from_geometry(geom)
        if len(ring_ll) < 3:
            continue
        nuts_id = str(props.get("NUTS_ID") or "").strip()
        if not nuts_id:
            continue
        cntr = str(props.get("CNTR_CODE") or nuts_id[:2]).upper()
        # GISCO 20M: NAME_ENGL / NAME_FREN are *country* labels (e.g. "Germany"), not
        # NUTS-3 unit names. Prefer NUTS_NAME / NAME_LATN (district) then local names.
        name = str(
            props.get("NUTS_NAME")
            or props.get("NAME_LATN")
            or props.get("NAME_GERM")
            or props.get("NAME_ENGL")
            or nuts_id
        ).strip()
        if not name:
            name = nuts_id
        out.append(
            {
                "nuts_id": nuts_id,
                "name": name,
                "cntr_code": cntr,
                "ring_ll": ring_ll,
                "props": props,
            }
        )
    out.sort(key=lambda r: r["nuts_id"])
    return out


def build_nuts3_pilot(
    geojson_path: Path = DEFAULT_GEOJSON,
    id_base: int = PILOT_ID_BASE,
    max_verts: int = 48,
    simplify_epsilon: float = 1.2,
    min_verts: int = 20,
) -> Dict[str, Any]:
    """Core pure path: features → projected provinces (memory only)."""
    features = load_nuts3_features(geojson_path)
    base_out: List[Dict[str, Any]] = []
    geom_out: List[Dict[str, Any]] = []
    own_out: Dict[str, str] = {}
    nuts_map: Dict[str, int] = {}
    next_id = int(id_base)

    used_names: Dict[str, int] = {}
    for feat in features:
        ring_w = project_ring_lonlat(feat["ring_ll"])
        ring = simplify_ring(ring_w, max_verts=max_verts, epsilon=simplify_epsilon, min_verts=min_verts)
        if len(ring) < 3:
            continue
        cx, cy = _centroid(ring)
        # skip degenerate / off-canvas
        if not (0 <= cx <= WORLD_CANVAS[0] and 0 <= cy <= WORLD_CANVAS[1]):
            # still keep if near Europe canvas
            if cx < -100 or cx > WORLD_CANVAS[0] + 100 or cy < -100 or cy > WORLD_CANVAS[1] + 100:
                continue
        cntr = feat["cntr_code"]
        tag = CNTR_TO_TAG.get(cntr, cntr if len(cntr) == 3 else "NEU")
        reg = REGION_BY_CNTR.get(cntr, "Central Europe")
        pid = next_id
        next_id += 1
        nuts_id = feat["nuts_id"]
        name = str(feat["name"] or nuts_id).strip()
        # Disambiguate rare shared NUTS_NAME collisions (e.g. two "Jura").
        if name in used_names:
            used_names[name] += 1
            name = "%s (%s)" % (name, nuts_id)
        else:
            used_names[name] = 1
        base_out.append(
            {
                "id": pid,
                "name": name,
                "terrain": "plains",
                "domain": "land",
                "theater": "europe_core",
                "strategic_region_hint": reg,
                "population_base": 250000,
                "nuts_id": nuts_id,
                "cntr_code": cntr,
                "core_for_tags": [tag] if tag != "NEU" else [],
                "natural_resources": {},
                "special_features": [],
                "island_class": "mainland",
                "facility_tier": 1,
            }
        )
        geom_out.append(
            {
                "id": pid,
                "points": ring,
                "name": name,
                "label_anchor": [cx, cy],
                "meta": {
                    "pilot": True,
                    "nuts3": True,
                    "nuts_id": nuts_id,
                    "cntr_code": cntr,
                    "source": "eurostat_gisco_nuts3_2021_20m",
                    "vertex_n": len(ring),
                    "area": _poly_area(ring),
                    "strategic_region_hint": reg,
                },
            }
        )
        own_out[str(pid)] = tag
        nuts_map[nuts_id] = pid

    land_n = len(base_out)
    states, regions, p2s, p2r, super_regions = _build_hierarchy(base_out, geom_out, own_out)
    mean_verts = sum(len(g["points"]) for g in geom_out) / max(1, len(geom_out))
    names = [str(p.get("name") or "") for p in base_out]
    unique_names = len(set(names))
    # Near 1:1 unique display names (allow tiny NUTS_NAME collisions that get id suffixes).
    name_ok = unique_names >= max(500, int(land_n * 0.95)) if land_n else False
    return {
        "provinces_base": {
            "provinces": base_out,
            "meta": {
                "pilot": True,
                "nuts3": True,
                "source": "nuts3_europe_gis_product",
                "id_base": id_base,
                "name_fields": ["NUTS_NAME", "NAME_LATN", "NAME_GERM", "NAME_ENGL", "NUTS_ID"],
            },
        },
        "provinces_geometry": {
            "meta": {
                "version": 1,
                "phase": "pilot_europe_nuts3_gis",
                "source": "nuts3_europe_gis_product.py",
                "geometry_space": "world",
                "parent_board": "none_new_mesh",
                "id_base": id_base,
                "land_n": land_n,
                "feature_n_source": len(features),
                "pilot": True,
                "nuts3": True,
                "gis_source": "Eurostat GISCO NUTS_RG_20M_2021_4326_LEVL_3",
                "projection": "ne_full_geometry_align.lonlat_to_canvas",
                "world_canvas": list(WORLD_CANVAS),
                "mean_verts": mean_verts,
                "simplify_epsilon": simplify_epsilon,
                "max_verts": max_verts,
                "unique_names": unique_names,
            },
            "provinces": geom_out,
        },
        "ownership": {
            "meta": {
                "era_year": 2021,
                "seed_only": True,
                "pilot": True,
                "nuts3": True,
                "source": "CNTR_CODE→EOA tag map",
                "player_agency": {
                    "seed_on_scenario_load": True,
                    "reapply_on_year_tick": False,
                },
            },
            "owners": own_out,
            "capitals": {},
        },
        "nuts_id_to_province": nuts_map,
        "states": states,
        "regions": regions,
        "super_regions": super_regions,
        "province_to_state": p2s,
        "province_to_region": p2r,
        "stats": {
            "province_n": land_n,
            "land_n": land_n,
            "feature_n_source": len(features),
            "state_n": len(states),
            "region_n": len(regions),
            "mean_verts": mean_verts,
            "id_base": id_base,
            "id_min": id_base if land_n else 0,
            "id_max": id_base + land_n - 1 if land_n else 0,
            "unique_names": unique_names,
            "name_ok": name_ok,
            "method": "eurostat_nuts3_20m_projected_simplified",
            "densify_pilot_land_n": 1840,
            "europe_core_parent_approx": 460,
            "denser_than_europe_core": land_n > 460,
            "vs_densify_pilot": "gis_truth_not_procedural_split",
        },
        "empty": land_n < 1,
        "ok": land_n >= 500 and mean_verts >= 12 and name_ok,
    }


def _build_hierarchy(base_out, geom_out, own_out):
    gcent = {int(g["id"]): _centroid(g["points"]) for g in geom_out}
    by_reg: Dict[str, List[int]] = defaultdict(list)
    for p in base_out:
        pid = int(p["id"])
        reg = str(p.get("strategic_region_hint") or "Central Europe")
        by_reg[reg].append(pid)

    regions = []
    p2r: Dict[str, int] = {}
    rid = 1
    for name, pids in sorted(by_reg.items(), key=lambda kv: -len(kv[1])):
        regions.append(
            {
                "id": rid,
                "name": name,
                "province_ids": sorted(pids),
                "province_n": len(pids),
                "theater": "europe_core",
            }
        )
        for pid in pids:
            p2r[str(pid)] = rid
        rid += 1

    try:
        from state_name_gazetteer import assign_state_name  # type: ignore
    except Exception:  # pragma: no cover
        def assign_state_name(reg, ni, owner_hint=""):  # type: ignore
            return "%s State %d" % (reg, ni + 1)

    states = []
    p2s: Dict[str, int] = {}
    sid = 1
    by_own_reg: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for p in base_out:
        pid = int(p["id"])
        tag = own_out.get(str(pid), "NEU") or "NEU"
        reg = str(p.get("strategic_region_hint") or "Central Europe")
        by_own_reg[(tag, reg)].append(pid)
    reg_name_idx: Dict[str, int] = defaultdict(int)
    for (tag, reg), pids in sorted(by_own_reg.items()):
        pids = sorted(pids)
        chunk = 8  # NUTS-3 already fine-grained; states group ~8
        for i in range(0, len(pids), chunk):
            part = pids[i : i + chunk]
            ni = reg_name_idx[reg]
            reg_name_idx[reg] = ni + 1
            name = assign_state_name(reg, ni, owner_hint=tag)
            states.append(
                {
                    "id": sid,
                    "name": name,
                    "owner_hint": tag,
                    "region_hint": reg,
                    "province_ids": part,
                    "province_n": len(part),
                }
            )
            for pid in part:
                p2s[str(pid)] = sid
            sid += 1

    super_regions = [
        {
            "id": 1,
            "name": "Europe",
            "region_ids": [r["id"] for r in regions],
            "theater": "europe_core",
        }
    ]
    return states, regions, p2s, p2r, super_regions


def build_adjacency_for_geom(geom_provs: List[Dict[str, Any]], quant: float = 3.0) -> Dict[str, Any]:
    try:
        from shared_edge_adjacency_product import (  # type: ignore
            build_shared_edge_adjacency,
        )
    except Exception:
        build_shared_edge_adjacency = None  # type: ignore

    rings = {int(g["id"]): g.get("points") or [] for g in geom_provs}
    water = {int(g["id"]): False for g in geom_provs}
    if build_shared_edge_adjacency is not None:
        try:
            res = build_shared_edge_adjacency(rings=rings, water=water, quant=quant)  # type: ignore
            if isinstance(res, dict) and res.get("adjacency"):
                stats = res.get("stats") or {}
                if "orphan_n" not in res:
                    res = dict(res)
                    res["orphan_n"] = int(stats.get("orphan_n") or stats.get("orphans") or 0)
                    res["province_n"] = int(stats.get("province_n") or len(res.get("adjacency") or {}))
                return res
        except TypeError:
            pass
        except Exception:
            pass

    # Inline shared-edge + KNN fallback (same method honesty as product)
    from collections import defaultdict as dd

    edge_to: Dict[Any, set] = dd(set)

    def ekey(a, b, q):
        ax, ay = int(round(float(a[0]) / q)), int(round(float(a[1]) / q))
        bx, by = int(round(float(b[0]) / q)), int(round(float(b[1]) / q))
        p1, p2 = (ax, ay), (bx, by)
        return (p1, p2) if p1 <= p2 else (p2, p1)

    for pid, ring in rings.items():
        if len(ring) < 2:
            continue
        closed = ring if ring[0] == ring[-1] else ring + [ring[0]]
        for i in range(len(closed) - 1):
            ek = ekey(closed[i], closed[i + 1], quant)
            if ek[0] != ek[1]:
                edge_to[ek].add(pid)
    adj: Dict[int, set] = dd(set)
    shared_edges = 0
    for pids in edge_to.values():
        if len(pids) < 2:
            continue
        shared_edges += 1
        pl = list(pids)
        for i in range(len(pl)):
            for j in range(i + 1, len(pl)):
                adj[pl[i]].add(pl[j])
                adj[pl[j]].add(pl[i])
    # KNN fallback for orphans
    cents = {pid: _centroid(ring) for pid, ring in rings.items() if len(ring) >= 3}
    orphans = [pid for pid in rings if not adj.get(pid)]
    for pid in orphans:
        cx, cy = cents.get(pid, (0.0, 0.0))
        dists = []
        for pid2, (x2, y2) in cents.items():
            if pid2 == pid:
                continue
            dists.append(((cx - x2) ** 2 + (cy - y2) ** 2, pid2))
        dists.sort()
        for _, pid2 in dists[:5]:
            adj[pid].add(pid2)
            adj[pid2].add(pid)
    out_adj = {str(k): sorted(v) for k, v in adj.items()}
    orphan_n = sum(1 for pid in rings if not adj.get(pid))
    return {
        "version": 1,
        "adjacency": out_adj,
        "method": "shared_edge_plus_knn_fallback",
        "quant": quant,
        "shared_edge_groups": shared_edges,
        "orphan_n": orphan_n,
        "province_n": len(rings),
    }


def write_nuts3_pilot_dir(out: Dict[str, Any], pilot_dir: Optional[Path] = None) -> Dict[str, Any]:
    pilot_dir = pilot_dir or (ROOT / "data" / PILOT_DIR_NAME)
    pilot_dir.mkdir(parents=True, exist_ok=True)
    geom_provs = out["provinces_geometry"]["provinces"]
    adj = build_adjacency_for_geom(geom_provs)

    (pilot_dir / "provinces_base.json").write_text(
        json.dumps(out["provinces_base"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (pilot_dir / "provinces_geometry.json").write_text(
        json.dumps(out["provinces_geometry"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    own = out["ownership"]
    for era in (1910, 1918, 1936, 1945, 2026):
        payload = {
            "meta": {**own["meta"], "era_year": era, "note": "NUTS-3 CNTR_CODE seed (modern map; eras share seed)"},
            "owners": own["owners"],
            "capitals": {},
        }
        (pilot_dir / ("province_ownership_%d.json" % era)).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    eras = [
        {"year": y, "file": "province_ownership_%d.json" % y}
        for y in (1910, 1918, 1936, 1945, 2026)
    ]
    (pilot_dir / "ownership_era_index.json").write_text(
        json.dumps(
            {
                "version": 1,
                "policy": {
                    "seed_on_scenario_load": True,
                    "reapply_on_year_tick": False,
                    "player_conquest_preserved": True,
                },
                "eras": eras,
                "pilot": True,
                "nuts3": True,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    states = out["states"]
    regions = out["regions"]
    p2s = out["province_to_state"]
    p2r = out["province_to_region"]
    super_regions = out["super_regions"]
    p2super = {str(pid): 1 for pid in p2s}

    (pilot_dir / "province_states.json").write_text(
        json.dumps({"states": states, "meta": {"pilot": True, "nuts3": True}}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "strategic_regions.json").write_text(
        json.dumps({"regions": regions, "meta": {"pilot": True, "nuts3": True}}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "super_regions.json").write_text(
        json.dumps({"super_regions": super_regions, "meta": {"pilot": True, "nuts3": True}}, indent=2, ensure_ascii=False)
        + "\n",
        encoding="utf-8",
    )
    scaffold = {
        "version": 2,
        "pilot": True,
        "nuts3": True,
        "four_tier": True,
        "province_to_state": p2s,
        "province_to_region": p2r,
        "province_to_super_region": p2super,
        "state_n": len(states),
        "region_n": len(regions),
        "super_region_n": len(super_regions),
    }
    (pilot_dir / "hierarchy_scaffold.json").write_text(
        json.dumps(scaffold, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    # Membership full eras (province→state→region→super)
    for era in (1910, 1918, 1936, 2026):
        memb = {
            "meta": {
                "era_year": era,
                "mode": "full",
                "seed_only": True,
                "pilot": True,
                "nuts3": True,
                "reapply_on_year_tick": False,
            },
            "province_to_state": p2s,
            "province_to_region": p2r,
            "province_to_super_region": p2super,
        }
        (pilot_dir / ("hierarchy_membership_%d.json" % era)).write_text(
            json.dumps(memb, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    (pilot_dir / "membership_era_index.json").write_text(
        json.dumps(
            {
                "version": 1,
                "mode": "full",
                "policy": {"seed_on_scenario_load": True, "reapply_on_year_tick": False},
                "eras": [
                    {"year": y, "file": "hierarchy_membership_%d.json" % y}
                    for y in (1910, 1918, 1936, 2026)
                ],
                "pilot": True,
                "nuts3": True,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    (pilot_dir / "province_adjacency.json").write_text(
        json.dumps(adj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    for stub in (
        "project_sites.json",
        "province_city_layer.json",
        "province_economy_layer.json",
        "province_resources_layer.json",
        "province_terrain_layer.json",
    ):
        if stub == "project_sites.json":
            (pilot_dir / stub).write_text('{"sites":[]}\n', encoding="utf-8")
        else:
            (pilot_dir / stub).write_text("{}\n", encoding="utf-8")

    (pilot_dir / "manifest_pilot_europe_nuts3.json").write_text(
        json.dumps(
            {
                "name": PILOT_DIR_NAME,
                "id_base": PILOT_ID_BASE,
                "stats": out.get("stats"),
                "gis_source": "Eurostat GISCO NUTS_RG_20M_2021_4326_LEVL_3",
                "method": out.get("stats", {}).get("method"),
                "parent_world_full_renumbered": False,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return {
        "ok": bool(out.get("ok")),
        "path": str(pilot_dir),
        "stats": out.get("stats"),
        "adjacency": {
            "method": adj.get("method"),
            "orphan_n": adj.get("orphan_n"),
            "province_n": adj.get("province_n"),
        },
    }


def build_and_write_nuts3_pilot(
    geojson_path: Path = DEFAULT_GEOJSON,
    pilot_rel: str = PILOT_DIR_NAME,
) -> Dict[str, Any]:
    out = build_nuts3_pilot(geojson_path=geojson_path)
    written = write_nuts3_pilot_dir(out, ROOT / "data" / pilot_rel)
    written["ok"] = bool(out.get("ok")) and bool(written.get("ok", True))
    written["stats"] = out.get("stats")
    written["product"] = out
    return written


def _count_adjacency_orphans(
    province_ids: Sequence[int],
    adjacency: Dict[str, Any],
) -> int:
    """Honest orphan count: province with zero neighbor degree (missing key or empty list)."""
    if not province_ids:
        return 0
    if not isinstance(adjacency, dict) or not adjacency:
        return len(list(province_ids))
    orphans = 0
    for pid in province_ids:
        key = str(pid)
        neighbors = adjacency.get(key)
        if neighbors is None:
            # also accept int keys if present
            neighbors = adjacency.get(pid)  # type: ignore
        if not neighbors:
            orphans += 1
            continue
        if isinstance(neighbors, (list, tuple, set)) and len(neighbors) == 0:
            orphans += 1
    return orphans


def nuts3_europe_gis_integrity(pilot_dir: Optional[Path] = None) -> Dict[str, Any]:
    pilot_dir = pilot_dir or (ROOT / "data" / PILOT_DIR_NAME)
    geom_p = pilot_dir / "provinces_geometry.json"
    if not geom_p.is_file():
        return {"ok": False, "summary": "NUTS-3 pilot missing", "empty": True}
    geom = json.loads(geom_p.read_text(encoding="utf-8"))
    meta = geom.get("meta") or {}
    n = len(geom.get("provinces") or [])
    verts = [len(p.get("points") or []) for p in geom.get("provinces") or []]
    mean_v = sum(verts) / max(1, len(verts))
    ids = [int(p["id"]) for p in geom.get("provinces") or []]
    id_ok = all(i >= PILOT_ID_BASE for i in ids) and all(i < 800000 for i in ids)
    adj_p = pilot_dir / "province_adjacency.json"
    orphan_n = n if n else 999  # missing adjacency file ⇒ all orphans
    adj_map: Dict[str, Any] = {}
    if adj_p.is_file():
        adj_doc = json.loads(adj_p.read_text(encoding="utf-8"))
        adj_map = adj_doc.get("adjacency") or {}
        # Prefer recomputed degree orphans (do not trust missing orphan_n → 0).
        orphan_n = _count_adjacency_orphans(ids, adj_map)
        # Cross-check declared stats when present
        stats = adj_doc.get("stats") or {}
        declared = stats.get("orphan_land_after", stats.get("orphan_n", adj_doc.get("orphan_n")))
        if declared is not None:
            try:
                orphan_n = max(orphan_n, int(declared))
            except (TypeError, ValueError):
                pass
    base_p = pilot_dir / "provinces_base.json"
    unique_names = 0
    if base_p.is_file():
        base = json.loads(base_p.read_text(encoding="utf-8"))
        names = [str(p.get("name") or "") for p in (base.get("provinces") or [])]
        unique_names = len(set(n for n in names if n))
    name_ok = unique_names >= max(500, int(n * 0.95)) if n else False
    hs = {}
    hsp = pilot_dir / "hierarchy_scaffold.json"
    if hsp.is_file():
        hs = json.loads(hsp.read_text(encoding="utf-8"))
    ok = (
        n >= 500
        and mean_v >= 12
        and id_ok
        and bool(meta.get("nuts3"))
        and orphan_n == 0
        and bool(adj_map)
        and name_ok
        and int(hs.get("state_n") or 0) >= 40
        and int(hs.get("region_n") or 0) >= 5
        and bool(hs.get("four_tier"))
    )
    return {
        "ok": ok,
        "province_n": n,
        "mean_verts": mean_v,
        "id_base": PILOT_ID_BASE,
        "id_min": min(ids) if ids else 0,
        "id_max": max(ids) if ids else 0,
        "orphan_n": orphan_n,
        "adjacency_keys": len(adj_map) if isinstance(adj_map, dict) else 0,
        "unique_names": unique_names,
        "name_ok": name_ok,
        "state_n": int(hs.get("state_n") or 0),
        "region_n": int(hs.get("region_n") or 0),
        "gis_source": meta.get("gis_source"),
        "summary": "NUTS-3 GIS integrity %s · n=%d mean_v=%.1f orphans=%d names=%d states=%d regions=%d"
        % (
            "PASS" if ok else "FAIL",
            n,
            mean_v,
            orphan_n,
            unique_names,
            int(hs.get("state_n") or 0),
            int(hs.get("region_n") or 0),
        ),
        "empty": False,
    }


if __name__ == "__main__":
    res = build_and_write_nuts3_pilot()
    print(json.dumps({k: res[k] for k in ("ok", "path", "stats", "adjacency") if k in res}, indent=2))
