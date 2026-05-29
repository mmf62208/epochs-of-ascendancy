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


# =============================================================================
# CONFIGURATION (will move to YAML later)
# =============================================================================

# NOTE: Current seed geometry (provinces_geometry.json) uses very coarse ~6-point polygons.
# We deliberately lower the threshold so the pipeline can demonstrate real subdivision
# on the playable starter map. When we ingest higher-resolution source data this can rise.
MIN_POINTS_FOR_SPLIT = 5
MAX_SPLITS_PER_PROVINCE = 4

# Scoring weights
NAVAL_IMPORTANCE_WEIGHT = 2.8
SIZE_WEIGHT = 1.0
COASTAL_BONUS = 1.1
STRAIT_PROTECTION_PENALTY = 0.55   # Strongly discourage splitting strait provinces


# =============================================================================
# CORE DECISION FUNCTIONS
# =============================================================================

def should_split_province(
    province_id: int,
    geometry: Dict,
    naval_data: Dict,
    avg_point_count: float
) -> bool:
    """
    Returns whether this province is a good candidate for subdivision.
    Relaxed thresholds for the current coarse 6-point seed geometry.
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

    # Much more permissive threshold for the starter map
    return score > 0.95


def suggest_number_of_splits(
    province_id: int,
    geometry: Dict,
    naval_data: Dict
) -> int:
    """
    Given that we want to split this province, how many pieces should we aim for?
    Tuned for coarse 6-point starter geometry (most provinces get 2-3 children).
    """
    prov = next((p for p in geometry.get("provinces", []) if p.get("id") == province_id), None)
    if not prov:
        return 2

    points = len(prov.get("points", []))
    naval_score = naval_data.get("naval_importance_scores", {}).get(province_id, 0.0)

    # With 6-pt input we rarely want >3 children per parent in Phase 1
    base = 2
    if points >= 8:
        base = 3

    # Give coastal and high-naval provinces a slight push toward 3
    if naval_score > 1.0 or province_id in naval_data.get("coastal_provinces", []):
        base = min(MAX_SPLITS_PER_PROVINCE, base + 1)

    # Be conservative with protected straits
    for key, data in naval_data.get("protected_straits", {}).items():
        if province_id in (data.get("province_a", -1), data.get("province_b", -1)):
            base = min(2, base)
            break

    return max(2, min(MAX_SPLITS_PER_PROVINCE, base))


# =============================================================================
# RANKING & PRIORITIZATION
# =============================================================================

def rank_provinces_for_subdivision(
    province_ids: List[int],
    geometry: Dict,
    naval_data: Dict
) -> List[Tuple[int, float]]:
    """
    Returns a sorted list of (province_id, priority) for subdivision.
    Higher score = split this one earlier / more aggressively.

    Strongly favors:
    - Large provinces
    - High naval importance provinces
    - Coastal provinces
    - While protecting major straits
    """
    ranked = []
    avg_points = sum(len(p.get("points", [])) for p in geometry.get("provinces", [])) / max(len(geometry.get("provinces", [])), 1)

    for pid in province_ids:
        if not should_split_province(pid, geometry, naval_data, avg_points):
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


def _densify_boundary(points: List[List[float]], target_points: int = 14) -> List[List[float]]:
    """
    Insert linearly interpolated points along edges so low-vertex polygons
    (the current 6-point seed provinces) can be split into sensible children.
    Returns a new list with approximately target_points or more.
    """
    if len(points) >= target_points:
        return list(points)

    # Compute total length and per-edge lengths
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

    # How many extra points we want to insert in total
    extras_needed = max(0, target_points - n)
    if extras_needed == 0:
        return list(points)

    # Distribute extras proportionally to edge length
    result = []
    for i in range(n):
        result.append(list(points[i]))
        length = edge_lengths[i]
        if length < 1e-6:
            continue
        # Number of inserts on this edge (at least 1 if edge is long)
        inserts = max(1, int(round(extras_needed * (length / total_len))))
        inserts = min(inserts, extras_needed)
        extras_needed -= inserts
        for j in range(1, inserts + 1):
            t = j / float(inserts + 1)
            result.append(_interpolate(points[i], points[(i + 1) % n], t))

    # If we still need more (rounding), add midpoints on longest edges
    while len(result) < target_points and len(result) < n * 3:
        # Find longest current edge in result ring
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


def _radial_split(points: List[List[float]], k: int) -> List[List[List[float]]]:
    """
    Improved radial subdivision:
    - Densifies low-vertex input first
    - Each child owns a contiguous arc of the (densified) perimeter
    - Children are formed as [arc_points..., centroid]
    This gives far better shape fidelity than the original fan-on-6-pts version.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    # Densify so we have enough vertices to distribute fairly
    dense = _densify_boundary(points, target_points=max(14, len(points) * 2))

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


def _bisect_polygon(points: List[List[float]], k: int) -> List[List[List[float]]]:
    """
    Simple but robust recursive bisection for when radial gives poor results.
    Repeatedly splits along a reasonable chord (using densified ring + index cuts).
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    dense = _densify_boundary(points, target_points=max(12, len(points) * 2))
    n = len(dense)

    pieces: List[List[List[float]]] = [dense]

    while len(pieces) < k:
        # Pick the current largest piece (by point count as proxy for area)
        pieces.sort(key=lambda p: len(p), reverse=True)
        parent = pieces.pop(0)
        if len(parent) < 5:
            pieces.append(parent)
            break

        # Cut roughly in half along the ring
        m = len(parent)
        cut1 = m // 3
        cut2 = (m * 2) // 3

        # Create two children sharing the cut chord (parent[cut1] and parent[cut2])
        p1 = parent[cut1:cut2+1]
        p2 = parent[cut2:] + parent[:cut1+1]

        # Add a small interior bias point (average of the two cut points) to avoid flatness
        c = _interpolate(parent[cut1], parent[cut2], 0.5)
        p1 = p1 + [c]
        p2 = p2 + [c]

        if _is_valid_polygon(p1):
            pieces.append(p1)
        else:
            pieces.append(parent)
        if _is_valid_polygon(p2) and len(pieces) < k:
            pieces.append(p2)
        elif len(pieces) < k:
            pieces.append(parent)

    # Final cleanup + center fallback for any degenerate
    cleaned = []
    ctr = _centroid(points)
    for p in pieces[:k]:
        if _is_valid_polygon(p):
            cleaned.append(p)
        else:
            # Emergency fan from center using original
            cleaned.append(points[:3] + [ctr])

    return cleaned if len(cleaned) >= 2 else [list(points)]


def _simple_cluster_split(points: List[List[float]], k: int) -> List[List[List[float]]]:
    """
    Fallback clustering (used only if better methods fail).
    Works on densified points then snaps children to convex hull.
    """
    if k <= 1 or len(points) < 3:
        return [list(points)]

    dense = _densify_boundary(points, target_points=max(12, len(points) * 2))

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
    num_pieces: int = 2
) -> List[Dict]:
    """
    Proposes a subdivision of a province into N child provinces.

    2026-05-28 improvements:
    - Always densifies low-vertex input (current seed provinces are ~6 pts)
    - Prefers a robust radial arc-ownership method for natural slices
    - Falls back to repeated geometric bisection for better balance
    - Produces children with real perimeter ownership + reasonable interior points
    - Includes area and validity diagnostics
    """
    original_points = _get_province_points(province_id, geometry)
    if not original_points or len(original_points) < 3:
        return []

    parent_area = _polygon_area(original_points)

    # Primary path: improved radial on densified boundary
    child_polygons = _radial_split(original_points, num_pieces)

    # If we got too few or degenerate results, use bisection
    valid_children = [p for p in child_polygons if _is_valid_polygon(p)]
    if len(valid_children) < max(2, num_pieces // 2):
        child_polygons = _bisect_polygon(original_points, num_pieces)
        valid_children = [p for p in child_polygons if _is_valid_polygon(p)]

    # Last resort
    if len(valid_children) < 2:
        child_polygons = _simple_cluster_split(original_points, num_pieces)
        valid_children = [p for p in child_polygons if _is_valid_polygon(p)]

    proposals = []
    total_child_area = 0.0
    for i, poly in enumerate(child_polygons):
        if not _is_valid_polygon(poly):
            continue
        area = _polygon_area(poly)
        total_child_area += area
        proposals.append({
            "parent_id": province_id,
            "child_index": i,
            "suggested_points": poly,
            "notes": f"Densify + radial/bisect split. Parent area {parent_area:.1f} -> child area {area:.1f}.",
            "naval_aware": True,
            "suggested_center": _centroid(poly),
            "approx_area": round(area, 1)
        })

    # If we somehow produced more than requested, trim (rare)
    if len(proposals) > num_pieces:
        proposals = sorted(proposals, key=lambda p: p["approx_area"], reverse=True)[:num_pieces]

    return proposals


if __name__ == "__main__":
    print("subdivision_utils.py - Supporting module for naval-aware map generation.")