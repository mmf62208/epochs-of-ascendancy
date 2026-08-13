#!/usr/bin/env python3
"""Pure industrial placement helpers for world_full factory/shipyard bootstrap.

Mirrors ScenarioFactorySpawner.resolve_industrial_province_ids logic.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Sequence, Set


def resolve_industrial_province_ids(
    capital_id: int,
    key_province_ids: Sequence[int],
    valid_land_ids: Optional[Sequence[int]] = None,
) -> List[int]:
    valid: Set[int] = set()
    if valid_land_ids is not None:
        for raw in valid_land_ids:
            pid = int(raw)
            if pid > 0:
                valid.add(pid)
    out: List[int] = []
    seen: Set[int] = set()
    if capital_id > 0 and (not valid or capital_id in valid):
        out.append(int(capital_id))
        seen.add(int(capital_id))
    for raw in key_province_ids:
        pid = int(raw)
        if pid <= 0 or pid in seen:
            continue
        if valid and pid not in valid:
            continue
        out.append(pid)
        seen.add(pid)
    return out


def pick_shipyard_province(
    industrial_pids: Sequence[int],
    owned_port_pids: Sequence[int],
) -> Optional[int]:
    """Prefer industrial port, else first owned port id."""
    ports = {int(p) for p in owned_port_pids if int(p) > 0}
    for pid in industrial_pids:
        if int(pid) in ports:
            return int(pid)
    ordered = sorted(ports)
    return ordered[0] if ordered else None


def starting_oob_designs(country: Dict[str, Any]) -> List[str]:
    oob = country.get("starting_oob") or {}
    if not isinstance(oob, dict):
        return []
    out: List[str] = []
    for key in ("land_designs", "air_designs", "naval_designs"):
        arr = oob.get(key) or []
        if not isinstance(arr, list):
            continue
        for d in arr:
            s = str(d).strip()
            if s and s not in out:
                out.append(s)
    return out


def primary_land_design(country: Dict[str, Any]) -> str:
    oob = country.get("starting_oob") or {}
    if not isinstance(oob, dict):
        return ""
    land = oob.get("land_designs") or []
    if isinstance(land, list) and land:
        return str(land[0]).strip()
    designs = starting_oob_designs(country)
    return designs[0] if designs else ""


def template_base_production_days(template: Dict[str, Any], default: float = 60.0) -> float:
    """Read base production days from a unit template JSON dict."""
    if not isinstance(template, dict):
        return float(default)
    if "base_production_days" in template:
        return float(template["base_production_days"])
    if "production_days" in template:
        return float(template["production_days"])
    return float(default)


def min_evidence_advance_days(
    base_days_list: Sequence[float],
    *,
    output_multiplier: float = 0.95,
    layer_speed: float = 1.15,
    margin_days: float = 10.0,
) -> float:
    """Minimum calendar days of ProductionLine.advance_days needed to finish one unit.

    progress += days * output_multiplier * factory_eff (≈1)
    days_needed = base_days / layer_speed
    require days * output_multiplier >= days_needed
    """
    if not base_days_list:
        return 60.0 + margin_days
    worst = max(float(d) for d in base_days_list)
    speed = max(float(layer_speed), 0.01)
    out_m = max(float(output_multiplier), 0.01)
    days_needed = worst / speed
    return days_needed / out_m + margin_days


def stockpile_delta(before: Dict[str, int], after: Dict[str, int]) -> Dict[str, int]:
    """Non-zero equipment deltas after production advance."""
    keys = set(before) | set(after)
    out: Dict[str, int] = {}
    for k in keys:
        d = int(after.get(k, 0)) - int(before.get(k, 0))
        if d != 0:
            out[str(k)] = d
    return out
