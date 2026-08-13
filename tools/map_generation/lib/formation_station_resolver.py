#!/usr/bin/env python3
"""Pure station province resolver for OOB formation spawn.

Mirrors FormationSpawner.resolve_station_province_id logic:
prefer capital if it is owned land; else first sorted owned land id;
reject sea / unowned / missing ids.
"""
from __future__ import annotations

from typing import Dict, Iterable, List, Optional, Sequence, Set


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


def resolve_stations_hoi_deploy(
    count: int,
    capital_id: int,
    owned_land_ids: Sequence[int],
    *,
    key_provinces: Optional[Sequence[int]] = None,
    border_provinces: Optional[Sequence[int]] = None,
    valid_land_ids: Optional[Set[int]] = None,
    water_ids: Optional[Set[int]] = None,
) -> List[int]:
    """HOI-style station order: capital → key hubs → border → remaining owned land.

    Spreads land OOB across industrial hubs and fronts instead of packing only
    the capital (or first sorted owned id).
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

    def _push(pid: int) -> None:
        if pid in seen and pid not in used:
            ordered.append(pid)
            used.add(pid)

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
    out: List[int] = []
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
