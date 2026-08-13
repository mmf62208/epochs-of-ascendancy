"""Industry surge day: production surge · depot capacity · industry compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from gameplay_loops import sole_mult_integrity  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore
from priority_systems import industry_economy_depth  # type: ignore
from theater_ops_polish import production_weather_alert, depot_weather_capacity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def production_surge_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    line_id: str = "primary",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Production priority + weather alert → surge/shield apply day."""
    w = dict(weather or {})
    try:
        mut = production_priority_mutation(
            weather=w, base_output=base_output, line_id=line_id
        )
    except TypeError:
        try:
            mut = production_priority_mutation(w, base_output, line_id)  # type: ignore
        except Exception:
            mut = {"score": 0.5, "plan": {"priority": "MONITOR", "enabled": False}, "empty": False}

    try:
        alert = production_weather_alert(w)
    except Exception:
        precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)
        mult = max(0.2, 1.0 - precip * 0.5)
        alert = {
            "alert": mult < 0.85,
            "mult": mult,
            "empty": mult >= 0.85,
            "summary": "prod alert stub",
        }

    plan = mut.get("plan") if isinstance(mut.get("plan"), Mapping) else {}
    priority = str(plan.get("priority", mut.get("priority", "MONITOR")) or "MONITOR")
    score = _score(mut, "score")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    alert_on = bool(alert.get("alert", not alert.get("empty", True)))
    prod_mult = _score(alert, "mult", default=1.0)
    if prod_mult > 2.0:
        prod_mult = min(1.2, prod_mult)

    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_production",
            "province_id": province_id,
            "score": max(0.35, score),
            "line_id": line_id,
            "priority": priority,
            "enabled": True,
        }
    ]
    if alert_on or priority in ("SHIELD", "SURGE"):
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.45,
                "focus_id": "industrial_effort",
                "enabled": True,
            }
        )
    if alert_on:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - prod_mult),
                "enabled": True,
            }
        )

    label = "Production surge day · priority %s · out×%.2f · alert=%s" % (
        priority,
        prod_mult,
        "yes" if alert_on else "no",
    )
    return {
        "mutation": mut,
        "alert": alert,
        "priority": priority,
        "prod_mult": prod_mult,
        "score": score * (0.75 if alert_on else 1.0),
        "apply_ready": True,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "production_surge_day",
                "label": "Run production surge day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6ec8ff]🏭 Production surge day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["production_priority", "weather_alert", "apply"],
    }


def depot_capacity_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_capacity: float = 100.0,
    sea_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Depot weather capacity + supply sustain day."""
    w = dict(weather or {})
    ground = str(w.get("ground_state", "dry") or "dry")
    precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)
    try:
        depot = depot_weather_capacity(weather=w, base_capacity=base_capacity)
    except TypeError:
        try:
            depot = depot_weather_capacity(w, base_capacity)  # type: ignore
        except Exception:
            mult = max(0.2, 1.0 - precip * 0.4)
            if ground == "mud":
                mult *= 0.85
            depot = {
                "capacity": base_capacity * mult,
                "weather_mult": mult,
                "summary": "depot stub",
                "empty": False,
            }

    cap = _score(depot, "capacity", default=base_capacity)
    wx_m = _score(depot, "weather_mult", default=1.0)
    fill_pressure = max(0.0, min(1.0, 1.0 - (cap / max(10.0, base_capacity))))
    sea = max(0.2, min(1.5, float(sea_mult)))
    score = (wx_m * 0.55 + min(1.2, sea) * 0.45) * (1.0 - fill_pressure * 0.35)
    apply_ready = cap >= 15.0

    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.35, 1.0 - score + 0.2),
            "enabled": True,
        }
    ]
    if fill_pressure >= 0.25 or precip > 0.45:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.4 + fill_pressure * 0.3,
                "enabled": True,
            }
        )
    if sea < 0.75:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "order": "escort",
            }
        )

    label = "Depot capacity day · cap %.0f (base %.0f · wx×%.2f) · sea×%.2f" % (
        cap,
        base_capacity,
        wx_m,
        sea,
    )
    return {
        "depot": depot,
        "capacity": cap,
        "weather_mult": wx_m,
        "sea_mult": sea,
        "fill_pressure": fill_pressure,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "depot_capacity_day",
                "label": "Run depot capacity day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]📦 Depot capacity day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["depot_wx", "supply", "sea"],
    }


def industry_surge_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    base_output: float = 1.0,
    base_capacity: float = 100.0,
    sea_mult: float = 1.0,
    line_id: str = "primary",
) -> Dict[str, Any]:
    """Compose production surge + depot capacity + industry economy depth."""
    w = dict(weather or {"precip_intensity": 0.0, "visibility": 1.0})
    surge = production_surge_day(
        weather=w, base_output=base_output, line_id=line_id, province_id=province_id
    )
    depot = depot_capacity_day(
        weather=w,
        base_capacity=base_capacity,
        sea_mult=sea_mult,
        province_id=province_id,
    )
    try:
        industry = industry_economy_depth(weather=w, base_output=base_output, sea_mult=sea_mult)
    except TypeError:
        try:
            industry = industry_economy_depth(w, base_output, sea_mult)  # type: ignore
        except Exception:
            industry = {"score": 0.55, "risk": 0.3, "empty": False, "summary": "industry stub"}

    apply_queue: List[Dict[str, Any]] = []
    for block in (surge, depot):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    # Promote industry economy actions
    for a in list(industry.get("actions") or []):
        if not isinstance(a, dict) or not a.get("enabled", True):
            continue
        aid = str(a.get("action_id", ""))
        if aid in ("apply_production", "apply_supply", "apply_focus"):
            apply_queue.append(
                {
                    "action_id": aid,
                    "province_id": province_id,
                    "score": float(a.get("score", industry.get("score", 0.45))),
                    "enabled": True,
                    "focus_id": a.get("focus_id", "industrial_effort"),
                }
            )

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)), str(q.get("focus_id", "")))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    s_surge = _score(surge, "score")
    s_depot = _score(depot, "score")
    s_ind = _score(industry, "score")
    score = (s_surge + s_depot + s_ind) / 3.0
    label = (
        "Industry surge day · prod %.2f · depot %.2f · industry %.2f · q %d"
        % (s_surge, s_depot, s_ind, len(apply_queue))
    )
    return {
        "surge": surge,
        "depot": depot,
        "industry": industry,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "industry_surge_day",
                "label": "Run industry surge day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(surge.get("summary", "")),
                str(depot.get("summary", "")),
                str(industry.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#6ec8ff]🏭 Industry surge day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["production_surge", "depot_capacity", "industry_economy"],
        "sole_mult": True,
    }


def industry_surge_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Industry surge integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_industry_surge_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "temperature_c": 12.0, "ground_state": "dry"}
    foul = {
        "precip_intensity": 0.9,
        "visibility": 0.3,
        "temperature_c": -12.0,
        "ground_state": "mud",
    }
    p_c = production_surge_day(weather=clear)
    p_f = production_surge_day(weather=foul)
    d_c = depot_capacity_day(weather=clear, sea_mult=1.1)
    d_f = depot_capacity_day(weather=foul, sea_mult=0.55)
    day = industry_surge_day(weather=weather or clear)
    gate = industry_surge_integrity()
    wx_shift = abs(float(p_c.get("score", 0.5)) - float(p_f.get("score", 0.5)))
    sea_shift = abs(float(d_c.get("score", 0.5)) - float(d_f.get("score", 0.5)))
    label = (
        "Close industry surge · prod Δwx %.3f · depot Δsea %.3f · q %d · %s"
        % (
            wx_shift,
            sea_shift,
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "prod_clear": p_c,
        "prod_foul": p_f,
        "depot_clear": d_c,
        "depot_foul": d_f,
        "day": day,
        "weather_score_shift": wx_shift,
        "sea_score_shift": sea_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6ec8ff]✓ Close industry surge[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
