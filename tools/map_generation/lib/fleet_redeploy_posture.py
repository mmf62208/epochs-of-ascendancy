"""Fleet redeploy / posture pilot beyond station-pref, tasking, and escort.

Chooses posture: HOLD_BASE, PATROL_SCREEN, CONVOY_COVER, POWER_PROJECTION, REFUEL_RETURN
from basing level, fuel, zone relation, and escort need.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

POSTURES = (
    "HOLD_BASE",
    "PATROL_SCREEN",
    "CONVOY_COVER",
    "POWER_PROJECTION",
    "REFUEL_RETURN",
)


def score_fleet_posture(
    posture: str,
    *,
    basing_level: str = "none",
    fuel_level: float = 1.0,
    zone_relation: str = "no_zone",
    escort_need: float = 0.0,
    can_service: bool = False,
) -> Dict[str, Any]:
    p = str(posture or "PATROL_SCREEN").upper()
    if p not in POSTURES:
        p = "PATROL_SCREEN"
    fuel = max(0.1, min(1.2, float(fuel_level)))
    rel = str(zone_relation or "no_zone").lower()
    need = max(0.0, float(escort_need))
    rank = {"none": 0, "anchorage": 1, "port": 2, "major_base": 3}.get(
        str(basing_level).lower(), 0
    )

    base = {
        "HOLD_BASE": 40.0,
        "PATROL_SCREEN": 50.0,
        "CONVOY_COVER": 48.0,
        "POWER_PROJECTION": 55.0,
        "REFUEL_RETURN": 35.0,
    }[p]

    if fuel < 0.4:
        if p == "REFUEL_RETURN":
            base += 40.0
        if p == "POWER_PROJECTION":
            base -= 30.0
    if can_service and p == "HOLD_BASE":
        base += 12.0 + rank * 5.0
    if need >= 25.0 and p == "CONVOY_COVER":
        base += 28.0 + min(20.0, need * 0.05)
    if rel == "hostile" and p == "POWER_PROJECTION":
        base += 22.0
    if rel == "contested" and p in ("PATROL_SCREEN", "CONVOY_COVER"):
        base += 16.0
    if rel == "friendly" and p == "PATROL_SCREEN":
        base += 10.0
    if rank >= 3 and p == "POWER_PROJECTION":
        base += 15.0
    if rank == 0 and p == "POWER_PROJECTION":
        base -= 20.0

    base *= 0.85 + 0.15 * fuel
    return {
        "posture": p,
        "score": float(base),
        "basing_level": basing_level,
        "zone_relation": rel,
        "fuel_level": fuel,
        "escort_need": need,
    }


def rank_fleet_postures(
    *,
    basing_level: str = "none",
    fuel_level: float = 1.0,
    zone_relation: str = "no_zone",
    escort_need: float = 0.0,
    can_service: bool = False,
) -> Dict[str, Any]:
    scored = [
        score_fleet_posture(
            p,
            basing_level=basing_level,
            fuel_level=fuel_level,
            zone_relation=zone_relation,
            escort_need=escort_need,
            can_service=can_service,
        )
        for p in POSTURES
    ]
    scored.sort(key=lambda x: (-float(x["score"]), x["posture"]))
    best = scored[0] if scored else {}
    return {
        "best_posture": str(best.get("posture", "")),
        "best_score": float(best.get("score", 0.0)) if best else 0.0,
        "ranked": scored,
        "empty": len(scored) == 0,
        "summary": (
            "Fleet posture %s (score %.1f)" % (best.get("posture"), float(best.get("score", 0.0)))
            if best
            else "Fleet posture: none"
        ),
    }
