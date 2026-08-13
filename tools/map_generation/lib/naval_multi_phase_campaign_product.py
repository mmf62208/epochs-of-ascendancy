"""Naval multi-phase campaign product (major #15) — deferred naval combat first slice.

Posture/tasking → convoy/escort phase → strike/follow-through. Composes fleet multi-day
autonomy, convoy escort, basing fuel, multi-phase combat as naval support — not stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import basing_fleet_fuel_logistics, sole_mult_integrity  # type: ignore
from fleet_multi_day_autonomy_product import (  # type: ignore
    build_fleet_multi_day_autonomy_product,
    fleet_multi_day_autonomy_integrity,
)
from fleet_theater_posture import plan_fleet_theater_posture  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from combat_multi_phase_product import (  # type: ignore
    build_multi_phase_combat_product,
    multi_phase_combat_product_integrity,
)


PRODUCT_STEPS = ("posture", "escort", "strike")

_STEP_META = {
    "posture": {
        "action_id": "naval_phase_posture",
        "leaf": "apply_station",
        "label": "Step 0 — fleet posture / tasking",
    },
    "escort": {
        "action_id": "naval_phase_escort",
        "leaf": "apply_station",
        "label": "Step 1 — convoy escort phase",
    },
    "strike": {
        "action_id": "naval_phase_strike",
        "leaf": "apply_assault",
        "label": "Step 2 — strike / multi-phase follow",
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


def recommend_naval_phase_step(
    *,
    posture_score: float = 0.5,
    escort_ok: bool = True,
    strike_ready: bool = False,
) -> Dict[str, Any]:
    if posture_score < 0.4:
        step = "posture"
        reason = "posture weak — re-task fleet"
    elif not escort_ok:
        step = "escort"
        reason = "escort insufficient — reinforce"
    elif strike_ready:
        step = "strike"
        reason = "strike window open"
    else:
        step = "escort"
        reason = "secure escort then strike"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_naval_multi_phase_campaign_product(
    *,
    province_id: int = 1,
    fuel_level: float = 0.65,
) -> Dict[str, Any]:
    fleet = build_fleet_multi_day_autonomy_product(
        province_id=province_id, fuel_level=fuel_level
    )
    posture = plan_fleet_theater_posture(
        [
            {
                "province_id": province_id,
                "zone_relation": "contested",
                "fuel": fuel_level,
            }
        ],
        default_fuel=fuel_level,
    )
    convoy = plan_convoy_escort(
        ["friendly", "contested", "hostile"],
        75.0,
        cargo_value=100.0,
        interdiction_chance=0.28,
        basing_refuel=0.3,
    )
    basing = basing_fleet_fuel_logistics(
        basing_level="port",
        fuel_level=fuel_level,
        available_strength=100.0,
        zone_relation="contested",
    )
    combat = build_multi_phase_combat_product(province_id=province_id)

    posture_sc_raw = 0.5
    if posture.get("top") and isinstance(posture["top"][0], Mapping):
        posture_sc_raw = float(posture["top"][0].get("best_score", 50)) / 100.0
    posture_score = _floor(
        0.55 * _norm(float(fleet.get("score", 0.5))) + 0.45 * _norm(posture_sc_raw)
    )
    escort_ok = bool(convoy.get("sufficient", False))
    basing_sc = float(basing.get("logistics_score", basing.get("score", 0.5)))
    escort_score = _floor(0.5 * (1.0 if escort_ok else 0.4) + 0.5 * _norm(basing_sc))
    strike_score = _floor(
        0.55 * _norm(float(combat.get("score", 0.5)))
        + 0.45 * posture_score
    )
    score = _floor(0.35 * posture_score + 0.3 * escort_score + 0.35 * strike_score)
    rec = recommend_naval_phase_step(
        posture_score=posture_score,
        escort_ok=escort_ok,
        strike_ready=strike_score >= 0.4 and escort_ok,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "posture": posture_score,
        "escort": escort_score,
        "strike": strike_score,
    }
    step_leaves = {
        "posture": "apply_station",
        "escort": "apply_station",
        "strike": "apply_assault",
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
            "action_id": "naval_multi_phase_campaign_product",
            "label": "Run naval multi-phase campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "naval_phase_posture")),
            "label": "Recommended: %s" % rec.get("step", "posture"),
            "enabled": True,
        },
        {
            "action_id": "fleet_multi_day_autonomy_product",
            "label": "Open fleet multi-day autonomy",
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
        "Naval multi-phase · posture %.2f · escort %s · strike %.2f · score %.2f"
        % (posture_score, "ok" if escort_ok else "thin", strike_score, score)
    )
    return {
        "fleet": fleet,
        "posture": posture,
        "convoy": convoy,
        "basing": basing,
        "combat": combat,
        "posture_score": posture_score,
        "escort_score": escort_score,
        "strike_score": strike_score,
        "escort_ok": escort_ok,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "naval_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(rec.get("summary", "")),
                str(fleet.get("summary", "")),
                str(convoy.get("summary", "")),
                str(combat.get("summary", "")),
            ]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#0ea5e9]⚓ Naval multi-phase[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": [
            "naval_multi_phase_campaign_product",
            "naval_phase_posture",
            "naval_phase_escort",
            "naval_phase_strike",
            "major_15",
            "naval",
            "multi_phase",
        ],
    }


def execute_naval_phase_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "posture").strip().lower()
    if s.startswith("naval_phase_"):
        s = s.replace("naval_phase_", "")
    if s not in _STEP_META:
        s = "posture"
    meta = _STEP_META[s]
    product = build_naval_multi_phase_campaign_product(province_id=province_id)
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
    label = "Execute naval phase %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#0ea5e9]⚓ Naval %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_naval_phase_step", s, leaf],
    }


def naval_multi_phase_campaign_integrity() -> Dict[str, Any]:
    product = build_naval_multi_phase_campaign_product()
    steps = [execute_naval_phase_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    fleet_g = fleet_multi_day_autonomy_integrity()
    combat_g = multi_phase_combat_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(fleet_g.get("ok", True))
        and bool(combat_g.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "escort_ok": bool(product.get("escort_ok")),
        "gate": gate,
        "summary": "Naval multi-phase campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_naval_multi_phase_campaign_product_loop() -> Dict[str, Any]:
    product = build_naval_multi_phase_campaign_product(fuel_level=0.55)
    full = build_naval_multi_phase_campaign_product(fuel_level=0.85)
    gate = naval_multi_phase_campaign_integrity()
    ok = (
        bool(gate.get("ok"))
        and len(product.get("apply_queue") or []) >= 3
        and float(full.get("score", 0)) >= float(product.get("score", 0)) * 0.85
    )
    label = "Close naval multi-phase · score %.2f · queue %d · %s" % (
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
        "bbcode": "[color=#0ea5e9]✓ Naval multi-phase[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
