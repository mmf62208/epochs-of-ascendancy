"""Naval fleet-ops pilot: station preference by basing tier (not full fleet AI).

Ranks candidate coastal/port provinces for fleet basing/stationing using
existing naval basing levels. Pure decision helper for tests + GD mirror.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from naval_basing import (  # type: ignore
    LEVEL_ANCHORAGE,
    LEVEL_MAJOR,
    LEVEL_NONE,
    LEVEL_PORT,
    basing_from_province_signals,
    basing_repair_refuel_rates,
    compute_naval_basing,
    level_rank,
)


def score_fleet_station_candidate(
    basing: Mapping[str, Any],
    *,
    is_owned: bool = True,
    is_enemy: bool = False,
    distance_penalty: float = 0.0,
    has_treaty_basing: bool = False,
) -> Dict[str, Any]:
    """Score one basing-shaped province for fleet station preference.

    Higher score = better basing for friendly fleets.
    Enemy / none basing score very low.
    Treaty basing (DOCKING_RIGHTS graph) nearly matches owned access.
    """
    b = dict(basing or {})
    lv = str(b.get("level", LEVEL_NONE))
    cap = int(b.get("capacity", 0) or 0)
    rates = basing_repair_refuel_rates(b)
    rank = level_rank(lv)
    score = float(rank * 100 + cap * 2)
    if bool(rates.get("can_service")):
        score += float(rates.get("refuel_rate", 0.0)) * 50.0
        score += float(rates.get("repair_org_rate", 0.0)) * 100.0
    treaty = bool(has_treaty_basing) and not bool(is_owned)
    if not is_owned:
        if treaty:
            # Foreign port with docking rights — nearly as useful as owned
            score *= 0.88
            score += 40.0
        else:
            score *= 0.35
    if is_enemy and not treaty:
        score = -abs(score) - 50.0
    if lv == LEVEL_NONE:
        score = min(score, 0.0)
    score -= max(0.0, float(distance_penalty))
    return {
        "province_id": int(b.get("province_id", 0) or 0),
        "level": lv,
        "capacity": cap,
        "score": float(score),
        "can_service": bool(rates.get("can_service", False)),
        "refuel_rate": float(rates.get("refuel_rate", 0.0)),
        "label": str(b.get("label", lv)),
        "is_owned": bool(is_owned),
        "is_enemy": bool(is_enemy),
        "has_treaty_basing": treaty,
    }


def rank_fleet_station_candidates(
    candidates: Sequence[Mapping[str, Any]],
    *,
    prefer_owned: bool = True,
) -> Dict[str, Any]:
    """Rank basing candidates; return best + ordered list.

    Each candidate: province_id, basing dict or domain/port signals, optional is_owned/is_enemy.
    """
    scored: List[Dict[str, Any]] = []
    for c in candidates or []:
        if not isinstance(c, dict):
            continue
        basing = c.get("basing")
        if not isinstance(basing, dict) or not basing:
            basing = basing_from_province_signals(c) if c.get("domain") or c.get("is_coastal") else compute_naval_basing(
                domain=str(c.get("domain", "")),
                is_coastal=bool(c.get("is_coastal", False)),
                has_port=bool(c.get("has_port", False)),
                port_tier=int(c.get("port_tier", 0) or 0),
                has_naval_shipyard=bool(c.get("has_naval_shipyard", False)),
                is_chokepoint=bool(c.get("is_chokepoint", False)),
                facility_tier=str(c.get("facility_tier", "")),
                in_sea_zone=bool(c.get("in_sea_zone", False)),
                province_id=int(c.get("province_id", 0) or 0),
            )
        if "province_id" not in basing or not basing.get("province_id"):
            basing = dict(basing)
            basing["province_id"] = int(c.get("province_id", 0) or 0)
        sc = score_fleet_station_candidate(
            basing,
            is_owned=bool(c.get("is_owned", True if prefer_owned else True)),
            is_enemy=bool(c.get("is_enemy", False)),
            distance_penalty=float(c.get("distance_penalty", 0.0) or 0.0),
            has_treaty_basing=bool(c.get("has_treaty_basing", False)),
        )
        scored.append(sc)
    scored.sort(key=lambda x: (-float(x["score"]), int(x.get("province_id", 0))))
    best = scored[0] if scored else {}
    return {
        "count": len(scored),
        "best": best,
        "best_province_id": int(best.get("province_id", -1)) if best else -1,
        "best_level": str(best.get("level", LEVEL_NONE)) if best else LEVEL_NONE,
        "best_score": float(best.get("score", 0.0)) if best else 0.0,
        "ranked": scored,
        "empty": len(scored) == 0,
    }


def format_fleet_station_preference(rank_result: Mapping[str, Any]) -> str:
    """Plain one-line preference for inspector/debug."""
    if not rank_result or rank_result.get("empty"):
        return "Fleet basing: no candidates"
    best = rank_result.get("best") or {}
    treaty = " · treaty basing" if best.get("has_treaty_basing") else ""
    return (
        "Fleet basing prefer #%s · %s · score %.1f · refuel %.2f/d%s"
        % (
            best.get("province_id", "?"),
            best.get("level", "none"),
            float(best.get("score", 0.0)),
            float(best.get("refuel_rate", 0.0)),
            treaty,
        )
    )


def treaty_basing_beats_unowned_foreign(
    owned_anchorage: Mapping[str, Any],
    foreign_major: Mapping[str, Any],
) -> Dict[str, Any]:
    """Prove docking treaty tips preference toward foreign major base over owned anchorage."""
    s_owned = score_fleet_station_candidate(owned_anchorage, is_owned=True)
    s_foreign_raw = score_fleet_station_candidate(foreign_major, is_owned=False, has_treaty_basing=False)
    s_treaty = score_fleet_station_candidate(foreign_major, is_owned=False, has_treaty_basing=True)
    ok = (
        float(s_treaty["score"]) > float(s_owned["score"])
        and float(s_treaty["score"]) > float(s_foreign_raw["score"])
        and bool(s_treaty.get("has_treaty_basing"))
    )
    return {
        "ok": ok,
        "owned_score": float(s_owned["score"]),
        "foreign_raw_score": float(s_foreign_raw["score"]),
        "treaty_score": float(s_treaty["score"]),
        "prefer_treaty": float(s_treaty["score"]) >= float(s_owned["score"]),
    }
