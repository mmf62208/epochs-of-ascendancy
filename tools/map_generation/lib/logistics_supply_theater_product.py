"""Logistics supply theater product (major #18) — world-class supply spine.

Route audit → basing/fuel sustain → force readiness joint.
Composes supply mutation, war economy, basing logistics, force readiness.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import basing_fleet_fuel_logistics, sole_mult_integrity, trade_supply_weather_chain  # type: ignore
from live_mutation import supply_route_mutation  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from fleet_multi_day_autonomy_product import build_fleet_multi_day_autonomy_product  # type: ignore


PRODUCT_STEPS = ("route", "sustain", "readiness")

_STEP_META = {
    "route": {
        "action_id": "logistics_supply_route",
        "leaf": "apply_supply",
        "label": "Step 0 — supply route audit",
    },
    "sustain": {
        "action_id": "logistics_supply_sustain",
        "leaf": "apply_station",
        "label": "Step 1 — basing/fuel sustain",
    },
    "readiness": {
        "action_id": "logistics_supply_readiness",
        "leaf": "apply_production",
        "label": "Step 2 — force readiness joint",
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


def recommend_logistics_step(
    *,
    route_score: float = 0.5,
    sustain_score: float = 0.5,
    ready: bool = False,
) -> Dict[str, Any]:
    if route_score < 0.45:
        step = "route"
        reason = "route health low — re-audit supply"
    elif sustain_score < 0.45:
        step = "sustain"
        reason = "basing/fuel thin — sustain"
    elif ready:
        step = "readiness"
        reason = "spine ready — push force readiness"
    else:
        step = "sustain"
        reason = "refresh sustain"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_logistics_supply_theater_product(*, province_id: int = 1) -> Dict[str, Any]:
    supply = supply_route_mutation(basing_level="port", province_id=province_id)
    trade = trade_supply_weather_chain(sea_trade_mult=1.0)
    economy = war_economy_day_package()
    basing = basing_fleet_fuel_logistics(
        basing_level="port", fuel_level=0.6, available_strength=100.0, zone_relation="contested"
    )
    fleet = build_fleet_multi_day_autonomy_product(province_id=province_id, fuel_level=0.6)
    ready = force_readiness_day()

    route_score = _floor(
        0.55 * _norm(float(supply.get("score", 0.5)))
        + 0.45 * _norm(float(trade.get("score", trade.get("health", 0.5))))
    )
    sustain_score = _floor(
        0.45 * _norm(float(basing.get("logistics_score", basing.get("score", 0.5))))
        + 0.3 * _norm(float(fleet.get("score", 0.5)))
        + 0.25 * _norm(float(economy.get("score", 0.5)))
    )
    ready_score = _floor(
        0.55 * _norm(float(ready.get("score", 0.5))) + 0.45 * route_score
    )
    score = _floor(0.35 * route_score + 0.35 * sustain_score + 0.3 * ready_score)
    rec = recommend_logistics_step(
        route_score=route_score,
        sustain_score=sustain_score,
        ready=ready_score >= 0.45 and route_score >= 0.45,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {"route": route_score, "sustain": sustain_score, "readiness": ready_score}
    step_leaves = {
        "route": "apply_supply",
        "sustain": "apply_station",
        "readiness": "apply_production",
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

    actions = [
        {
            "action_id": "logistics_supply_theater_product",
            "label": "Run logistics supply theater product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "logistics_supply_route")),
            "label": "Recommended: %s" % rec.get("step", "route"),
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
        "Logistics supply theater · route %.2f · sustain %.2f · ready %.2f · score %.2f"
        % (route_score, sustain_score, ready_score, score)
    )
    return {
        "supply": supply,
        "trade": trade,
        "economy": economy,
        "basing": basing,
        "fleet": fleet,
        "ready": ready,
        "route_score": route_score,
        "sustain_score": sustain_score,
        "ready_score": ready_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "logistics_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [label, str(rec.get("summary", "")), str(supply.get("summary", "")), str(basing.get("summary", ""))]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#5ec8ff]📦 Logistics theater[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "logistics_supply_theater_product",
            "logistics_supply_route",
            "logistics_supply_sustain",
            "logistics_supply_readiness",
            "major_18",
            "logistics",
            "supply",
        ],
    }


def execute_logistics_supply_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "route").strip().lower()
    if s.startswith("logistics_supply_"):
        s = s.replace("logistics_supply_", "")
    if s not in _STEP_META:
        s = "route"
    meta = _STEP_META[s]
    product = build_logistics_supply_theater_product(province_id=province_id)
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
    label = "Execute logistics %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]📦 Logistics %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_logistics_supply_step", s, leaf],
    }


def logistics_supply_theater_integrity() -> Dict[str, Any]:
    product = build_logistics_supply_theater_product()
    steps = [execute_logistics_supply_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Logistics supply theater integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_logistics_supply_theater_product_loop() -> Dict[str, Any]:
    product = build_logistics_supply_theater_product(province_id=2)
    gate = logistics_supply_theater_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close logistics supply theater · score %.2f · %s" % (
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Logistics theater[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
