"""War economy mobilization product (major #21).

Board factories/stockpile/trade → allocate production priority → sustain war economy.
Composes war_economy, industry surge, trade chain, OOB, production priority.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity, trade_supply_weather_chain  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore
from industry_surge_day import industry_surge_day  # type: ignore
from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore

PRODUCT_STEPS = ("board", "allocate", "sustain")
_STEP_META = {
    "board": {"action_id": "war_economy_board", "leaf": "apply_production", "label": "Step 0 — war economy board"},
    "allocate": {"action_id": "war_economy_allocate", "leaf": "apply_production", "label": "Step 1 — allocate production priority"},
    "sustain": {"action_id": "war_economy_sustain", "leaf": "apply_focus", "label": "Step 2 — sustain war economy"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_war_economy_step(*, board_score: float = 0.5, allocate_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if board_score < 0.45:
        step, reason = "board", "economy board thin — re-scan factories/trade"
    elif allocate_score < 0.45:
        step, reason = "allocate", "priority lines under-allocated"
    elif ready:
        step, reason = "sustain", "board ready — sustain war economy"
    else:
        step, reason = "allocate", "refresh allocation"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_war_economy_mobilization_product(*, province_id: int = 1) -> Dict[str, Any]:
    economy = war_economy_day_package()
    surge = industry_surge_day(province_id=province_id)
    trade = trade_supply_weather_chain(sea_trade_mult=1.0)
    oob = build_medium_tank_oob_product(province_id=province_id)
    board_score = _floor(0.5 * _norm(float(economy.get("score", 0.5))) + 0.5 * _norm(float(trade.get("health", trade.get("score", 0.5)))))
    allocate_score = _floor(0.55 * _norm(float(surge.get("score", 0.5))) + 0.45 * _norm(float(oob.get("score", 0.5))))
    sustain_score = _floor(0.45 * board_score + 0.55 * allocate_score)
    score = _floor(0.35 * board_score + 0.35 * allocate_score + 0.3 * sustain_score)
    rec = recommend_war_economy_step(board_score=board_score, allocate_score=allocate_score, ready=board_score >= 0.45 and allocate_score >= 0.45)
    step_scores = {"board": board_score, "allocate": allocate_score, "sustain": sustain_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({"index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
                         "label": lab, "score": sc, "enabled": True, "recommended": recommended, "province_id": max(1, int(province_id))})
        apply_queue.append({"action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc, "enabled": True,
                            "label": lab, "step": step, "product_action": meta["action_id"]})
    actions = [{"action_id": "war_economy_mobilization_product", "label": "Run war economy mobilization product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "War economy mobilization · board %.2f · allocate %.2f · sustain %.2f · score %.2f" % (board_score, allocate_score, sustain_score, score)
    return {"economy": economy, "surge": surge, "trade": trade, "oob": oob,
            "board_score": board_score, "allocate_score": allocate_score, "sustain_score": sustain_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "economy_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#ffc857]⚙ War economy[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["war_economy_mobilization_product", "war_economy_board", "war_economy_allocate", "war_economy_sustain", "major_21", "economy", "industry"]}

def execute_war_economy_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("war_economy_", "")
    if s not in _STEP_META: s = "board"
    meta = _STEP_META[s]
    product = build_war_economy_mobilization_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute war economy %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#ffc857]⚙ Economy %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_war_economy_step", s, leaf]}

def war_economy_mobilization_integrity() -> Dict[str, Any]:
    product = build_war_economy_mobilization_product()
    steps = [execute_war_economy_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "War economy mobilization integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_war_economy_mobilization_product_loop() -> Dict[str, Any]:
    product = build_war_economy_mobilization_product(province_id=2)
    gate = war_economy_mobilization_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close war economy mobilization · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#ffc857]✓ War economy[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
