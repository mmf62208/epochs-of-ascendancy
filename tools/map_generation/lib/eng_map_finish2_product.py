"""ENG-MAP-FINISH-2: leftover water faces, ON/QC specks, DC triangles, NY West, Gulf rename.

Lake Ontario 950337 already exists as domain=lake. New York West 800446 covers
most of that basin, so the lake paints as land and the NY West pick outline
includes the water. Natural Earth 10m Lake Ontario replaces the coarse basin
ring; overlapping land is clipped off that water (and off Lake Erie for NY
West). St Lawrence leftover water faces and ON/QC specks are absorbed into
the existing neighbour chosen by canada_hole_measure. Two ~70 px² uncovered
land triangles near Washington are absorbed into Pennsylvania East and
Maryland East. Gulf of Mexico display names become Gulf of America. No new
province id. Nothing is renamed Lake America.
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from canada_hole_measure import (  # noqa: E402
    LAND_GEOJSON,
    WATER_DOMAINS,
    WINDOW_PAD,
    _area,
    _bbox,
    _clean,
    _edge_index,
    _even_odd,
    _in_ne,
    _interior_point,
    _load_ne_polys,
    _owners_of_edge,
    _point_in_rings,
    _poly_centroid,
    _winding,
    arrange,
    canvas_to_lonlat,
    choose_absorb_target,
    measure_canada_holes,
    merge_positive_rings,
)
from gap_china2_outline import as_points, region_loops, snap  # noqa: E402
from gap_eng1_product import ring_is_raw_invalid  # noqa: E402
from gap_ussr_west2_product import overlap_px, ring_bbox  # noqa: E402
from great_lakes_water_province_product import (  # noqa: E402
    LAKE_ERIE_ID,
    LAKE_ONTARIO_ID,
    lonlat_to_canvas,
    ne_named_lake_ring,
)

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

NY_WEST_ID = 800446
DC_ID = 800792
PA_EAST_ID = 801515
MD_EAST_ID = 800273
HAMILTON_NIAGARA_ID = 903049
LONDON_ID = 903050
WINDSOR_SARNIA_ID = 903051
GULF_ACCURATE_ID = 950029
GULF_FULL_ID = 20115
GULF_PILOT_ID = 901121
GULF_OLD = "Gulf of Mexico Zone"
GULF_NEW = "Gulf of America Zone"
LAKE_AMERICA = "Lake America"

# Faces at or over this in the Washington window are the leftover triangles.
DC_FACE_MIN = 20.0
# Canada residual specks along Ontario / Quebec / St Lawrence.
SPECK_MIN = 1.0
SPECK_WINDOW = (-81.5, 42.5, -70.0, 50.5)
DC_WINDOW = (-78.6, 38.5, -75.3, 40.2)
OVERLAP_PX_MAX = 1
POLY_OVERLAP_MAX = 1.0
SLIVER_AREA = 5.0
KEEP_LOOP_MIN = 8.0
# Near-water band for the Hamilton–Niagara sliver that followed Erie to Windsor.
ERIE_TAIL_BAND_PX = 4.0
# London #903050 original west edge on main / 2e1e6f98 (before r1 speck absorb).
LONDON_ORIG_WEST_X = 2227.4681
# r1 already clipped Hamilton; do not recut the Niagara/Port Dover coast.
HAMILTON_KEEP_WEST_X = 2250.0
# Erie-shore tip of the leftover corridor (Windsor-end vertex on 2e1e6f98 / 5109bd41).
WINDSOR_END_VERTEX = (2204.4536, 1206.6906)
LEFTOVER_LAND_IDS = (
    MD_EAST_ID,
    NY_WEST_ID,
    PA_EAST_ID,
    *tuple(range(903029, 903054)),
)

GULF_NAME_FILES = (
    ROOT / "data" / "provinces_world_accurate" / "provinces_base.json",
    ROOT / "data" / "provinces_world_full" / "provinces_base.json",
    ROOT / "data" / "provinces_grand_theater" / "provinces_base.json",
    ROOT / "data" / "provinces_pilot_global_density" / "provinces_base.json",
    ROOT / "tools" / "map_generation" / "scripts" / "expand_grand_theater_provinces.py",
)

# NY cities that must stay inside New York West after the lake clip.
NY_WEST_CITIES = {
    "Buffalo": (-78.88, 42.89),
    "Rochester": (-77.61, 43.16),
    "Syracuse": (-76.15, 43.05),
    "Oswego": (-76.51, 43.45),
}


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _domain(prov: dict) -> str:
    return str(prov.get("domain") or "land")


def _positive(ring):
    pts = _clean([(float(p[0]), float(p[1])) for p in ring])
    if _area(pts) < 0:
        pts = list(reversed(pts))
    return pts


def snap_ring(ring: Sequence[Sequence[float]]) -> List[Tuple[float, float]]:
    pts = [snap((float(p[0]), float(p[1]))) for p in ring]
    out: List[Tuple[float, float]] = []
    for pt in pts:
        if not out or pt != out[-1]:
            out.append(pt)
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    return out


def as_ring(loop) -> List[Tuple[float, float]]:
    return snap_ring(as_points(loop, 6))


def ontario_ne_ring() -> List[Tuple[float, float]]:
    ring = ne_named_lake_ring("Lake Ontario", -81.0, -74.5, 42.5, 45.5)
    out = as_ring(ring)
    if len(out) < 8:
        raise RuntimeError("NE Lake Ontario ring too short")
    if ring_is_raw_invalid(out):
        raise RuntimeError("NE Lake Ontario ring is self-crossing")
    return out


def clip_land_off_water(land, waters: Sequence) -> List[List[Tuple[float, float]]]:
    """Largest-first difference of a land ring minus water rings."""
    loops = region_loops([_positive(land)], [_positive(w) for w in waters], "difference")
    kept = []
    for loop in loops:
        if abs(_area(loop)) < 0.5:
            continue
        kept.append(as_ring(loop))
    kept.sort(key=lambda r: -abs(_area(r)))
    return kept


def _anchor_inside(ring, anchor) -> bool:
    return _winding(ring, float(anchor[0]), float(anchor[1])) != 0


def choose_keep_loop(loops: Sequence, original, anchor) -> List[Tuple[float, float]]:
    """Keep the largest remaining land loop. Prefer one that still holds the label."""
    if not loops:
        raise RuntimeError("clip removed the land ring")
    if _anchor_inside(loops[0], anchor):
        return list(loops[0])
    for loop in loops:
        if abs(_area(loop)) >= KEEP_LOOP_MIN and _anchor_inside(loop, anchor):
            return list(loop)
    # Label sat in the water. Keep the largest land body and move the label later.
    return list(loops[0])


def land_water_overlap_px(land_ring, water_ring) -> int:
    return int(overlap_px([[p[0], p[1]] for p in land_ring], [[p[0], p[1]] for p in water_ring]))


def dist_point_to_ring(pt, ring) -> float:
    x, y = float(pt[0]), float(pt[1])
    best = None
    n = len(ring)
    for i in range(n):
        x1, y1 = float(ring[i][0]), float(ring[i][1])
        x2, y2 = float(ring[(i + 1) % n][0]), float(ring[(i + 1) % n][1])
        dx = x2 - x1
        dy = y2 - y1
        if dx == 0.0 and dy == 0.0:
            d2 = (x - x1) ** 2 + (y - y1) ** 2
        else:
            t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
            px = x1 + t * dx
            py = y1 + t * dy
            d2 = (x - px) ** 2 + (y - py) ** 2
        if best is None or d2 < best:
            best = d2
    return math.sqrt(best) if best is not None else 0.0


def erie_peninsula_junction(erie, probe):
    """Erie vertex nearest the peninsula probe (label / Hamilton). Port Dover contact."""
    px, py = float(probe[0]), float(probe[1])
    return min(erie, key=lambda p: (float(p[0]) - px) ** 2 + (float(p[1]) - py) ** 2)


def leftover_erie_cutoff_x(pid, erie, ham_probe) -> Optional[float]:
    """West-of-body cutoff for a leftover land face. None means skip.

    London keeps its original body (west ~2227.47) and any wider Port
    Stanley / Port Dover shore east of that. Windsor already owns that
    west coast — do not strip it. Hamilton stays at the r1 peninsula clip.
    Other leftover land is flagged if it sends an Erie-shore run into the
    same west-of-London corridor (x < 2227.47).
    """
    if pid == WINDSOR_SARNIA_ID:
        return None
    if pid == LONDON_ID:
        return LONDON_ORIG_WEST_X
    if pid == HAMILTON_NIAGARA_ID:
        return HAMILTON_KEEP_WEST_X
    if ham_probe is None:
        return None
    return LONDON_ORIG_WEST_X


def erie_shore_tail_indices(land, erie, probe, band: float = ERIE_TAIL_BAND_PX, cutoff_x: Optional[float] = None) -> List[int]:
    """Land vertices that follow Erie west of a body cutoff.

    Fails on tip 2e1e6f98 for Hamilton and on 5109bd41 for London's
    1–2 px Windsor corridor. Boundary vertices at the cutoff are kept.
    """
    if len(land) < 4 or len(erie) < 3:
        return []
    if cutoff_x is None:
        junction = erie_peninsula_junction(erie, probe)
        cutoff_x = float(junction[0]) - 0.05
    hits = []
    for i, pt in enumerate(land):
        if float(pt[0]) >= float(cutoff_x):
            continue
        if dist_point_to_ring(pt, erie) < band:
            hits.append(i)
    return hits


def clip_erie_shore_tail(land, erie, anchor, probe=None, band: float = ERIE_TAIL_BAND_PX, cutoff_x: Optional[float] = None):
    """Drop the west-along-Erie spike. Returns (ring, dropped_count)."""
    if probe is None:
        probe = anchor
    drop = set(erie_shore_tail_indices(land, erie, probe, band=band, cutoff_x=cutoff_x))
    if not drop:
        return list(land), 0
    kept = [pt for i, pt in enumerate(land) if i not in drop]
    kept = snap_ring(kept)
    if len(kept) < 3:
        raise RuntimeError("erie tail clip removed the land ring")
    if abs(_area(kept)) < KEEP_LOOP_MIN:
        raise RuntimeError("erie tail clip left the land ring too small")
    if ring_is_raw_invalid(kept) and not ring_is_raw_invalid(land):
        raise RuntimeError("erie tail clip made the land ring self-crossing")
    if not _anchor_inside(kept, anchor):
        raise RuntimeError("erie tail clip left the label outside the land ring")
    return kept, len(drop)


def split_ring_at_x(ring, x_cut: float, eps: float = 1e-9):
    """Walk-ring split on a vertical line. On-cut body verts stay east-only."""
    pts = [(float(p[0]), float(p[1])) for p in ring]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    east: List[Tuple[float, float]] = []
    west: List[Tuple[float, float]] = []
    crossings = 0
    n = len(pts)
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        sa = a[0] - float(x_cut)
        sb = b[0] - float(x_cut)
        if sa > eps:
            east.append(a)
        elif sa < -eps:
            west.append(a)
        else:
            east.append(a)
        if sa * sb < -1e-12:
            den = a[0] - b[0]
            t = (a[0] - float(x_cut)) / den if abs(den) > 1e-15 else 0.5
            t = min(1.0, max(0.0, t))
            hit = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            east.append(hit)
            west.append(hit)
            crossings += 1
    return snap_ring(east), snap_ring(west), crossings


def reassign_london_west_erie_corridor(rings: dict, anchors: dict, metas: dict, changed: dict) -> list:
    """Move London's thin Erie corridor west of its original body onto Windsor.

    Vertex-drop is the wrong clip here: it chords through Port Stanley shore.
    Split at London's original west edge, keep the east body + thicker shore,
    absorb only the west piece into #903051.
    """
    if LONDON_ID not in rings or WINDSOR_SARNIA_ID not in rings:
        return []
    east, west, crossings = split_ring_at_x(rings[LONDON_ID], LONDON_ORIG_WEST_X)
    if len(west) < 3 or abs(_area(west)) < 0.5:
        return []
    if len(east) < 3:
        raise RuntimeError("london west clip removed the land ring")
    if abs(_area(east)) < KEEP_LOOP_MIN:
        raise RuntimeError("london west clip left the land ring too small")
    if ring_is_raw_invalid(east) and not ring_is_raw_invalid(rings[LONDON_ID]):
        raise RuntimeError("london west clip made London self-crossing")
    if not _anchor_inside(east, anchors[LONDON_ID]):
        raise RuntimeError("london west clip left the label outside London")
    if min(p[0] for p in east) < LONDON_ORIG_WEST_X - 0.05:
        raise RuntimeError("london west clip left the Windsor corridor on London")
    rings[LONDON_ID] = east
    metas[LONDON_ID]["eng_map_finish2_erie_tail"] = "west_clip_%d" % crossings
    changed[LONDON_ID] = ((changed.get(LONDON_ID) or "") + " clip erie west corridor").strip()
    absorb_hole_into(rings, anchors, WINDSOR_SARNIA_ID, west)
    metas[WINDSOR_SARNIA_ID]["eng_map_finish2_erie_corridor"] = "absorb_%.1f" % abs(_area(west))
    changed[WINDSOR_SARNIA_ID] = (
        (changed.get(WINDSOR_SARNIA_ID) or "") + " absorb erie corridor %.1f" % abs(_area(west))
    ).strip()
    return [
        {"id": LONDON_ID, "dropped": len(west), "verts": len(east)},
        {"id": WINDSOR_SARNIA_ID, "dropped": 0, "verts": len(rings[WINDSOR_SARNIA_ID])},
    ]


def clip_leftover_erie_tails(rings: dict, anchors: dict, metas: dict, changed: dict, leftover_ids=LEFTOVER_LAND_IDS) -> list:
    """Clip leftover land faces that send a thin tail into Lake Erie.

    London's west corridor is split onto Windsor. Hamilton keeps the r1
    peninsula drop-vert. Other leftover ids are not rewritten here.
    """
    clipped = reassign_london_west_erie_corridor(rings, anchors, metas, changed)
    if HAMILTON_NIAGARA_ID not in leftover_ids or HAMILTON_NIAGARA_ID not in rings:
        return clipped
    erie = rings[LAKE_ERIE_ID]
    probe = anchors.get(HAMILTON_NIAGARA_ID)
    if probe is None:
        probe = _poly_centroid(rings[HAMILTON_NIAGARA_ID])
    kept, n_drop = clip_erie_shore_tail(
        rings[HAMILTON_NIAGARA_ID],
        erie,
        anchors[HAMILTON_NIAGARA_ID],
        probe=probe,
        band=ERIE_TAIL_BAND_PX,
        cutoff_x=HAMILTON_KEEP_WEST_X,
    )
    if n_drop <= 0:
        return clipped
    rings[HAMILTON_NIAGARA_ID] = kept
    metas[HAMILTON_NIAGARA_ID]["eng_map_finish2_erie_tail"] = "drop_%d" % n_drop
    changed[HAMILTON_NIAGARA_ID] = (
        (changed.get(HAMILTON_NIAGARA_ID) or "") + " clip erie tail %d" % n_drop
    ).strip()
    clipped.append({"id": HAMILTON_NIAGARA_ID, "dropped": n_drop, "verts": len(kept)})
    return clipped


def measure_washington_faces(board: Path = DEFAULT_DIR) -> dict:
    """Uncovered land faces in the Maryland / Virginia / Pennsylvania window."""
    base = _load(board / "provinces_base.json")
    geo = _load(board / "provinces_geometry.json")
    provs = {int(p["id"]): p for p in base["provinces"]}
    rings = {}
    for g in geo["provinces"]:
        pts = _clean([(float(p[0]), float(p[1])) for p in (g.get("points") or [])])
        if len(pts) >= 3:
            rings[int(g["id"])] = pts
    lon0, lat0, lon1, lat1 = DC_WINDOW
    x0, y1 = lonlat_to_canvas(lon0, lat0)
    x1, y0 = lonlat_to_canvas(lon1, lat1)
    minx, maxx = (x0, x1) if x0 <= x1 else (x1, x0)
    miny, maxy = (y0, y1) if y0 <= y1 else (y1, y0)
    minx -= 40.0
    miny -= 40.0
    maxx += 40.0
    maxy += 40.0
    scope = []
    for pid, ring in rings.items():
        if _domain(provs.get(pid) or {}) in WATER_DOMAINS:
            continue
        bb = _bbox(ring)
        if bb[2] < minx or bb[0] > maxx or bb[3] < miny or bb[1] > maxy:
            continue
        scope.append(pid)
    land_rings = [rings[pid] for pid in scope]
    faces = arrange(land_rings)
    edge_grid = _edge_index({pid: rings[pid] for pid in scope})
    land_boxes = [_bbox(r) for r in land_rings]
    holes = []
    for face in faces:
        area = _area(face)
        if area < DC_FACE_MIN:
            continue
        pt = _interior_point(face)
        if pt is None:
            continue
        x, y = pt
        if _point_in_rings(land_rings, land_boxes, x, y, lambda r, px, py: _winding(r, px, py) != 0):
            continue
        if _point_in_rings(land_rings, land_boxes, x, y, _even_odd):
            continue
        lengths: Dict[int, float] = defaultdict(float)
        owners: List[int] = []
        n = len(face)
        for i in range(n):
            u, v = face[i], face[(i + 1) % n]
            for pid in _owners_of_edge(edge_grid, u, v):
                lengths[pid] += ((v[0] - u[0]) ** 2 + (v[1] - u[1]) ** 2) ** 0.5
                if pid not in owners:
                    owners.append(pid)
        if not owners:
            continue
        cx, cy = _poly_centroid(face)
        lon, lat = canvas_to_lonlat(cx, cy)
        surround = []
        for pid in sorted(owners, key=lambda p: -lengths[p]):
            prov = provs.get(pid) or {}
            surround.append(
                {
                    "id": pid,
                    "name": prov.get("name") or "",
                    "domain": _domain(prov),
                    "edge_px": round(lengths[pid], 2),
                }
            )
        holes.append(
            {
                "area_px2": round(area, 2),
                "area_exact": area,
                "centroid": [round(cx, 2), round(cy, 2)],
                "centroid_exact": [cx, cy],
                "lon": round(lon, 4),
                "lat": round(lat, 4),
                "surrounding": surround,
                "ring": [[round(p[0], 4), round(p[1], 4)] for p in face],
            }
        )
    holes.sort(key=lambda h: -h["area_exact"])
    return {
        "window": [minx, miny, maxx, maxy],
        "scope_provinces": len(scope),
        "holes": holes,
        "faces_over_min": [h for h in holes if h["area_px2"] >= DC_FACE_MIN],
    }


def choose_washington_target(hole: dict) -> Optional[int]:
    lands = [row for row in hole.get("surrounding") or [] if row.get("domain") not in WATER_DOMAINS]
    if not lands:
        return None
    return int(max(lands, key=lambda row: row.get("edge_px") or 0)["id"])


def speck_holes(report: dict) -> list:
    lon0, lat0, lon1, lat1 = SPECK_WINDOW
    out = []
    for hole in report.get("holes") or []:
        if float(hole.get("area_px2") or 0) + 1e-9 < SPECK_MIN:
            continue
        lon = float(hole.get("lon") or 0.0)
        lat = float(hole.get("lat") or 0.0)
        if lon0 <= lon <= lon1 and lat0 <= lat <= lat1:
            out.append(hole)
    return out


def gulf_name_hits() -> List[dict]:
    hits = []
    for path in GULF_NAME_FILES:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        if "Gulf of Mexico" in text:
            hits.append({"path": str(path.relative_to(ROOT)), "count": text.count("Gulf of Mexico")})
    return hits


def lake_america_hits(board: Path = DEFAULT_DIR) -> List[str]:
    names = []
    base = _load(board / "provinces_base.json")
    for p in base["provinces"]:
        if LAKE_AMERICA in str(p.get("name") or ""):
            names.append("%s:%s" % (p.get("id"), p.get("name")))
    return names


def ny_west_city_hits(ring) -> Dict[str, bool]:
    out = {}
    for name, (lon, lat) in NY_WEST_CITIES.items():
        x, y = lonlat_to_canvas(lon, lat)
        out[name] = _winding(ring, x, y) != 0
    return out


def overlapping_land_ids(rings: dict, domains: dict, water_ring, extra_ids=()) -> List[int]:
    wb = ring_bbox([[p[0], p[1]] for p in water_ring])
    hits = []
    for pid, ring in rings.items():
        if _domain({"domain": domains.get(pid)}) in WATER_DOMAINS:
            continue
        if pid == LAKE_ONTARIO_ID:
            continue
        bb = ring_bbox([[p[0], p[1]] for p in ring])
        if bb[2] < wb[0] or wb[2] < bb[0] or bb[3] < wb[1] or wb[3] < bb[1]:
            continue
        n = land_water_overlap_px(ring, water_ring)
        if n >= 1:
            hits.append(pid)
    return sorted(set(hits) | set(extra_ids))


def _stitch_shared_vertex(main, extra):
    extra_set = set(extra)
    pivots = []
    seen = set()
    for point in main:
        if point in extra_set and point not in seen:
            seen.add(point)
            pivots.append(point)
    if len(pivots) != 1:
        return None
    pivot = pivots[0]
    i = main.index(pivot)
    j = extra.index(pivot)
    body = extra[j + 1 :] + extra[:j]
    if body and body[-1] == pivot:
        body = body[:-1]
    if not body:
        return None
    return main[: i + 1] + body + main[i:]


def absorb_hole_into(rings: dict, anchors: dict, target: int, hole_ring) -> None:
    src = rings[target]
    was = ring_is_raw_invalid(src)
    hole = _positive(hole_ring)
    loops = merge_positive_rings(src, hole)
    if not loops:
        raise RuntimeError("absorb produced no ring for %s" % target)
    merged = loops[0]
    for loop in loops[1:]:
        if abs(_area(loop)) >= SLIVER_AREA:
            raise RuntimeError("absorb %s left a %.2f px² loop" % (target, abs(_area(loop))))
        ip = _interior_point(loop)
        if ip is not None and _winding(src, ip[0], ip[1]) != 0:
            stitched = _stitch_shared_vertex(merged, loop)
            if stitched is None:
                raise RuntimeError("absorb pinched off a real lobe of %s" % target)
            merged = stitched
    merged = as_ring(merged)
    if ring_is_raw_invalid(merged) and not was:
        raise RuntimeError("absorb made %s self-crossing" % target)
    probe = _interior_point(hole)
    if probe is None or _winding(merged, probe[0], probe[1]) == 0:
        raise RuntimeError("hole interior left outside %s" % target)
    if not _anchor_inside(merged, anchors[target]):
        raise RuntimeError("label anchor left outside %s" % target)
    rings[target] = merged


def _centroid_or_interior(ring):
    cx, cy = _poly_centroid(ring)
    if _winding(ring, cx, cy) != 0:
        return [round(cx, 4), round(cy, 4)]
    ip = _interior_point(ring)
    if ip is None:
        raise RuntimeError("no interior for label anchor")
    return [round(ip[0], 4), round(ip[1], 4)]


def build_plan(board: Path = DEFAULT_DIR) -> dict:
    """Compute new rings/anchors/metas. Does not write."""
    geo = _load(board / "provinces_geometry.json")
    base = _load(board / "provinces_base.json")
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
    names = {int(p["id"]): p.get("name") for p in base["provinces"]}
    rings = {
        pid: [(float(p[0]), float(p[1])) for p in g["points"]]
        for pid, g in by_id.items()
        if len(g.get("points") or []) >= 3
    }
    anchors = {pid: [float(g["label_anchor"][0]), float(g["label_anchor"][1])] for pid, g in by_id.items()}
    metas = {pid: dict(g.get("meta") or {}) for pid, g in by_id.items()}
    changed: Dict[int, str] = {}

    ontario = ontario_ne_ring()
    rings[LAKE_ONTARIO_ID] = ontario
    anchors[LAKE_ONTARIO_ID] = _centroid_or_interior(ontario)
    meta = metas[LAKE_ONTARIO_ID]
    meta["great_lakes_feed"] = "v2_ne_10m_lakes"
    meta["gis_ne_source"] = "ne_10m_lakes"
    meta["gis_ne_domain"] = "water"
    meta["gis_points_after"] = len(ontario)
    meta["eng_map_finish2"] = "ne_lake_ontario"
    changed[LAKE_ONTARIO_ID] = "rering NE Lake Ontario"

    erie = rings[LAKE_ERIE_ID]
    land_ids = overlapping_land_ids(rings, domains, ontario, extra_ids=(NY_WEST_ID,))
    clipped = []
    for pid in land_ids:
        waters = [ontario]
        if pid == NY_WEST_ID:
            waters.append(erie)
        was = ring_is_raw_invalid(rings[pid])
        loops = clip_land_off_water(rings[pid], waters)
        if not loops:
            raise RuntimeError("clip removed land %s %s" % (pid, names.get(pid)))
        kept = choose_keep_loop(loops, rings[pid], anchors[pid])
        if ring_is_raw_invalid(kept) and not was:
            raise RuntimeError("clip made %s self-crossing" % pid)
        if abs(_area(kept)) < KEEP_LOOP_MIN:
            raise RuntimeError("clip left %s too small" % pid)
        rings[pid] = kept
        if not _anchor_inside(kept, anchors[pid]):
            anchors[pid] = _centroid_or_interior(kept)
        metas[pid]["eng_map_finish2_clip"] = "minus_ontario" + ("_erie" if pid == NY_WEST_ID else "")
        changed[pid] = "clip off water"
        clipped.append(pid)

    dc_report = measure_washington_faces(board)
    dc_absorbed = []
    for hole in dc_report["faces_over_min"]:
        target = choose_washington_target(hole)
        if target is None:
            raise RuntimeError("no land target for DC face %.2f" % hole["area_px2"])
        absorb_hole_into(rings, anchors, target, hole["ring"])
        metas[target]["eng_map_finish2_absorb"] = "dc_face_%.1f" % hole["area_px2"]
        changed[target] = "absorb DC %.1f px²" % hole["area_px2"]
        dc_absorbed.append({"area_px2": hole["area_px2"], "target": target, "lon": hole["lon"], "lat": hole["lat"]})

    # Canada specks after the lake clip: measure on a temporary geometry copy.
    tmp = board
    speck_absorbed = []
    # Measure uses files. Caller apply writes after this plan only if we measure
    # against in-memory rings by temporarily swapping points in a shallow copy
    # of the board files is too heavy. Apply measures after writing Ontario+clips.
    return {
        "rings": rings,
        "anchors": anchors,
        "metas": metas,
        "changed": changed,
        "clipped": clipped,
        "dc_absorbed": dc_absorbed,
        "speck_absorbed": speck_absorbed,
        "by_id": by_id,
        "geo": geo,
        "names": names,
        "domains": domains,
        "dc_report": dc_report,
        "tmp": tmp,
    }
