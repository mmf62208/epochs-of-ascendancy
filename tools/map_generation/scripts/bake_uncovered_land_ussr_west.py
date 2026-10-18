#!/usr/bin/env python3
"""Bake the OLDMAP_TURKEY cosmetic mask (render-only).

Natural Earth 10m land ∩ lon 22–42°E / lat 43–56°N, minus province rings.
Sea hole: the same window's water, minus sea-zone rings (id >= 950000).

Output is canvas space (unscaled 8192×4096). MapRenderer multiplies by
THEATER_SCALE at mount. Does not write data/.

Bake-time dependency: shapely (not required by the unit test).
  python3 -m venv /tmp/eoa-mask-venv && /tmp/eoa-mask-venv/bin/pip install 'shapely>=2'
  /tmp/eoa-mask-venv/bin/python3 tools/map_generation/scripts/bake_uncovered_land_ussr_west.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ne_full_geometry_align import DEFAULT_NE_LAND, lonlat_to_canvas  # noqa: E402
from oldmap_turkey_mask_product import (  # noqa: E402
    BBOX_LONLAT,
    BLACK_SEA_LONLAT,
    CRIMEA_LONLAT,
    GEOM_PATH,
    KIEV_LONLAT,
    MASK_PATH,
    canvas_bbox,
    load_province_rings,
    witness_report,
)

try:
    from shapely.geometry import GeometryCollection, MultiPolygon, Polygon, box, shape
    from shapely.ops import unary_union
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "shapely is required to bake the mask. "
        "Install it in a venv and re-run this script. " + str(exc)
    )


def _as_polys(geom) -> list:
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, (MultiPolygon, GeometryCollection)):
        out = []
        for g in geom.geoms:
            out.extend(_as_polys(g))
        return out
    return []


def _slice_no_holes(geom, depth: int = 0) -> list:
    """Split holed polygons on cell borders until every piece is a simple ring."""
    out = []
    for poly in _as_polys(geom):
        if poly.area < 1.0:
            continue
        if not list(poly.interiors):
            if poly.exterior is not None and len(poly.exterior.coords) >= 4 and poly.area >= 1.0:
                out.append(poly)
            continue
        if depth >= 12:
            # Still holed: punch interiors out and keep only simple pieces.
            holes = [Polygon(ring) for ring in poly.interiors]
            punched = Polygon(poly.exterior.coords).difference(unary_union(holes))
            for piece in _as_polys(punched):
                if not list(piece.interiors) and piece.area >= 1.0 and len(piece.exterior.coords) >= 4:
                    out.append(piece)
            continue
        minx, miny, maxx, maxy = poly.bounds
        mx = (minx + maxx) * 0.5
        my = (miny + maxy) * 0.5
        cells = (
            box(minx, miny, mx, my),
            box(mx, miny, maxx, my),
            box(minx, my, mx, maxy),
            box(mx, my, maxx, maxy),
        )
        for cell in cells:
            piece = poly.intersection(cell)
            out.extend(_slice_no_holes(piece, depth + 1))
    return out


def _ring_of(poly: Polygon) -> list:
    coords = [(round(float(x), 2), round(float(y), 2)) for x, y in poly.exterior.coords]
    if len(coords) >= 2 and coords[0] == coords[-1]:
        coords = coords[:-1]
    return [[x, y] for x, y in coords]


def _load_ne_land_in_window():
    lon0, lat0, lon1, lat1 = BBOX_LONLAT
    # Slightly padded lon/lat window so the canvas clip does not drop a coastline vertex.
    lon_pad, lat_pad = 0.4, 0.3
    window_ll = box(lon0 - lon_pad, lat0 - lat_pad, lon1 + lon_pad, lat1 + lat_pad)
    fc = json.loads(Path(DEFAULT_NE_LAND).read_text(encoding="utf-8"))
    parts = []
    for feat in fc.get("features") or []:
        geom = feat.get("geometry")
        if not geom:
            continue
        g = shape(geom)
        if g.is_empty or not g.intersects(window_ll):
            continue
        clipped = g.intersection(window_ll)
        if clipped.is_empty:
            continue

        def _xy(x, y, z=None):
            return lonlat_to_canvas(x, y)

        from shapely.ops import transform
        parts.append(transform(_xy, clipped))
    if not parts:
        raise SystemExit("NE land did not intersect the Turkey/Ukraine window")
    land = unary_union(parts)
    x0, y0, x1, y1 = canvas_bbox()
    return land.intersection(box(x0, y0, x1, y1))


def _province_union(provinces: list, buf: float):
    """Every ring in the window, land and sea. The mask must not cover either."""
    geoms = []
    for p in provinces:
        try:
            poly = Polygon([(float(x), float(y)) for x, y in p["points"]])
        except Exception:
            continue
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            continue
        geoms.append(poly)
    if not geoms:
        return None
    merged = unary_union(geoms)
    if buf > 0.0:
        merged = merged.buffer(buf)
    return merged


def bake(subtract_rings: bool = True) -> dict:
    land = _load_ne_land_in_window()
    provinces = load_province_rings()
    # One buffer around every province ring (land and sea). The coarse RUS West
    # ring reaches into the Black Sea, and the 24-pt sea blobs sit on the coast,
    # so both masks have to lose both kinds of ring.
    cut = _province_union(provinces, buf=1.2) if subtract_rings else None
    land_mask = land.difference(cut) if cut is not None else land
    x0, y0, x1, y1 = canvas_bbox()
    window = box(x0, y0, x1, y1)
    water = window.difference(land)
    if cut is not None:
        water = water.difference(cut)
    water = water.difference(land_mask.buffer(0.4))
    land_mask = land_mask.simplify(1.15, preserve_topology=True)
    water = water.simplify(1.35, preserve_topology=True)
    if cut is not None:
        land_mask = land_mask.difference(cut)
        water = water.difference(cut)
    land_rings = [_ring_of(p) for p in _slice_no_holes(land_mask) if len(p.exterior.coords) >= 4]
    sea_rings = [_ring_of(p) for p in _slice_no_holes(water) if len(p.exterior.coords) >= 4]
    land_rings = [r for r in land_rings if len(r) >= 3]
    sea_rings = [r for r in sea_rings if len(r) >= 3]
    doc = {
        "version": 1,
        "space": "canvas",
        "note": "Multiply by MapCanvasConfig.THEATER_SCALE (1.728) at mount. Cosmetic only; no province id.",
        "bbox_lonlat": list(BBOX_LONLAT),
        "bbox_canvas": [round(x0, 2), round(y0, 2), round(x1, 2), round(y1, 2)],
        "subtracted_province_rings": bool(subtract_rings),
        "land": land_rings,
        "sea": sea_rings,
        "witnesses": {
            "kiev_lonlat": list(KIEV_LONLAT),
            "crimea_lonlat": list(CRIMEA_LONLAT),
            "black_sea_lonlat": list(BLACK_SEA_LONLAT),
        },
    }
    return doc


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-subtract", action="store_true", help="Mutant: do not remove province rings.")
    ap.add_argument("--out", default=str(MASK_PATH))
    ap.add_argument("--check-only", action="store_true")
    args = ap.parse_args()
    if args.check_only:
        doc = json.loads(Path(args.out).read_text(encoding="utf-8"))
    else:
        doc = bake(subtract_rings=not args.no_subtract)
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
        print("wrote", out, "bytes", out.stat().st_size)
    report = witness_report(doc)
    print(json.dumps(report, indent=2))
    if not args.no_subtract:
        if not report["kiev_in_land"] or report["kiev_in_province"]:
            raise SystemExit("Kiev witness failed: %s" % report)
        if not report["crimea_in_land"]:
            raise SystemExit("Crimea witness failed: %s" % report)
        if not report["black_sea_in_sea"] or report["black_sea_in_land"]:
            raise SystemExit("Black Sea witness failed: %s" % report)
        if report["owned_centroid_hits"] or report["overlap_samples"] > 0:
            raise SystemExit("mask covers province rings: %s" % report)


if __name__ == "__main__":
    main()
