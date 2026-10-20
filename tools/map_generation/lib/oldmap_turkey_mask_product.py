"""OLDMAP_TURKEY render-only mask checks.

The baked asset is canvas space (the same units as provinces_geometry.json).
The renderer multiplies by MapCanvasConfig.THEATER_SCALE when it mounts polygons.
This module does not import shapely and does not write data/.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

from ne_full_geometry_align import lonlat_to_canvas

ROOT = Path(__file__).resolve().parents[3]
GEOM_PATH = ROOT / "data" / "provinces_world_accurate" / "provinces_geometry.json"
MASK_PATH = ROOT / "assets" / "maps" / "layers" / "uncovered_land_ussr_west.json"
RENDERER_PATH = ROOT / "scripts" / "map" / "MapRenderer.gd"

# lon_min, lat_min, lon_max, lat_max
BBOX_LONLAT = (22.0, 43.0, 42.0, 56.0)
KIEV_LONLAT = (30.5234, 50.4501)
CRIMEA_LONLAT = (34.1000, 45.3000)
BLACK_SEA_LONLAT = (34.0000, 43.6000)
MASK_Z = -14
# Grid step in canvas px. A mask that still covers province rings fails this.
OVERLAP_STEP = 2.0
# Sliver tolerance: samples that land on a shared edge. A real overlap is dozens.
OVERLAP_SAMPLE_LIMIT = 0

Ring = Sequence[Sequence[float]]
Point = Tuple[float, float]


def canvas_bbox() -> Tuple[float, float, float, float]:
    lon0, lat0, lon1, lat1 = BBOX_LONLAT
    x_west, y_north = lonlat_to_canvas(lon0, lat1)
    x_east, y_south = lonlat_to_canvas(lon1, lat0)
    return (min(x_west, x_east), min(y_north, y_south), max(x_west, x_east), max(y_north, y_south))


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


def ring_bbox(ring: Ring) -> Tuple[float, float, float, float]:
    pts = _open_ring(ring)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def bboxes_overlap(a: Tuple[float, float, float, float], b: Tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def point_in_bbox(x: float, y: float, box: Tuple[float, float, float, float]) -> bool:
    return box[0] <= x <= box[2] and box[1] <= y <= box[3]


def load_mask(path: Path = MASK_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_province_rings(path: Path = GEOM_PATH) -> List[dict]:
    """Rings whose bbox meets the mask window. Read-only."""
    box = canvas_bbox()
    # Pad so a ring that only kisses the window is still subtracted in the check.
    pad = 4.0
    window = (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)
    data = json.loads(path.read_text(encoding="utf-8"))
    out: List[dict] = []
    for g in data.get("provinces") or []:
        pts = g.get("points") or []
        if len(pts) < 3:
            continue
        bb = ring_bbox(pts)
        if not bboxes_overlap(bb, window):
            continue
        out.append({
            "id": int(g.get("id") or 0),
            "name": str(g.get("name") or ""),
            "points": pts,
            "bbox": bb,
            "sea": int(g.get("id") or 0) >= 950000,
        })
    return out


def _covered(x: float, y: float, rings: Iterable[Ring]) -> bool:
    for ring in rings:
        if point_in_ring(x, y, ring):
            return True
    return False


def overlap_samples(mask_rings: Sequence[Ring], provinces: Sequence[dict], step: float = OVERLAP_STEP) -> List[Point]:
    """Canvas points that fall in the mask and in a province ring."""
    if step <= 0.0:
        step = OVERLAP_STEP
    box = canvas_bbox()
    prov = []
    for p in provinces:
        prov.append((p["bbox"], p["points"]))
    hits: List[Point] = []
    y = box[1]
    while y <= box[3]:
        x = box[0]
        while x <= box[2]:
            if _covered(x, y, mask_rings):
                for bb, ring in prov:
                    if point_in_bbox(x, y, bb) and point_in_ring(x, y, ring):
                        hits.append((x, y))
                        break
            x += step
        y += step
    return hits


def witness_report(mask: dict, provinces: Sequence[dict] | None = None) -> dict:
    if provinces is None:
        provinces = load_province_rings()
    land = mask.get("land") or []
    sea = mask.get("sea") or []
    kx, ky = lonlat_to_canvas(*KIEV_LONLAT)
    cx, cy = lonlat_to_canvas(*CRIMEA_LONLAT)
    sx, sy = lonlat_to_canvas(*BLACK_SEA_LONLAT)
    def _at(x: float, y: float, sea: bool | None = None):
        for p in provinces:
            if sea is True and not p["sea"]:
                continue
            if sea is False and p["sea"]:
                continue
            if point_in_bbox(x, y, p["bbox"]) and point_in_ring(x, y, p["points"]):
                return p["id"]
        return None

    kiev_prov = _at(kx, ky, sea=False)
    crimea_prov = _at(cx, cy, sea=False)
    black_sea_prov = _at(sx, sy, sea=True)
    owned_centroids_in_mask = []
    for p in provinces:
        if p["sea"]:
            continue
        pts = _open_ring(p["points"])
        if len(pts) < 3:
            continue
        mx = sum(pt[0] for pt in pts) / len(pts)
        my = sum(pt[1] for pt in pts) / len(pts)
        if not point_in_bbox(mx, my, canvas_bbox()):
            continue
        if not point_in_ring(mx, my, p["points"]):
            continue
        if _covered(mx, my, land):
            owned_centroids_in_mask.append(p["id"])
    overlaps = overlap_samples(list(land) + list(sea), provinces)
    return {
        "kiev_in_land": _covered(kx, ky, land),
        "kiev_in_province": kiev_prov,
        "crimea_in_land": _covered(cx, cy, land),
        "crimea_in_province": crimea_prov,
        "black_sea_in_sea": _covered(sx, sy, sea),
        "black_sea_in_land": _covered(sx, sy, land),
        "black_sea_in_province": black_sea_prov,
        "owned_centroids_in_mask": owned_centroids_in_mask[:12],
        "owned_centroid_hits": len(owned_centroids_in_mask),
        "overlap_samples": len(overlaps),
        "land_rings": len(land),
        "sea_rings": len(sea),
        "space": mask.get("space"),
    }


def renderer_mount_ok(text: str | None = None) -> dict:
    if text is None:
        text = RENDERER_PATH.read_text(encoding="utf-8")
    missing = []
    for needle in (
        "func _ensure_ussr_west_gap_mask",
        "USSR_WEST_GAP_MASK_Z := -14",
        "uncovered_land_ussr_west.json",
        "func _apply_legacy_underlay_policy",
    ):
        if needle not in text:
            missing.append(needle)
    # The mount has to be invoked from the world-underlay path, not only defined.
    if text.count("_ensure_ussr_west_gap_mask()") < 2:
        missing.append("call _ensure_ussr_west_gap_mask()")
    if text.count("_apply_legacy_underlay_policy()") < 2:
        missing.append("call _apply_legacy_underlay_policy()")
    return {"ok": not missing, "missing": missing, "mask_z": MASK_Z}


def full_bbox_land_ring() -> List[List[float]]:
    """Mutant geometry: the window rectangle, with no province rings removed."""
    x0, y0, x1, y1 = canvas_bbox()
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
