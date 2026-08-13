"""Joint campaign day: naval campaign · air-land joint · leader campaign compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity  # type: ignore
from campaign_cohesion import (  # type: ignore
    naval_campaign_package,
    air_land_joint_package,
    leader_campaign_assign,
)


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def naval_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Naval campaign package → fleet autonomy / station / supply day apply."""
    w = dict(weather or {})
    try:
        pkg = naval_campaign_package(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=w,
        )
    except TypeError:
        try:
            pkg = naval_campaign_package(
                basing_level, fuel_level, available_strength, zone_relation, w
            )  # type: ignore
        except Exception:
            pkg = {"score": 0.55, "empty": False, "summary": "naval campaign stub"}

    score = _score(pkg, "score")
    if score > 2.0:
        score = min(1.0, score / 10.0 if score > 10 else score / 100.0)
    fuel = max(0.05, min(1.2, float(fuel_level)))
    apply_ready = fuel >= 0.2 and available_strength >= 15.0

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready and score >= 0.35:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "order": "patrol",
            }
        )
    apply_queue.append(
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": min(1.0, 0.35 + score * 0.4),
            "enabled": True,
        }
    )
    if fuel < 0.55 or score < 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - fuel),
                "enabled": True,
            }
        )

    label = "Naval campaign day · score %.2f · fuel %.0f%% · basing %s" % (
        score,
        fuel * 100.0,
        basing_level,
    )
    return {
        "package": pkg,
        "score": score,
        "fuel_level": fuel,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "naval_campaign_day",
                "label": "Run naval campaign day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]🚢 Naval campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["naval_campaign", "fleet", "station", "supply"],
    }


def air_land_joint_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Air-land joint package → assault / focus day apply."""
    w = dict(weather or {})
    tgts = list(targets or [{"id": province_id, "power": 40.0, "province_id": province_id}])
    try:
        pkg = air_land_joint_package(
            weather=w,
            month=month,
            targets=tgts,
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
        )
    except TypeError:
        try:
            pkg = air_land_joint_package(w, month, tgts, attacker_power, attacker_supply)  # type: ignore
        except Exception:
            pkg = {"score": 0.5, "empty": False, "summary": "air-land stub"}

    score = _score(pkg, "score")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    air = pkg.get("air") if isinstance(pkg.get("air"), Mapping) else {}
    grounded = bool(air.get("grounded", False)) if air else False
    vis = float(w.get("visibility", 1.0) or 1.0)
    apply_ready = not grounded and score >= 0.3

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready and score >= 0.4:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
            }
        )
    if grounded or vis < 0.45:
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.4,
                "focus_id": "military_effort" if grounded else "industrial_effort",
                "enabled": True,
            }
        )
    if attacker_supply < 0.7:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - attacker_supply),
                "enabled": True,
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.4,
                "enabled": True,
            }
        )

    label = "Air-land joint day · score %.2f · %s · supply %.0f%%" % (
        score,
        "GROUNDED" if grounded else "flyable",
        attacker_supply * 100.0,
    )
    return {
        "package": pkg,
        "grounded": grounded,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "air_land_joint_day",
                "label": "Run air-land joint day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6ec8ff]✈ Air-land joint day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["air_land_joint", "assault", "focus"],
    }


def joint_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    month: int = 6,
    fuel_level: float = 0.55,
    leader_skill: float = 0.65,
    attacker_power: float = 100.0,
) -> Dict[str, Any]:
    """Compose naval campaign + air-land joint + leader assign into one day."""
    w = dict(weather or {"precip_intensity": 0.0, "visibility": 1.0})
    naval = naval_campaign_day(
        weather=w, fuel_level=fuel_level, province_id=province_id
    )
    air_land = air_land_joint_day(
        weather=w,
        month=month,
        attacker_power=attacker_power,
        province_id=province_id,
    )
    try:
        leader = leader_campaign_assign(leader_skill=leader_skill, weather=w)
    except TypeError:
        try:
            leader = leader_campaign_assign(leader_skill, w)  # type: ignore
        except Exception:
            leader = {"score": leader_skill, "empty": False, "summary": "leader stub"}

    apply_queue: List[Dict[str, Any]] = []
    for block in (naval, air_land):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    l_score = _score(leader, "score")
    if l_score >= 0.4:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": min(1.0, l_score),
                "enabled": True,
                "domain": "leader",
            }
        )

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)), str(q.get("domain", "")))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    scores = [
        _score(naval, "score"),
        _score(air_land, "score"),
        l_score,
    ]
    score = sum(scores) / 3.0
    label = (
        "Joint campaign day · naval %.2f · air-land %.2f · leader %.2f · q %d"
        % (scores[0], scores[1], scores[2], len(apply_queue))
    )
    return {
        "naval": naval,
        "air_land": air_land,
        "leader": leader,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "joint_campaign_day",
                "label": "Run joint campaign day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(naval.get("summary", "")),
                str(air_land.get("summary", "")),
                str(leader.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#6eb5ff]🎖 Joint campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["naval_campaign", "air_land_joint", "leader_campaign"],
    }


def joint_campaign_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Joint campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_joint_campaign_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2}
    foul = {"precip_intensity": 0.9, "visibility": 0.25, "wind": 0.85, "ground_state": "mud"}
    n_c = naval_campaign_day(weather=clear, fuel_level=0.7)
    n_f = naval_campaign_day(weather=foul, fuel_level=0.35)
    a_c = air_land_joint_day(weather=clear)
    a_f = air_land_joint_day(weather=foul)
    day = joint_campaign_day(weather=weather or clear)
    gate = joint_campaign_integrity()
    wx_shift = abs(float(a_c.get("score", 0.5)) - float(a_f.get("score", 0.5)))
    fuel_shift = abs(float(n_c.get("score", 0.5)) - float(n_f.get("score", 0.5)))
    label = (
        "Close joint campaign · air-land Δwx %.3f · naval Δfuel %.3f · q %d · %s"
        % (
            wx_shift,
            fuel_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "naval_clear": n_c,
        "naval_strained": n_f,
        "air_clear": a_c,
        "air_foul": a_f,
        "day": day,
        "weather_score_shift": wx_shift,
        "fuel_score_shift": fuel_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Close joint campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
