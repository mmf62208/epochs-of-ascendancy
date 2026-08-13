#!/usr/bin/env python3
"""Densify RoW provinces on world_accurate using geoBoundaries (open license).

Replaces NE admin1 cells for selected countries with merged ADM2 (or ADM1)
geometry. Never touches Europe NUTS (710k) or US TIGER (800k) or seas (950k).

  python3 tools/map_generation/scripts/densify_row_geoboundaries.py --write
  python3 tools/map_generation/scripts/densify_row_geoboundaries.py --dry-run

Requires cached GeoJSON under tools/map_generation/data/cache/geoboundaries/
(run downloads first or this script will attempt API fetch).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ne_full_geometry_align import lonlat_to_canvas, polygon_centroid  # noqa: E402

D = ROOT / "data" / "provinces_world_accurate"
CACHE = ROOT / "tools" / "map_generation" / "data" / "cache" / "geoboundaries"
ROW_ID_BASE = 900000
SEA_ID_BASE = 950000

# Target province counts after merge (playable grand-strategy density).
# BRA/CHN/MEX municipalities are huge → aggressive merge.
# Tranche 1 = majors; Tranche 2 = strategic mid-tier / thin NE cells.
TARGETS: Dict[str, Tuple[str, int]] = {
    # --- Tranche 1 ---
    "CHN": ("ADM2", 200),
    "IND": ("ADM2", 160),
    "IDN": ("ADM2", 110),
    "BRA": ("ADM2", 140),
    "CAN": ("ADM2", 76),
    "AUS": ("ADM2", 90),
    "MEX": ("ADM2", 110),
    "ZAF": ("ADM2", 52),
    "IRN": ("ADM2", 90),
    "EGY": ("ADM2", 75),
    "ARG": ("ADM2", 90),
    "RUS": ("ADM1", 83),
    # --- Tranche 2 (Phase 3 expansion) ---
    "PAK": ("ADM2", 70),
    "NGA": ("ADM2", 60),
    "COL": ("ADM2", 55),
    "PER": ("ADM2", 45),
    "CHL": ("ADM2", 40),
    "VEN": ("ADM2", 40),
    "BOL": ("ADM2", 25),
    "SAU": ("ADM2", 40),
    "IRQ": ("ADM2", 35),
    "SYR": ("ADM2", 25),
    "KOR": ("ADM2", 40),
    "PRK": ("ADM2", 25),
    "TWN": ("ADM2", 25),
    "JPN": ("ADM1", 47),  # prefectures
    "NZL": ("ADM2", 35),
    "PNG": ("ADM2", 30),
    "KAZ": ("ADM2", 40),
    "MNG": ("ADM2", 30),
    "DZA": ("ADM2", 50),
    "MAR": ("ADM2", 35),
    "LBY": ("ADM2", 30),
    "COD": ("ADM2", 45),
    "KEN": ("ADM2", 30),
    "ETH": ("ADM2", 35),
    "SDN": ("ADM2", 35),
    "MMR": ("ADM2", 40),
    "MYS": ("ADM2", 30),
    "LKA": ("ADM2", 25),
    "GHA": ("ADM2", 25),
    "AGO": ("ADM2", 30),
    "CUB": ("ADM2", 25),
    "THA": ("ADM2", 80),
    "VNM": ("ADM2", 70),
    "PHL": ("ADM2", 90),
    # --- Tranche 3 (remaining play-relevant NE-only RoW) ---
    "UGA": ("ADM2", 50),
    "TZA": ("ADM2", 40),
    "AFG": ("ADM2", 40),
    "AZE": ("ADM2", 30),
    "BFA": ("ADM2", 30),
    "GIN": ("ADM2", 30),
    "DOM": ("ADM2", 25),
    "ECU": ("ADM2", 30),
    "KHM": ("ADM2", 30),
    "TUN": ("ADM2", 25),
    "GTM": ("ADM2", 25),
    "MDG": ("ADM2", 30),
    "TCD": ("ADM2", 30),
    "YEM": ("ADM2", 25),
    "URY": ("ADM2", 25),
    "CIV": ("ADM2", 30),
    "HND": ("ADM2", 25),
    "PRY": ("ADM2", 25),
    "NIC": ("ADM2", 25),
    "LAO": ("ADM2", 25),
    "BDI": ("ADM2", 20),
    "CAF": ("ADM2", 25),
    "UZB": ("ADM2", 25),
    "SEN": ("ADM2", 25),
    "NPL": ("ADM2", 25),
    "SOM": ("ADM2", 25),
    "NAM": ("ADM2", 20),
    "GEO": ("ADM2", 20),
    "JOR": ("ADM2", 20),
    "PAN": ("ADM2", 20),
    "HTI": ("ADM2", 20),
    "SLV": ("ADM2", 20),
    "CRI": ("ADM2", 15),
    "RWA": ("ADM2", 15),
    "MOZ": ("ADM2", 25),
    "ZMB": ("ADM2", 20),
    "ZWE": ("ADM2", 20),
    "BWA": ("ADM2", 15),
    "CMR": ("ADM2", 25),
    "GAB": ("ADM2", 15),
    "COG": ("ADM2", 15),
    "BEN": ("ADM2", 15),
    "TGO": ("ADM2", 15),
    "MLI": ("ADM2", 25),
    "NER": ("ADM2", 20),
    "TKM": ("ADM2", 15),
    "KGZ": ("ADM2", 15),
    "TJK": ("ADM2", 15),
    "ARM": ("ADM2", 15),
    "ISR": ("ADM2", 15),
    "LBN": ("ADM2", 12),
    "OMN": ("ADM2", 15),
    "ARE": ("ADM2", 12),
    "KWT": ("ADM2", 8),
    "QAT": ("ADM2", 8),
    "BGD": ("ADM2", 40),
    "FJI": ("ADM2", 12),
    "GRL": ("ADM1", 8),
    "ISL": ("ADM2", 10),
    "BLR": ("ADM2", 20),  # if NE has BLR outside NUTS
    "MDA": ("ADM2", 20),
}

# Ownership tags for densified RoW (1936-ish)
ADM0_TAG: Dict[str, str] = {
    "CHN": "CHI",
    "IND": "ENG",
    "IDN": "NLD",
    "BRA": "BRA",
    "CAN": "ENG",
    "AUS": "ENG",
    "MEX": "MEX",
    "ZAF": "ENG",
    "IRN": "PER",
    "EGY": "ENG",
    "ARG": "ARG",
    "RUS": "SOV",
    "PAK": "ENG",
    "NGA": "ENG",
    "COL": "COL",
    "PER": "PER",
    "CHL": "CHL",
    "VEN": "VEN",
    "BOL": "BOL",
    "SAU": "SAU",
    "IRQ": "ENG",
    "SYR": "FRA",
    "KOR": "JAP",
    "PRK": "JAP",
    "TWN": "JAP",
    "JPN": "JAP",
    "NZL": "ENG",
    "PNG": "ENG",
    "KAZ": "SOV",
    "MNG": "MON",
    "DZA": "FRA",
    "MAR": "FRA",
    "LBY": "ITA",
    "COD": "BEL",
    "KEN": "ENG",
    "ETH": "ITA",
    "SDN": "ENG",
    "MMR": "ENG",
    "MYS": "ENG",
    "LKA": "ENG",
    "GHA": "ENG",
    "AGO": "POR",
    "CUB": "CUB",
    "THA": "SIA",
    "VNM": "FRA",
    "PHL": "USA",
    # Tranche 3
    "UGA": "ENG",
    "TZA": "ENG",
    "AFG": "AFG",
    "AZE": "SOV",
    "BFA": "FRA",
    "GIN": "FRA",
    "DOM": "DOM",
    "ECU": "ECU",
    "KHM": "FRA",
    "TUN": "FRA",
    "GTM": "GUA",
    "MDG": "FRA",
    "TCD": "FRA",
    "YEM": "YEM",
    "URY": "URG",
    "CIV": "FRA",
    "HND": "HON",
    "PRY": "PAR",
    "NIC": "NIC",
    "LAO": "FRA",
    "BDI": "BEL",
    "CAF": "FRA",
    "UZB": "SOV",
    "SEN": "FRA",
    "NPL": "NEP",
    "SOM": "ITA",
    "NAM": "ENG",
    "GEO": "SOV",
    "JOR": "ENG",
    "PAN": "PAN",
    "HTI": "HAI",
    "SLV": "ELS",
    "CRI": "COS",
    "RWA": "BEL",
    "MOZ": "POR",
    "ZMB": "ENG",
    "ZWE": "ENG",
    "BWA": "ENG",
    "CMR": "FRA",
    "GAB": "FRA",
    "COG": "FRA",
    "BEN": "FRA",
    "TGO": "FRA",
    "MLI": "FRA",
    "NER": "FRA",
    "TKM": "SOV",
    "KGZ": "SOV",
    "TJK": "SOV",
    "ARM": "SOV",
    "ISR": "ENG",
    "LBN": "FRA",
    "OMN": "ENG",
    "ARE": "ENG",
    "KWT": "ENG",
    "QAT": "ENG",
    "BGD": "ENG",
    "FJI": "ENG",
    "GRL": "DNK",
    "ISL": "DNK",
    "BLR": "SOV",
    "MDA": "ROM",
}

# Theater region ids matching assemble_world_accurate coarse map
ADM0_REGION: Dict[str, int] = {
    "CHN": 7,
    "IND": 6,
    "IDN": 8,
    "BRA": 3,
    "CAN": 2,
    "AUS": 9,
    "MEX": 3,
    "ZAF": 4,
    "IRN": 5,
    "EGY": 4,
    "ARG": 3,
    "RUS": 5,
    "PAK": 6,
    "NGA": 4,
    "COL": 3,
    "PER": 3,
    "CHL": 3,
    "VEN": 3,
    "BOL": 3,
    "SAU": 5,
    "IRQ": 5,
    "SYR": 5,
    "KOR": 7,
    "PRK": 7,
    "TWN": 7,
    "JPN": 7,
    "NZL": 9,
    "PNG": 8,
    "KAZ": 5,
    "MNG": 7,
    "DZA": 4,
    "MAR": 4,
    "LBY": 4,
    "COD": 4,
    "KEN": 4,
    "ETH": 4,
    "SDN": 4,
    "MMR": 8,
    "MYS": 8,
    "LKA": 6,
    "GHA": 4,
    "AGO": 4,
    "CUB": 3,
    "THA": 8,
    "VNM": 8,
    "PHL": 8,
    # Tranche 3 theaters
    "UGA": 4,
    "TZA": 4,
    "AFG": 5,
    "AZE": 5,
    "BFA": 4,
    "GIN": 4,
    "DOM": 3,
    "ECU": 3,
    "KHM": 8,
    "TUN": 4,
    "GTM": 3,
    "MDG": 4,
    "TCD": 4,
    "YEM": 5,
    "URY": 3,
    "CIV": 4,
    "HND": 3,
    "PRY": 3,
    "NIC": 3,
    "LAO": 8,
    "BDI": 4,
    "CAF": 4,
    "UZB": 5,
    "SEN": 4,
    "NPL": 6,
    "SOM": 4,
    "NAM": 4,
    "GEO": 5,
    "JOR": 5,
    "PAN": 3,
    "HTI": 3,
    "SLV": 3,
    "CRI": 3,
    "RWA": 4,
    "MOZ": 4,
    "ZMB": 4,
    "ZWE": 4,
    "BWA": 4,
    "CMR": 4,
    "GAB": 4,
    "COG": 4,
    "BEN": 4,
    "TGO": 4,
    "MLI": 4,
    "NER": 4,
    "TKM": 5,
    "KGZ": 5,
    "TJK": 5,
    "ARM": 5,
    "ISR": 5,
    "LBN": 5,
    "OMN": 5,
    "ARE": 5,
    "KWT": 5,
    "QAT": 5,
    "BGD": 6,
    "FJI": 9,
    "GRL": 2,
    "ISL": 1,
    "BLR": 5,
    "MDA": 1,
}


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _write(p: Path, obj: Any) -> None:
    p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


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


def _simplify(ring: List[List[float]], max_verts: int) -> List[List[float]]:
    if len(ring) <= max_verts:
        return ring
    step = max(1, len(ring) // max_verts)
    out = ring[::step]
    if out[0] != ring[0]:
        out[0] = list(ring[0])
    if out[-1] != ring[-1]:
        out.append(list(ring[-1]))
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
    step = max(1, len(outer) // 600)
    for i in range(0, len(outer), step):
        pt = outer[i]
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            ring.append([float(pt[0]), float(pt[1])])
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    return ring if len(ring) >= 3 else None


def _to_canvas(ring_ll: List[List[float]], max_verts: int = 36) -> List[List[float]]:
    canvas = []
    for lon, lat in ring_ll:
        x, y = lonlat_to_canvas(float(lon), float(lat))
        canvas.append([x, y])
    return _simplify(canvas, max_verts)


def ensure_cache(adm0: str, level: str) -> Optional[Path]:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"geoBoundaries-{adm0}-{level}_simplified.geojson"
    if path.is_file() and path.stat().st_size > 1000:
        return path
    api = f"https://www.geoboundaries.org/api/current/gbOpen/{adm0}/{level}/"
    try:
        with urllib.request.urlopen(api, timeout=60) as r:
            meta = json.loads(r.read().decode())
    except Exception as exc:
        print(f"WARN {adm0} {level} API failed: {exc}")
        return None
    d = meta[0] if isinstance(meta, list) else meta
    url = d.get("simplifiedGeometryGeoJSON") or d.get("gjDownloadURL")
    if not url:
        print(f"WARN no download URL for {adm0} {level}")
        return None
    print(f"Downloading {adm0} {level} …")
    try:
        with urllib.request.urlopen(url, timeout=300) as r:
            path.write_bytes(r.read())
    except Exception as exc:
        print(f"WARN download failed {adm0} {level}: {exc}")
        return None
    return path


def load_features(adm0: str, level: str) -> List[Tuple[str, List[List[float]], float, float, float]]:
    """Return list of (name, canvas_ring, area, cx, cy). Falls back ADM2→ADM1."""
    path = ensure_cache(adm0, level)
    if path is None and level == "ADM2":
        print(f"  fallback {adm0} ADM2 → ADM1")
        path = ensure_cache(adm0, "ADM1")
        level = "ADM1"
    if path is None:
        return []
    gj = _load(path)
    out: List[Tuple[str, List[List[float]], float, float, float]] = []
    for f in gj.get("features") or []:
        props = f.get("properties") if isinstance(f.get("properties"), dict) else {}
        name = str(props.get("shapeName") or props.get("name") or f"{adm0} unit").strip()
        # QC treats names starting with "Province " as placeholders — strip FR/EN admin prefix.
        import re as _re

        name = _re.sub(r"^Province\s+d[e']\s*", "", name, flags=_re.I)
        name = _re.sub(r"^Province\s+", "", name, flags=_re.I)
        name = _re.sub(r"[\u0600-\u06FF].*$", "", name).strip() or name
        ring_ll = _largest_ring_lonlat(f.get("geometry") or {})
        if not ring_ll:
            continue
        ring = _to_canvas(ring_ll, max_verts=36)
        if len(ring) < 3:
            continue
        ar = _area(ring)
        if ar < 2.0:
            continue
        cx, cy = polygon_centroid(ring)
        out.append((name, ring, ar, float(cx), float(cy)))
    return out


def merge_to_target(
    units: List[Tuple[str, List[List[float]], float, float, float]],
    target: int,
) -> List[Tuple[str, List[List[float]], float, float, float]]:
    """Grid-bin merge to target count (O(n) class; keeps largest ring per cell).

    Not a true geometric union — each output province uses the largest source
    ring in its bin (centroid grid). Good enough for playable density.
    """
    if len(units) <= target:
        return units
    # Adaptive grid so cells ≈ target
    xs = [u[3] for u in units]
    ys = [u[4] for u in units]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    span_x = max(maxx - minx, 1.0)
    span_y = max(maxy - miny, 1.0)
    # aim for ~target cells
    cols = max(1, int(math.ceil(math.sqrt(target * span_x / span_y))))
    rows = max(1, int(math.ceil(target / cols)))
    # enlarge until bins produce enough non-empty (then merge down if over)
    for _ in range(6):
        bins: Dict[Tuple[int, int], List[Tuple[str, List[List[float]], float, float, float]]] = defaultdict(list)
        for u in units:
            name, ring, ar, cx, cy = u
            gx = int((cx - minx) / span_x * cols) if span_x else 0
            gy = int((cy - miny) / span_y * rows) if span_y else 0
            gx = min(max(gx, 0), cols - 1)
            gy = min(max(gy, 0), rows - 1)
            bins[(gx, gy)].append(u)
        if len(bins) >= target * 0.7:
            break
        cols = max(cols + 1, int(cols * 1.3))
        rows = max(rows + 1, int(rows * 1.3))

    merged: List[Tuple[str, List[List[float]], float, float, float]] = []
    for _key, group in bins.items():
        group_sorted = sorted(group, key=lambda x: x[2], reverse=True)
        name, ring, ar, cx, cy = group_sorted[0]
        if len(group_sorted) > 1:
            name = f"{name} area"
            # weighted centroid of group
            tw = sum(g[2] for g in group_sorted) or 1.0
            cx = sum(g[3] * g[2] for g in group_sorted) / tw
            cy = sum(g[4] * g[2] for g in group_sorted) / tw
        merged.append((name, ring, ar, cx, cy))

    # If still over target, re-bin; if stuck, take largest-area units only
    if len(merged) > target:
        if len(merged) >= len(units):
            return sorted(merged, key=lambda x: x[2], reverse=True)[:target]
        return merge_to_target(merged, target)
    return merged


def densify(write: bool = True) -> dict:
    base_doc = _load(D / "provinces_base.json")
    geo_doc = _load(D / "provinces_geometry.json")
    bases: List[dict] = list(base_doc.get("provinces") or [])
    geos: List[dict] = list(geo_doc.get("provinces") or [])
    own_doc = _load(D / "province_ownership_1936.json")
    owners: Dict[str, str] = dict(own_doc.get("owners") or {})
    mem_doc = _load(D / "hierarchy_membership_1936.json")
    p2r: Dict[str, int] = dict(mem_doc.get("province_to_region") or {})
    sr_doc = _load(D / "strategic_regions.json")

    replace_set = set(TARGETS.keys())
    removed = 0
    keep_bases: List[dict] = []
    keep_ids: Set[int] = set()
    for b in bases:
        pid = int(b["id"])
        meta = b.get("meta") if isinstance(b.get("meta"), dict) else {}
        adm0 = str(meta.get("adm0_a3") or "").upper()
        # only replace RoW block
        if ROW_ID_BASE <= pid < SEA_ID_BASE and adm0 in replace_set:
            removed += 1
            owners.pop(str(pid), None)
            p2r.pop(str(pid), None)
            continue
        keep_bases.append(b)
        keep_ids.add(pid)

    keep_geos = [g for g in geos if int(g["id"]) in keep_ids]

    next_id = max(
        (int(b["id"]) for b in keep_bases if ROW_ID_BASE <= int(b["id"]) < SEA_ID_BASE),
        default=ROW_ID_BASE - 1,
    ) + 1
    if next_id < 902487:
        next_id = 902487

    added_by: Dict[str, int] = {}
    new_bases: List[dict] = []
    new_geos: List[dict] = []

    skipped: List[str] = []
    for adm0, (level, target) in TARGETS.items():
        units = load_features(adm0, level)
        before = len(units)
        if before == 0:
            print(f"  SKIP {adm0} {level}: no features")
            skipped.append(adm0)
            continue
        units = merge_to_target(units, target)
        added_by[adm0] = len(units)
        print(f"  {adm0} {level}: {before} → {len(units)} (target {target})")
        tag = ADM0_TAG.get(adm0, "ENG")
        rid = ADM0_REGION.get(adm0, 8)
        for name, ring, ar, cx, cy in units:
            pid = next_id
            next_id += 1
            if pid >= SEA_ID_BASE:
                raise SystemExit("ID collision with sea block — abort")
            new_bases.append(
                {
                    "id": pid,
                    "name": name,
                    "terrain": "plains",
                    "domain": "land",
                    "core_for_tags": [],
                    "natural_resources": {},
                    "population_base": 0,
                    "meta": {
                        "source": "geoboundaries",
                        "adm0_a3": adm0,
                        "admin": adm0,
                        "level": level,
                        "area": round(ar, 1),
                    },
                }
            )
            new_geos.append(
                {
                    "id": pid,
                    "points": ring,
                    "label_anchor": [cx, cy],
                    "meta": {"source": "geoboundaries", "adm0_a3": adm0, "level": level},
                }
            )
            owners[str(pid)] = tag
            p2r[str(pid)] = rid

    all_bases = keep_bases + new_bases
    all_geos = keep_geos + new_geos
    # sort by id for stability
    all_bases.sort(key=lambda b: int(b["id"]))
    all_geos.sort(key=lambda g: int(g["id"]))

    report = {
        "removed_old_row": removed,
        "added": sum(added_by.values()),
        "added_by": added_by,
        "skipped": skipped,
        "total_provinces": len(all_bases),
        "id_next": next_id,
        "land_sea": {
            "land": sum(
                1
                for b in all_bases
                if str(b.get("domain", "land")).lower() not in ("sea", "strait", "lake", "ocean")
                and str(b.get("terrain", "")).lower() not in ("sea", "ocean", "water", "lake")
            ),
            "total": len(all_bases),
        },
    }

    if not write:
        print(json.dumps(report, indent=2))
        return report

    # Rebuild strategic region province_ids from p2r
    regions = sr_doc.get("regions") or []
    rid_to_pids: Dict[int, List[int]] = defaultdict(list)
    for pid_s, rid in p2r.items():
        rid_to_pids[int(rid)].append(int(pid_s))
    for r in regions:
        rid = int(r["id"])
        if rid in rid_to_pids:
            r["province_ids"] = sorted(rid_to_pids[rid])
            r["province_count"] = len(r["province_ids"])

    # Strip layer entries for removed ids; leave new ids for enrich/polish
    def _filter_layer(path: Path, key: str = "provinces") -> None:
        if not path.is_file():
            return
        doc = _load(path)
        provs = doc.get(key)
        if isinstance(provs, dict):
            doc[key] = {k: v for k, v in provs.items() if int(k) in keep_ids or int(k) >= 902487}
            # keep only existing
            valid = {int(b["id"]) for b in all_bases}
            doc[key] = {k: v for k, v in doc[key].items() if int(k) in valid}
        _write(path, doc)

    base_doc["provinces"] = all_bases
    geo_doc["provinces"] = all_geos
    _write(D / "provinces_base.json", base_doc)
    _write(D / "provinces_geometry.json", geo_doc)

    own_doc["owners"] = owners
    own_doc["meta"] = {
        "source": "densify_row_geoboundaries",
        "note": "RoW priority countries replaced with geoBoundaries ADM2/ADM1 merges",
    }
    _write(D / "province_ownership_1936.json", own_doc)

    mem_doc["province_to_region"] = p2r
    _write(D / "hierarchy_membership_1936.json", mem_doc)
    for era in (1910, 1918, 1945, 2026):
        mp = D / f"hierarchy_membership_{era}.json"
        if mp.is_file():
            md = _load(mp)
            md["province_to_region"] = dict(p2r)
            _write(mp, md)

    _write(D / "strategic_regions.json", sr_doc)

    for layer in (
        "province_city_layer.json",
        "province_economy_layer.json",
        "province_resources_layer.json",
        "province_terrain_layer.json",
    ):
        _filter_layer(D / layer)

    # Manifest
    man_path = D / "manifest_world_accurate.json"
    man = _load(man_path) if man_path.is_file() else {}
    man["geometry_quality"] = "gis_hybrid_v1_5_row_geoboundaries"
    man["stats"] = {
        "provinces": len(all_bases),
        "land": report["land_sea"]["land"],
        "sea": len(all_bases) - report["land_sea"]["land"],
    }
    man["row_densify"] = report
    man["blocks"] = man.get("blocks") or {}
    man["blocks"]["row_geoboundaries"] = added_by
    man["blocks"]["row_removed_ne"] = removed
    _write(man_path, man)

    # Remap scenario capitals that lived on replaced RoW cells (name heuristics)
    scen_path = ROOT / "data" / "scenarios" / "world_accurate.json"
    if scen_path.is_file():
        sc = _load(scen_path)
        by_name = {
            str(b.get("name") or "").strip().lower(): int(b["id"]) for b in all_bases
        }
        # preferred labels for major capitals on densified board
        prefer = {
            "SOV": ("moscow", "moskovskaya", "moskva"),
            "JAP": ("tokyo", "tōkyō", "tokyo-to"),
        }
        # Prefer exact city names over oblasts / composite names
        exact_prefer = {
            "SOV": ("moscow",),
            "JAP": ("tokyo",),
        }
        all_ids = {int(b["id"]) for b in all_bases}
        changes = []
        for c in sc.get("countries") or []:
            tag = str(c.get("tag") or "")
            cap = int(c.get("capital_province_id") or 0)
            keys = prefer.get(tag) or ()
            if not keys:
                continue
            # Always re-resolve if current capital name does not match prefer keys
            cur_name = ""
            for b in all_bases:
                if int(b["id"]) == cap:
                    cur_name = str(b.get("name") or "").lower()
                    break
            needs = (cap not in all_ids) or not any(k in cur_name for k in keys)
            if not needs:
                continue
            found = None
            for exact in exact_prefer.get(tag, ()):
                if exact in by_name:
                    found = by_name[exact]
                    break
            if found is None:
                for k in keys:
                    for nm, pid in by_name.items():
                        if k in nm and "oblast" not in nm:
                            found = pid
                            break
                    if found:
                        break
            if found and found != cap:
                changes.append({"tag": tag, "from": cap, "to": found, "name": next((b.get("name") for b in all_bases if int(b["id"]) == found), None)})
                c["capital_province_id"] = found
                c["key_provinces"] = [found]
        if changes:
            _write(scen_path, sc)
            report["scenario_capital_remaps"] = changes

    print(json.dumps(report, indent=2))
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", default=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    densify(write=not args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
