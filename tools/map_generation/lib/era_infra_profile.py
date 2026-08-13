#!/usr/bin/env python3
"""Pure era-band infrastructure density profiles (mirrors InfrastructureOverlayLayer).

Year → band → road/rail/city thresholds. Used by CI to prove 1918-sparse is
stricter than 1936-baseline without loading Godot.
"""

from __future__ import annotations

from typing import Any, Dict


def era_band_for_year(year: int) -> int:
    y = int(year)
    if y <= 1924:
        return 0  # sparse_1918
    if y >= 2000:
        return 2  # dense_2026
    return 1  # standard_1936


def era_infra_profile_for_year(year: int) -> Dict[str, Any]:
    band = era_band_for_year(year)
    if band == 0:
        return {
            "label": "sparse_1918",
            "year": int(year),
            "band": 0,
            "road_infra_min": 5.0,
            "rail_infra_min": 9.0,
            "city_dev_min": 5.0,
            "road_width_explicit": 2.0,
            "road_width_implicit": 1.0,
            "rail_width": 1.8,
            "rail_tie_step": 45.0,
        }
    if band == 2:
        return {
            "label": "dense_2026",
            "year": int(year),
            "band": 2,
            "road_infra_min": 2.0,
            "rail_infra_min": 4.0,
            "city_dev_min": 2.0,
            "road_width_explicit": 4.0,
            "road_width_implicit": 2.5,
            "rail_width": 3.0,
            "rail_tie_step": 22.0,
        }
    return {
        "label": "standard_1936",
        "year": int(year),
        "band": 1,
        "road_infra_min": 3.0,
        "rail_infra_min": 6.0,
        "city_dev_min": 3.0,
        "road_width_explicit": 3.6,
        "road_width_implicit": 2.0,
        "rail_width": 2.9,
        "rail_tie_step": 28.0,
    }


def profile_is_sparser(a: Dict[str, Any], b: Dict[str, Any]) -> bool:
    """True if profile `a` is stricter/sparser than `b` (higher mins, thinner roads)."""
    return (
        float(a.get("road_infra_min", 0)) > float(b.get("road_infra_min", 0))
        and float(a.get("rail_infra_min", 0)) > float(b.get("rail_infra_min", 0))
        and float(a.get("city_dev_min", 0)) > float(b.get("city_dev_min", 0))
        and float(a.get("road_width_explicit", 0)) < float(b.get("road_width_explicit", 99))
    )
