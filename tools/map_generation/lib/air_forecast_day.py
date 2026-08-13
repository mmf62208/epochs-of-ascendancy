"""Air-ops day, weather forecast planning day, reinforced assault day packages.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from weather_forecast import forecast_next_day, air_sortie_weather_gate  # type: ignore
from integrated_theater_ops import air_ops_package  # type: ignore
from theater_ops_polish import convoy_weather_window  # type: ignore
from gameplay_loops import reinforced_assault_loop, sole_mult_integrity  # type: ignore
from war_economy_day import multi_front_assault_day  # type: ignore
from product_depth import multi_phase_combat_ui_product, weather_mult_from  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def air_ops_day_package(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
) -> Dict[str, Any]:
    """Air sortie readiness + gate for day apply (assault support / hold if grounded)."""
    w = dict(weather or {})
    try:
        air = air_ops_package(w, month=month)
    except TypeError:
        air = air_ops_package(weather=w, month=month)  # type: ignore
    try:
        gate = air_sortie_weather_gate(w)
    except Exception:
        gate = {"grounded": bool(air.get("grounded", False)), "summary": "", "empty": False}

    grounded = bool(air.get("grounded", gate.get("grounded", False)))
    eff = _score(air, "effective", "score", default=0.7)
    if eff > 2.0:
        eff = min(1.2, eff)
    score = eff * (0.35 if grounded else 1.0)
    apply_ready = not grounded and eff >= 0.4
    label = "Air ops day · sortie %.0f%% · %s · score %.2f" % (
        min(1.0, eff) * 100.0,
        "GROUNDED" if grounded else "flyable",
        score,
    )
    return {
        "air": air,
        "gate": gate,
        "grounded": grounded,
        "score": score,
        "apply_ready": apply_ready,
        "actions": [
            {
                "action_id": "apply_assault",
                "label": "Stage air-supported assault",
                "enabled": apply_ready,
            },
            {
                "action_id": "apply_focus",
                "label": "Hold air/industrial focus",
                "enabled": True,
                "focus_id": "military_effort" if grounded else "industrial_effort",
            },
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✈ Air ops day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["air_ops", "sortie_gate", "apply"],
    }


def weather_forecast_planning_day(
    weather: Optional[Mapping[str, Any]] = None,
    forecasts: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Next-day forecast + convoy window → wait/go recommendations."""
    w = dict(weather or {})
    nxt = forecast_next_day(w)
    days = list(forecasts or [])
    if not days:
        days = [dict(w, day_index=0), dict(nxt.get("forecast") or {}, day_index=1)]
        # ensure day_index
        for i, d in enumerate(days):
            if isinstance(d, dict) and "day_index" not in d:
                d["day_index"] = i
    try:
        window = convoy_weather_window(days)
    except TypeError:
        try:
            window = convoy_weather_window(forecasts=days)  # type: ignore
        except Exception:
            window = {"best_day": 0, "summary": "window stub", "empty": False}

    combat_m = float(nxt.get("combat_mult", 1.0) or 1.0)
    supply_m = float(nxt.get("supply_mult", 1.0) or 1.0)
    best_day = int(window.get("best_day", 0) or 0)
    recommend_wait = best_day > 0 or combat_m < 0.75
    score = (combat_m * 0.5 + supply_m * 0.5) * (0.8 if recommend_wait else 1.0)
    label = "Forecast planning day · combat×%.2f · supply×%.2f · wait=%s · best_day %s" % (
        combat_m,
        supply_m,
        "yes" if recommend_wait else "no",
        best_day,
    )
    return {
        "forecast": nxt,
        "window": window,
        "recommend_wait": recommend_wait,
        "best_day": best_day,
        "score": score,
        "apply_ready": not recommend_wait,
        "actions": [
            {
                "action_id": "apply_supply",
                "label": "Sustain supply (go window)",
                "enabled": not recommend_wait,
            },
            {
                "action_id": "apply_assault",
                "label": "Stage assault (go weather)",
                "enabled": not recommend_wait and combat_m >= 0.7,
            },
            {
                "action_id": "apply_focus",
                "label": "Hold focus through weather",
                "enabled": recommend_wait,
                "focus_id": "industrial_effort",
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [label, str(nxt.get("summary", "")), str(window.get("summary", ""))]
        ),
        "bbcode": "[color=#5ec8ff]📅 Forecast day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["forecast", "convoy_window", "wait_go"],
    }


def reinforced_assault_day(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    month: int = 6,
    is_choke: bool = False,
    max_targets: int = 3,
) -> Dict[str, Any]:
    """Reinforced assault score + multi-front queue for day stage applies."""
    w = dict(weather or {})
    tgts = list(targets or [])
    if not tgts:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    try:
        reinforced = reinforced_assault_loop(
            tgts,
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
            weather=w,
            month=month,
            is_choke=is_choke,
        )
    except TypeError:
        reinforced = reinforced_assault_loop(tgts, attacker_power, attacker_supply, w)  # type: ignore

    fronts = multi_front_assault_day(
        tgts, attacker_power=attacker_power, attacker_supply=attacker_supply, weather=w, max_targets=max_targets
    )
    combat = multi_phase_combat_ui_product(
        attacker_power=attacker_power,
        defender_power=float((tgts[0] or {}).get("defender_power", 80.0) if tgts else 80.0),
        attacker_supply=attacker_supply,
        weather=w,
    )

    r_score = _score(reinforced, "score")
    if r_score > 2.0:
        r_score = min(1.0, r_score)
    f_score = 0.0 if fronts.get("empty") else _score(fronts, "score")
    score = (r_score * 0.55 + f_score * 0.25 + _score(combat, "score") * 0.2)

    apply_queue: List[Dict[str, Any]] = []
    for q in list(fronts.get("apply_queue") or []):
        if isinstance(q, dict) and q.get("enabled", True):
            # Gate by reinforced readiness
            if r_score >= 0.35 or bool(combat.get("apply_ready", False)):
                apply_queue.append(dict(q))
    if not apply_queue and not reinforced.get("empty") and r_score >= 0.35:
        pid = int((tgts[0] or {}).get("province_id", (tgts[0] or {}).get("id", 1)) or 1)
        apply_queue.append(
            {
                "province_id": pid,
                "action_id": "apply_assault",
                "score": r_score,
                "enabled": True,
            }
        )

    if not apply_queue and reinforced.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    label = "Reinforced assault day · score %.0f%% · queue %d · phases %d" % (
        score * 100.0,
        len(apply_queue),
        int(combat.get("phase_count", 0)),
    )
    return {
        "reinforced": reinforced,
        "multi_front": fronts,
        "combat": combat,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "reinforced_assault_day",
                "label": "Stage reinforced assaults",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(reinforced.get("summary", "")),
                str(fronts.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#ff9a6e]⚔ Reinforced day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(apply_queue) == 0 and bool(reinforced.get("empty", False)),
        "integration": ["reinforced", "multi_front", "combat_ui", "apply_assault"],
    }


def air_forecast_assault_day(
    weather: Optional[Mapping[str, Any]] = None,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    month: int = 6,
) -> Dict[str, Any]:
    """Compose air ops + forecast planning + reinforced assault into one day package."""
    w = dict(weather or {})
    air = air_ops_day_package(weather=w, month=month)
    forecast = weather_forecast_planning_day(weather=w)
    assault = reinforced_assault_day(
        targets
        or [
            {"province_id": 10, "defender_power": 65.0},
            {"province_id": 20, "defender_power": 90.0},
        ],
        weather=w,
        month=month,
    )

    apply_queue: List[Dict[str, Any]] = []
    # Prefer forecast-gated actions
    if not forecast.get("recommend_wait"):
        for a in list(air.get("actions") or []):
            if isinstance(a, dict) and a.get("enabled", True) and a.get("action_id") == "apply_assault":
                apply_queue.append({"action_id": "apply_assault", "province_id": 10, "score": float(air.get("score", 0.5))})
        for q in list(assault.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))
    else:
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": 1,
                "score": 0.4,
                "focus_id": "industrial_effort",
            }
        )
        if air.get("grounded"):
            apply_queue.append(
                {
                    "action_id": "apply_focus",
                    "province_id": 1,
                    "score": 0.35,
                    "focus_id": "military_effort",
                }
            )

    # Dedupe by action+province
    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:6]

    score = (
        _score(air, "score")
        + _score(forecast, "score")
        + (0.0 if assault.get("empty") else _score(assault, "score"))
    ) / 3.0
    label = "Air-forecast assault day · air %.2f · forecast wait=%s · assault_q %d" % (
        _score(air, "score"),
        forecast.get("recommend_wait"),
        len(assault.get("apply_queue") or []),
    )
    return {
        "air": air,
        "forecast": forecast,
        "assault": assault,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "air_forecast_day",
                "label": "Run air-forecast assault day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(air.get("summary", "")),
                str(forecast.get("summary", "")),
                str(assault.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]✈📅 Air-forecast day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["air_ops_day", "forecast_day", "reinforced_day"],
    }


def air_forecast_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Air-forecast integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_air_forecast_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2}
    foul = {"precip_intensity": 0.95, "visibility": 0.2, "wind": 0.9, "ground_state": "mud"}
    a_c = air_ops_day_package(weather=clear)
    a_f = air_ops_day_package(weather=foul)
    f_c = weather_forecast_planning_day(weather=clear)
    f_f = weather_forecast_planning_day(weather=foul)
    r = reinforced_assault_day(
        [{"province_id": 1, "defender_power": 70.0}], weather=clear
    )
    empty_r = reinforced_assault_day([])
    day = air_forecast_assault_day(weather=weather or clear)
    gate = air_forecast_integrity()
    wx_shift = abs(float(a_c["score"]) - float(a_f["score"]))
    label = "Close air-forecast day · air Δwx %.3f · foul_wait %s · empty_assault %s · %s" % (
        wx_shift,
        f_f.get("recommend_wait"),
        empty_r.get("empty"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "air_clear": a_c,
        "air_foul": a_f,
        "forecast_clear": f_c,
        "forecast_foul": f_f,
        "reinforced": r,
        "empty_assault": empty_r,
        "day": day,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
