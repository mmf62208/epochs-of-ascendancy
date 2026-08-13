#!/usr/bin/env python3
"""US TIGER county ingest scaffold → EOA world canvas pilot dir (dry-run by default).

Phase 2 of map accuracy build. Does **not** renumber world_full IDs.
Writes pilot under data/provinces_pilot_us_tiger/ only with --write.

Download (manual or --download when network allowed):
  Census TIGER/Line Cartographic Boundary Counties (cb_…_us_county_5m.shp or GeoJSON)

Usage:
  python3 tools/map_generation/scripts/ingest_us_tiger_counties.py --dry-run
  python3 tools/map_generation/scripts/ingest_us_tiger_counties.py \\
      --source path/to/counties.geojson --dry-run
  python3 tools/map_generation/scripts/ingest_us_tiger_counties.py \\
      --source path/to/counties.geojson --write --id-base 800000
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ne_full_geometry_align import WORLD_BBOX, WORLD_CANVAS, lonlat_to_canvas  # noqa: E402

DEFAULT_OUT = ROOT / "data" / "provinces_pilot_us_tiger"
ID_BASE = 800000


def _ring_lonlat_to_canvas(coords: Sequence[Sequence[float]]) -> List[List[float]]:
    out: List[List[float]] = []
    for pt in coords:
        if not isinstance(pt, (list, tuple)) or len(pt) < 2:
            continue
        lon, lat = float(pt[0]), float(pt[1])
        # Continental US focus; keep AK/HI/PR if present
        if lat < -90 or lat > 90:
            continue
        x, y = lonlat_to_canvas(lon, lat)
        out.append([x, y])
    # drop closing duplicate
    if len(out) >= 2 and out[0][0] == out[-1][0] and out[0][1] == out[-1][1]:
        out = out[:-1]
    return out


def _simplify_ring(ring: List[List[float]], max_verts: int = 48) -> List[List[float]]:
    if len(ring) <= max_verts:
        return ring
    step = max(1, len(ring) // max_verts)
    simplified = ring[::step]
    if simplified[0] != ring[0]:
        simplified[0] = ring[0]
    if simplified[-1] != ring[-1]:
        simplified.append(ring[-1])
    return simplified[:max_verts] if len(simplified) > max_verts else simplified


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


def _centroid(pts: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in pts) / len(pts),
        sum(float(p[1]) for p in pts) / len(pts),
    )


def load_geojson_features(path: Path) -> List[dict]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, dict) and isinstance(raw.get("features"), list):
        return [f for f in raw["features"] if isinstance(f, dict)]
    if isinstance(raw, list):
        return [f for f in raw if isinstance(f, dict)]
    return []


def feature_to_province(
    feat: dict,
    *,
    pid: int,
    max_verts: int = 48,
) -> Optional[Tuple[dict, dict]]:
    props = feat.get("properties") if isinstance(feat.get("properties"), dict) else {}
    geom = feat.get("geometry") if isinstance(feat.get("geometry"), dict) else {}
    gtype = str(geom.get("type", ""))
    coords = geom.get("coordinates")
    if not coords:
        return None
    # largest outer ring if multi
    rings_src: List[Any] = []
    if gtype == "Polygon":
        rings_src = [coords[0]] if coords else []
    elif gtype == "MultiPolygon":
        # pick largest by vertex count as crude area proxy
        candidates = []
        for poly in coords:
            if poly and poly[0]:
                candidates.append(poly[0])
        if not candidates:
            return None
        rings_src = [max(candidates, key=len)]
    else:
        return None
    ring = _ring_lonlat_to_canvas(rings_src[0])
    ring = _simplify_ring(ring, max_verts=max_verts)
    if len(ring) < 3:
        return None
    name = (
        str(
            props.get("NAME")
            or props.get("NAMELSAD")
            or props.get("name")
            or props.get("LSAD")
            or f"County {pid}"
        ).strip()
    )
    statefp = str(props.get("STATEFP") or props.get("statefp") or props.get("STATE") or "")
    geoid = str(
        props.get("GEOID")
        or props.get("geoid")
        or props.get("GEO_ID")
        or ""
    )
    # plotly FIPS geojson: GEO_ID like 0500000US01001
    if geoid.startswith("0500000US"):
        geoid = geoid.replace("0500000US", "")
    cx, cy = _centroid(ring)
    base = {
        "id": pid,
        "name": name,
        "terrain": "plains",
        "domain": "land",
        "core_for_tags": [],
        "natural_resources": {},
        "population_base": 0,
        "meta": {"tiger_geoid": geoid, "statefp": statefp, "source": "tiger_county"},
    }
    geo = {
        "id": pid,
        "points": ring,
        "label_anchor": [cx, cy],
        "meta": {"source": "tiger_county", "geoid": geoid},
    }
    return base, geo


def build_from_geojson(
    source: Path,
    *,
    id_base: int = ID_BASE,
    max_features: int = 0,
    max_verts: int = 48,
    merge_area_below: float = 0.0,
) -> Dict[str, Any]:
    feats = load_geojson_features(source)
    bases: List[dict] = []
    geos: List[dict] = []
    pid = int(id_base)
    n = 0
    for feat in feats:
        if max_features > 0 and n >= max_features:
            break
        built = feature_to_province(feat, pid=pid, max_verts=max_verts)
        if not built:
            continue
        b, g = built
        if merge_area_below > 0 and _area(g["points"]) < merge_area_below:
            # Phase 2 full: merge into neighbor; scaffold keeps tiny counties
            pass
        bases.append(b)
        geos.append(g)
        pid += 1
        n += 1
    return {
        "base": {"provinces": bases},
        "geometry": {"provinces": geos, "meta": {"space": "world_canvas", "source": "tiger_county"}},
        "stats": {
            "province_n": len(bases),
            "id_base": id_base,
            "id_min": id_base if bases else None,
            "id_max": pid - 1 if bases else None,
            "source": str(source),
            "method": "tiger_county_project_simplify",
            "world_bbox": list(WORLD_BBOX),
            "world_canvas": list(WORLD_CANVAS),
        },
    }


def write_pilot(out_dir: Path, payload: Dict[str, Any]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "provinces_base.json").write_text(
        json.dumps(payload["base"], indent=2) + "\n", encoding="utf-8"
    )
    (out_dir / "provinces_geometry.json").write_text(
        json.dumps(payload["geometry"], indent=2) + "\n", encoding="utf-8"
    )
    manifest = {
        "name": "provinces_pilot_us_tiger",
        "id_base": payload["stats"]["id_base"],
        "stats": payload["stats"],
        "gis_source": "US Census TIGER county cartographic boundaries",
        "method": "tiger_county_project_simplify",
        "parent_world_full_renumbered": False,
        "geometry_quality": "tiger_gis_pilot",
    }
    (out_dir / "manifest_pilot_us_tiger.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    # Minimal empty hierarchy stubs so ScenarioLoader does not crash if pointed here early
    for name, body in (
        (
            "strategic_regions.json",
            {"regions": [{"id": 1, "name": "United States", "province_ids": [p["id"] for p in payload["base"]["provinces"]]}]},
        ),
        (
            "hierarchy_membership_1936.json",
            {
                "version": 1,
                "era_year": 1936,
                "mode": "full",
                "province_to_region": {str(p["id"]): 1 for p in payload["base"]["provinces"]},
                "province_to_state": {},
                "province_to_super_region": {},
            },
        ),
    ):
        (out_dir / name).write_text(json.dumps(body, indent=2) + "\n", encoding="utf-8")


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", default="", help="Path to TIGER counties GeoJSON")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--id-base", type=int, default=ID_BASE)
    ap.add_argument("--max-features", type=int, default=0, help="0 = all")
    ap.add_argument("--max-verts", type=int, default=48)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="Default if no --write")
    args = ap.parse_args(argv)

    if not args.source:
        print(
            "US TIGER ingest scaffold ready.\n"
            "Provide --source path/to/counties.geojson\n"
            "Example CB download (external):\n"
            "  https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_5m.zip\n"
            "Convert SHP→GeoJSON (ogr2ogr) then re-run with --source.\n"
            "Dry-run without source exits 0 (scaffold present)."
        )
        return 0

    source = Path(args.source)
    if not source.is_absolute():
        source = ROOT / source
    if not source.is_file():
        print("ERROR: missing source", source, file=sys.stderr)
        return 1

    payload = build_from_geojson(
        source,
        id_base=int(args.id_base),
        max_features=int(args.max_features),
        max_verts=int(args.max_verts),
    )
    stats = payload["stats"]
    print("TIGER pilot stats:", json.dumps(stats, indent=2))
    if stats["province_n"] == 0:
        print("ERROR: no features projected", file=sys.stderr)
        return 1

    if args.write:
        out_dir = Path(args.out)
        if not out_dir.is_absolute():
            out_dir = ROOT / out_dir
        write_pilot(out_dir, payload)
        print("Wrote pilot to", out_dir)
    else:
        print("Dry-run only (pass --write to emit data/provinces_pilot_us_tiger/)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
