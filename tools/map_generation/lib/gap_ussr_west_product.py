"""GAP-USSR-WEST checks that do not import shapely.

Black Sea coverage is a grid over Natural Earth water in a fixed bbox.
The live rings tile that water. The parent 24-vertex blobs do not.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Sequence, Tuple

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
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gap_ussr_west_parent_blobs.json"

# lon_min, lat_min, lon_max, lat_max. Includes the Azov.
BLACK_SEA_BBOX = (27.50, 41.20, 41.90, 47.30)
# Bosporus / Marmara approaches are not the Black Sea tile.
MARMARA_BBOX = (26.00, 40.40, 29.20, 41.42)
COVERAGE_MIN = 0.98  # GAP_USSR_COVERAGE_MIN
SAMPLE_STEP = 0.08
SEA_IDS = (950124, 950006, 950123)  # west, central-north, east+Azov

Point = Tuple[float, float]
Ring = Sequence[Sequence[float]]


def prefer_live_black_sea() -> bool:
    return True  # GAP_USSR_BLACK_SEA


def canvas_to_lonlat(x: float, y: float) -> Point:
    lon = -180.0 + (float(x) / 8191.0) * 360.0
    lat = 83.0 - (float(y) / 4095.0) * 139.0
    return lon, lat


def lonlat_to_canvas(lon: float, lat: float) -> Point:
    x = (float(lon) - (-180.0)) / 360.0 * 8191.0
    y = (83.0 - float(lat)) / 139.0 * 4095.0
    return x, y


def _open_ring(ring: Ring) -> List[Point]:
    pts = [(float(p[0]), float(p[1])) for p in ring if len(p) >= 2]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def point_in_ring(x: float, y: float, ring: Ring) -> bool:
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


def _bbox(ring: Ring) -> Tuple[float, float, float, float]:
    pts = _open_ring(ring)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _hits(x: float, y: float, rings: Iterable[Ring]) -> bool:
    for ring in rings:
        bb = _bbox(ring)
        if x < bb[0] or x > bb[2] or y < bb[1] or y > bb[3]:
            continue
        if point_in_ring(x, y, ring):
            return True
    return False


def _ne_land_sampler():
    """Boolean (lon, lat) -> on land, rasterized over the Black Sea bbox."""
    import numpy as np
    from PIL import Image, ImageDraw

    lon0, lat0, lon1, lat1 = BLACK_SEA_BBOX
    # Pad so a coastline vertex on the edge still paints.
    pad = 0.4
    step = 0.02
    w = max(8, int(round((lon1 - lon0 + 2 * pad) / step)) + 1)
    h = max(8, int(round((lat1 - lat0 + 2 * pad) / step)) + 1)
    img = Image.new("1", (w, h), 0)
    draw = ImageDraw.Draw(img)

    def pix(lon: float, lat: float) -> Tuple[float, float]:
        return ((lon - (lon0 - pad)) / step, ((lat1 + pad) - lat) / step)

    fc = json.loads(NE_LAND.read_text(encoding="utf-8"))
    for feat in fc.get("features") or []:
        geom = feat.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates") or []
        polys = []
        if gtype == "Polygon":
            polys = [coords]
        elif gtype == "MultiPolygon":
            polys = coords
        for poly in polys:
            if not poly:
                continue
            ring = poly[0]
            xs = [c[0] for c in ring]
            ys = [c[1] for c in ring]
            if max(xs) < lon0 - pad or min(xs) > lon1 + pad or max(ys) < lat0 - pad or min(ys) > lat1 + pad:
                continue
            draw.polygon([pix(c[0], c[1]) for c in ring], fill=1)
            for hole in poly[1:]:
                draw.polygon([pix(c[0], c[1]) for c in hole], fill=0)
    arr = np.array(img, dtype=bool)

    def on_land(lon: float, lat: float) -> bool:
        col = int(round((lon - (lon0 - pad)) / step))
        row = int(round(((lat1 + pad) - lat) / step))
        if col < 0 or row < 0 or col >= w or row >= h:
            return False
        return bool(arr[row, col])

    return on_land


def black_sea_coverage(rings_by_id: Mapping[int, Ring]) -> dict:
    """Fraction of Black Sea bbox water whose canvas point sits in a zone ring."""
    on_land = _ne_land_sampler()
    lon0, lat0, lon1, lat1 = BLACK_SEA_BBOX
    mx0, my0, mx1, my1 = MARMARA_BBOX
    zones = [rings_by_id[i] for i in SEA_IDS if i in rings_by_id]
    water = 0
    hit = 0
    lat = lat0
    while lat <= lat1 + 1e-9:
        lon = lon0
        while lon <= lon1 + 1e-9:
            in_marmara = mx0 <= lon <= mx1 and my0 <= lat <= my1
            if not in_marmara and not on_land(lon, lat):
                water += 1
                x, y = lonlat_to_canvas(lon, lat)
                if _hits(x, y, zones):
                    hit += 1
            lon += SAMPLE_STEP
        lat += SAMPLE_STEP
    rate = (hit / water) if water else 0.0
    return {"water": water, "hit": hit, "rate": rate, "min": COVERAGE_MIN}


def load_geometry_rings() -> Dict[int, List[List[float]]]:
    doc = json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))
    out: Dict[int, List[List[float]]] = {}
    for row in doc.get("provinces") or []:
        out[int(row["id"])] = row.get("points") or []
    return out


def load_blob_rings() -> Dict[int, List[List[float]]]:
    doc = json.loads(FIXTURE.read_text(encoding="utf-8"))
    rings = doc.get("rings") or {}
    return {int(k): v for k, v in rings.items()}


def selected_black_sea_coverage() -> dict:
    live = load_geometry_rings()
    if prefer_live_black_sea():
        rings = live
    else:
        blobs = load_blob_rings()
        rings = dict(live)
        for pid, pts in blobs.items():
            if pid in SEA_IDS:
                rings[pid] = pts
    return black_sea_coverage(rings)
