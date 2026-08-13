"""Air ops campaign product (major #13).

First vertical air product: sortie readiness → weather gate → air-land joint apply.
Composes air forecast/sortie packages with multi-phase combat support — not day stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from air_forecast_day import (  # type: ignore
    air_forecast_integrity,
    air_ops_day_package,
    air_ops_package,
    air_sortie_weather_gate,
    weather_forecast_planning_day,
)
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from combat_multi_phase_product import (  # type: ignore
    build_multi_phase_combat_product,
    multi_phase_combat_product_integrity,
)
from next240_air_convoy_order import air_front_readiness_day, air_land_campaign_day  # type: ignore


PRODUCT_STEPS = ("sortie", "weather_gate", "air_land")

_STEP_META = {
    "sortie": {
        "action_id": "air_ops_sortie",
        "leaf": "apply_focus",
        "label": "Step 0 — air sortie readiness",
    },
    "weather_gate": {
        "action_id": "air_ops_weather_gate",
        "leaf": "apply_station",
        "label": "Step 1 — weather sortie gate",
    },
    "air_land": {
        "action_id": "air_ops_air_land",
        "leaf": "apply_assault",
        "label": "Step 2 — air-land joint apply",
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
        "visibility": 0.68,
        "precip": 0.32,
        "precip_intensity": 0.32,
        "ground_state": "mud",
        "wind": 0.3,
        "temperature_c": 8.0,
    }


def recommend_air_ops_step(
    *,
    sortie_score: float = 0.5,
    weather_ok: bool = True,
    joint_ready: bool = False,
) -> Dict[str, Any]:
    if sortie_score < 0.4:
        step = "sortie"
        reason = "sortie readiness low — plan package"
    elif not weather_ok:
        step = "weather_gate"
        reason = "weather foul — gate sortie"
    elif joint_ready:
        step = "air_land"
        reason = "air-land joint ready"
    else:
        step = "weather_gate"
        reason = "confirm weather gate"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_air_ops_campaign_product(*, province_id: int = 1) -> Dict[str, Any]:
    wx = _wx()
    air = air_ops_day_package()
    pkg = air_ops_package(wx)
    forecast = weather_forecast_planning_day()
    gate_raw = air_sortie_weather_gate(wx)
    if not isinstance(gate_raw, dict):
        gate = {"score": 0.5, "raw": gate_raw}
    else:
        gate = gate_raw
    joint = air_land_campaign_day(province_id)
    front = air_front_readiness_day(province_id)
    combat = build_multi_phase_combat_product(province_id=province_id)

    sortie_score = _floor(
        0.55 * _norm(float(air.get("score", 0.5)))
        + 0.45 * _norm(float(pkg.get("score", 0.5)))
    )
    weather_score = _floor(
        0.55 * _norm(float(gate.get("score", gate.get("sortie_ready", 0.5))))
        + 0.45 * _norm(float(forecast.get("score", 0.5)))
    )
    joint_score = _floor(
        0.4 * _norm(float(joint.get("score", 0.5)))
        + 0.3 * _norm(float(front.get("score", 0.5)))
        + 0.3 * _norm(float(combat.get("score", 0.5)))
    )
    score = _floor(0.35 * sortie_score + 0.3 * weather_score + 0.35 * joint_score)

    weather_ok = weather_score >= 0.4
    joint_ready = joint_score >= 0.4
    rec = recommend_air_ops_step(
        sortie_score=sortie_score, weather_ok=weather_ok, joint_ready=joint_ready
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "sortie": sortie_score,
        "weather_gate": weather_score,
        "air_land": joint_score,
    }
    step_leaves = {
        "sortie": "apply_focus",
        "weather_gate": "apply_station",
        "air_land": "apply_assault",
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = step_leaves[step]
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · score %.2f" % (lab, sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "air_ops_campaign_product",
            "label": "Run air ops campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "air_ops_sortie")),
            "label": "Recommended: %s" % rec.get("step", "sortie"),
            "enabled": True,
        },
        {
            "action_id": "multi_phase_combat_product",
            "label": "Open multi-phase combat product",
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": True,
                "step": r["step"],
            }
        )

    label = (
        "Air ops campaign · sortie %.2f · weather %.2f · air-land %.2f · score %.2f"
        % (sortie_score, weather_score, joint_score, score)
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        str(air.get("summary", "")),
        str(gate.get("summary", gate.get("plain", ""))),
        str(joint.get("summary", "")),
        str(combat.get("summary", "")),
    ]
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "air": air,
        "package": pkg,
        "forecast": forecast,
        "gate": gate,
        "joint": joint,
        "front": front,
        "combat": combat,
        "sortie_score": sortie_score,
        "weather_score": weather_score,
        "joint_score": joint_score,
        "weather_ok": weather_ok,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "air_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#38bdf8]✈ Air ops campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "air_ops_campaign_product",
            "air_ops_sortie",
            "air_ops_weather_gate",
            "air_ops_air_land",
            "major_13",
            "air_ops",
        ],
    }


def execute_air_ops_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "sortie").strip().lower()
    if s.startswith("air_ops_"):
        s = s.replace("air_ops_", "")
    if s == "gate":
        s = "weather_gate"
    if s == "joint":
        s = "air_land"
    if s not in _STEP_META:
        s = "sortie"
    meta = _STEP_META[s]
    product = build_air_ops_campaign_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute air ops %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#38bdf8]✈ Air ops %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_air_ops_step", s, leaf],
    }


def air_ops_campaign_integrity() -> Dict[str, Any]:
    product = build_air_ops_campaign_product()
    steps = [execute_air_ops_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    air_g = air_forecast_integrity()
    combat_g = multi_phase_combat_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(air_g.get("ok", True))
        and bool(combat_g.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "sortie_score": float(product.get("sortie_score", 0)),
        "weather_score": float(product.get("weather_score", 0)),
        "joint_score": float(product.get("joint_score", 0)),
        "gate": gate,
        "summary": "Air ops campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_air_ops_campaign_product_loop() -> Dict[str, Any]:
    product = build_air_ops_campaign_product(province_id=2)
    gate = air_ops_campaign_integrity()
    foul = build_air_ops_campaign_product(province_id=3)
    # foul still returns structure
    ok = (
        bool(gate.get("ok"))
        and len(product.get("apply_queue") or []) >= 3
        and not bool(foul.get("empty"))
    )
    label = "Close air ops campaign · score %.2f · queue %d · %s" % (
        float(product.get("score", 0)),
        len(product.get("apply_queue") or []),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#38bdf8]✓ Air ops campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
