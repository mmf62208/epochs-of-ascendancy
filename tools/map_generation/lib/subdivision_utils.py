"""
Subdivision Utilities
=====================

Contains the actual logic for deciding *how* and *where* to split provinces
during the map generation process.

This module is deliberately naval-aware. It uses output from `naval_analysis`
to make smarter decisions about which provinces should be split more aggressively
and which should be protected (especially straits and key coastal areas).
"""

from typing import Dict, List, Tuple, Set
from . import naval_analysis
import json
from pathlib import Path


# =============================================================================
# CONFIGURATION (will move to YAML later)
# =============================================================================

# NOTE: Current seed geometry (provinces_geometry.json) uses very coarse ~6-point polygons.
# We deliberately lower the threshold so the pipeline can demonstrate real subdivision
# on the playable starter map. When we ingest higher-resolution source data this can rise.
MIN_POINTS_FOR_SPLIT = 5
MAX_SPLITS_PER_PROVINCE = 6

# Scoring weights
NAVAL_IMPORTANCE_WEIGHT = 2.8
SIZE_WEIGHT = 1.0
COASTAL_BONUS = 1.1
STRAIT_PROTECTION_PENALTY = 0.55   # Strongly discourage splitting strait provinces
# For full 350-450 Europe target (from ~100 seed), make subdivision more aggressive
SUBDIVISION_SCORE_THRESHOLD = 0.70  # Lowered from 0.95 for denser Phase1 Europe playtest map
AGGRESSIVE_SPLIT_BONUS = 1.5  # Extra push for non-protected to hit target density

# Real layers awareness (new for natural borders from NASA/Natural Earth rivers + elev)
RIVER_CROSS_BONUS = 1.8  # Provinces crossed by major real rivers (from build rivers.json) get priority split so rivers become natural boundaries
HIGH_ELEV_SPLIT_BONUS = 1.2  # High elev areas (from snow/elev layers) prefer more splits for mountain provinces
RIVER_MAJOR_THRESHOLD = 3  # number of points in river poly to count as "major" for crossing

# =============================================================================
# REAL DATA LAYERS HELPERS (rivers + elev for natural borders)
# =============================================================================

def load_real_rivers(rivers_json_path: str = None) -> List[List[List[float]]]:
    """Load the real rivers polylines from the map build (data/map/rivers.json or rivers_world.json).
    Returns list of polylines (each a list of [x,y] in canvas pixels).
    """
    if rivers_json_path is None:
        base = Path(__file__).resolve().parent.parent.parent.parent / "data" / "map"
        rivers_json_path = str(base / "rivers.json")
        if not Path(rivers_json_path).exists():
            rivers_json_path = str(base / "rivers_world.json")
    if not Path(rivers_json_path).exists():
        return []
    try:
        with open(rivers_json_path) as f:
            data = json.load(f)
        rivers = data.get("rivers", [])
        polylines = []
        for r in rivers:
            pts = r.get("points", [])
            if len(pts) >= RIVER_MAJOR_THRESHOLD:
                polylines.append(pts)
        return polylines
    except Exception:
        return []

def river_crosses_province(river_poly: List[List[float]], prov_points: List[List[float]]) -> bool:
    """Simple check if a river polyline crosses or touches the interior of the province poly (coarse bbox + segment test).
    Pure python, no deps.
    """
    if not river_poly or not prov_points or len(prov_points) < 3:
        return False
    # Bbox quick reject
    minx = min(p[0] for p in prov_points)
    maxx = max(p[0] for p in prov_points)
    miny = min(p[1] for p in prov_points)
    maxy = max(p[1] for p in prov_points)
    rminx = min(p[0] for p in river_poly)
    rmaxx = max(p[0] for p in river_poly)
    rminy = min(p[1] for p in river_poly)
    rmaxy = max(p[1] for p in river_poly)
    if rmaxx < minx or rminx > maxx or rmaxy < miny or rminy > maxy:
        return False
    # Sample a few segments of river vs province edges (coarse but effective for major rivers)
    for i in range(len(river_poly)-1):
        ra, rb = river_poly[i], river_poly[i+1]
        for j in range(len(prov_points)):
            pa = prov_points[j]
            pb = prov_points[(j+1) % len(prov_points)]
            # Simple segment bbox overlap as proxy for cross (good enough for guidance)
            if max(ra[0], rb[0]) >= min(pa[0], pb[0]) and min(ra[0], rb[0]) <= max(pa[0], pb[0]) and \
               max(ra[1], rb[1]) >= min(pa[1], pb[1]) and min(ra[1], rb[1]) <= max(pa[1], pb[1]):
                return True
    return False

def compute_river_cross_score(province_id: int, geometry: Dict, real_rivers: List[List[List[float]]]) -> float:
    """Return bonus [0..RIVER_CROSS_BONUS] if this province is crossed by one or more major real rivers.
    Encourages splitting so the river becomes the new border between children.
    """
    prov = next((p for p in geometry.get("provinces", []) if p.get("id") == province_id), None)
    if not prov or not real_rivers:
        return 0.0
    pts = prov.get("points", [])
    crossings = sum(1 for rv in real_rivers if river_crosses_province(rv, pts))
    return min(RIVER_CROSS_BONUS, crossings * 0.9)

# =============================================================================
# CORE DECISION FUNCTIONS
# =============================================================================

def should_split_province(
    province_id: int,
    geometry: Dict,
    naval_data: Dict,
    avg_point_count: float,
    real_rivers: List[List[List[float]]] = None
) -> bool:
    """
    Returns whether this province is a good candidate for subdivision.
    Relaxed thresholds for the current coarse 6-point seed geometry.
    Now also respects real rivers (from layers build) as natural boundaries: provinces crossed by major rivers get boosted split priority.
    """
    prov = next((p for p in geometry.get("provinces", []) if p.get("id") == province_id), None)
    if not prov:
        return False

    points = len(prov.get("points", []))
    if points < MIN_POINTS_FOR_SPLIT:
        return False

    naval_score = naval_data.get("naval_importance_scores", {}).get(province_id, 0.0)

    # Basic size pressure (with low point counts we mostly rely on naval + coastal)
    size_pressure = max(0.6, points / max(avg_point_count, 1))

    # Naval pressure (high naval importance provinces benefit from being split more)
    naval_pressure = 1.0 + (naval_score * NAVAL_IMPORTANCE_WEIGHT)

    # Final decision score
    score = size_pressure * naval_pressure

    # Hard protection for very high-value strait provinces (use real IDs when available)
    for key, data in naval_data.get("protected_straits", {}).items():
        if province_id in (data.get("province_a", -1), data.get("province_b", -1)):
            if points < 12:   # With coarse data, almost never split protected straits
                return False

    # Real rivers awareness (drive natural borders): boost score for river-crossed provinces so splits respect rivers as boundaries
    if real_rivers:
        river_bonus = compute_river_cross_score(province_id, geometry, real_rivers)
        score += river_bonus

    # Much more permissive threshold for the starter map
    # Use aggressive threshold + bonus for full 350-450 target density
    score = score * (1.0 + AGGRESSIVE_SPLIT_BONUS * 0.1)  # slight boost
    return score > SUBDIVISION_SCORE_THRESHOLD


def suggest_number_of_splits(
    province_id: int,
    geometry: Dict,
    naval_data: Dict,
    real_rivers: List[List[List[float]]] = None
) -> int:
    """
    Given that we want to split this province, how many pieces should we aim for?
    Tuned for coarse 6-point starter geometry (most provinces get 2-3 children).
    Now river-aware: river-crossed get +1 splits so rivers define children borders.
    """
    prov = next((p for p in geometry.get("provinces", []) if p.get("id") == province_id), None)
    if not prov:
        return 2

    points = len(prov.get("points", []))
    naval_score = naval_data.get("naval_importance_scores", {}).get(province_id, 0.0)

    # With 6-pt input we rarely want >3 children per parent in Phase 1
    # Aggressive for 350-450 full Europe playtest territories (avg ~4x from seed)
    base = 3
    if points >= 6:
        base = 4
    if points >= 10:
        base = 5

    # Give coastal and high-naval provinces push toward higher for dense Europe theater
    if naval_score > 0.5 or province_id in naval_data.get("coastal_provinces", []):
        base = min(MAX_SPLITS_PER_PROVINCE, base + 1)

    # Be conservative with protected straits
    for key, data in naval_data.get("protected_straits", {}).items():
        if province_id in (data.get("province_a", -1), data.get("province_b", -1)):
            base = min(2, base)
            break

    # Drive real rivers: + splits for crossed so river lines become the new province borders (natural)
    if real_rivers:
        river_cross = compute_river_cross_score(province_id, geometry, real_rivers)
        if river_cross > 0.5:
            base = min(MAX_SPLITS_PER_PROVINCE, base + 1)

    return max(2, min(MAX_SPLITS_PER_PROVINCE, base))


# =============================================================================
# RANKING & PRIORITIZATION
# =============================================================================

def rank_provinces_for_subdivision(
    province_ids: List[int],
    geometry: Dict,
    naval_data: Dict,
    real_rivers: List[List[List[float]]] = None
) -> List[Tuple[int, float]]:
    """
    Returns a sorted list of (province_id, priority) for subdivision.
    Higher score = split this one earlier / more aggressively.

    Strongly favors:
    - Large provinces
    - High naval importance provinces
    - Coastal provinces
    - While protecting major straits
    - NEW: provinces crossed by real rivers from layers (rivers become natural borders between children)
    """
    ranked = []
    avg_points = sum(len(p.get("points", [])) for p in geometry.get("provinces", [])) / max(len(geometry.get("provinces", [])), 1)

    for pid in province_ids:
        if not should_split_province(pid, geometry, naval_data, avg_points, real_rivers):
            continue

        prov = next((p for p in geometry.get("provinces", []) if p.get("id") == pid), None)
        points = len(prov.get("points", [])) if prov else 0
        naval_score = naval_data.get("naval_importance_scores", {}).get(pid, 0.0)

        size_score = points / max(avg_points, 1)
        naval_bonus = naval_score * NAVAL_IMPORTANCE_WEIGHT

        # Coastal bonus
        coastal_bonus = COASTAL_BONUS if pid in naval_data.get("coastal_provinces", []) else 0.0

        # Penalty for protected straits
        strait_penalty = 1.0
        for key, data in naval_data.get("protected_straits", {}).items():
            if pid in (data.get("province_a", -1), data.get("province_b", -1)):
                strait_penalty = STRAIT_PROTECTION_PENALTY
                break

        final_score = (size_score + naval_bonus + coastal_bonus) * strait_penalty

        # Real rivers bonus (drive hard on natural borders from build data)
        if real_rivers:
            river_bonus = compute_river_cross_score(pid, geometry, real_rivers)
            final_score += river_bonus

        ranked.append((pid, round(final_score, 3)))

    # Fallback relaxation for early development
    if len(ranked) < 8:
        for pid in province_ids:
            if pid in [r[0] for r in ranked]:
                continue
            naval_score = naval_data.get("naval_importance_scores", {}).get(pid, 0.0)
            is_coastal = pid in naval_data.get("coastal_provinces", [])
            if naval_score > 0.7 or is_coastal:
                prov = next((p for p in geometry.get("provinces", []) if p.get("id") == pid), None)
                points = len(prov.get("points", [])) if prov else 0
                size_score = points / max(avg_points, 1)
                relaxed = (size_score + naval_score * 1.5) * 1.3
                ranked.append((pid, round(relaxed, 3)))

    ranked.sort(key=lambda x: x[1], reverse=True)
    return ranked


# =============================================================================
# ACTUAL GEOMETRIC SUBDIVISION (Improved Implementation)
# =============================================================================

import random
import math
from typing import List, Dict, Tuple


def _get_province_points(province_id: int, geometry: Dict) -> List[List[float]]:
    """Helper to get the polygon points for a province."""
    for p in geometry.get("provinces", []):
        if p.get("id") == province_id:
            return p.get("points", [])
    return []


def _centroid(points: List[List[float]]) -> List[float]:
    """Simple centroid calculation."""
    if not points:
        return [0.0, 0.0]
    x = sum(p[0] for p in points) / len(points)
    y = sum(p[1] for p in points) / len(points)
    return [x, y]


def _principal_axis_direction(points: List[List[float]]) -> Tuple[float, float]:
    """
    Compute the direction of the first principal component (major axis) of the point set.
    Returns a unit vector (dx, dy).
    Pure Python 2D covariance implementation (no numpy dependency).
    """
    if len(points) < 2:
        return 1.0, 0.0

    cx, cy = _centroid(points)
    n = len(points)
    cov_xx = sum((p[0] - cx) ** 2 for p in points) / n
    cov_yy = sum((p[1] - cy) ** 2 for p in points) / n
    cov_xy = sum((p[0] - cx) * (p[1] - cy) for p in points) / n

    if abs(cov_xy) < 1e-9:
        if cov_xx >= cov_yy:
            return 1.0, 0.0
        else:
            return 0.0, 1.0

    trace = cov_xx + cov_yy
    det = cov_xx * cov_yy - cov_xy * cov_xy
    # Largest eigenvalue
    disc = max(0.0, trace**2 - 4 * det)
    lambda1 = (trace + math.sqrt(disc)) / 2.0

    dx = cov_xy
    dy = lambda1 - cov_xx
    length = math.hypot(dx, dy)
    if length < 1e-9:
        return 1.0, 0.0
    return dx / length, dy / length


def _polygon_area(points: List[List[float]]) -> float:
    """Shoelace formula area (assumes simple polygon, winding agnostic)."""
    if len(points) < 3:
        return 0.0
    area = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return abs(area) * 0.5


def _is_valid_polygon(points: List[List[float]], min_points: int = 3) -> bool:
    if len(points) < min_points:
        return False
    # Check not all points identical
    if all(p[0] == points[0][0] and p[1] == points[0][1] for p in points):
        return False
    return _polygon_area(points) > 1e-4


def _interpolate(a: List[float], b: List[float], t: float) -> List[float]:
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]


def _densify_boundary(points: List[List[float]], target_points: int = 14, coastal_boost: bool = False) -> List[List[float]]:
    """
    Insert linearly interpolated points along edges so low-vertex polygons
    (the current 6-point seed provinces) can be split into sensible children.
    Returns a new list with approximately target_points or more.

    When coastal_boost=True (high naval importance provinces), we put extra
    density on the longest edges. These are usually the most valuable coastal
    frontage that we want to preserve across children.
    """
    if len(points) >= target_points:
        return list(points)

    n = len(points)
    edge_lengths = []
    total_len = 0.0
    for i in range(n):
        a = points[i]
        b = points[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        edge_lengths.append(length)
        total_len += length

    if total_len < 1e-6:
        return list(points)

    extras_needed = max(0, target_points - n)
    if extras_needed == 0:
        return list(points)

    result = []
    for i in range(n):
        result.append(list(points[i]))
        length = edge_lengths[i]
        if length < 1e-6:
            continue

        # Base inserts proportional to length
        inserts = max(1, int(round(extras_needed * (length / total_len))))

        # Coastal boost: give even more points to the longest edges
        # (these are the valuable outer/coastal frontage we want to keep intact)
        if coastal_boost and length > (total_len / n) * 1.3:
            inserts += 1

        inserts = min(inserts, extras_needed)
        extras_needed -= inserts

        for j in range(1, inserts + 1):
            t = j / float(inserts + 1)
            result.append(_interpolate(points[i], points[(i + 1) % n], t))

    # Fill remaining points on longest edges (standard behavior)
    while len(result) < target_points and len(result) < n * 3:
        best_i, best_len = 0, 0.0
        m = len(result)
        for i in range(m):
            a = result[i]
            b = result[(i + 1) % m]
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            if ln > best_len:
                best_len = ln
                best_i = i
        if best_len < 1e-6:
            break
        mid = _interpolate(result[best_i], result[(best_i + 1) % m], 0.5)
        result.insert((best_i + 1) % m, mid)

    return result


def _convex_hull(points: List[List[float]]) -> List[List[float]]:
    """
    Graham scan convex hull. Returns the convex hull of the given points.
    """
    if len(points) <= 3:
        return list(points)

    p0 = min(points, key=lambda p: (p[1], p[0]))

    def polar_angle(p):
        return math.atan2(p[1] - p0[1], p[0] - p0[0])

    sorted_points = sorted(points, key=polar_angle)

    hull = []
    for p in sorted_points:
        while len(hull) >= 2 and _cross(hull[-2], hull[-1], p) <= 0:
            hull.pop()
        hull.append(p)
    return hull


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _pca_split(points: List[List[float]], k: int, coastal_boost: bool = False, real_rivers: List[List[List[float]]] = None) -> List[List[List[float]]]:
    """
    PCA-guided split: cut perpendicular to the major axis of the province.
    Excellent for elongated or irregular provinces (common in real geography).
    Falls back gracefully for near-circular shapes.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    dense = _densify_boundary(points, target_points=max(14, len(points) * 2), coastal_boost=coastal_boost)
    center = _centroid(dense)

    dx, dy = _principal_axis_direction(dense)
    # Perpendicular direction for the cut line
    px, py = -dy, dx

    # Real rivers drive: if this province is crossed by major river(s), align one cut axis to a river direction
    # so the river polyline becomes (part of) the new border between children. Natural borders from data!
    if real_rivers:
        for rv in real_rivers[:3]:  # few major
            if len(rv) >= 2 and river_crosses_province(rv, dense):
                # river direction as preferred cut axis (parallel to river for boundary)
                r0, r1 = rv[0], rv[-1]
                rdx = r1[0] - r0[0]
                rdy = r1[1] - r0[1]
                rlen = math.hypot(rdx, rdy) or 1.0
                rdx /= rlen; rdy /= rlen
                # blend or override to river-parallel for natural split
                px, py = rdx, rdy
                break  # use first crossing major river for guidance

    # Project all points onto the perpendicular axis
    projs = []
    for p in dense:
        vec_x = p[0] - center[0]
        vec_y = p[1] - center[1]
        proj = vec_x * px + vec_y * py
        projs.append((proj, p))

    projs.sort(key=lambda x: x[0])

    if len(projs) < k * 2:
        return _radial_split(points, k)  # fallback

    # Evenly divide the sorted projections
    n = len(projs)
    slice_size = n // k
    children = []

    for i in range(k):
        start = i * slice_size
        end = (i + 1) * slice_size if i < k - 1 else n
        arc = [p for _, p in projs[start:end]]
        if len(arc) >= 2:
            # Close with center for a clean polygon
            children.append(arc + [center])

    return children if len(children) >= 2 else [list(points)]


def _radial_split(points: List[List[float]], k: int, extra_densify: int = 0, coastal_boost: bool = False, real_rivers: List[List[List[float]]] = None) -> List[List[List[float]]]:
    """
    Improved radial subdivision:
    - Densifies low-vertex input first
    - Each child owns a contiguous arc of the (densified) perimeter
    - Children are formed as [arc_points..., centroid]
    This gives far better shape fidelity than the original fan-on-6-pts version.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    base_target = max(14, len(points) * 2) + extra_densify
    # Densify so we have enough vertices to distribute fairly
    dense = _densify_boundary(points, target_points=base_target, coastal_boost=coastal_boost)

    center = _centroid(dense)

    # Sort by angle around center (stable for our convexish provinces)
    def angle(p):
        return math.atan2(p[1] - center[1], p[0] - center[0])

    sorted_pts = sorted(dense, key=angle)

    n = len(sorted_pts)
    if n < k * 2:
        # Still too few after densify — fall back to simple even slicing on original
        sorted_pts = sorted(points, key=angle)
        n = len(sorted_pts)

    # Real rivers: bias rotation so one radial cut / boundary aligns with river dir
    # (makes the river polyline form a natural edge between two children)
    if real_rivers:
        river_cut_angle = None
        for rv in real_rivers[:3]:
            if len(rv) >= 2 and river_crosses_province(rv, dense):
                r0, r1 = rv[0], rv[-1]
                rdx = r1[0] - r0[0]
                rdy = r1[1] - r0[1]
                river_cut_angle = math.atan2(rdy, rdx)
                break
        if river_cut_angle is not None:
            def ang_diff(a):
                d = abs(a - river_cut_angle) % (2 * math.pi)
                return min(d, 2 * math.pi - d)
            best_i = 0
            best_d = 1e9
            for ii in range(n):
                aa = angle(sorted_pts[ii])
                dd = ang_diff(aa)
                if dd < best_d:
                    best_d = dd
                    best_i = ii
            if best_i > 0:
                sorted_pts = sorted_pts[best_i:] + sorted_pts[:best_i]

    slice_size = max(2, n // k)
    child_polygons: List[List[List[float]]] = []

    for i in range(k):
        start = i * slice_size
        end = (i + 1) * slice_size if i < k - 1 else n
        arc = sorted_pts[start:end]

        if len(arc) < 2:
            continue

        # Build child: the perimeter arc + the interior centroid
        # This creates a coherent "slice" that owns real outer boundary
        poly = arc + [center]
        if _is_valid_polygon(poly):
            child_polygons.append(poly)

    if len(child_polygons) >= max(2, k // 2):
        return child_polygons

    # Fallback
    return _bisect_polygon(points, k)


def _bisect_polygon(points: List[List[float]], k: int, extra_densify: int = 0, coastal_boost: bool = False, real_rivers: List[List[List[float]]] = None) -> List[List[List[float]]]:
    """
    Improved bisection with area-balanced cut selection.
    Evaluates several candidate cut locations on the densified ring and picks
    the one that produces the most balanced child areas (plus basic perimeter fairness).
    This produces significantly better-looking splits than fixed 1/3 cuts,
    especially on irregular or elongated provinces.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    base_target = max(12, len(points) * 2) + extra_densify
    dense = _densify_boundary(points, target_points=base_target, coastal_boost=coastal_boost)
    n = len(dense)
    if n < 6:
        dense = _densify_boundary(points, target_points=16)
        n = len(dense)

    # Real rivers bias for bisect: compute river dir to prefer aligned cuts (river as natural shared edge)
    river_cut_angle = None
    if real_rivers:
        for rv in real_rivers[:3]:
            if len(rv) >= 2 and river_crosses_province(rv, dense):
                r0, r1 = rv[0], rv[-1]
                river_cut_angle = math.atan2(r1[1]-r0[1], r1[0]-r0[0])
                break

    pieces: List[List[List[float]]] = [dense]
    parent_area = _polygon_area(dense)

    while len(pieces) < k:
        pieces.sort(key=lambda p: _polygon_area(p), reverse=True)
        parent = pieces.pop(0)
        if len(parent) < 6:
            pieces.append(parent)
            break

        m = len(parent)
        best_cuts = None
        best_score = 1e12

        # Evaluate a range of possible cut pairs for best area balance
        step = max(1, m // 12)
        for i in range(1, m - 2, step):
            for j in range(i + 2, m - 1, step):
                seg1 = parent[i:j+1]
                seg2 = parent[j:] + parent[:i+1]

                if len(seg1) < 3 or len(seg2) < 3:
                    continue

                c = _interpolate(parent[i], parent[j], 0.5)
                p1 = seg1 + [c]
                p2 = seg2 + [c]

                if not _is_valid_polygon(p1) or not _is_valid_polygon(p2):
                    continue

                a1 = _polygon_area(p1)
                a2 = _polygon_area(p2)
                if a1 + a2 < 1e-4:
                    continue

                # Score: area imbalance + slight penalty for very unbalanced perimeter
                imbalance = abs(a1 - a2) / max(a1 + a2, 1e-6)
                perim1 = len(p1)
                perim2 = len(p2)
                perim_imbalance = abs(perim1 - perim2) / max(perim1 + perim2, 1)
                score = imbalance * 1.0 + perim_imbalance * 0.3

                # Coastal preservation bonus: when we care about coastal frontage,
                # slightly prefer cuts that are more "radial" (cut points roughly opposite).
                # This helps keep long contiguous coastal arcs on single children.
                if coastal_boost:
                    # Rough measure of how "across" the cut is (good for preserving outer arcs)
                    cut_span = min(abs(i - j), m - abs(i - j))
                    radial_bonus = (cut_span / (m / 2.0)) * 0.25  # up to ~0.25 bonus
                    score -= radial_bonus

                if river_cut_angle is not None:
                    cut_dx = parent[j][0] - parent[i][0]
                    cut_dy = parent[j][1] - parent[i][1]
                    cang = math.atan2(cut_dy, cut_dx) if (cut_dx or cut_dy) else 0
                    dang = abs(cang - river_cut_angle) % (2 * math.pi)
                    dang = min(dang, 2 * math.pi - dang)
                    if dang < 0.8:
                        score *= 0.6  # prefer river-aligned cut for natural border

                if score < best_score:
                    best_score = score
                    best_cuts = (p1, p2)

        if best_cuts is None:
            # Fallback to simple cut
            cut1 = m // 3
            cut2 = (m * 2) // 3
            p1 = parent[cut1:cut2+1] + [_interpolate(parent[cut1], parent[cut2], 0.5)]
            p2 = parent[cut2:] + parent[:cut1+1] + [_interpolate(parent[cut1], parent[cut2], 0.5)]
            best_cuts = (p1, p2)

        p1, p2 = best_cuts
        if _is_valid_polygon(p1):
            pieces.append(p1)
        else:
            pieces.append(parent)
        if _is_valid_polygon(p2) and len(pieces) < k:
            pieces.append(p2)
        elif len(pieces) < k:
            pieces.append(parent)

    # Final cleanup
    cleaned = []
    ctr = _centroid(points)
    for p in pieces[:k]:
        if _is_valid_polygon(p):
            cleaned.append(p)
        else:
            cleaned.append(points[:3] + [ctr])

    return cleaned if len(cleaned) >= 2 else [list(points)]


def _simple_cluster_split(points: List[List[float]], k: int, extra_densify: int = 0, coastal_boost: bool = False, real_rivers: List[List[List[float]]] = None) -> List[List[List[float]]]:
    """
    Fallback clustering (used only if better methods fail).
    Works on densified points then snaps children to convex hull.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    base_target = max(12, len(points) * 2) + extra_densify
    dense = _densify_boundary(points, target_points=base_target, coastal_boost=coastal_boost)

    centroids = random.sample(dense, min(k, len(dense)))

    for _ in range(6):
        clusters: List[List[List[float]]] = [[] for _ in range(len(centroids))]
        for p in dense:
            distances = [((p[0] - c[0])**2 + (p[1] - c[1])**2) for c in centroids]
            idx = distances.index(min(distances))
            clusters[idx].append(p)

        new_centroids = []
        for cluster in clusters:
            if cluster:
                cx = sum(pp[0] for pp in cluster) / len(cluster)
                cy = sum(pp[1] for pp in cluster) / len(cluster)
                new_centroids.append([cx, cy])
            else:
                new_centroids.append(centroids[len(new_centroids)])
        centroids = new_centroids

    child_polygons = []
    for cluster in clusters:
        if len(cluster) >= 3:
            hull = _convex_hull(cluster)
            if len(hull) >= 3 and _is_valid_polygon(hull):
                child_polygons.append(hull)

    return child_polygons if len(child_polygons) >= 2 else [list(points)]


def generate_split_geometry(
    province_id: int,
    geometry: Dict,
    naval_data: Dict,
    num_pieces: int = 2,
    real_rivers: List[List[List[float]]] = None
) -> List[Dict]:
    """
    Proposes a subdivision of a province into N child provinces.

    2026-05-29 improvements (item 3):
    - Smarter area-balanced bisection with candidate cut evaluation
    - Naval / coastal awareness: high-importance provinces get more aggressive
      densification and a slight bias toward more even perimeter distribution
      (important for future port/special site placement on children).
    """
    original_points = _get_province_points(province_id, geometry)
    if not original_points or len(original_points) < 3:
        return []

    parent_area = _polygon_area(original_points)

    naval_score = naval_data.get("naval_importance_scores", {}).get(province_id, 0.0)
    is_coastal = province_id in naval_data.get("coastal_provinces", [])

    # For high naval value or coastal provinces, densify more aggressively
    # and apply coastal_boost so we put extra points on long outer edges
    # (valuable coastal frontage we want to preserve for children).
    extra_densify = 0
    coastal_boost = False
    if naval_score > 1.0 or is_coastal:
        extra_densify = 6
        coastal_boost = True

    # Primary path: PCA for elongated provinces (great for real geography), else radial
    aspect = 1.0
    dx, dy = _principal_axis_direction(original_points)
    # Rough elongation from bounding box in principal direction (simple heuristic)
    projs = []
    for p in original_points:
        cx, cy = _centroid(original_points)
        vx, vy = p[0] - cx, p[1] - cy
        projs.append(vx * dx + vy * dy)
    if projs:
        aspect = (max(projs) - min(projs)) / (max([abs(p[0]) for p in original_points] + [1]) or 1)

    if num_pieces == 2 and aspect > 1.6:
        child_polygons = _pca_split(original_points, num_pieces, coastal_boost=coastal_boost, real_rivers=real_rivers)
    else:
        child_polygons = _radial_split(original_points, num_pieces, extra_densify=extra_densify, coastal_boost=coastal_boost, real_rivers=real_rivers)

    # If we got too few or degenerate results, use the new smarter bisection
    valid_children = [p for p in child_polygons if _is_valid_polygon(p)]
    if len(valid_children) < max(2, num_pieces // 2):
        child_polygons = _bisect_polygon(original_points, num_pieces, extra_densify=extra_densify, coastal_boost=coastal_boost, real_rivers=real_rivers)
        valid_children = [p for p in child_polygons if _is_valid_polygon(p)]

    # Last resort
    if len(valid_children) < 2:
        child_polygons = _simple_cluster_split(original_points, num_pieces, extra_densify=extra_densify, coastal_boost=coastal_boost, real_rivers=real_rivers)
        valid_children = [p for p in child_polygons if _is_valid_polygon(p)]

    proposals = []
    for i, poly in enumerate(child_polygons):
        if not _is_valid_polygon(poly):
            continue
        area = _polygon_area(poly)
        notes = f"Densify + radial/bisect. Area {parent_area:.1f}→{area:.1f}."
        if naval_score > 1.0 or is_coastal:
            notes += " (naval-aware densify)"
        rc = 0.0
        if real_rivers:
            rc = compute_river_cross_score(province_id, geometry, real_rivers)
            if rc > 0.5:
                notes += " (river-cross natural border guidance)"
        proposals.append({
            "parent_id": province_id,
            "child_index": i,
            "suggested_points": poly,
            "notes": notes,
            "naval_aware": True,
            "river_aware": rc > 0.5 if real_rivers else False,
            "suggested_center": _centroid(poly),
            "approx_area": round(area, 1),
            "naval_importance": round(naval_score, 2)
        })

    if len(proposals) > num_pieces:
        proposals = sorted(proposals, key=lambda p: p["approx_area"], reverse=True)[:num_pieces]

    return proposals


if __name__ == "__main__":
    print("subdivision_utils.py - Supporting module for naval-aware map generation.")