"""Fleet patrol/tasking pilot — order preference beyond station basing (not full fleet AI).

Given basing quality + sea-zone control relation, rank naval orders:
SEARCH_PATROL, ESCORT, ASW, STRIKE, AMBUSH, SEARCH_AND_DESTROY.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from naval_basing import basing_repair_refuel_rates, level_rank  # type: ignore
from naval_fleet_ops import score_fleet_station_candidate  # type: ignore

# Base affinity by order when basing is strong vs weak / zone hostile
_ORDERS = (
    "SEARCH_PATROL",
    "ESCORT",
    "ASW",
    "STRIKE",
    "AMBUSH",
    "SEARCH_AND_DESTROY",
)


def score_naval_order(
    order: str,
    *,
    basing_level: str = "none",
    basing_capacity: int = 0,
    zone_relation: str = "no_zone",  # friendly|contested|hostile|neutral|no_zone
    fuel_level: float = 1.0,
) -> Dict[str, Any]:
    """Score one naval order for current basing + sealane context."""
    o = str(order or "SEARCH_PATROL").strip().upper()
    if o not in _ORDERS:
        o = "SEARCH_PATROL"
    rank = level_rank(basing_level)
    fuel = max(0.1, min(1.2, float(fuel_level)))
    rel = str(zone_relation or "no_zone").strip().lower()

    # Base scores
    base = {
        "SEARCH_PATROL": 50.0,
        "ESCORT": 48.0,
        "ASW": 45.0,
        "STRIKE": 55.0,
        "AMBUSH": 40.0,
        "SEARCH_AND_DESTROY": 52.0,
    }[o]

    # Strong basing favors strike/S&D readiness; weak favors patrol/escort near home
    if rank >= 3:  # major_base
        if o in ("STRIKE", "SEARCH_AND_DESTROY"):
            base += 25.0
        if o == "ASW":
            base += 10.0
    elif rank >= 2:  # port
        if o in ("ESCORT", "SEARCH_PATROL"):
            base += 15.0
        if o == "STRIKE":
            base += 10.0
    elif rank >= 1:  # anchorage
        if o in ("SEARCH_PATROL", "AMBUSH"):
            base += 12.0
        if o == "STRIKE":
            base -= 8.0
    else:
        if o in ("STRIKE", "SEARCH_AND_DESTROY"):
            base -= 20.0
        base += 5.0  # still allow light patrol

    # Zone relation
    if rel == "hostile":
        if o in ("STRIKE", "SEARCH_AND_DESTROY", "AMBUSH"):
            base += 18.0
        if o == "ESCORT":
            base += 8.0
    elif rel == "contested":
        if o in ("ESCORT", "ASW", "SEARCH_PATROL"):
            base += 16.0
    elif rel == "friendly":
        if o in ("SEARCH_PATROL", "ASW"):
            base += 10.0
        if o == "STRIKE":
            base += 5.0
    elif rel == "neutral":
        if o == "SEARCH_PATROL":
            base += 8.0

    # Fuel: low fuel discourages strike/S&D
    if fuel < 0.45:
        if o in ("STRIKE", "SEARCH_AND_DESTROY"):
            base -= 25.0
        if o in ("SEARCH_PATROL", "ESCORT"):
            base += 5.0
    base += float(basing_capacity) * 0.3
    base *= 0.85 + 0.15 * fuel

    return {
        "order": o,
        "score": float(base),
        "basing_level": basing_level,
        "zone_relation": rel,
        "fuel_level": fuel,
    }


def rank_naval_orders(
    basing: Optional[Mapping[str, Any]] = None,
    *,
    zone_relation: str = "no_zone",
    fuel_level: float = 1.0,
    orders: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Rank all (or given) naval orders; return best + ordered list."""
    b = dict(basing or {})
    lv = str(b.get("level", "none"))
    cap = int(b.get("capacity", 0) or 0)
    order_list = list(orders) if orders else list(_ORDERS)
    scored = [
        score_naval_order(
            o,
            basing_level=lv,
            basing_capacity=cap,
            zone_relation=zone_relation,
            fuel_level=fuel_level,
        )
        for o in order_list
    ]
    scored.sort(key=lambda x: (-float(x["score"]), x["order"]))
    best = scored[0] if scored else {}
    return {
        "best_order": str(best.get("order", "")),
        "best_score": float(best.get("score", 0.0)) if best else 0.0,
        "ranked": scored,
        "count": len(scored),
        "empty": len(scored) == 0,
        "summary": (
            "Fleet tasking prefer %s (score %.1f) · basing %s · zone %s"
            % (
                best.get("order", "?"),
                float(best.get("score", 0.0)),
                lv,
                zone_relation,
            )
        )
        if best
        else "Fleet tasking: no orders",
    }


def format_fleet_tasking_line(result: Mapping[str, Any]) -> str:
    if not result or result.get("empty"):
        return ""
    return str(result.get("summary", ""))
