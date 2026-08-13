"""Force readiness day: force posture · theater readiness · readiness compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity  # type: ignore
from campaign_cohesion import force_posture_board  # type: ignore
from integrated_theater_ops import (  # type: ignore
    theater_readiness_board,
    fleet_weather_mission_package,
    assault_readiness_compose,
)
from theater_ops_polish import campaign_day_risk  # type: ignore
from ops_depth import combat_phase_depth  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def force_posture_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    force_strength: float = 80.0,
    supply_health: float = 0.85,
    province_id: int = 1,
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Force×supply posture → station / assault / supply day apply."""
    w = dict(weather or {})
    try:
        board = force_posture_board(
            force_strength=force_strength,
            supply_health=supply_health,
            weather=w,
            fronts=fronts,
        )
    except TypeError:
        try:
            board = force_posture_board(force_strength, supply_health, w, fronts)  # type: ignore
        except Exception:
            board = {"score": 0.5, "empty": False, "summary": "posture stub"}

    score = _score(board, "score", "posture")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    supply_h = max(0.05, min(1.2, float(supply_health)))
    strain = max(0.0, 1.0 - supply_h)
    apply_ready = force_strength >= 20.0

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready and score >= 0.35:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": score >= 0.4 and supply_h >= 0.4,
            }
        )
    if strain >= 0.25 or supply_h < 0.7:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, strain),
                "enabled": True,
            }
        )
    apply_queue.append(
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": min(1.0, 0.3 + score * 0.5),
            "enabled": True,
        }
    )

    label = "Force posture day · force %.0f · supply %.0f%% · score %.2f" % (
        force_strength,
        supply_h * 100.0,
        score,
    )
    return {
        "board": board,
        "force_strength": force_strength,
        "supply_health": supply_h,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "force_posture_day",
                "label": "Run force posture day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]🛡 Force posture day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["force_supply", "station", "assault", "supply"],
    }


def theater_readiness_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    available_fleet: float = 80.0,
    attacker_power: float = 100.0,
) -> Dict[str, Any]:
    """Theater readiness board (fleet+wx · assault · day risk) → day apply."""
    w = dict(weather or {})
    precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)

    try:
        fleet = fleet_weather_mission_package(weather=w, available_strength=available_fleet)
    except Exception:
        try:
            fleet = fleet_weather_mission_package(w, available_fleet)  # type: ignore
        except Exception:
            fleet = {
                "score": 0.55 * vis * (1.0 - precip * 0.3),
                "summary": "fleet wx stub",
                "empty": False,
            }

    try:
        assault = assault_readiness_compose(
            weather=w, attacker_power=attacker_power, attacker_supply=0.85
        )
    except Exception:
        try:
            assault = assault_readiness_compose(w, attacker_power, 0.85)  # type: ignore
        except Exception:
            assault = {
                "score": 0.5 * vis,
                "summary": "assault ready stub",
                "empty": False,
            }

    try:
        day_risk = campaign_day_risk(weather=w)
    except Exception:
        try:
            day_risk = campaign_day_risk(w)  # type: ignore
        except Exception:
            risk = min(1.0, precip * 0.6 + (1.0 - vis) * 0.4)
            day_risk = {
                "score": 1.0 - risk,
                "risk": risk,
                "summary": "day risk stub",
                "empty": False,
            }

    try:
        board = theater_readiness_board(fleet, assault, day_risk)
    except TypeError:
        try:
            board = theater_readiness_board(
                fleet_package=fleet, assault=assault, day_risk=day_risk
            )
        except Exception:
            parts = [
                str(x.get("summary", ""))
                for x in (fleet, assault, day_risk)
                if isinstance(x, Mapping) and not x.get("empty")
            ]
            board = {
                "lines": parts,
                "count": len(parts),
                "empty": len(parts) == 0,
                "summary": "Theater readiness · %d signals" % len(parts),
            }

    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    f_s = _score(fleet, "score")
    a_s = _score(assault, "score")
    r_s = _score(day_risk, "score")
    if "risk" in day_risk and day_risk.get("score") is None:
        r_s = 1.0 - _score(day_risk, "risk", default=0.3)
    score = (f_s + a_s + r_s) / 3.0
    risk = max(0.0, min(1.0, 1.0 - r_s))

    apply_queue: List[Dict[str, Any]] = []
    if a_s >= 0.4 and risk < 0.65:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": a_s,
                "enabled": True,
            }
        )
    if f_s >= 0.35:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": province_id,
                "score": f_s,
                "enabled": True,
            }
        )
    if risk >= 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": risk,
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

    label = "Theater readiness day · fleet %.2f · assault %.2f · risk %.0f%%" % (
        f_s,
        a_s,
        risk * 100.0,
    )
    return {
        "board": board,
        "fleet": fleet,
        "assault": assault,
        "day_risk": day_risk,
        "score": score,
        "risk": risk,
        "apply_ready": risk < 0.85,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "theater_readiness_day",
                "label": "Run theater readiness day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]── Theater readiness day ──[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet_wx", "assault_ready", "day_risk", "apply"],
    }


def force_readiness_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    force_strength: float = 80.0,
    supply_health: float = 0.85,
    available_fleet: float = 80.0,
) -> Dict[str, Any]:
    """Compose force posture + theater readiness + combat phase depth."""
    w = dict(weather or {"precip_intensity": 0.0, "visibility": 1.0})
    posture = force_posture_day(
        weather=w,
        force_strength=force_strength,
        supply_health=supply_health,
        province_id=province_id,
    )
    readiness = theater_readiness_day(
        weather=w,
        province_id=province_id,
        available_fleet=available_fleet,
        attacker_power=force_strength,
    )
    try:
        phase = combat_phase_depth(
            weather=w,
            attacker_power=force_strength,
            defender_power=70.0,
            attacker_supply=supply_health,
        )
    except Exception:
        try:
            phase = combat_phase_depth(force_strength, 70.0, supply_health, 1.0)  # type: ignore
        except Exception:
            vis = float(w.get("visibility", 1.0) or 1.0)
            phase = {
                "score": 0.5 * vis,
                "summary": "phase depth stub",
                "empty": False,
            }

    apply_queue: List[Dict[str, Any]] = []
    for block in (posture, readiness):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    p_score = _score(phase, "score")
    if p_score >= 0.45 and not readiness.get("empty"):
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": p_score,
                "enabled": True,
                "domain": "phase_depth",
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
        _score(posture, "score"),
        0.0 if readiness.get("empty") else _score(readiness, "score"),
        _score(phase, "score"),
    ]
    score = sum(scores) / 3.0
    label = (
        "Force readiness day · posture %.2f · theater %.2f · phase %.2f · q %d"
        % (scores[0], scores[1], scores[2], len(apply_queue))
    )
    return {
        "posture": posture,
        "readiness": readiness,
        "phase": phase,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "force_readiness_day",
                "label": "Run force readiness day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(posture.get("summary", "")),
                str(readiness.get("summary", "")),
                str(phase.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#6eb5ff]🎖 Force readiness day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["force_posture", "theater_readiness", "combat_phase"],
    }


def force_readiness_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Force readiness integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_force_readiness_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2}
    foul = {"precip_intensity": 0.9, "visibility": 0.25, "wind": 0.8, "ground_state": "mud"}
    p_c = force_posture_day(weather=clear, force_strength=80.0, supply_health=0.9)
    p_f = force_posture_day(weather=foul, force_strength=80.0, supply_health=0.55)
    t_c = theater_readiness_day(weather=clear)
    t_f = theater_readiness_day(weather=foul)
    day = force_readiness_day(weather=weather or clear)
    gate = force_readiness_integrity()
    wx_shift = abs(float(t_c.get("score", 0.5)) - float(t_f.get("score", 0.5)))
    supply_shift = abs(float(p_c.get("score", 0.5)) - float(p_f.get("score", 0.5)))
    label = (
        "Close force readiness · theater Δwx %.3f · posture Δsupply %.3f · q %d · %s"
        % (
            wx_shift,
            supply_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "posture_clear": p_c,
        "posture_strained": p_f,
        "theater_clear": t_c,
        "theater_foul": t_f,
        "day": day,
        "weather_score_shift": wx_shift,
        "supply_score_shift": supply_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Close readiness[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
