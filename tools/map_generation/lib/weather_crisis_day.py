"""Weather crisis day: ground transition · fog/air crisis · crisis compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from gameplay_loops import sole_mult_integrity  # type: ignore
from weather_ops_polish import (  # type: ignore
    freeze_thaw_transition,
    infra_weather_wear,
    coastal_fog_naval_gate,
    air_grounding_alert,
    weather_pressure_index,
)


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def ground_transition_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Freeze/thaw + infra wear → station / supply / focus day apply."""
    w = dict(weather or {})
    ground = str(w.get("ground_state", "dry") or "dry")
    temp = float(w.get("temperature_c", w.get("temp", 10.0)) or 10.0)
    precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)

    try:
        ft = freeze_thaw_transition(ground, temp, precip)
    except TypeError:
        try:
            ft = freeze_thaw_transition(
                current_ground=ground, temp=temp, precip_intensity=precip
            )
        except Exception:
            ft = {
                "from": ground,
                "to": ground,
                "changed": False,
                "note": "stable",
                "summary": "ground stub",
                "empty": False,
            }

    try:
        wear = infra_weather_wear(w)
    except TypeError:
        try:
            wear = infra_weather_wear(weather=w)
        except Exception:
            wear = {"wear_factor": 1.0, "summary": "wear stub", "empty": False}

    changed = bool(ft.get("changed", False))
    wear_f = _score(wear, "wear_factor", default=1.0)
    if wear_f > 2.0:
        wear_f = min(1.2, wear_f)
    # Higher score = more crisis / need for action
    crisis = (0.55 if changed else 0.15) + max(0.0, 1.0 - wear_f) * 0.7
    crisis = max(0.05, min(1.2, crisis))
    score = crisis

    apply_queue: List[Dict[str, Any]] = []
    if changed or wear_f < 0.92:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": max(0.35, crisis),
                "enabled": True,
            }
        )
    if wear_f < 0.9 or precip > 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - wear_f + precip * 0.2),
                "enabled": True,
            }
        )
    if changed and str(ft.get("note", "")) in ("thaw", "freeze-in", "snowfall"):
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.4,
                "focus_id": "industrial_effort",
                "enabled": True,
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.35,
                "enabled": True,
            }
        )

    label = "Ground transition day · %s · wear×%.2f · crisis %.2f" % (
        str(ft.get("summary", ft.get("plain", "ground"))),
        wear_f,
        crisis,
    )
    return {
        "freeze_thaw": ft,
        "wear": wear,
        "changed": changed,
        "wear_factor": wear_f,
        "score": score,
        "apply_ready": True,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "ground_transition_day",
                "label": "Run ground transition day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]❄ Ground transition day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["freeze_thaw", "infra_wear", "station", "supply"],
    }


def fog_air_crisis_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Coastal fog gate + air grounding alert → fleet / focus / supply day apply."""
    w = dict(weather or {})
    try:
        fog = coastal_fog_naval_gate(w)
    except TypeError:
        try:
            fog = coastal_fog_naval_gate(weather=w)
        except Exception:
            vis = float(w.get("visibility", 1.0) or 1.0)
            fog = {
                "fog": vis < 0.4,
                "ops_mult": max(0.1, vis),
                "summary": "fog stub",
                "empty": False,
            }

    try:
        air = air_grounding_alert(w)
    except TypeError:
        try:
            air = air_grounding_alert(weather=w)
        except Exception:
            air = {"grounded": False, "empty": True, "effectiveness": 1.0}

    fog_on = bool(fog.get("fog", False))
    grounded = bool(air.get("grounded", False))
    air_empty = bool(air.get("empty", True)) and not grounded
    ops = _score(fog, "ops_mult", default=1.0)
    eff = _score(air, "effectiveness", default=1.0)
    if not air_empty:
        crisis = (0.5 if fog_on else 0.15) + (0.45 if grounded else max(0.0, 0.5 - eff) * 0.5)
    else:
        crisis = 0.45 if fog_on else 0.1
    crisis = max(0.05, min(1.2, crisis))

    if not fog_on and air_empty and crisis < 0.2:
        # Fair weather: still return non-empty day with mild hold actions
        pass

    apply_queue: List[Dict[str, Any]] = []
    if fog_on:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": province_id,
                "score": max(0.4, 1.0 - ops),
                "enabled": True,
                "order": "hold",
            }
        )
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - ops),
                "enabled": True,
            }
        )
    if grounded or (not air_empty and eff < 0.5):
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.45,
                "focus_id": "military_effort",
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

    label = "Fog/air crisis day · fog=%s · grounded=%s · ops×%.2f · crisis %.2f" % (
        "yes" if fog_on else "no",
        "yes" if grounded else "no",
        ops,
        crisis,
    )
    return {
        "fog": fog,
        "air": air,
        "fog_closed": fog_on,
        "grounded": grounded,
        "score": crisis,
        "apply_ready": True,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "fog_air_crisis_day",
                "label": "Run fog/air crisis day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#f87171]🌫 Fog/air crisis day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["coastal_fog", "air_grounding", "fleet", "focus"],
    }


def weather_crisis_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Compose ground transition + fog/air crisis + pressure index."""
    w = dict(
        weather
        or {
            "precip_intensity": 0.0,
            "visibility": 1.0,
            "temperature_c": 10.0,
            "ground_state": "dry",
        }
    )
    ground = ground_transition_day(weather=w, province_id=province_id)
    fog_air = fog_air_crisis_day(weather=w, province_id=province_id)
    try:
        pressure = weather_pressure_index(w)
    except TypeError:
        try:
            pressure = weather_pressure_index(weather=w)
        except Exception:
            pressure = {"pressure": 0.2, "summary": "pressure stub", "empty": False}

    p = _score(pressure, "pressure", "score", default=0.2)
    if p > 2.0:
        p = min(1.0, p)

    apply_queue: List[Dict[str, Any]] = []
    for block in (ground, fog_air):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    if p >= 0.55:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": p,
                "enabled": True,
                "domain": "pressure",
            }
        )

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (
            str(q.get("action_id")),
            int(q.get("province_id", -1)),
            str(q.get("domain", "")),
            str(q.get("focus_id", "")),
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    scores = [
        _score(ground, "score"),
        _score(fog_air, "score"),
        p,
    ]
    score = sum(scores) / 3.0
    label = (
        "Weather crisis day · ground %.2f · fog/air %.2f · pressure %.2f · q %d"
        % (scores[0], scores[1], scores[2], len(apply_queue))
    )
    return {
        "ground": ground,
        "fog_air": fog_air,
        "pressure": pressure,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "weather_crisis_day",
                "label": "Run weather crisis day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(ground.get("summary", "")),
                str(fog_air.get("summary", "")),
                str(pressure.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#f87171]⛈ Weather crisis day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["ground_transition", "fog_air_crisis", "pressure"],
    }


def weather_crisis_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Weather crisis integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_weather_crisis_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {
        "precip_intensity": 0.0,
        "visibility": 1.0,
        "temperature_c": 12.0,
        "ground_state": "dry",
        "wind": 0.2,
    }
    foul = {
        "precip_intensity": 0.9,
        "visibility": 0.25,
        "temperature_c": -8.0,
        "ground_state": "mud",
        "wind": 0.9,
    }
    g_c = ground_transition_day(weather=clear)
    g_f = ground_transition_day(weather=foul)
    f_c = fog_air_crisis_day(weather=clear)
    f_f = fog_air_crisis_day(weather=foul)
    day = weather_crisis_day(weather=weather or foul)
    gate = weather_crisis_integrity()
    wx_shift = abs(float(f_c.get("score", 0.1)) - float(f_f.get("score", 0.5)))
    ground_shift = abs(float(g_c.get("score", 0.1)) - float(g_f.get("score", 0.5)))
    label = (
        "Close weather crisis · fog/air Δ %.3f · ground Δ %.3f · q %d · %s"
        % (
            wx_shift,
            ground_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "ground_clear": g_c,
        "ground_foul": g_f,
        "fog_clear": f_c,
        "fog_foul": f_f,
        "day": day,
        "weather_score_shift": wx_shift,
        "ground_score_shift": ground_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#f87171]✓ Close weather crisis[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
