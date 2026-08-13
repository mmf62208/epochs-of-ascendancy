"""Fleet campaign day: redeploy day · task group day · campaign compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity  # type: ignore
from fleet_redeploy_route import plan_fleet_redeploy_routes  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def fleet_redeploy_day(
    candidates: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    fuel_level: float = 0.65,
    origin_basing: str = "anchorage",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Fleet redeploy routes → station / fleet autonomy day apply."""
    cands = list(
        candidates
        or [
            {
                "province_id": province_id,
                "basing_level": "port",
                "fuel_level": fuel_level,
                "path_hostile_segments": 0,
                "path_length": 2,
                "zone_relation": "friendly",
                "origin_basing": origin_basing,
            },
            {
                "province_id": province_id + 1 if province_id else 2,
                "basing_level": "major_base",
                "fuel_level": fuel_level,
                "path_hostile_segments": 1,
                "path_length": 3,
                "zone_relation": "contested",
                "origin_basing": origin_basing,
            },
        ]
    )
    try:
        plan = plan_fleet_redeploy_routes(
            cands, fuel_level=fuel_level, origin_basing=origin_basing
        )
    except TypeError:
        try:
            plan = plan_fleet_redeploy_routes(cands, fuel_level, origin_basing)  # type: ignore
        except Exception:
            plan = {
                "best_score": 50.0,
                "best_province_id": province_id,
                "empty": False,
                "summary": "redeploy stub",
            }

    if plan.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    raw_score = _score(plan, "best_score", "score", default=50.0)
    # Redeploy scores are typically 30–80 scale
    score = min(1.0, max(0.05, raw_score / 100.0 if raw_score > 2.0 else raw_score))
    best_pid = int(plan.get("best_province_id", province_id) or province_id)
    if best_pid < 0:
        best_pid = province_id
    fuel = max(0.1, min(1.2, float(fuel_level)))
    apply_ready = score >= 0.35 and fuel >= 0.25

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": best_pid,
                "score": max(0.35, score),
                "enabled": True,
            }
        )
    if fuel < 0.55 or score < 0.45:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": best_pid,
                "score": max(0.3, 1.0 - fuel),
                "enabled": True,
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.35,
                "enabled": True,
            }
        )

    label = "Fleet redeploy day · best #%d · score %.2f · fuel %.0f%%" % (
        best_pid,
        score,
        fuel * 100.0,
    )
    return {
        "plan": plan,
        "best_province_id": best_pid,
        "score": score,
        "fuel_level": fuel,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "fleet_redeploy_day",
                "label": "Run fleet redeploy day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🚢 Fleet redeploy day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["redeploy_route", "station", "fleet_autonomy"],
    }


def fleet_task_group_day(
    *,
    available_strength: float = 100.0,
    mission: str = "patrol",
    zone_relation: str = "contested",
    escort_need: float = 0.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Task-group composition → station / fleet autonomy day apply."""
    try:
        tg = compose_task_group(
            available_strength=available_strength,
            mission=mission,
            zone_relation=zone_relation,
            escort_need=escort_need,
        )
    except TypeError:
        try:
            tg = compose_task_group(
                available_strength, mission, zone_relation, escort_need
            )  # type: ignore
        except Exception:
            tg = {
                "primary_role": "SCREEN",
                "available_strength": available_strength,
                "empty": False,
                "summary": "task group stub",
            }

    if tg.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    strength = max(0.0, float(tg.get("available_strength", available_strength) or 0.0))
    primary = str(tg.get("primary_role", "SCREEN") or "SCREEN")
    # Score from strength + mission urgency
    score = min(1.2, max(0.05, strength / 120.0 + 0.25))
    if str(zone_relation).lower() == "hostile":
        score = min(1.2, score + 0.15)
    if float(escort_need) >= 25.0:
        score = min(1.2, score + 0.1)
    apply_ready = strength >= 10.0

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": max(0.35, score),
                "enabled": True,
            }
        )
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": province_id,
                "score": max(0.3, score * 0.9),
                "enabled": True,
            }
        )
    if str(mission).lower() in ("convoy", "escort", "cover") or float(escort_need) >= 20.0:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.4,
                "enabled": True,
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.35,
                "enabled": True,
            }
        )

    label = "Fleet task group day · primary %s · strength %.0f · %s" % (
        primary,
        strength,
        str(mission or "patrol").lower(),
    )
    return {
        "task_group": tg,
        "primary_role": primary,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "fleet_task_group_day",
                "label": "Run fleet task group day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🚢 Fleet task group day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["task_group", "station", "fleet_autonomy"],
    }


def fleet_campaign_day(
    candidates: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    fuel_level: float = 0.65,
    origin_basing: str = "anchorage",
    available_strength: float = 100.0,
    mission: str = "patrol",
    zone_relation: str = "contested",
    escort_need: float = 0.0,
) -> Dict[str, Any]:
    """Compose fleet redeploy + task group into one day package."""
    redeploy = fleet_redeploy_day(
        candidates=candidates,
        fuel_level=fuel_level,
        origin_basing=origin_basing,
        province_id=province_id,
    )
    task = fleet_task_group_day(
        available_strength=available_strength,
        mission=mission,
        zone_relation=zone_relation,
        escort_need=escort_need,
        province_id=province_id,
    )

    apply_queue: List[Dict[str, Any]] = []
    for block in (redeploy, task):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (
            str(q.get("action_id")),
            int(q.get("province_id", -1)),
            str(q.get("focus_id", "")),
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    r_score = 0.0 if redeploy.get("empty") else _score(redeploy, "score")
    t_score = 0.0 if task.get("empty") else _score(task, "score")
    score = (r_score + t_score) / 2.0
    label = (
        "Fleet campaign day · redeploy %.2f · task %.2f · q %d"
        % (r_score, t_score, len(apply_queue))
    )
    return {
        "redeploy": redeploy,
        "task_group": task,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "fleet_campaign_day",
                "label": "Run fleet campaign day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(redeploy.get("summary", "")),
                str(task.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]⚓ Fleet campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet_redeploy", "fleet_task_group"],
    }


def fleet_campaign_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Fleet campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_fleet_campaign_day_loop(
    fuel_clear: float = 0.9,
    fuel_low: float = 0.35,
) -> Dict[str, Any]:
    r_c = fleet_redeploy_day(fuel_level=fuel_clear, province_id=1)
    r_l = fleet_redeploy_day(fuel_level=fuel_low, province_id=1)
    t_patrol = fleet_task_group_day(mission="patrol", zone_relation="friendly", available_strength=100.0)
    t_strike = fleet_task_group_day(
        mission="strike", zone_relation="hostile", available_strength=80.0, escort_need=30.0
    )
    day = fleet_campaign_day(fuel_level=fuel_clear, available_strength=100.0)
    gate = fleet_campaign_integrity()
    fuel_shift = abs(float(r_c.get("score", 0.5)) - float(r_l.get("score", 0.5)))
    task_shift = abs(float(t_patrol.get("score", 0.5)) - float(t_strike.get("score", 0.5)))
    label = (
        "Close fleet campaign · fuel Δ %.3f · task Δ %.3f · q %d · %s"
        % (
            fuel_shift,
            task_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "redeploy_clear": r_c,
        "redeploy_low": r_l,
        "task_patrol": t_patrol,
        "task_strike": t_strike,
        "day": day,
        "fuel_score_shift": fuel_shift,
        "task_score_shift": task_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close fleet campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
