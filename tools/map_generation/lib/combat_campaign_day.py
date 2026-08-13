"""Combat campaign day: combat ops · move path · campaign compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity, move_path_ops_loop  # type: ignore
from campaign_cohesion import combat_campaign_phase  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def combat_ops_day(
    weather: Optional[Mapping[str, Any]] = None,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    month: int = 6,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Combat campaign phase → assault / supply day apply."""
    w = dict(weather or {})
    tgts = list(
        targets
        or [
            {
                "id": province_id,
                "province_id": province_id,
                "power": 40.0,
                "defender_power": 40.0,
                "supply": 0.7,
            }
        ]
    )
    try:
        phase = combat_campaign_phase(
            targets=tgts,
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
            weather=w,
            month=month,
        )
    except TypeError:
        try:
            phase = combat_campaign_phase(
                tgts, attacker_power, attacker_supply, w, month
            )  # type: ignore
        except Exception:
            phase = {"score": 0.5, "empty": False, "summary": "combat ops stub"}

    if phase.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _score(phase, "score")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    supply = max(0.05, min(1.2, float(attacker_supply)))
    apply_ready = score >= 0.3 and supply >= 0.35

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
    if supply < 0.75 or score < 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - supply),
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

    label = "Combat ops day · score %.2f · supply %.0f%% · power %.0f" % (
        score,
        supply * 100.0,
        attacker_power,
    )
    return {
        "phase": phase,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "combat_ops_day",
                "label": "Run combat ops day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#ff9a6e]⚔ Combat ops day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["combat_campaign", "assault", "supply"],
    }


def move_path_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_cost: float = 1.0,
    supply_health: float = 0.85,
    armored: bool = False,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Move path ops loop → station / supply day apply when costly."""
    w = dict(weather or {})
    ground = str(w.get("ground_state", "dry") or "dry")
    vis = float(w.get("visibility", 1.0) or 1.0)
    try:
        path = move_path_ops_loop(
            base_cost=base_cost,
            weather=w,
            supply_health=supply_health,
            armored=armored,
        )
    except TypeError:
        try:
            path = move_path_ops_loop(
                base_cost, ground, vis, supply_health, armored
            )  # type: ignore
        except Exception:
            path = {
                "path_cost": base_cost,
                "summary": "move path stub",
                "empty": False,
            }

    cost = _score(path, "path_cost", "cost", default=base_cost)
    supply_h = max(0.15, min(1.5, float(supply_health)))
    # Higher cost / lower supply → more day urgency
    urgency = min(1.2, max(0.05, (cost - 0.8) * 0.5 + max(0.0, 1.0 - supply_h) * 0.6 + 0.25))
    score = urgency

    apply_queue: List[Dict[str, Any]] = []
    if cost >= 1.15 or supply_h < 0.7:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, urgency),
                "enabled": True,
            }
        )
    apply_queue.append(
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": min(1.0, 0.3 + urgency * 0.5),
            "enabled": True,
        }
    )
    if cost >= 1.4:
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.4,
                "focus_id": "military_effort",
                "enabled": True,
            }
        )

    label = "Move path day · cost %.2f · supply %.0f%% · urgency %.2f" % (
        cost,
        supply_h * 100.0,
        urgency,
    )
    return {
        "path": path,
        "path_cost": cost,
        "supply_health": supply_h,
        "score": score,
        "apply_ready": True,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "move_path_day",
                "label": "Run move path day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]🥾 Move path day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["move_path", "station", "supply"],
    }


def combat_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    month: int = 6,
) -> Dict[str, Any]:
    """Compose combat ops + move path into one day package."""
    w = dict(weather or {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"})
    combat = combat_ops_day(
        weather=w,
        targets=targets,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        month=month,
        province_id=province_id,
    )
    move = move_path_day(
        weather=w,
        supply_health=attacker_supply,
        province_id=province_id,
    )

    apply_queue: List[Dict[str, Any]] = []
    for block in (combat, move):
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

    c_score = 0.0 if combat.get("empty") else _score(combat, "score")
    m_score = _score(move, "score")
    score = (c_score + m_score) / 2.0
    label = (
        "Combat campaign day · combat %.2f · move %.2f · q %d"
        % (c_score, m_score, len(apply_queue))
    )
    return {
        "combat": combat,
        "move": move,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "combat_campaign_day",
                "label": "Run combat campaign day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(combat.get("summary", "")),
                str(move.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#ff9a6e]⚔ Combat campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["combat_ops", "move_path"],
    }


def combat_campaign_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Combat campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_combat_campaign_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"}
    foul = {
        "precip_intensity": 0.85,
        "visibility": 0.3,
        "ground_state": "mud",
        "wind": 0.8,
    }
    c_c = combat_ops_day(weather=clear, attacker_supply=0.9)
    c_f = combat_ops_day(weather=foul, attacker_supply=0.45)
    m_c = move_path_day(weather=clear, supply_health=0.95)
    m_f = move_path_day(weather=foul, supply_health=0.4)
    day = combat_campaign_day(weather=weather or clear)
    gate = combat_campaign_integrity()
    wx_shift = abs(float(c_c.get("score", 0.5)) - float(c_f.get("score", 0.5)))
    move_shift = abs(float(m_c.get("score", 0.3)) - float(m_f.get("score", 0.6)))
    label = (
        "Close combat campaign · combat Δ %.3f · move Δ %.3f · q %d · %s"
        % (
            wx_shift,
            move_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "combat_clear": c_c,
        "combat_foul": c_f,
        "move_clear": m_c,
        "move_foul": m_f,
        "day": day,
        "weather_score_shift": wx_shift,
        "move_score_shift": move_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#ff9a6e]✓ Close combat campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
