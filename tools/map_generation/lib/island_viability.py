"""Island / province facility viability rules for map authoring.

Determines island_class and facility_tier from polygon area (canvas units)
and optional critical flags. Used by grand theater expansion and validators.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Optional, Sequence

# Defaults match config/grand_theater.yaml (can be overridden).
DEFAULT_THRESHOLDS: Dict[str, float] = {
    "min_area_micro_exclude": 80.0,
    "min_area_airfield": 180.0,
    "min_area_port": 320.0,
    "min_area_full_facilities": 700.0,
}


def polygon_area(points: Sequence[Sequence[float]]) -> float:
    """Shoelace area (absolute). Open or closed ring."""
    if not points or len(points) < 3:
        return 0.0
    pts = list(points)
    if pts[0][0] == pts[-1][0] and pts[0][1] == pts[-1][1]:
        pts = pts[:-1]
    if len(pts) < 3:
        return 0.0
    area = 0.0
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        area += float(pts[i][0]) * float(pts[j][1])
        area -= float(pts[j][0]) * float(pts[i][1])
    return abs(area) * 0.5


def classify_island(
    area: float,
    *,
    domain: str = "land",
    critical: bool = False,
    explicit_class: Optional[str] = None,
    thresholds: Optional[Mapping[str, float]] = None,
) -> Dict[str, Any]:
    """Return island_class, facility_tier, keep_as_province, reasons."""
    th = dict(DEFAULT_THRESHOLDS)
    if thresholds:
        th.update({k: float(v) for k, v in thresholds.items() if k in th})

    dom = (domain or "land").lower()
    if dom in ("sea", "ocean", "lake", "strait"):
        return {
            "island_class": "none",
            "facility_tier": "none",
            "keep_as_province": True,
            "domain": "strait" if dom == "strait" else ("lake" if dom == "lake" else "sea"),
            "area": area,
            "reason": "water_domain",
        }

    if explicit_class in ("mainland", "large", "medium", "small", "micro"):
        ic = explicit_class
    elif area >= th["min_area_full_facilities"]:
        ic = "large" if area < th["min_area_full_facilities"] * 3 else "mainland"
        if explicit_class == "mainland" or area >= th["min_area_full_facilities"] * 2:
            ic = "mainland" if area >= th["min_area_full_facilities"] * 1.5 else "large"
    elif area >= th["min_area_port"]:
        ic = "medium"
    elif area >= th["min_area_airfield"]:
        ic = "small"
    else:
        ic = "micro"

    # Refine mainland vs large when no explicit
    if explicit_class is None and ic == "large" and area >= th["min_area_full_facilities"] * 2:
        ic = "mainland"
    if explicit_class is None and area >= th["min_area_full_facilities"]:
        if ic not in ("mainland", "large"):
            ic = "large"

    if ic == "mainland":
        tier = "full"
        keep = True
        reason = "mainland_full"
    elif ic == "large":
        tier = "full"
        keep = True
        reason = "large_island_full"
    elif ic == "medium":
        tier = "limited"
        keep = True
        reason = "medium_port_airfield"
    elif ic == "small":
        tier = "anchor_only" if area < th["min_area_port"] else "limited"
        keep = True
        reason = "small_limited"
    else:  # micro
        if critical:
            tier = "limited"
            keep = True
            reason = "critical_micro_kept"
        elif area < th["min_area_micro_exclude"]:
            tier = "none"
            keep = False
            reason = "too_small_exclude"
        else:
            tier = "none"
            keep = True  # flag-only province (VP / radar later)
            reason = "micro_flag_only"

    return {
        "island_class": ic,
        "facility_tier": tier,
        "keep_as_province": keep,
        "domain": "coastal_land" if dom in ("coastal_land", "coastal") else "land",
        "area": area,
        "reason": reason,
        "can_airfield": tier in ("full", "limited", "anchor_only") and ic != "micro" or (critical and tier != "none"),
        "can_port": tier in ("full", "limited") or (critical and tier == "limited"),
        "can_factory": tier == "full",
    }


def classify_points(
    points: Sequence[Sequence[float]],
    **kwargs: Any,
) -> Dict[str, Any]:
    return classify_island(polygon_area(points), **kwargs)
