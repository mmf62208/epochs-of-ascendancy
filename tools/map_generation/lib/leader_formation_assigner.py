#!/usr/bin/env python3
"""Pure deterministic picker: assign leaders to formations without double-assign.

Mirrors ScenarioLoader / LeaderManager auto-assign rules:
- same country_tag
- leader_type valid for formation branch (land / naval / air)
- skip already-used leader ids
- prefer higher skill, then leader_id order
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

LAND_FORMATION_TYPES = frozenset({"division", "garrison", "army", "army_group", "brigade"})
NAVAL_FORMATION_TYPES = frozenset({"fleet", "task_force", "ship"})
AIR_FORMATION_TYPES = frozenset({"air_wing", "air_squadron", "air_group"})

LAND_LEADER_TYPES = frozenset({"general", "field_marshal"})
NAVAL_LEADER_TYPES = frozenset({"admiral"})
AIR_LEADER_TYPES = frozenset({"air_marshal"})


def formation_branch(formation_type: str) -> str:
    ft = str(formation_type or "").strip().lower()
    if ft in LAND_FORMATION_TYPES:
        return "land"
    if ft in NAVAL_FORMATION_TYPES:
        return "naval"
    if ft in AIR_FORMATION_TYPES:
        return "air"
    return ""


def allowed_leader_types_for_formation(formation_type: str) -> Set[str]:
    branch = formation_branch(formation_type)
    if branch == "land":
        return set(LAND_LEADER_TYPES)
    if branch == "naval":
        return set(NAVAL_LEADER_TYPES)
    if branch == "air":
        return set(AIR_LEADER_TYPES)
    return set()


def is_land_formation_type(formation_type: str) -> bool:
    return formation_branch(formation_type) == "land"


def is_naval_formation_type(formation_type: str) -> bool:
    return formation_branch(formation_type) == "naval"


def is_air_formation_type(formation_type: str) -> bool:
    return formation_branch(formation_type) == "air"


def is_land_leader_type(leader_type: str) -> bool:
    return str(leader_type or "").strip().lower() in LAND_LEADER_TYPES


def is_naval_leader_type(leader_type: str) -> bool:
    return str(leader_type or "").strip().lower() in NAVAL_LEADER_TYPES


def is_air_leader_type(leader_type: str) -> bool:
    return str(leader_type or "").strip().lower() in AIR_LEADER_TYPES


def leader_sort_key(entry: Dict[str, Any]) -> Tuple[int, str]:
    skill = (
        int(entry.get("attack_skill") or 0)
        + int(entry.get("defense_skill") or 0)
        + int(entry.get("planning_skill") or 0)
        + int(entry.get("organization_skill") or 0)
    )
    return (-skill, str(entry.get("leader_id") or ""))


def pick_leader_for_formation(
    country_tag: str,
    formation_type: str,
    leaders: Sequence[Dict[str, Any]],
    used_leader_ids: Set[str],
    *,
    current_leader_id: str = "",
    allowed_leader_types: Optional[Set[str]] = None,
) -> str:
    """Return leader_id to assign, or "" if none / already filled / wrong branch."""
    tag = str(country_tag or "").strip().upper()
    if not tag:
        return ""
    if current_leader_id and str(current_leader_id).strip():
        return ""
    allowed = allowed_leader_types if allowed_leader_types is not None else allowed_leader_types_for_formation(
        formation_type
    )
    if not allowed:
        return ""

    candidates: List[Dict[str, Any]] = []
    for raw in leaders:
        if not isinstance(raw, dict):
            continue
        lid = str(raw.get("leader_id") or "").strip()
        if not lid or lid in used_leader_ids:
            continue
        if str(raw.get("country_tag") or "").strip().upper() != tag:
            continue
        if str(raw.get("leader_type") or "").strip().lower() not in allowed:
            continue
        assigned = str(raw.get("assigned_army_id") or raw.get("assigned_formation_id") or "").strip()
        if assigned:
            continue
        candidates.append(raw)

    if not candidates:
        return ""
    candidates.sort(key=leader_sort_key)
    return str(candidates[0].get("leader_id") or "")


def pick_leader_for_land_formation(
    country_tag: str,
    formation_type: str,
    leaders: Sequence[Dict[str, Any]],
    used_leader_ids: Set[str],
    *,
    current_leader_id: str = "",
) -> str:
    """Land-only wrapper (compat with prior land-assign tests)."""
    if not is_land_formation_type(formation_type):
        return ""
    return pick_leader_for_formation(
        country_tag,
        formation_type,
        leaders,
        used_leader_ids,
        current_leader_id=current_leader_id,
        allowed_leader_types=LAND_LEADER_TYPES,
    )


def assign_leaders_to_formations(
    formations: Sequence[Dict[str, Any]],
    leaders: Sequence[Dict[str, Any]],
    *,
    branches: Optional[Set[str]] = None,
) -> Dict[str, Any]:
    """Assign leaders to formations. branches filters land/naval/air (default all known)."""
    if branches is None:
        branches = {"land", "naval", "air"}
    used: Set[str] = set()
    for f in formations:
        lid = str(f.get("leader_id") or "").strip()
        if lid:
            used.add(lid)
    for raw in leaders:
        if not isinstance(raw, dict):
            continue
        assigned = str(raw.get("assigned_army_id") or "").strip()
        lid = str(raw.get("leader_id") or "").strip()
        if assigned and lid:
            used.add(lid)

    assignments: Dict[str, str] = {}
    ordered = sorted(formations, key=lambda f: str(f.get("formation_id") or ""))
    for f in ordered:
        fid = str(f.get("formation_id") or "").strip()
        if not fid:
            continue
        ft = str(f.get("formation_type") or "")
        br = formation_branch(ft)
        if br not in branches:
            continue
        cur = str(f.get("leader_id") or "").strip()
        pick = pick_leader_for_formation(
            str(f.get("country_tag") or ""),
            ft,
            leaders,
            used,
            current_leader_id=cur,
        )
        if not pick:
            continue
        assignments[fid] = pick
        used.add(pick)

    stats_by_branch: Dict[str, Dict[str, int]] = {
        "land": {},
        "naval": {},
        "air": {},
    }
    totals_by_branch: Dict[str, Dict[str, int]] = {
        "land": {},
        "naval": {},
        "air": {},
    }
    for f in formations:
        ft = str(f.get("formation_type") or "")
        br = formation_branch(ft)
        if br not in totals_by_branch:
            continue
        tag = str(f.get("country_tag") or "").strip().upper()
        totals_by_branch[br][tag] = totals_by_branch[br].get(tag, 0) + 1
        fid = str(f.get("formation_id") or "")
        has = bool(str(f.get("leader_id") or "").strip()) or fid in assignments
        if has:
            stats_by_branch[br][tag] = stats_by_branch[br].get(tag, 0) + 1

    return {
        "assignments": assignments,
        "used_leader_ids": sorted(used),
        "stats": {
            "assigned_count": len(assignments),
            "by_tag_land_with_leader": stats_by_branch["land"],
            "by_tag_land_total": totals_by_branch["land"],
            "by_tag_naval_with_leader": stats_by_branch["naval"],
            "by_tag_naval_total": totals_by_branch["naval"],
            "by_tag_air_with_leader": stats_by_branch["air"],
            "by_tag_air_total": totals_by_branch["air"],
        },
    }


def assign_leaders_to_land_formations(
    formations: Sequence[Dict[str, Any]],
    leaders: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    return assign_leaders_to_formations(formations, leaders, branches={"land"})


def assign_leaders_to_branch_formations(
    formations: Sequence[Dict[str, Any]],
    leaders: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    """Naval + air only (land left for separate pass or prior assign)."""
    return assign_leaders_to_formations(formations, leaders, branches={"naval", "air"})


def active_leaders_from_rosters(
    roster_entries: Sequence[Dict[str, Any]],
    year: int = 1936,
    leader_types: Optional[Set[str]] = None,
) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for e in roster_entries:
        if not isinstance(e, dict):
            continue
        lt = str(e.get("leader_type") or "").strip().lower()
        if leader_types is not None and lt not in leader_types:
            continue
        sy = int(e.get("start_year") or 0)
        ey = int(e.get("end_year") or 0)
        if sy > 0 and year < sy:
            continue
        if ey > 0 and year > ey:
            continue
        out.append(e)
    return out


def active_land_leaders_from_rosters(
    roster_entries: Sequence[Dict[str, Any]],
    year: int = 1936,
) -> List[Dict[str, Any]]:
    return active_leaders_from_rosters(roster_entries, year, LAND_LEADER_TYPES)


def active_naval_leaders_from_rosters(
    roster_entries: Sequence[Dict[str, Any]],
    year: int = 1936,
) -> List[Dict[str, Any]]:
    return active_leaders_from_rosters(roster_entries, year, NAVAL_LEADER_TYPES)


def active_air_leaders_from_rosters(
    roster_entries: Sequence[Dict[str, Any]],
    year: int = 1936,
) -> List[Dict[str, Any]]:
    return active_leaders_from_rosters(roster_entries, year, AIR_LEADER_TYPES)
