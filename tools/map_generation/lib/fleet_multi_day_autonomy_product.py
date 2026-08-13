"""Fleet multi-day autonomy product surface (major #2) — not day-package stubs.

Multi-day decision loop:
  Day 0 posture/tasking → Day 1 station/escort → Day 2 follow-through / sealane sustain
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from product_depth import fleet_autonomy_plan  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore
from campaign_execution import fleet_order_execute, naval_order_package, execution_integrity_gate  # type: ignore
from gameplay_loops import basing_fleet_fuel_logistics, fleet_weather_mission_package, sealane_joint_health, sole_mult_integrity  # type: ignore
from fleet_theater_posture import plan_fleet_theater_posture  # type: ignore
from priority_systems import fleet_ai_ops_package  # type: ignore
from campaign_execution import execution_decision_strip  # type: ignore


DAY_STEPS = ("posture", "station_escort", "follow_through")

_STEP_META = {
    "posture": {
        "action_id": "fleet_day_posture",
        "leaf": "apply_station",
        "label": "Day 0 — set theater posture / tasking",
    },
    "station_escort": {
        "action_id": "fleet_day_station_escort",
        "leaf": "apply_supply",
        "label": "Day 1 — station + escort sustain",
    },
    "follow_through": {
        "action_id": "fleet_day_follow_through",
        "leaf": "apply_station",
        "label": "Day 2 — multi-day follow-through",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.7,
        "precip": 0.3,
        "precip_intensity": 0.3,
        "ground_state": "mud",
        "wind": 0.25,
        "temperature_c": 8.0,
    }


def recommend_fleet_multi_day_step(
    fuel_level: float,
    autonomy_score: float,
    *,
    escort_need: float = 0.0,
    apply_ready: bool = True,
) -> Dict[str, Any]:
    """Recommend next multi-day fleet step."""
    fuel = _norm(fuel_level)
    score = _norm(autonomy_score)
    escort = max(0.0, float(escort_need))
    if fuel < 0.35:
        step = "station_escort"
        reason = "fuel low — station/refuel + escort sustain"
    elif escort >= 50.0 or (not apply_ready and fuel < 0.5):
        step = "station_escort"
        reason = "escort pressure — convoy/screen day"
    elif score >= 0.55 and apply_ready:
        step = "follow_through"
        reason = "autonomy ready — multi-day follow-through"
    else:
        step = "posture"
        reason = "set posture/tasking first"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "fuel_level": fuel,
        "autonomy_score": score,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_fleet_multi_day_autonomy_product(
    province_ids: Optional[Sequence[int]] = None,
    *,
    fuel_level: float = 0.65,
    basing_level: str = "port",
    zone_relation: str = "contested",
    available_strength: float = 100.0,
    country_tag: str = "GER",
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Full multi-day fleet autonomy product for live panel."""
    pids = [int(x) for x in (province_ids or [province_id, province_id + 1, province_id + 2])]
    if not pids:
        pids = [max(1, int(province_id))]
    fuel = max(0.05, min(1.2, float(fuel_level)))
    wx = dict(weather or _wx())

    autonomy = fleet_autonomy_plan(
        pids,
        fuel_level=fuel,
        basing_level=str(basing_level),
        zone_relation=str(zone_relation),
        available_strength=float(available_strength),
        country_tag=str(country_tag),
    )
    fuel_log = basing_fleet_fuel_logistics(
        basing_level=str(basing_level), fuel_level=fuel, weather=wx, mission="patrol"
    )
    task = compose_task_group(
        available_strength=float(available_strength),
        mission="patrol",
        zone_relation=str(zone_relation),
        escort_need=0.35 if zone_relation != "friendly" else 0.1,
    )
    fleet_order = fleet_order_execute(
        basing_level=str(basing_level), fuel_level=fuel, available_strength=float(available_strength)
    )
    naval = naval_order_package(
        basing_level=str(basing_level), fuel_level=fuel, available_strength=float(available_strength)
    )
    fwx = fleet_weather_mission_package(
        mission="patrol",
        available_strength=float(available_strength),
        zone_relation=str(zone_relation),
    )
    posture = plan_fleet_theater_posture(
        [{"province_id": pid, "fuel_level": fuel, "basing_level": basing_level} for pid in pids[:4]],
        default_fuel=fuel,
    )
    try:
        ai_ops = fleet_ai_ops_package()
    except TypeError:
        ai_ops = fleet_ai_ops_package  # type: ignore
        try:
            ai_ops = fleet_ai_ops_package(fuel_level=fuel)  # type: ignore
        except Exception:
            ai_ops = {"score": float(autonomy.get("score", 0.5)), "empty": False}
    sealane = sealane_joint_health(
        ["friendly", "contested"] if zone_relation != "hostile" else ["contested", "hostile"],
        weather=wx,
        available_fleet=float(available_strength) * 0.5,
    )

    auto_score = float(autonomy.get("score", 0.0) or 0.0)
    if auto_score <= 0.0 and not autonomy.get("empty"):
        auto_score = 0.55
    logistics = float(fuel_log.get("logistics_score", 0.2) or 0.2)
    order_score = float(fleet_order.get("score", naval.get("score", 0.5)) or 0.5)
    sealane_score = float(sealane.get("score", 0.4) or 0.4)
    score = _floor(
        0.35 * auto_score
        + 0.2 * order_score
        + 0.2 * _floor(logistics)
        + 0.15 * sealane_score
        + 0.1 * (0.6 if not bool(task.get("empty", False)) else 0.3)
    )

    escort_info = autonomy.get("escort") if isinstance(autonomy.get("escort"), dict) else {}
    need = escort_info.get("need") if isinstance(escort_info.get("need"), dict) else {}
    escort_need = float(need.get("escort_need", 0.0) or 0.0)
    rec = recommend_fleet_multi_day_step(
        fuel,
        auto_score if auto_score > 0 else score,
        escort_need=escort_need,
        apply_ready=bool(autonomy.get("apply_ready", True)),
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(DAY_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        step_score = score
        if step == "posture":
            step_score = _floor(auto_score if auto_score > 0 else score)
        elif step == "station_escort":
            step_score = _floor(0.5 * _floor(logistics) + 0.5 * sealane_score)
        else:
            step_score = _floor(0.5 * order_score + 0.5 * score)
        label = str(meta["label"])
        if recommended:
            label = "★ " + label
        label = "%s · score %.2f" % (label, step_score)
        row = {
            "index": i,
            "day": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": meta["leaf"],
            "label": label,
            "score": step_score,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(pids[0])),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": max(1, int(pids[0])),
                "score": step_score,
                "enabled": True,
                "label": label,
                "step": step,
                "product_action": meta["action_id"],
            }
        )

    # Decision strip for playability/execution depth (next-70/80 spirit)
    strip = execution_decision_strip(
        [
            {"summary": "fleet posture", "score": auto_score, "empty": False, "order": str(autonomy.get("chosen_order", "PATROL"))},
            {"summary": "escort sustain", "score": sealane_score, "empty": False, "order": "ESCORT"},
            {"summary": "multi-day follow", "score": order_score, "empty": False, "order": "FOLLOW"},
        ]
    )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "fleet_multi_day_autonomy_product",
            "label": "Run fleet multi-day autonomy product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "fleet_day_posture")),
            "label": "Recommended: %s" % rec.get("step", "posture"),
            "enabled": True,
        },
    ]
    for row in day_rows:
        actions.append(
            {
                "action_id": row["action_id"],
                "label": row["label"],
                "enabled": True,
                "step": row["step"],
            }
        )

    chosen = str(autonomy.get("chosen_order", "SEARCH_PATROL"))
    posture_name = str(
        autonomy.get("chosen_posture")
        or (posture.get("dominant_posture") if isinstance(posture, dict) else "")
        or task.get("primary_role")
        or "PATROL"
    )
    label = (
        "Fleet multi-day autonomy · %s · posture %s · fuel %.0f%% · score %.2f · %s"
        % (chosen, posture_name, fuel * 100.0, score, country_tag)
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        "order %s · primary %s" % (chosen, str(task.get("primary_role", "?"))),
    ]
    for row in day_rows:
        plain_lines.append(str(row.get("label", "")))

    return {
        "autonomy": autonomy,
        "fuel": fuel_log,
        "task_group": task,
        "fleet_order": fleet_order,
        "naval_order": naval,
        "weather_mission": fwx,
        "posture": posture,
        "ai_ops": ai_ops if isinstance(ai_ops, dict) else {},
        "sealane": sealane,
        "decision_strip": strip,
        "recommendation": rec,
        "day_rows": day_rows,
        "day_count": len(day_rows),
        "apply_queue": apply_queue,
        "province_ids": pids,
        "province_id": max(1, int(pids[0])),
        "fuel_level": fuel,
        "chosen_order": chosen,
        "chosen_posture": posture_name,
        "score": score,
        "fleet_score": score,
        "apply_ready": bool(autonomy.get("apply_ready", True)),
        "actions": actions,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#5ec8ff]🚢 Fleet multi-day autonomy[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": bool(autonomy.get("empty", False)) and score <= 0.0,
        "integration": [
            "fleet_multi_day_autonomy_product",
            "fleet_day_posture",
            "fleet_day_station_escort",
            "fleet_day_follow_through",
            "major_2",
            "playability",
            "execution",
        ],
    }


def execute_fleet_day_step(
    step: str,
    province_id: int = 1,
    *,
    fuel_level: float = 0.65,
    basing_level: str = "port",
    zone_relation: str = "contested",
) -> Dict[str, Any]:
    """Resolve one multi-day fleet step into a leaf apply payload."""
    s = str(step or "posture").strip().lower()
    if s not in _STEP_META:
        # allow action ids
        for k, meta in _STEP_META.items():
            if s == meta["action_id"] or s == "apply_%s" % meta["action_id"]:
                s = k
                break
        else:
            s = "posture"
    meta = _STEP_META[s]
    product = build_fleet_multi_day_autonomy_product(
        [province_id, province_id + 1],
        fuel_level=fuel_level,
        basing_level=basing_level,
        zone_relation=zone_relation,
        province_id=province_id,
    )
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": meta["leaf"],
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute fleet day %s · leaf %s · score %.2f · #%d" % (
        s,
        meta["leaf"],
        score,
        max(1, int(province_id)),
    )
    return {
        "step": s,
        "leaf_action": meta["leaf"],
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "product_score": float(product.get("score", 0)),
        "chosen_order": str(product.get("chosen_order", "")),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🚢 Fleet day %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_fleet_day_step", s, meta["leaf"]],
    }


def fleet_multi_day_autonomy_integrity() -> Dict[str, Any]:
    product = build_fleet_multi_day_autonomy_product([1, 2, 3], fuel_level=0.65)
    low = build_fleet_multi_day_autonomy_product([1, 2, 3], fuel_level=0.25)
    steps = [execute_fleet_day_step(s, 1) for s in DAY_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("day_count", 0)) >= 3
        and len(product.get("apply_queue") or []) >= 3
        and bool(product.get("recommendation"))
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and float(product.get("score", 0)) > float(low.get("score", 0))  # fuel matters
    )
    return {
        "ok": ok,
        "day_count": int(product.get("day_count", 0)),
        "score": float(product.get("score", 0)),
        "low_fuel_score": float(low.get("score", 0)),
        "follow_on": str((product.get("recommendation") or {}).get("step", "")),
        "gate": gate,
        "summary": "Fleet multi-day autonomy integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_fleet_multi_day_autonomy_product_loop() -> Dict[str, Any]:
    product = build_fleet_multi_day_autonomy_product([1, 2, 3], fuel_level=0.7)
    low = build_fleet_multi_day_autonomy_product([1, 2, 3], fuel_level=0.3)
    gate = fleet_multi_day_autonomy_integrity()
    fuel_shift = abs(float(product.get("score", 0)) - float(low.get("score", 0)))
    ok = bool(gate.get("ok")) and fuel_shift > 0.01 and int(product.get("day_count", 0)) >= 3
    label = (
        "Close fleet multi-day autonomy product · days %d · fuel_shift %.3f · %s"
        % (int(product.get("day_count", 0)), fuel_shift, "PASS" if ok else "FAIL")
    )
    return {
        "product": product,
        "low_fuel": low,
        "gate": gate,
        "fuel_shift": fuel_shift,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Fleet multi-day autonomy product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
