#!/usr/bin/env python3
"""Pure station province resolver for OOB formation spawn.

Mirrors FormationSpawner.resolve_station_province_id logic:
prefer capital if it is owned land; else first sorted owned land id;
reject sea / unowned / missing ids.
"""
from __future__ import annotations

from typing import Dict, Iterable, List, Optional, Sequence, Set

# Mirrors FormationSpawner.TEST_FORMATION_TYPES / LAND_FORMATION_TYPES.
DEFAULT_FORMATION_TYPES: List[str] = [
    "division",
    "division",
    "fleet",
    "air_wing",
    "garrison",
    "task_force",
]
LAND_FORMATION_TYPES: Set[str] = {"division", "garrison"}


def resolve_station_province_id(
    capital_id: int,
    owned_land_ids: Sequence[int],
    *,
    valid_land_ids: Optional[Set[int]] = None,
    water_ids: Optional[Set[int]] = None,
) -> int:
    """Return a valid owned land province id for stationing, or -1.

    Args:
        capital_id: preferred station (scenario capital); may be invalid
        owned_land_ids: land provinces owned by the country
        valid_land_ids: optional board land id set (if None, owned list trusted)
        water_ids: optional water id set to reject
    """
    owned: List[int] = []
    seen: Set[int] = set()
    for raw in owned_land_ids:
        try:
            pid = int(raw)
        except (TypeError, ValueError):
            continue
        if pid <= 0 or pid in seen:
            continue
        if water_ids is not None and pid in water_ids:
            continue
        if valid_land_ids is not None and pid not in valid_land_ids:
            continue
        seen.add(pid)
        owned.append(pid)
    owned.sort()

    try:
        cap = int(capital_id)
    except (TypeError, ValueError):
        cap = -1
    if cap > 0 and cap in seen:
        if water_ids is None or cap not in water_ids:
            if valid_land_ids is None or cap in valid_land_ids:
                return cap

    if owned:
        return owned[0]
    return -1


def resolve_stations_for_count(
    count: int,
    capital_id: int,
    owned_land_ids: Sequence[int],
    *,
    valid_land_ids: Optional[Set[int]] = None,
    water_ids: Optional[Set[int]] = None,
) -> List[int]:
    """Deterministic list of station ids (length count); all owned land when possible."""
    primary = resolve_station_province_id(
        capital_id,
        owned_land_ids,
        valid_land_ids=valid_land_ids,
        water_ids=water_ids,
    )
    if primary <= 0:
        return [-1] * max(0, count)

    owned_sorted = sorted(
        {
            int(x)
            for x in owned_land_ids
            if int(x) > 0
            and (water_ids is None or int(x) not in water_ids)
            and (valid_land_ids is None or int(x) in valid_land_ids)
        }
    )
    # Capital first, then other owned land cycling for multi-unit spread
    ordered: List[int] = [primary] + [p for p in owned_sorted if p != primary]
    if not ordered:
        return [-1] * max(0, count)
    out: List[int] = []
    for i in range(max(0, count)):
        out.append(ordered[i % len(ordered)])
    return out


def _normalize_formation_type(raw: object) -> str:
    return str(raw or "").strip().lower()


def land_slot_indices(count: int, formation_types: Sequence[str]) -> List[int]:
    """Indices i in range(count) whose type cycle entry is land (division|garrison)."""
    if count <= 0 or not formation_types:
        return []
    n = len(formation_types)
    out: List[int] = []
    for i in range(count):
        if _normalize_formation_type(formation_types[i % n]) in LAND_FORMATION_TYPES:
            out.append(i)
    return out


def resolve_stations_hoi_deploy(
    count: int,
    capital_id: int,
    owned_land_ids: Sequence[int],
    *,
    key_provinces: Optional[Sequence[int]] = None,
    border_provinces: Optional[Sequence[int]] = None,
    front_reserve: Optional[Sequence[int]] = None,
    formation_types: Optional[Sequence[str]] = None,
    valid_land_ids: Optional[Set[int]] = None,
    water_ids: Optional[Set[int]] = None,
) -> List[int]:
    """HOI-style station order: front_reserve → capital → key hubs → border → rest.

    When formation_types is set, land slots (division|garrison in the type cycle)
    are filled from ordered; naval/air use capital (or first non-reserved owned)
    so they never consume a reserved front pid.
    """
    owned: List[int] = []
    seen: Set[int] = set()
    for raw in owned_land_ids:
        try:
            pid = int(raw)
        except (TypeError, ValueError):
            continue
        if pid <= 0 or pid in seen:
            continue
        if water_ids is not None and pid in water_ids:
            continue
        if valid_land_ids is not None and pid not in valid_land_ids:
            continue
        seen.add(pid)
        owned.append(pid)
    if not owned:
        return [-1] * max(0, count)

    ordered: List[int] = []
    used: Set[int] = set()
    reserved: Set[int] = set()

    def _push(pid: int) -> None:
        if pid in seen and pid not in used:
            ordered.append(pid)
            used.add(pid)

    for raw in front_reserve or []:
        try:
            pid = int(raw)
        except (TypeError, ValueError):
            continue
        if pid > 0 and pid in seen:
            reserved.add(pid)
            _push(pid)

    try:
        cap = int(capital_id)
    except (TypeError, ValueError):
        cap = -1
    if cap > 0:
        _push(cap)

    for raw in key_provinces or []:
        try:
            _push(int(raw))
        except (TypeError, ValueError):
            continue

    for raw in border_provinces or []:
        try:
            _push(int(raw))
        except (TypeError, ValueError):
            continue

    for pid in sorted(owned):
        _push(pid)

    if not ordered:
        return [-1] * max(0, count)

    # Non-land fallback: owned capital only if not front_reserve; else first non-reserved.
    non_land = -1
    if cap > 0 and cap in seen and cap not in reserved:
        non_land = cap
    else:
        for pid in ordered:
            if pid not in reserved:
                non_land = pid
                break
        if non_land <= 0:
            non_land = ordered[0]

    types = list(formation_types) if formation_types is not None else None
    out: List[int] = []
    if types:
        land_cursor = 0
        n_types = len(types)
        for i in range(max(0, count)):
            ftype = _normalize_formation_type(types[i % n_types]) if n_types else ""
            if ftype in LAND_FORMATION_TYPES:
                out.append(ordered[land_cursor % len(ordered)])
                land_cursor += 1
            else:
                out.append(non_land)
        return out

    for i in range(max(0, count)):
        out.append(ordered[i % len(ordered)])
    return out


def owned_land_from_scenario_overrides(
    provinces_overrides: Sequence[dict],
    tag: str,
    base_by_id: Optional[Dict[int, dict]] = None,
) -> List[int]:
    """Collect owned land ids for tag from world_full scenario province array."""
    tag_u = str(tag).strip().upper()
    out: List[int] = []
    for p in provinces_overrides:
        if str(p.get("owner_tag") or "").strip().upper() != tag_u:
            continue
        pid = int(p.get("id") or 0)
        if pid <= 0:
            continue
        if base_by_id is not None:
            bp = base_by_id.get(pid) or {}
            dom = str(bp.get("domain") or "land")
            if dom in ("sea", "strait", "lake"):
                continue
        out.append(pid)
    return sorted(set(out))
