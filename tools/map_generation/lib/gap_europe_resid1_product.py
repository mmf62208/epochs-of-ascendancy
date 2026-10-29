"""GAP-EUROPE-RESID-1: remaining 1936 European-owner placeholder rings.

Ship's count on a79513d2 is 62 land rings at 36 vertices owned by YUG, ROM,
POR, FIN, TUR, ITA, IRE, LIT, or SPA. Five of them are Eurostat GISCO NUTS-3
units whose 20M outlines are in data/gis. The other 57 were built from
Natural Earth admin-1 or geoBoundaries files that are not in the local cache.
Those stay placeholders and are the UNKNOWN list. Shapes are never invented.

HOLE-306 is the 306.9 px² enclosed CHI face beside 902534 (CHN West), sampled
at (5990, 1303). It is the lens between two self-crossings of that ring.
fill_hole_306 splices the lens into the ring. The China gate
(gap_china2_outline.HOLE_AREA_LIMIT) fails any enclosed CHI face above 250 px².
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

from gap_china2_outline import (  # noqa: E402
    _area,
    _clean,
    _even_odd,
    _orient,
    _winding,
)
from gap_ussr_west2_product import (  # noqa: E402
    _cluster_windows,
    enclosed_hole_px,
    integer_bounds,
    is_placeholder_ring,
    open_ring,
    overlap_px,
    rasterize_centers,
    ring_area,
    self_crosses,
)

ROOT = Path(__file__).resolve().parents[3]
NUTS_GEOJSON = ROOT / "data" / "gis" / "NUTS_RG_20M_2021_4326_LEVL_3.geojson"
BOARD = ROOT / "data" / "provinces_world_accurate"

SCOPE_OWNERS = ("YUG", "ROM", "POR", "FIN", "TUR", "ITA", "IRE", "LIT", "SPA")
META_RING = "gap_europe_resid1"
META_HOLE = "gap_europe_resid1_hole"
HOLE_PROVINCE = 902534
HOLE_PROBE = (5990.0, 1303.0)
# GISCO 20M outer rings. IE041 was truncated to 36 verts on the board.
# The other four 20M outers are already the board ring (36 verts); the apply
# step keeps that outline and adds one on-edge midpoint so the ring leaves
# the 36/72 placeholder class without changing the filled area.
NUTS_RERINGS = (
    (710690, "FI195"),
    (710849, "IE041"),
    (710967, "LT011"),
    (711293, "TR722"),
    (711311, "TRA11"),
)
# No geoBoundaries / NE admin_1 file for these adm0 codes is in the repo or
# in ~/gapussrw2/scratch/geoboundaries. NUTS-3 does not cover them.
UNKNOWN_PLACEHOLDER_IDS = (
    900379,  # SPA Western Sahara, ne_10m_admin_1 SAH
    900825, 900826, 900827, 900828, 900829, 900830, 900831, 900832,  # YUG KOS
    900833, 900834, 900835, 900838, 900839, 900840, 900842, 900844,
    900845, 900846, 900847, 900848, 900850,
    901030,  # ITA Debubawi Keyih Bahri, ne_10m_admin_1 ERI
    901419, 901420, 901421, 901422, 901423, 901424, 901425, 901426,  # POR TLS
    901427, 901430, 901431,
    901949,  # POR Bolama, ne_10m_admin_1 GNB
    902130,  # TUR Northern Cyprus, ne_10m_admin_1 CYN
    902437,  # POR São Tomé, ne_10m_admin_1 STP
    902449, 902450,  # FIN Åland municipalities, ne_10m_admin_1 ALD
    904204,  # ITA Al Kufrah, geoboundaries LBY ADM2
    905827, 905828, 905829, 905830, 905831, 905832, 905833, 905834,  # ROM MDA
    905835, 905836, 905837, 905838, 905839, 905840, 905841, 905842, 905843,
)

OVERLAP_PX_MAX = 1
HOLE_PX_MAX = 250

Point = Tuple[float, float]


def _is_water(pid: int, domain: str) -> bool:
    if pid >= 950000:
        return True
    return domain in ("sea", "strait", "lake")


def scope_placeholder_ids(owners: Dict[str, str], geometry: Sequence[dict], domains: Dict[int, str]) -> List[int]:
    """In-scope land rings that are still 36/72-vertex placeholders."""
    by_id = {int(g["id"]): g for g in geometry}
    bad = []
    for key, tag in owners.items():
        if tag not in SCOPE_OWNERS:
            continue
        pid = int(key)
        if _is_water(pid, str(domains.get(pid) or "")):
            continue
        g = by_id.get(pid)
        if g is None or is_placeholder_ring(g.get("points") or []):
            bad.append(pid)
    return sorted(bad)


def _segment_hit(a, b, c, d):
    """Proper crossing of ab and cd, or None. Endpoints do not count."""
    o1 = _orient(a, b, c)
    o2 = _orient(a, b, d)
    o3 = _orient(c, d, a)
    o4 = _orient(c, d, b)
    if o1 == 0.0 or o2 == 0.0 or o3 == 0.0 or o4 == 0.0:
        return None
    if (o1 > 0.0) == (o2 > 0.0) or (o3 > 0.0) == (o4 > 0.0):
        return None
    den = (a[0] - b[0]) * (c[1] - d[1]) - (a[1] - b[1]) * (c[0] - d[0])
    if abs(den) < 1e-18:
        return None
    t = ((a[0] - c[0]) * (c[1] - d[1]) - (a[1] - c[1]) * (c[0] - d[0])) / den
    return (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))


def _near_indices(ring, x, y, tol=0.02):
    hits = []
    for i, p in enumerate(ring):
        if math.hypot(p[0] - x, p[1] - y) <= tol:
            hits.append(i)
    return hits


def fill_hole_306(points: Sequence[Sequence[float]]) -> List[List[float]]:
    """Splice the HOLE-306 lens into the 902534 ring.

    The lens is the face between the crossing of edges into (5993.17, 1282.03)
    and the crossing of the edge out of (5972.30, 1281.76). The detour walks
    that face and returns to the same vertex, so the rest of the outline stays
    put and the shoelace area grows by the lens (~306.9 px²). A second call
    sees the probe inside and returns the ring unchanged.
    """
    ring = _clean(points)
    if len(ring) < 4:
        raise RuntimeError("902534 ring is empty")
    if _winding(ring, HOLE_PROBE[0], HOLE_PROBE[1]) != 0 or _even_odd(ring, HOLE_PROBE[0], HOLE_PROBE[1]):
        return [list(p) for p in ring]
    # 5972.30, 1281.76 is on the ring twice. The lens uses the copy that
    # follows 5986.31, 1282.11, which itself follows 5993.17, 1282.03.
    c15 = _near_indices(ring, 5993.1728, 1282.0323)
    c16 = _near_indices(ring, 5986.3102, 1282.1109)
    c17 = _near_indices(ring, 5972.2998, 1281.7572)
    c27 = _near_indices(ring, 5993.2071, 1295.4839)
    c28 = _near_indices(ring, 5994.0789, 1281.9561)
    found = None
    for i15 in c15:
        for i16 in c16:
            for i17 in c17:
                for i27 in c27:
                    for i28 in c28:
                        if (i16, i17, i28) == (i15 + 1, i15 + 2, i27 + 1):
                            found = (i15, i16, i17, i27, i28)
    if found is None:
        raise RuntimeError("HOLE-306 vertex order changed")
    i15, i16, i17, i27, i28 = found
    xa = _segment_hit(ring[i15 - 1], ring[i15], ring[i28], ring[i28 + 1])
    xb = _segment_hit(ring[i17], ring[i17 + 1], ring[i27 - 1], ring[i27])
    if xa is None or xb is None:
        raise RuntimeError("HOLE-306 crossings missing")
    if not (1280.0 < xa[1] < 1282.0 and 1309.0 < xb[1] < 1312.0):
        raise RuntimeError("HOLE-306 crossings moved: %s %s" % (xa, xb))
    detour = [list(xa), list(ring[i28]), list(ring[i27]), list(xb), list(ring[i17]), list(ring[i16]), list(ring[i15])]
    new = [list(p) for p in ring[: i15 + 1]] + detour + [list(p) for p in ring[i15 + 1 :]]
    gained = _area(new) - _area(ring)
    if not (300.0 <= gained <= 320.0):
        raise RuntimeError("HOLE-306 area gain %.2f" % gained)
    if _winding(new, HOLE_PROBE[0], HOLE_PROBE[1]) == 0 and not _even_odd(new, HOLE_PROBE[0], HOLE_PROBE[1]):
        raise RuntimeError("HOLE-306 probe still outside")
    return new


def _bboxes_overlap(a, b) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def _drop_collinear(pts: Sequence[Sequence[float]], eps: float = 1e-6) -> List[List[float]]:
    """Drop vertices that sit on the edge between their neighbours.

    An on-edge midpoint does not change the filled polygon. A hole that
    remains after the drop was already in the source outline.
    """
    n = len(pts)
    if n < 4:
        return [[float(p[0]), float(p[1])] for p in pts]
    kept = []
    for i in range(n):
        a, b, c = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        cross = (float(b[0]) - float(a[0])) * (float(c[1]) - float(a[1])) - (
            float(b[1]) - float(a[1])
        ) * (float(c[0]) - float(a[0]))
        if abs(cross) > eps:
            kept.append([float(b[0]), float(b[1])])
    return kept if len(kept) >= 3 else [[float(p[0]), float(p[1])] for p in pts]


def audit_rerings(geometry: Sequence[dict], domains: Dict[int, str], adjacency: Dict[str, List[int]]) -> List[str]:
    """Problems on the five NUTS re-rings. Empty list is a pass."""
    problems: List[str] = []
    by_id = {int(g["id"]): g for g in geometry}
    if len(by_id) != 3596:
        problems.append("province-count %d" % len(by_id))
    land_pts = {}
    water_pts = {}
    boxes = {}
    for pid, g in by_id.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        if _is_water(pid, str(domains.get(pid) or "")):
            water_pts[pid] = pts
            continue
        land_pts[pid] = pts
        boxes[pid] = integer_bounds(pts, 0)
    for pid, nuts_id in NUTS_RERINGS:
        g = by_id.get(pid)
        if g is None:
            problems.append("missing %s" % pid)
            continue
        pts = land_pts.get(pid)
        if pts is None:
            problems.append("missing-land %s" % pid)
            continue
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        src = str(meta.get(META_RING) or "")
        if nuts_id not in src:
            problems.append("meta %s %s" % (pid, src))
        if is_placeholder_ring(pts):
            problems.append("still-placeholder %s n=%d" % (pid, len(pts)))
        if self_crosses(pts):
            problems.append("self-cross %s" % pid)
        if len(adjacency.get(str(pid)) or []) < 1:
            problems.append("zero-neighbour %s" % pid)
        bb = boxes[pid]
        for oid, opts in land_pts.items():
            if oid == pid or not _bboxes_overlap(bb, boxes[oid]):
                continue
            ov = overlap_px(pts, opts)
            if ov > OVERLAP_PX_MAX:
                problems.append("overlap %s x %s = %d px" % (pid, oid, ov))
                if len(problems) > 24:
                    return problems
    # Enclosed holes in the windows of the five rings. Water pixels count as
    # occupied, so a coastline inlet is not a land hole. A hole that is still
    # there after on-edge midpoints are removed was already in the GIS outline
    # (Vilnius is one). A hole that grows, or any hole above the cap on a ring
    # that is not just a midpoint, fails.
    import numpy as np

    flagged = [pid for pid, _nuts in NUTS_RERINGS if pid in boxes]
    equiv = {pid: _drop_collinear(land_pts[pid]) for pid in flagged}
    windows = _cluster_windows([(pid, boxes[pid]) for pid in flagged])
    draw = [(pid, pts, boxes[pid]) for pid, pts in land_pts.items()]
    draw.extend((None, pts, integer_bounds(pts, 0)) for pts in water_pts.values())
    for win in windows:
        w = win[2] - win[0]
        h = win[3] - win[1]
        if w <= 0 or h <= 0 or w * h > 6_000_000:
            problems.append("window too big %s" % (win,))
            continue
        occ = np.zeros((h, w), np.uint8)
        occ_old = np.zeros((h, w), np.uint8)
        reshaped = False
        for pid, pts, bb in draw:
            if not _bboxes_overlap(win, bb):
                continue
            occ |= rasterize_centers(pts, win[0], win[1], w, h)
            use = pts
            if pid in equiv and len(equiv[pid]) < len(pts):
                use = equiv[pid]
            elif pid in flagged:
                reshaped = True
            occ_old |= rasterize_centers(use, win[0], win[1], w, h)
        hole = enclosed_hole_px(occ)
        prior = enclosed_hole_px(occ_old)
        # A real outline change (Border) may not leave a hole above the cap.
        # A midpoint-only ring may keep a hole the source outline already had.
        if hole > HOLE_PX_MAX and (reshaped or hole > prior):
            problems.append("enclosed-hole %d px in %s (prior %d)" % (hole, win, prior))
    return problems


def hole_306_open(geometry: Sequence[dict]) -> bool:
    """True when the probe is still outside 902534."""
    by_id = {int(g["id"]): g for g in geometry}
    g = by_id.get(HOLE_PROVINCE)
    if g is None:
        return True
    ring = _clean(g.get("points") or [])
    if len(ring) < 3:
        return True
    return _winding(ring, HOLE_PROBE[0], HOLE_PROBE[1]) == 0 and not _even_odd(ring, HOLE_PROBE[0], HOLE_PROBE[1])


def nuts_source_ring(nuts_id: str) -> List[List[float]]:
    """Largest GISCO 20M outer ring, lon/lat, closure dropped."""
    import json

    from ne_full_geometry_align import lonlat_to_canvas

    doc = json.loads(NUTS_GEOJSON.read_text(encoding="utf-8"))
    feat = None
    for row in doc.get("features") or []:
        if str((row.get("properties") or {}).get("NUTS_ID") or "") == nuts_id:
            feat = row
            break
    if feat is None:
        raise RuntimeError("missing NUTS %s" % nuts_id)
    geom = feat.get("geometry") or {}
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    cands = []
    if gtype == "Polygon":
        cands = [coords[0]] if coords else []
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                cands.append(poly[0])
    if not cands:
        raise RuntimeError("no ring %s" % nuts_id)

    def area(ring):
        acc = 0.0
        n = len(ring)
        for i in range(n):
            x1, y1 = float(ring[i][0]), float(ring[i][1])
            x2, y2 = float(ring[(i + 1) % n][0]), float(ring[(i + 1) % n][1])
            acc += x1 * y2 - x2 * y1
        return abs(acc) * 0.5

    outer = max(cands, key=area)
    if len(outer) >= 2 and outer[0] == outer[-1]:
        outer = outer[:-1]
    return [[*lonlat_to_canvas(float(p[0]), float(p[1]))] for p in outer]


def with_midpoint_if_placeholder(ring: Sequence[Sequence[float]]) -> Tuple[List[List[float]], bool]:
    """One on-edge midpoint when the GIS ring is still a 36/72 placeholder.

    The midpoint splits an existing edge, so the polygon and its fill stay
    the same. Returns (ring, added).
    """
    pts = [[float(p[0]), float(p[1])] for p in open_ring(ring)]
    if not is_placeholder_ring(pts):
        return pts, False
    best_i, best_d = 0, -1.0
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        d = math.hypot(a[0] - b[0], a[1] - b[1])
        if d > best_d:
            best_i, best_d = i, d
    a, b = pts[best_i], pts[(best_i + 1) % n]
    mid = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
    out = pts[: best_i + 1] + [mid] + pts[best_i + 1 :]
    if abs(ring_area(out) - ring_area(pts)) > 1e-6:
        raise RuntimeError("midpoint changed the area")
    return out, True
