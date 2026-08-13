"""Convoy escort assignment pilot (not full fleet AI).

Scores escort value for a trade/supply route using basing quality along path
and sea-zone control relations.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence


def score_convoy_escort_need(
    path_zone_relations: Sequence[str],
    *,
    cargo_value: float = 100.0,
    interdiction_chance: float = 0.1,
) -> Dict[str, Any]:
    """Higher need when path has hostile/contested sealanes + valuable cargo."""
    rels = [str(r or "no_zone").lower() for r in (path_zone_relations or [])]
    hostile = sum(1 for r in rels if r == "hostile")
    contested = sum(1 for r in rels if r == "contested")
    friendly = sum(1 for r in rels if r == "friendly")
    n = max(1, len(rels))
    risk = (hostile * 1.0 + contested * 0.6) / float(n)
    risk = min(1.0, risk + max(0.0, float(interdiction_chance)))
    need = risk * max(0.0, float(cargo_value)) * (1.0 + 0.15 * hostile)
    # Friendly path slightly reduces need
    need *= max(0.4, 1.0 - 0.1 * friendly / float(n))
    return {
        "escort_need": float(need),
        "risk": float(risk),
        "hostile_segments": hostile,
        "contested_segments": contested,
        "friendly_segments": friendly,
        "recommend_escort": need >= 25.0,
        "summary": (
            "escort need %.1f (risk %.2f · H%d C%d F%d)"
            % (need, risk, hostile, contested, friendly)
        ),
    }


def assign_escort_strength(
    escort_need: float,
    available_fleet_strength: float,
    *,
    basing_refuel: float = 0.25,
) -> Dict[str, Any]:
    """Assign escort strength from available fleet given need and basing support."""
    need = max(0.0, float(escort_need))
    avail = max(0.0, float(available_fleet_strength))
    support = max(0.5, min(1.5, 0.7 + float(basing_refuel)))
    desired = need * 0.15 * support
    assigned = min(avail, desired)
    coverage = assigned / desired if desired > 1e-6 else 1.0
    return {
        "desired": float(desired),
        "assigned": float(assigned),
        "coverage": float(min(1.5, coverage)),
        "sufficient": coverage >= 0.8,
        "summary": "escort assign %.1f/%.1f (coverage %.0f%%)"
        % (assigned, desired, min(150.0, coverage * 100.0)),
    }


def plan_convoy_escort(
    path_zone_relations: Sequence[str],
    available_fleet_strength: float,
    *,
    cargo_value: float = 100.0,
    interdiction_chance: float = 0.1,
    basing_refuel: float = 0.25,
) -> Dict[str, Any]:
    need = score_convoy_escort_need(
        path_zone_relations,
        cargo_value=cargo_value,
        interdiction_chance=interdiction_chance,
    )
    assign = assign_escort_strength(
        need["escort_need"],
        available_fleet_strength,
        basing_refuel=basing_refuel,
    )
    return {
        "need": need,
        "assign": assign,
        "recommend_escort": bool(need["recommend_escort"]),
        "sufficient": bool(assign["sufficient"]),
        "summary": "%s · %s" % (need["summary"], assign["summary"]),
    }
