"""Joint command day: naval interdiction · intel/HH counter · joint theater compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity  # type: ignore
from theater_day_depth import convoy_supply_day_package  # type: ignore
from air_forecast_day import air_forecast_assault_day  # type: ignore
from logistics_day_depth import sealane_choke_logistics_day  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def naval_interdiction_day(
    path_zone_relations: Optional[Sequence[str]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    sea_trade_mult: float = 1.0,
    available_fleet: float = 80.0,
    escort_coverage: float = 0.55,
    interdiction_pressure: float = 0.4,
) -> Dict[str, Any]:
    """Naval interdiction / convoy pressure day — stage escort or interdict apply."""
    if path_zone_relations is None:
        path = ["friendly", "contested", "hostile"]
    else:
        path = list(path_zone_relations)
    if not path:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }
    w = dict(weather or {})
    precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    try:
        convoy = convoy_supply_day_package(path, weather=w, available_fleet=available_fleet)
    except TypeError:
        try:
            convoy = convoy_supply_day_package(path, w, available_fleet)  # type: ignore
        except Exception:
            convoy = {"score": 0.55, "apply_ready": True, "summary": "convoy stub", "empty": False}

    # Interdiction effectiveness: pressure × visibility × (1 - escort) × sea openness
    sea = max(0.2, min(1.5, float(sea_trade_mult)))
    escort = max(0.0, min(1.0, float(escort_coverage)))
    pressure = max(0.0, min(1.0, float(interdiction_pressure)))
    wx_gate = max(0.25, min(1.0, vis * (1.0 - precip * 0.45)))
    interdict_score = pressure * (1.0 - escort * 0.65) * wx_gate * min(1.2, sea)
    escort_need = max(0.0, min(1.0, interdict_score * 0.9 + (1.0 - escort) * 0.35))
    apply_ready = wx_gate >= 0.35 and available_fleet >= 20.0
    score = interdict_score * 0.55 + _score(convoy, "score") * 0.45

    apply_queue: List[Dict[str, Any]] = []
    if apply_ready and interdict_score >= 0.35:
        apply_queue.append(
            {
                "action_id": "fleet_autonomy",
                "province_id": 1,
                "score": interdict_score,
                "order": "interdict",
                "enabled": True,
            }
        )
    if escort_need >= 0.45:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": 1,
                "score": escort_need,
                "order": "escort",
                "enabled": True,
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": 1,
                "score": 0.4,
                "enabled": True,
            }
        )

    label = "Naval interdiction day · interdict %.0f%% · escort_need %.0f%% · fleet %.0f" % (
        interdict_score * 100.0,
        escort_need * 100.0,
        available_fleet,
    )
    return {
        "convoy": convoy,
        "interdiction_score": interdict_score,
        "escort_need": escort_need,
        "wx_gate": wx_gate,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "naval_interdiction_day",
                "label": "Run naval interdiction day",
                "enabled": len(apply_queue) > 0,
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Fleet interdict posture",
                "enabled": apply_ready and interdict_score >= 0.35,
            },
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]⚓ Interdiction day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["convoy", "interdiction", "escort", "fleet"],
    }


def intel_counter_day(
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    pressure: float = 0.45,
) -> Dict[str, Any]:
    """HH signal + agent counterplay + agenda commit day package."""
    sig = dict(signal or {})
    trail_list = [dict(t) for t in (trail or []) if isinstance(t, Mapping)]
    action_class = str(sig.get("action_class", sig.get("class", "sabotage")) or "sabotage")
    sig_pid = int(sig.get("province_id", province_id) or province_id)
    has_signal = bool(sig) and action_class != ""
    has_trail = len(trail_list) > 0

    # Counterplay score: pressure + signal presence
    p = max(0.0, min(1.0, float(pressure)))
    counter_score = p * (1.15 if has_signal else 0.7) * (1.1 if has_trail else 1.0)
    counter_score = max(0.05, min(1.2, counter_score))

    apply_queue: List[Dict[str, Any]] = []
    if has_signal:
        apply_queue.append(
            {
                "action_id": "apply_agent_dispatch",
                "province_id": sig_pid,
                "score": counter_score,
                "action_class": action_class,
                "enabled": True,
            }
        )
        apply_queue.append(
            {
                "action_id": "apply_counterplay",
                "province_id": sig_pid,
                "score": counter_score * 0.9,
                "enabled": True,
            }
        )
    if has_trail:
        apply_queue.append(
            {
                "action_id": "apply_hh_commit",
                "province_id": -1,
                "score": 0.45 + 0.05 * min(3, len(trail_list)),
                "enabled": True,
            }
        )
    if not apply_queue:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    label = "Intel counter day · signal=%s · trail=%d · score %.2f" % (
        action_class if has_signal else "none",
        len(trail_list),
        counter_score,
    )
    return {
        "signal": sig,
        "trail_count": len(trail_list),
        "action_class": action_class,
        "score": counter_score,
        "apply_ready": True,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "intel_counter_day",
                "label": "Run intel counter day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8a0ff]◎ Intel counter day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["hh_signal", "agent_dispatch", "counterplay", "hh_commit"],
    }


def joint_command_day(
    weather: Optional[Mapping[str, Any]] = None,
    path_zone_relations: Optional[Sequence[str]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    sea_trade_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Compose naval interdiction + intel counter + air-forecast + logistics into one joint day."""
    w = dict(weather or {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2})
    path = list(path_zone_relations or ["friendly", "contested", "hostile"])

    naval = naval_interdiction_day(
        path, weather=w, sea_trade_mult=sea_trade_mult, available_fleet=80.0
    )
    intel = intel_counter_day(
        signal or {"action_class": "sabotage", "province_id": province_id},
        trail,
        province_id=province_id,
        pressure=0.5,
    )
    try:
        air = air_forecast_assault_day(weather=w, targets=targets)
    except Exception:
        air = {"score": 0.5, "apply_queue": [], "empty": False, "summary": "air stub"}
    try:
        logistics = sealane_choke_logistics_day(
            path, weather=w, sea_trade_mult=sea_trade_mult
        )
    except Exception:
        logistics = {"score": 0.55, "apply_ready": True, "empty": False, "summary": "logistics stub"}

    apply_queue: List[Dict[str, Any]] = []
    for block in (naval, intel, air, logistics):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))
        # Also promote top enabled actions without queues
        for a in list(block.get("actions") or []):
            if not isinstance(a, dict) or not a.get("enabled", True):
                continue
            aid = str(a.get("action_id", ""))
            if aid in (
                "apply_assault",
                "apply_supply",
                "apply_focus",
                "fleet_autonomy",
                "apply_station",
                "apply_agent_dispatch",
                "apply_counterplay",
                "apply_hh_commit",
                "apply_production",
            ):
                apply_queue.append(
                    {
                        "action_id": aid,
                        "province_id": int(a.get("province_id", province_id)),
                        "score": float(a.get("score", block.get("score", 0.45))),
                        "enabled": True,
                        "focus_id": a.get("focus_id"),
                    }
                )

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    scores = [
        _score(naval, "score"),
        _score(intel, "score") if not intel.get("empty") else 0.0,
        _score(air, "score"),
        _score(logistics, "score"),
    ]
    score = sum(scores) / 4.0
    label = (
        "Joint command day · naval %.2f · intel %.2f · air %.2f · log %.2f · q %d"
        % (scores[0], scores[1], scores[2], scores[3], len(apply_queue))
    )
    return {
        "naval": naval,
        "intel": intel,
        "air": air,
        "logistics": logistics,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "joint_command_day",
                "label": "Run joint command day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(naval.get("summary", "")),
                str(intel.get("summary", "")),
                str(air.get("summary", "")),
                str(logistics.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#6eb5ff]🎖 Joint command day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["naval_interdiction", "intel_counter", "air_forecast", "logistics"],
    }


def joint_command_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Joint command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_joint_command_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0, "wind": 0.2}
    foul = {"precip_intensity": 0.95, "visibility": 0.2, "wind": 0.9, "ground_state": "mud"}
    n_c = naval_interdiction_day(weather=clear)
    n_f = naval_interdiction_day(weather=foul)
    intel = intel_counter_day(
        {"action_class": "sabotage", "province_id": 42},
        [{"month": 1, "class": "sabotage"}],
        province_id=42,
    )
    empty_intel = intel_counter_day({}, [], province_id=1)
    day = joint_command_day(weather=weather or clear)
    gate = joint_command_integrity()
    wx_shift = abs(float(n_c["score"]) - float(n_f["score"]))
    label = (
        "Close joint command · naval Δwx %.3f · empty_intel %s · q %d · %s"
        % (
            wx_shift,
            empty_intel.get("empty"),
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "naval_clear": n_c,
        "naval_foul": n_f,
        "intel": intel,
        "empty_intel": empty_intel,
        "day": day,
        "weather_score_shift": wx_shift,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Close joint[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }
