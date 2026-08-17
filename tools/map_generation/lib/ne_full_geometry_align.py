"""Natural Earth full-world province geometry align (id-stable).

Projects NE 10m land to the world_full canvas, rasterizes a land mask, then
snaps every province ring onto land/water so coasts follow real NE shorelines.
Does **not** renumber province ids. Pure helpers + apply payload.
"""
from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

try:
    import numpy as np
except ImportError:  # pragma: no cover — lazy: constants/helpers stay importable
    np = None  # type: ignore[assignment]

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover — lazy: same as numpy
    Image = None  # type: ignore[assignment]
    ImageDraw = None  # type: ignore[assignment]

_NE_DEPS_HINT = (
    "numpy and Pillow are required for NE land-mask QC. "
    "Install: python3 -m pip install --user -r tools/map_generation/requirements.txt"
)


def _require_numpy():
    if np is None:
        raise ImportError(_NE_DEPS_HINT)
    return np


def _require_pillow():
    if Image is None or ImageDraw is None:
        raise ImportError(_NE_DEPS_HINT)
    return Image, ImageDraw

Point = List[float]
Ring = List[Point]

# Match tools/map_generation/scripts/build_real_world_map_layers.py world_full
WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)  # lon_min, lat_min, lon_max, lat_max
WORLD_CANVAS = (8192.0, 4096.0)

DEFAULT_NE_LAND = (
    Path(__file__).resolve().parents[1]
    / "data"
    / "cache"
    / "map_tiles"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_land.geojson"
)


def lonlat_to_canvas(lon: float, lat: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    x = (float(lon) - lon_min) / (lon_max - lon_min) * (w - 1.0)
    y = (lat_max - float(lat)) / (lat_max - lat_min) * (h - 1.0)
    return x, y


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    ring = list(points)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    sx = sum(float(p[0]) for p in ring)
    sy = sum(float(p[1]) for p in ring)
    n = float(len(ring))
    return sx / n, sy / n


def ensure_min_vertices(points: Sequence[Sequence[float]], min_vertices: int = 20) -> Ring:
    ring: Ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    guard = 0
    while len(ring) < min_vertices and guard < 20_000:
        guard += 1
        best_i = 0
        best_len = -1.0
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d > best_len:
                best_len = d
                best_i = i
        a, b = ring[best_i], ring[(best_i + 1) % n]
        mid = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
        ring.insert(best_i + 1, mid)
    return ring


def geometry_stats(provinces: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    sizes = [len(p.get("points") or []) for p in provinces]
    if not sizes:
        return {"count": 0, "min": 0, "max": 0, "median": 0, "triangles": 0}
    ordered = sorted(sizes)
    return {
        "count": len(sizes),
        "min": ordered[0],
        "max": ordered[-1],
        "median": ordered[len(ordered) // 2],
        "avg": sum(sizes) / float(len(sizes)),
        "triangles": sum(1 for s in sizes if s == 3),
        "below_16": sum(1 for s in sizes if s < 16),
    }


def load_ne_land_features(path: Path) -> List[List[Tuple[float, float]]]:
    """Return list of outer rings in canvas coordinates (float)."""
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    feats = raw.get("features") if isinstance(raw, dict) else raw
    rings: List[List[Tuple[float, float]]] = []
    if not isinstance(feats, list):
        return rings
    for f in feats:
        if not isinstance(f, dict):
            continue
        geom = f.get("geometry") if isinstance(f.get("geometry"), dict) else {}
        gtype = str(geom.get("type", ""))
        coords = geom.get("coordinates")
        if not coords:
            continue
        polys: List[Any] = []
        if gtype == "Polygon":
            polys = [coords]
        elif gtype == "MultiPolygon":
            polys = list(coords)
        for poly in polys:
            if not poly:
                continue
            outer = poly[0]
            if not outer or len(outer) < 3:
                continue
            # Subsample very dense rings for rasterization speed
            step = max(1, len(outer) // 4000)
            ring: List[Tuple[float, float]] = []
            for i in range(0, len(outer), step):
                pt = outer[i]
                if not isinstance(pt, (list, tuple)) or len(pt) < 2:
                    continue
                lon, lat = float(pt[0]), float(pt[1])
                # Skip poles outside world_full bbox slightly
                if lat < WORLD_BBOX[1] - 1.0 or lat > WORLD_BBOX[3] + 1.0:
                    continue
                x, y = lonlat_to_canvas(lon, lat)
                ring.append((x, y))
            if len(ring) >= 3:
                rings.append(ring)
    return rings


def rasterize_land_mask(
    rings: Sequence[Sequence[Tuple[float, float]]],
    *,
    width: int = 2048,
    height: int = 1024,
) -> np.ndarray:
    """Binary land mask (uint8 0/255) at reduced resolution for speed."""
    numpy = _require_numpy()
    pil_image, pil_draw = _require_pillow()
    w, h = int(width), int(height)
    cw, ch = WORLD_CANVAS
    img = pil_image.new("L", (w, h), 0)
    draw = pil_draw.Draw(img)
    for ring in rings:
        if len(ring) < 3:
            continue
        pts = []
        for x, y in ring:
            mx = int(float(x) / (cw - 1.0) * (w - 1))
            my = int(float(y) / (ch - 1.0) * (h - 1))
            pts.append((max(0, min(w - 1, mx)), max(0, min(h - 1, my))))
        if len(pts) >= 3:
            draw.polygon(pts, fill=255)
    return numpy.asarray(img, dtype=numpy.uint8)


def sample_mask(mask: np.ndarray, x: float, y: float) -> bool:
    h, w = mask.shape
    cw, ch = WORLD_CANVAS
    mx = int(round(float(x) / (cw - 1.0) * (w - 1)))
    my = int(round(float(y) / (ch - 1.0) * (h - 1)))
    mx = max(0, min(w - 1, mx))
    my = max(0, min(h - 1, my))
    return bool(mask[my, mx] >= 128)


def nearest_mask_pixel(
    mask: np.ndarray,
    x: float,
    y: float,
    *,
    want_land: bool,
    max_radius: int = 48,
) -> Tuple[float, float]:
    """Spiral search for nearest land/water pixel; return canvas coordinates."""
    h, w = mask.shape
    cw, ch = WORLD_CANVAS
    mx = int(round(float(x) / (cw - 1.0) * (w - 1)))
    my = int(round(float(y) / (ch - 1.0) * (h - 1)))
    mx = max(0, min(w - 1, mx))
    my = max(0, min(h - 1, my))
    target = 255 if want_land else 0
    if (mask[my, mx] >= 128) == want_land:
        return float(x), float(y)
    best = None
    best_d = 1e18
    for r in range(1, max_radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if abs(dx) != r and abs(dy) != r:
                    continue
                nx, ny = mx + dx, my + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h:
                    continue
                if (mask[ny, nx] >= 128) == want_land:
                    d = float(dx * dx + dy * dy)
                    if d < best_d:
                        best_d = d
                        best = (nx, ny)
        if best is not None:
            break
    if best is None:
        return float(x), float(y)
    bx, by = best
    ox = bx / max(1, w - 1) * (cw - 1.0)
    oy = by / max(1, h - 1) * (ch - 1.0)
    return ox, oy


def snap_ring_to_ne(
    points: Sequence[Sequence[float]],
    mask: np.ndarray,
    *,
    is_water: bool,
    min_vertices: int = 20,
    blend: float = 0.85,
) -> Tuple[Ring, int]:
    """Snap ring vertices toward NE land/water. Returns (ring, snapped_count)."""
    ring = ensure_min_vertices(points, min_vertices=min_vertices)
    if len(ring) < 3:
        return ring, 0
    cx, cy = polygon_centroid(ring)
    snapped = 0
    want_land = not is_water
    out: Ring = []
    for p in ring:
        x, y = float(p[0]), float(p[1])
        on_land = sample_mask(mask, x, y)
        need_fix = (want_land and not on_land) or ((not want_land) and on_land)
        if need_fix:
            nx, ny = nearest_mask_pixel(mask, x, y, want_land=want_land)
            # Blend toward NE snap (preserve some province identity)
            bx = x * (1.0 - blend) + nx * blend
            by = y * (1.0 - blend) + ny * blend
            # Keep roughly near original centroid to avoid total collapse
            bx = bx * 0.92 + cx * 0.08
            by = by * 0.92 + cy * 0.08
            out.append([bx, by])
            snapped += 1
        else:
            out.append([x, y])
    return out, snapped


def is_water_domain(domain: str) -> bool:
    d = str(domain or "").strip().lower()
    return d in ("sea", "strait", "lake", "ocean", "water")


def build_domain_map(terrain_payload: Mapping[str, Any]) -> Dict[int, str]:
    out: Dict[int, str] = {}
    provs = terrain_payload.get("provinces")
    if isinstance(provs, dict):
        for pid, row in provs.items():
            if isinstance(row, dict):
                out[int(pid)] = str(row.get("domain", "land"))
    return out


def apply_ne_full_align(
    geom_payload: Mapping[str, Any],
    mask: np.ndarray,
    domain_map: Mapping[int, str],
    *,
    min_vertices_land: int = 24,
    min_vertices_water: int = 18,
    blend: float = 0.85,
) -> Dict[str, Any]:
    """Return new geometry payload with all provinces NE-aligned. Ids preserved."""
    out = deepcopy(dict(geom_payload))
    provs = [dict(p) for p in (out.get("provinces") or [])]
    land_n = 0
    water_n = 0
    snap_total = 0
    for i, p in enumerate(provs):
        pid = int(p.get("id", -1))
        domain = domain_map.get(pid, str(p.get("domain", "land")))
        water = is_water_domain(domain)
        pts = p.get("points") or []
        if len(pts) < 3:
            continue
        min_v = min_vertices_water if water else min_vertices_land
        ring, sn = snap_ring_to_ne(pts, mask, is_water=water, min_vertices=min_v, blend=blend)
        if len(ring) < 3:
            continue
        provs[i] = dict(p)
        provs[i]["points"] = ring
        cx, cy = polygon_centroid(ring)
        provs[i]["label_anchor"] = [cx, cy]
        meta = dict(provs[i].get("meta") or {})
        meta["gis_pilot"] = True  # compat with existing gates
        meta["gis_ne_full"] = True
        meta["gis_ne_source"] = "ne_10m_land"
        meta["gis_ne_snapped_verts"] = sn
        meta["gis_points_before"] = len(pts)
        meta["gis_points_after"] = len(ring)
        if water:
            meta["gis_ne_domain"] = "water"
            water_n += 1
        else:
            meta["gis_ne_domain"] = "land"
            land_n += 1
        provs[i]["meta"] = meta
        snap_total += sn
    out["provinces"] = provs
    gmeta = dict(out.get("meta") or {})
    gmeta["gis_coastline_pilot"] = True
    gmeta["gis_ne_full"] = True
    gmeta["gis_ne_source"] = "ne_10m_land"
    gmeta["gis_pilot_count"] = land_n + water_n
    gmeta["gis_ne_land_count"] = land_n
    gmeta["gis_ne_water_count"] = water_n
    gmeta["gis_ne_snapped_verts_total"] = snap_total
    gmeta["gis_pilot_applied_ids"] = [int(p["id"]) for p in provs if (p.get("meta") or {}).get("gis_ne_full")]
    stats = geometry_stats(provs)
    gmeta["vertex_min"] = stats.get("min")
    gmeta["vertex_median"] = stats.get("median")
    gmeta["triangle_count"] = stats.get("triangles")
    out["meta"] = gmeta
    return out


def ne_full_integrity_report(geom_payload: Mapping[str, Any]) -> Dict[str, Any]:
    provs = list(geom_payload.get("provinces") or [])
    stamped = sum(1 for p in provs if (p.get("meta") or {}).get("gis_ne_full"))
    pilot = sum(1 for p in provs if (p.get("meta") or {}).get("gis_pilot"))
    stats = geometry_stats(provs)
    meta = geom_payload.get("meta") or {}
    ids = {int(p["id"]) for p in provs if "id" in p}
    ok = (
        len(provs) >= 2665
        and len(ids) == len(provs)
        and stamped >= 2665
        and pilot >= 2665
        and int(stats.get("triangles") or 0) == 0
        and int(stats.get("min") or 0) >= 16
        and bool(meta.get("gis_ne_full"))
    )
    return {
        "ok": ok,
        "province_count": len(provs),
        "id_count": len(ids),
        "gis_ne_full_count": stamped,
        "gis_pilot_count": pilot,
        "stats": stats,
        "meta_ne": bool(meta.get("gis_ne_full")),
        "summary": "NE full geometry %s · stamped %d/%d · triangles %s"
        % ("PASS" if ok else "FAIL", stamped, len(provs), stats.get("triangles")),
    }
