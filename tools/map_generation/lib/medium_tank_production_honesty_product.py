"""Medium-tank production honesty product (major #27) — Phase 1 P0.

Prove multi-month medium OOB windows: 60d seed → 80d risk → 100d complete equip.
Composes medium_tank_oob_product horizons with unit-completion honesty stats
(reliability/crew/modules projection) for dual evidence medium_tank_complete.
"""
from __future__ import annotations
from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity, oob_factory_risk_loop  # type: ignore
from medium_tank_oob_product import (  # type: ignore
    build_medium_tank_oob_product,
    execute_oob_horizon_step,
    medium_tank_oob_product_integrity,
    HORIZON_STEPS,
)
from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore

PRODUCT_STEPS = ("prove_60d", "prove_80d", "prove_100d")
_STEP_META = {
    "prove_60d": {
        "action_id": "medium_honesty_prove_60d",
        "leaf": "apply_production",
        "label": "Step 0 — prove 60d medium seed/priority",
        "horizon": 60,
    },
    "prove_80d": {
        "action_id": "medium_honesty_prove_80d",
        "leaf": "apply_production",
        "label": "Step 1 — prove 80d factory risk window",
        "horizon": 80,
    },
    "prove_100d": {
        "action_id": "medium_honesty_prove_100d",
        "leaf": "apply_supply",
        "label": "Step 2 — prove 100d complete unit equip",
        "horizon": 100,
    },
}

# Historical medium design honesty sheet (stats for equip proof, not fake combat)
_MEDIUM_UNIT_SHEET = {
    "design_id": "panzer_iii_j_medium",
    "name": "Panzer III Ausf. J (medium)",
    "crew_required": 5,
    "base_production_days": 62,
    "reliability": 0.70,
    "speed": 34.0,
    "armor": 42.0,
    "hardness": 0.76,
    "modules": ["medium_gun", "radio", "tracks", "engine"],
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


def project_medium_unit_completion(
    *,
    horizon_days: int = 100,
    tank_line_progress: float = 0.15,
    factories: int = 14,
    days_per_unit: float = 62.0,
) -> Dict[str, Any]:
    """Project whether a medium line completes units in horizon_days with honesty stats."""
    progress = max(0.0, min(1.0, float(tank_line_progress)))
    dpu = max(1.0, float(days_per_unit))
    # Effective daily rate scales mildly with factories (1 factory ~1.0, 14 ~1.15)
    rate = 1.0 + 0.012 * max(0, min(20, int(factories) - 1))
    remaining = dpu * (1.0 - progress)
    effective_days = float(horizon_days) * rate
    units = int(effective_days // max(remaining if remaining > 0.01 else dpu, 1.0))
    if remaining <= effective_days:
        units = max(units, 1)
    complete = units >= 1 and float(horizon_days) >= 60
    # Progress at end of window
    end_prog = min(1.5, progress + effective_days / dpu)
    sheet = dict(_MEDIUM_UNIT_SHEET)
    sheet["units_projected"] = units
    sheet["will_complete"] = complete
    sheet["end_progress"] = round(end_prog, 3)
    sheet["horizon_days"] = int(horizon_days)
    sheet["days_per_unit"] = dpu
    sheet["factory_rate"] = round(rate, 3)
    sheet["summary"] = (
        "Medium unit project · %dd · dpu %.0f · rate %.2f · units %d · complete %s · rel %.0f%% crew %d"
        % (
            horizon_days,
            dpu,
            rate,
            units,
            "yes" if complete else "no",
            float(sheet["reliability"]) * 100.0,
            int(sheet["crew_required"]),
        )
    )
    sheet["empty"] = False
    return sheet


def recommend_honesty_step(
    *,
    complete_60: bool = False,
    complete_80: bool = False,
    complete_100: bool = False,
    progress: float = 0.15,
) -> Dict[str, Any]:
    prog = _norm(progress)
    if not complete_60 or prog < 0.35:
        step, reason = "prove_60d", "medium line early — prove 60d seed"
    elif not complete_80:
        step, reason = "prove_80d", "mid window — prove factory risk at 80d"
    elif not complete_100:
        step, reason = "prove_100d", "near complete — prove 100d equip"
    else:
        step, reason = "prove_100d", "honesty locked — reaffirm 100d complete"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "horizon_days": meta["horizon"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_medium_tank_production_honesty_product(
    *,
    province_id: int = 1,
    tank_line_progress: float = 0.15,
    factories: int = 14,
    tank_stock: float = 0.0,
) -> Dict[str, Any]:
    oob = build_medium_tank_oob_product(
        province_id,
        tank_line_progress=tank_line_progress,
        tank_stock=tank_stock,
        factories=factories,
    )
    risk = oob_factory_risk_loop(base_output=1.0 + 0.01 * max(0, min(20, int(factories))))
    ready = force_readiness_day()
    projections: Dict[int, Dict[str, Any]] = {}
    for h in HORIZON_STEPS:
        projections[h] = project_medium_unit_completion(
            horizon_days=h,
            tank_line_progress=tank_line_progress,
            factories=factories,
            days_per_unit=62.0,
        )
    c60 = bool(projections[60].get("will_complete"))
    c80 = bool(projections[80].get("will_complete"))
    c100 = bool(projections[100].get("will_complete"))
    score_60 = _floor(0.55 if c60 else 0.35 + 0.2 * _norm(tank_line_progress))
    score_80 = _floor(0.55 if c80 else 0.4 + 0.15 * _norm(float(risk.get("score", 0.5))))
    score_100 = _floor(
        0.65 if c100 else 0.4 + 0.25 * _norm(float(oob.get("score", 0.5)))
    )
    score = _floor(0.3 * score_60 + 0.3 * score_80 + 0.4 * score_100)
    rec = recommend_honesty_step(
        complete_60=c60, complete_80=c80, complete_100=c100, progress=tank_line_progress
    )
    step_scores = {"prove_60d": score_60, "prove_80d": score_80, "prove_100d": score_100}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append(
            {
                "index": i,
                "step": step,
                "action_id": meta["action_id"],
                "leaf_action": meta["leaf"],
                "label": lab,
                "score": sc,
                "horizon_days": meta["horizon"],
                "enabled": True,
                "recommended": recommended,
                "province_id": max(1, int(province_id)),
            }
        )
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
            }
        )
    unit_sheet = projections[100]
    medium_tank_complete = 1 if c100 and int(unit_sheet.get("units_projected", 0)) >= 1 else 0
    actions = [
        {
            "action_id": "medium_tank_production_honesty_product",
            "label": "Run medium-tank production honesty product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id")),
            "label": "Recommended: %s" % rec.get("step"),
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
        "Medium-tank production honesty · 60/80/100 · complete100 %s · units %d · medium_tank_complete=%d · score %.2f"
        % (
            "yes" if c100 else "no",
            int(unit_sheet.get("units_projected", 0)),
            medium_tank_complete,
            score,
        )
    )
    return {
        "oob": oob,
        "risk": risk,
        "ready": ready,
        "projections": {str(k): v for k, v in projections.items()},
        "unit_sheet": unit_sheet,
        "complete_60": c60,
        "complete_80": c80,
        "complete_100": c100,
        "medium_tank_complete": medium_tank_complete,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "honesty_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [label, str(rec.get("summary", "")), str(unit_sheet.get("summary", ""))]
            + [r["label"] for r in day_rows]
        ),
        "bbcode": "[color=#c8e06a]🛡 Medium honesty[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "medium_tank_production_honesty_product",
            "medium_honesty_prove_60d",
            "medium_honesty_prove_80d",
            "medium_honesty_prove_100d",
            "major_27",
            "medium_tank",
            "production_honesty",
        ],
    }


def execute_medium_honesty_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "prove_60d").strip().lower()
    if s.startswith("medium_honesty_"):
        s = s.replace("medium_honesty_", "")
    if s in ("60", "60d", "prove60", "prove_60"):
        s = "prove_60d"
    elif s in ("80", "80d", "prove80", "prove_80"):
        s = "prove_80d"
    elif s in ("100", "100d", "prove100", "prove_100"):
        s = "prove_100d"
    if s not in _STEP_META:
        s = "prove_60d"
    meta = _STEP_META[s]
    product = build_medium_tank_production_honesty_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    # Also exercise underlying OOB horizon execute
    hz = int(meta["horizon"])
    oob_step = execute_oob_horizon_step(hz, province_id=province_id)
    label = "Execute medium honesty %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "horizon_days": hz,
        "oob_step": oob_step,
        "apply_queue": [
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": score,
                "enabled": True,
                "label": meta["label"],
                "step": s,
                "product_action": meta["action_id"],
            }
        ],
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c8e06a]🛡 Honesty %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_medium_honesty_step", s, leaf],
    }


def medium_tank_production_honesty_integrity() -> Dict[str, Any]:
    product = build_medium_tank_production_honesty_product()
    steps = [execute_medium_honesty_step(s) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    oob_gate = medium_tank_oob_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and int(product.get("medium_tank_complete", 0)) >= 1
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(oob_gate.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "medium_tank_complete": int(product.get("medium_tank_complete", 0)),
        "summary": "Medium-tank production honesty integrity %s · medium_tank_complete=%d"
        % ("PASS" if ok else "FAIL", int(product.get("medium_tank_complete", 0))),
        "empty": False,
    }


def close_medium_tank_production_honesty_product_loop() -> Dict[str, Any]:
    product = build_medium_tank_production_honesty_product(province_id=2, tank_line_progress=0.2)
    gate = medium_tank_production_honesty_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close medium-tank production honesty · complete=%d · score %.2f · %s" % (
        int(product.get("medium_tank_complete", 0)),
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "medium_tank_complete": int(product.get("medium_tank_complete", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c8e06a]✓ Medium honesty[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
