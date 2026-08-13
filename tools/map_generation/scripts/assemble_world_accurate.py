#!/usr/bin/env python3
"""Assemble provinces_world_accurate dual board from GIS pilots + NE admin_1 RoW.

ID blocks (no world_full renumber):
  Europe NUTS-3: 710000+ (copy from provinces_pilot_europe_nuts3)
  US (NE admin1 states if --us-source ne, else TIGER pilot): 800000+
  RoW NE admin_1 (non-Europe): 900000+
  Seas from world_full sea cells: 950000+

Usage:
  python3 tools/map_generation/scripts/assemble_world_accurate.py --write
  python3 tools/map_generation/scripts/assemble_world_accurate.py --dry-run
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ne_full_geometry_align import lonlat_to_canvas, polygon_centroid  # noqa: E402

NUTS_DIR = ROOT / "data" / "provinces_pilot_europe_nuts3"
US_TIGER_DIR = ROOT / "data" / "provinces_pilot_us_tiger"
WORLD_FULL_DIR = ROOT / "data" / "provinces_world_full"
OUT_DIR = ROOT / "data" / "provinces_world_accurate"
NE_ADMIN1 = ROOT / "tools" / "map_generation" / "data" / "cache" / "ne_10m_admin_1_states_provinces.geojson"

# Europe + microstates covered by NUTS pilot (exclude from NE RoW)
EUROPE_ADM0 = {
    "ALB", "AND", "AUT", "BEL", "BIH", "BGR", "BLR", "CHE", "CYP", "CZE", "DEU",
    "DNK", "ESP", "EST", "FIN", "FRA", "GBR", "GRC", "HRV", "HUN", "IRL", "ISL",
    "ITA", "LIE", "LTU", "LUX", "LVA", "MCO", "MKD", "MLT", "MNE", "NLD", "NOR",
    "POL", "PRT", "ROU", "SMR", "SRB", "SVK", "SVN", "SWE", "UKR", "VAT", "XKX",
    # Turkey often in NUTS; keep TUR out of RoW if NUTS has it
    "TUR",
}

US_ID_BASE = 800000
ROW_ID_BASE = 900000
SEA_ID_BASE = 950000


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _prov_list(doc: Any) -> List[dict]:
    if isinstance(doc, dict) and isinstance(doc.get("provinces"), list):
        return [p for p in doc["provinces"] if isinstance(p, dict)]
    return []


def _simplify(ring: List[List[float]], max_verts: int) -> List[List[float]]:
    if len(ring) <= max_verts:
        return ring
    step = max(1, len(ring) // max_verts)
    out = ring[::step]
    if out[0] != ring[0]:
        out[0] = ring[0]
    if out[-1] != ring[-1]:
        out.append(ring[-1])
    return out[:max_verts] if len(out) > max_verts else out


def _largest_ring_lonlat(geom: dict) -> Optional[List[List[float]]]:
    if not geom:
        return None
    gtype = str(geom.get("type", ""))
    coords = geom.get("coordinates")
    if not coords:
        return None
    candidates: List[Any] = []
    if gtype == "Polygon":
        candidates = [coords[0]] if coords else []
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                candidates.append(poly[0])
    if not candidates:
        return None
    outer = max(candidates, key=len)
    ring: List[List[float]] = []
    # subsample dense source rings
    step = max(1, len(outer) // 800)
    for i in range(0, len(outer), step):
        pt = outer[i]
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            ring.append([float(pt[0]), float(pt[1])])
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    return ring if len(ring) >= 3 else None


def _lonlat_ring_to_canvas(ring_ll: List[List[float]], max_verts: int = 40) -> List[List[float]]:
    canvas: List[List[float]] = []
    for lon, lat in ring_ll:
        x, y = lonlat_to_canvas(float(lon), float(lat))
        canvas.append([x, y])
    return _simplify(canvas, max_verts)


def _area(pts: Sequence[Sequence[float]]) -> float:
    if len(pts) < 3:
        return 0.0
    a = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = float(pts[i][0]), float(pts[i][1])
        x2, y2 = float(pts[(i + 1) % n][0]), float(pts[(i + 1) % n][1])
        a += x1 * y2 - x2 * y1
    return abs(a) * 0.5


def copy_board_provinces(
    data_dir: Path,
    *,
    id_remap: Optional[Dict[int, int]] = None,
) -> Tuple[List[dict], List[dict], Dict[int, int], Dict[int, str]]:
    """Return base rows, geo rows, old→new id map, ownership tag by new id."""
    base_rows = _prov_list(_load(data_dir / "provinces_base.json"))
    geo_rows = _prov_list(_load(data_dir / "provinces_geometry.json"))
    geo_by = {int(g["id"]): g for g in geo_rows if "id" in g}
    own_path = data_dir / "province_ownership_1936.json"
    owners_raw: Dict[str, str] = {}
    if own_path.is_file():
        od = _load(own_path)
        owners_raw = od.get("owners", {}) if isinstance(od, dict) else {}

    bases: List[dict] = []
    geos: List[dict] = []
    omap: Dict[int, int] = {}
    own_out: Dict[int, str] = {}
    for b in base_rows:
        old = int(b["id"])
        if old not in geo_by:
            continue
        new = int(id_remap[old]) if id_remap and old in id_remap else old
        omap[old] = new
        nb = dict(b)
        nb["id"] = new
        bases.append(nb)
        g = dict(geo_by[old])
        g["id"] = new
        geos.append(g)
        tag = owners_raw.get(str(old), owners_raw.get(old, ""))
        if tag:
            own_out[new] = str(tag)
    return bases, geos, omap, own_out


def ne_admin1_row(
    feats: List[dict],
    *,
    exclude_adm0: Set[str],
    id_base: int,
    max_verts: int = 40,
    min_area: float = 5.0,
    sparse_merge_adm0: Optional[Set[str]] = None,
    sparse_area_target: float = 800.0,
) -> Tuple[List[dict], List[dict], Dict[int, str]]:
    """Project NE admin_1 features to provinces; optional sparse merge by country."""
    sparse_merge_adm0 = sparse_merge_adm0 or set()
    # First pass: project all eligible
    raw: List[Tuple[str, str, str, List[List[float]]]] = []
    for f in feats:
        props = f.get("properties") if isinstance(f.get("properties"), dict) else {}
        adm0 = str(props.get("adm0_a3") or props.get("adm0_a3") or "").upper()
        if not adm0 or adm0 in exclude_adm0:
            continue
        ring_ll = _largest_ring_lonlat(f.get("geometry") or {})
        if not ring_ll:
            continue
        ring = _lonlat_ring_to_canvas(ring_ll, max_verts=max_verts)
        if len(ring) < 3:
            continue
        ar = _area(ring)
        if ar < min_area:
            continue
        name = str(props.get("name") or props.get("name_en") or f"{adm0} region").strip()
        admin = str(props.get("admin") or adm0).strip()
        raw.append((name, adm0, admin, ring))

    # Sparse merge: group small units in sparse countries until area target
    by_country: Dict[str, List[Tuple[str, str, str, List[List[float]]]]] = defaultdict(list)
    for row in raw:
        by_country[row[1]].append(row)

    merged_rows: List[Tuple[str, str, str, List[List[float]]]] = []
    for adm0, items in by_country.items():
        if adm0 not in sparse_merge_adm0:
            merged_rows.extend(items)
            continue
        # greedy: keep large; cluster small by appending names (use largest ring only)
        large = []
        small = []
        for it in items:
            if _area(it[3]) >= sparse_area_target * 0.35:
                large.append(it)
            else:
                small.append(it)
        merged_rows.extend(large)
        # pack small into groups of ~3-6
        i = 0
        while i < len(small):
            chunk = small[i : i + 4]
            i += 4
            # pick largest ring as geometry proxy
            chunk_sorted = sorted(chunk, key=lambda x: _area(x[3]), reverse=True)
            name = chunk_sorted[0][0]
            if len(chunk) > 1:
                name = f"{name} area"
            merged_rows.append((name, adm0, chunk_sorted[0][2], chunk_sorted[0][3]))

    bases: List[dict] = []
    geos: List[dict] = []
    own: Dict[int, str] = {}
    # crude ISO3 → 1936 tag guess for majors
    tag_map = {
        "USA": "USA", "CAN": "ENG", "MEX": "MEX" if False else "USA",
        "CHN": "JAP", "JPN": "JAP", "KOR": "JAP", "PRK": "JAP",
        "IND": "ENG", "AUS": "ENG", "NZL": "ENG", "ZAF": "ENG",
        "BRA": "USA", "ARG": "USA", "CHL": "USA",
        "EGY": "ENG", "SAU": "ENG", "IRN": "ENG", "IRQ": "ENG",
        "IDN": "ENG", "THA": "ENG", "VNM": "FRA", "PHL": "USA",
        "RUS": "SOV", "KAZ": "SOV", "UKR": "SOV",
    }
    pid = int(id_base)
    for name, adm0, admin, ring in merged_rows:
        cx, cy = polygon_centroid(ring)
        bases.append({
            "id": pid,
            "name": name,
            "terrain": "plains",
            "domain": "land",
            "core_for_tags": [],
            "natural_resources": {},
            "population_base": 0,
            "meta": {"source": "ne_10m_admin_1", "adm0_a3": adm0, "admin": admin},
        })
        geos.append({
            "id": pid,
            "points": ring,
            "label_anchor": [cx, cy],
            "meta": {"source": "ne_10m_admin_1", "adm0_a3": adm0},
        })
        own[pid] = tag_map.get(adm0, "ENG")
        pid += 1
    return bases, geos, own


def seas_from_world_full(id_base: int = SEA_ID_BASE) -> Tuple[List[dict], List[dict]]:
    base_rows = _prov_list(_load(WORLD_FULL_DIR / "provinces_base.json"))
    geo_by = {int(g["id"]): g for g in _prov_list(_load(WORLD_FULL_DIR / "provinces_geometry.json"))}
    bases: List[dict] = []
    geos: List[dict] = []
    pid = int(id_base)
    for b in base_rows:
        terr = str(b.get("terrain", "")).lower()
        if terr not in ("sea", "ocean", "water", "lake"):
            continue
        old = int(b["id"])
        if old not in geo_by:
            continue
        nb = dict(b)
        nb["id"] = pid
        g = dict(geo_by[old])
        g["id"] = pid
        bases.append(nb)
        geos.append(g)
        pid += 1
    return bases, geos


def build_hierarchy(
    bases: List[dict],
    *,
    europe_ids: Set[int],
    us_ids: Set[int],
    sea_ids: Set[int],
) -> Tuple[dict, dict]:
    """Simple theater regions for accurate board."""
    regions = {
        1: {"id": 1, "name": "Europe", "province_ids": []},
        2: {"id": 2, "name": "North America", "province_ids": []},
        3: {"id": 3, "name": "Latin America", "province_ids": []},
        4: {"id": 4, "name": "Africa", "province_ids": []},
        5: {"id": 5, "name": "Middle East & Central Asia", "province_ids": []},
        6: {"id": 6, "name": "South Asia", "province_ids": []},
        7: {"id": 7, "name": "East Asia", "province_ids": []},
        8: {"id": 8, "name": "Southeast Asia & Pacific", "province_ids": []},
        9: {"id": 9, "name": "Oceania", "province_ids": []},
        10: {"id": 10, "name": "World Oceans", "province_ids": []},
    }
    # Prefer copying Europe NUTS region names when present — assign all europe_ids to Europe for simplicity
    # (detailed NUTS regions remain on pilot board)
    p2r: Dict[str, int] = {}
    for b in bases:
        pid = int(b["id"])
        meta = b.get("meta") if isinstance(b.get("meta"), dict) else {}
        adm0 = str(meta.get("adm0_a3") or "").upper()
        if pid in sea_ids:
            rid = 10
        elif pid in europe_ids:
            rid = 1
        elif pid in us_ids or adm0 in ("USA", "CAN"):
            rid = 2
        elif adm0 in ("MEX", "GTM", "BLZ", "HND", "SLV", "NIC", "CRI", "PAN", "CUB", "JAM", "HTI", "DOM",
                      "COL", "VEN", "GUY", "SUR", "ECU", "PER", "BOL", "BRA", "PRY", "CHL", "ARG", "URY"):
            rid = 3
        elif adm0 in ("MAR", "DZA", "TUN", "LBY", "EGY", "SDN", "SSD", "ETH", "ERI", "DJI", "SOM", "KEN",
                      "UGA", "TZA", "RWA", "BDI", "COD", "COG", "GAB", "CMR", "NGA", "NER", "TCD", "MLI",
                      "BFA", "SEN", "GIN", "CIV", "GHA", "TGO", "BEN", "AGO", "ZMB", "ZWE", "BWA", "NAM",
                      "ZAF", "MOZ", "MDG", "MWI"):
            rid = 4
        elif adm0 in ("TUR", "SYR", "IRQ", "IRN", "SAU", "YEM", "OMN", "ARE", "QAT", "BHR", "KWT", "JOR",
                      "ISR", "LBN", "PSE", "GEO", "ARM", "AZE", "KAZ", "UZB", "TKM", "KGZ", "TJK", "AFG"):
            rid = 5
        elif adm0 in ("IND", "PAK", "BGD", "NPL", "BTN", "LKA", "MDV"):
            rid = 6
        elif adm0 in ("CHN", "MNG", "PRK", "KOR", "JPN", "TWN"):
            rid = 7
        elif adm0 in ("MMR", "THA", "LAO", "KHM", "VNM", "MYS", "SGP", "IDN", "BRN", "PHL", "TLS", "PNG"):
            rid = 8
        elif adm0 in ("AUS", "NZL", "FJI", "SLB", "VUT", "NCL", "PYF"):
            rid = 9
        else:
            # fallback by id block
            if pid >= SEA_ID_BASE:
                rid = 10
            elif pid >= ROW_ID_BASE:
                rid = 8
            elif pid >= US_ID_BASE:
                rid = 2
            else:
                rid = 1
        regions[rid]["province_ids"].append(pid)
        p2r[str(pid)] = rid

    for r in regions.values():
        r["province_ids"] = sorted(r["province_ids"])
        r["province_count"] = len(r["province_ids"])

    sr_doc = {"regions": list(regions.values()), "meta": {"source": "assemble_world_accurate"}}
    mem_doc = {
        "version": 1,
        "era_year": 1936,
        "mode": "full",
        "seed_only": True,
        "province_to_region": p2r,
        "province_to_state": {},
        "province_to_super_region": {},
    }
    return sr_doc, mem_doc


def build_knn_adjacency(geos: List[dict], k: int = 6) -> dict:
    """Lightweight centroid KNN adjacency fallback."""
    cents: Dict[int, Tuple[float, float]] = {}
    for g in geos:
        pid = int(g["id"])
        pts = g.get("points") or []
        if len(pts) < 1:
            continue
        c = polygon_centroid(pts)
        cents[pid] = (float(c[0]), float(c[1]))
    ids = list(cents.keys())
    adj: Dict[str, List[int]] = {str(i): [] for i in ids}
    for pid in ids:
        cx, cy = cents[pid]
        dists = []
        for oid in ids:
            if oid == pid:
                continue
            ox, oy = cents[oid]
            d = (cx - ox) ** 2 + (cy - oy) ** 2
            dists.append((d, oid))
        dists.sort()
        adj[str(pid)] = [oid for _, oid in dists[:k]]
    return {
        "version": 1,
        "method": "centroid_knn_assembly",
        "k": k,
        "adjacency": adj,
        "stats": {"province_n": len(ids), "k": k},
    }


def build_board_adjacency(geos: List[dict], bases: List[dict], *, quant: float = 2.0) -> dict:
    """Prefer shared-edge adjacency; fall back to KNN if product unavailable."""
    try:
        from shared_edge_adjacency_product import build_shared_edge_adjacency  # type: ignore
    except Exception:
        build_shared_edge_adjacency = None  # type: ignore

    rings: Dict[int, List[List[float]]] = {}
    water: Dict[int, bool] = {}
    base_by = {int(b["id"]): b for b in bases}
    for g in geos:
        pid = int(g["id"])
        pts = g.get("points") or []
        ring = [[float(pt[0]), float(pt[1])] for pt in pts if isinstance(pt, (list, tuple)) and len(pt) >= 2]
        if len(ring) < 3:
            continue
        rings[pid] = ring
        b = base_by.get(pid) or {}
        terr = str(b.get("terrain", "")).lower()
        dom = str(b.get("domain", "")).lower()
        water[pid] = terr in ("sea", "ocean", "water", "lake") or dom in ("sea", "ocean", "naval", "water")

    if build_shared_edge_adjacency is not None and rings:
        try:
            res = build_shared_edge_adjacency(rings=rings, water=water, quant=quant, knn_k=5, multi_quant=True)
            if isinstance(res, dict) and res.get("adjacency"):
                # normalize payload
                out = {
                    "version": 2,
                    "method": res.get("method") or "shared_edge_plus_knn_fallback",
                    "source": "shared_edge_adjacency_product",
                    "adjacency": res["adjacency"],
                    "stats": res.get("stats") or {},
                }
                return out
        except Exception as exc:
            print("WARN shared-edge failed, using KNN:", exc)

    return build_knn_adjacency(geos, k=6)


def assemble(*, us_mode: str = "ne", write: bool = False) -> Dict[str, Any]:
    report: Dict[str, Any] = {"blocks": {}}

    # Europe NUTS
    eu_b, eu_g, eu_map, eu_own = copy_board_provinces(NUTS_DIR)
    europe_ids = {int(b["id"]) for b in eu_b}
    report["blocks"]["europe_nuts3"] = {"n": len(eu_b), "id_min": min(europe_ids), "id_max": max(europe_ids)}

    # US
    us_b: List[dict] = []
    us_g: List[dict] = []
    us_own: Dict[int, str] = {}
    us_ids: Set[int] = set()
    if us_mode == "tiger" and US_TIGER_DIR.is_dir() and (US_TIGER_DIR / "provinces_base.json").is_file():
        us_b, us_g, _, us_own = copy_board_provinces(US_TIGER_DIR)
        # ensure ids in 800000 block
        if us_b and int(us_b[0]["id"]) < US_ID_BASE:
            remap = {}
            nb, ng = [], []
            for i, b in enumerate(us_b):
                old = int(b["id"])
                new = US_ID_BASE + i
                remap[old] = new
                b = dict(b)
                b["id"] = new
                g = dict(us_g[i])
                g["id"] = new
                nb.append(b)
                ng.append(g)
                if old in us_own:
                    us_own[new] = us_own.pop(old)
            us_b, us_g = nb, ng
        us_ids = {int(b["id"]) for b in us_b}
        # fill ownership USA
        for pid in us_ids:
            us_own.setdefault(pid, "USA")
        report["blocks"]["us"] = {"n": len(us_b), "source": "tiger_pilot"}
        exclude = set(EUROPE_ADM0) | {"USA"}  # RoW excludes USA if tiger present
    else:
        # NE admin1 USA + CAN as US block
        if not NE_ADMIN1.is_file():
            raise SystemExit(f"missing NE admin1: {NE_ADMIN1}")
        feats = _load(NE_ADMIN1).get("features") or []
        us_feats = [f for f in feats if str((f.get("properties") or {}).get("adm0_a3", "")).upper() in ("USA", "CAN")]
        # project manually with US id base
        bases, geos, own = ne_admin1_row(
            us_feats,
            exclude_adm0=set(),
            id_base=US_ID_BASE,
            max_verts=36,
        )
        # force tags
        for b in bases:
            adm0 = str((b.get("meta") or {}).get("adm0_a3", ""))
            own[int(b["id"])] = "USA" if adm0 == "USA" else "ENG"
        us_b, us_g, us_own = bases, geos, own
        us_ids = {int(b["id"]) for b in us_b}
        report["blocks"]["us"] = {"n": len(us_b), "source": "ne_admin1_usa_can"}
        exclude = set(EUROPE_ADM0) | {"USA", "CAN"}

    # RoW NE admin1
    if not NE_ADMIN1.is_file():
        raise SystemExit(f"missing NE admin1: {NE_ADMIN1}")
    feats = _load(NE_ADMIN1).get("features") or []
    sparse = {"RUS", "CAN", "AUS", "BRA", "KAZ", "DZA", "LBY", "SDN", "COD", "MNG", "SAU", "GRL"}
    # if US from NE, CAN already in US block; if tiger, CAN in RoW via NE
    row_b, row_g, row_own = ne_admin1_row(
        feats,
        exclude_adm0=exclude,
        id_base=ROW_ID_BASE,
        max_verts=36,
        min_area=8.0,
        sparse_merge_adm0=sparse,
        sparse_area_target=1200.0,
    )
    report["blocks"]["row_ne_admin1"] = {"n": len(row_b)}

    # Seas
    sea_b, sea_g = seas_from_world_full(SEA_ID_BASE)
    sea_ids = {int(b["id"]) for b in sea_b}
    report["blocks"]["seas_world_full"] = {"n": len(sea_b)}

    bases = eu_b + us_b + row_b + sea_b
    geos = eu_g + us_g + row_g + sea_g
    ownership: Dict[str, str] = {}
    for d in (eu_own, us_own, row_own):
        for pid, tag in d.items():
            ownership[str(pid)] = tag

    # Prefer Europe NUTS detailed strategic regions if we can map — use coarse theaters for assembled
    sr_doc, mem_doc = build_hierarchy(bases, europe_ids=europe_ids, us_ids=us_ids, sea_ids=sea_ids)

    # Prefer Europe pilot region assignment for NUTS ids when present
    nuts_mem = NUTS_DIR / "hierarchy_membership_1936.json"
    nuts_sr = NUTS_DIR / "strategic_regions.json"
    if nuts_mem.is_file() and nuts_sr.is_file():
        nm = _load(nuts_mem)
        nsr = _load(nuts_sr)
        # Offset Europe region ids to 100+ to avoid clash, keep names
        reg_list = list(sr_doc["regions"])
        next_id = 100
        id_map_reg: Dict[int, int] = {}
        eu_regs = []
        for r in nsr.get("regions") or []:
            old_rid = int(r.get("id", 0))
            new_rid = next_id
            next_id += 1
            id_map_reg[old_rid] = new_rid
            pids = [int(x) for x in r.get("province_ids") or [] if int(x) in europe_ids]
            eu_regs.append({
                "id": new_rid,
                "name": str(r.get("name", f"Europe {new_rid}")),
                "province_ids": pids,
                "province_count": len(pids),
            })
        # remove coarse Europe region 1 province list for nuts ids; keep region 1 for any leftover
        p2r = mem_doc["province_to_region"]
        for old_pid_s, old_rid in (nm.get("province_to_region") or {}).items():
            old_pid = int(old_pid_s)
            if old_pid in europe_ids and int(old_rid) in id_map_reg:
                p2r[str(old_pid)] = id_map_reg[int(old_rid)]
        # rebuild region province_ids for coarse regions without double-counting
        for r in reg_list:
            r["province_ids"] = sorted(int(pid) for pid, rid in p2r.items() if int(rid) == int(r["id"]))
            r["province_count"] = len(r["province_ids"])
        sr_doc["regions"] = eu_regs + [r for r in reg_list if int(r["id"]) != 1 or r["province_count"] > 0]
        mem_doc["province_to_region"] = p2r

    adj = build_board_adjacency(geos, bases, quant=2.0)

    report["totals"] = {
        "provinces": len(bases),
        "land": sum(1 for b in bases if str(b.get("terrain", "")).lower() not in ("sea", "ocean", "water", "lake")),
        "sea": len(sea_b),
        "geometry": len(geos),
    }
    report["id_match"] = len(bases) == len(geos)

    if write:
        if OUT_DIR.exists():
            shutil.rmtree(OUT_DIR)
        OUT_DIR.mkdir(parents=True)
        (OUT_DIR / "provinces_base.json").write_text(json.dumps({"provinces": bases}, indent=2) + "\n")
        (OUT_DIR / "provinces_geometry.json").write_text(
            json.dumps({"provinces": geos, "meta": {"space": "world_canvas", "source": "assemble_world_accurate"}}, indent=2) + "\n"
        )
        (OUT_DIR / "strategic_regions.json").write_text(json.dumps(sr_doc, indent=2) + "\n")
        for era in (1910, 1918, 1936, 2026):
            mem = dict(mem_doc)
            mem["era_year"] = era
            (OUT_DIR / f"hierarchy_membership_{era}.json").write_text(json.dumps(mem, indent=2) + "\n")
        (OUT_DIR / "province_adjacency.json").write_text(json.dumps(adj, indent=2) + "\n")
        (OUT_DIR / "province_ownership_1936.json").write_text(
            json.dumps({"owners": ownership, "meta": {"source": "assemble_world_accurate"}}, indent=2) + "\n"
        )
        # minimal terrain layer
        terr = {
            str(b["id"]): {"terrain": b.get("terrain", "plains"), "domain": b.get("domain", "land")}
            for b in bases
        }
        (OUT_DIR / "province_terrain_layer.json").write_text(json.dumps({"provinces": terr}, indent=2) + "\n")
        (OUT_DIR / "manifest_world_accurate.json").write_text(
            json.dumps(
                {
                    "name": "provinces_world_accurate",
                    "stats": report["totals"],
                    "blocks": report["blocks"],
                    "method": "nuts3_europe + us_block + ne_admin1_row + world_full_seas",
                    "parent_world_full_renumbered": False,
                    "geometry_quality": "gis_hybrid_v1",
                },
                indent=2,
            )
            + "\n"
        )
        report["wrote"] = str(OUT_DIR)

    return report


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--us-mode", choices=("ne", "tiger"), default="tiger",
                    help="US block: ne=NE admin1 USA+CAN (~64); tiger=pilot fixture/full TIGER")
    args = ap.parse_args(argv)
    write = bool(args.write) and not args.dry_run
    report = assemble(us_mode=args.us_mode, write=write)
    print(json.dumps(report, indent=2))
    if not report.get("id_match"):
        return 1
    if write and report["totals"]["provinces"] < 2000:
        print("WARN: assembled board smaller than expected", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
