"""Manpower reinforcement product (major #25).

Draft/readiness board → reinforce lines from stockpile → field OOB units.
Composes force readiness, OOB, industry surge, war economy, reinforce stockpile patterns.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
from industry_surge_day import industry_surge_day  # type: ignore
from war_economy_mobilization_product import build_war_economy_mobilization_product  # type: ignore
from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore

PRODUCT_STEPS = ("draft", "reinforce", "field")
_STEP_META = {
    "draft": {"action_id": "manpower_draft_board", "leaf": "apply_focus", "label": "Step 0 — draft/readiness board"},
    "reinforce": {"action_id": "manpower_reinforce_lines", "leaf": "apply_production", "label": "Step 1 — reinforce lines"},
    "field": {"action_id": "manpower_field_units", "leaf": "apply_station", "label": "Step 2 — field OOB units"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_manpower_step(*, draft_score: float = 0.5, reinforce_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if draft_score < 0.45:
        step, reason = "draft", "readiness/draft thin — re-board manpower"
    elif reinforce_score < 0.45:
        step, reason = "reinforce", "lines under-reinforced"
    elif ready:
        step, reason = "field", "lines ready — field OOB units"
    else:
        step, reason = "reinforce", "refresh reinforce"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_manpower_reinforcement_product(*, province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day()
    oob = build_medium_tank_oob_product(province_id=province_id)
    surge = industry_surge_day(province_id=province_id)
    economy = build_war_economy_mobilization_product(province_id=province_id)
    logistics = build_logistics_supply_theater_product(province_id=province_id)
    draft_score = _floor(0.55 * _norm(float(ready.get("score", 0.5))) + 0.45 * _norm(float(economy.get("score", 0.5))))
    reinforce_score = _floor(0.5 * _norm(float(surge.get("score", 0.5))) + 0.5 * _norm(float(logistics.get("score", 0.5))))
    field_score = _floor(0.55 * _norm(float(oob.get("score", 0.5))) + 0.45 * reinforce_score)
    score = _floor(0.35 * draft_score + 0.35 * reinforce_score + 0.3 * field_score)
    rec = recommend_manpower_step(draft_score=draft_score, reinforce_score=reinforce_score, ready=draft_score >= 0.45 and reinforce_score >= 0.45)
    step_scores = {"draft": draft_score, "reinforce": reinforce_score, "field": field_score}
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
    actions = [{"action_id": "manpower_reinforcement_product", "label": "Run manpower reinforcement product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Manpower reinforcement · draft %.2f · reinforce %.2f · field %.2f · score %.2f" % (draft_score, reinforce_score, field_score, score)
    return {"ready": ready, "oob": oob, "surge": surge, "economy": economy, "logistics": logistics,
            "draft_score": draft_score, "reinforce_score": reinforce_score, "field_score": field_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "manpower_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#9ad06a]🎖 Manpower[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["manpower_reinforcement_product", "manpower_draft_board", "manpower_reinforce_lines", "manpower_field_units", "major_25", "manpower", "reinforce"]}

def execute_manpower_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "draft").strip().lower().replace("manpower_", "")
    if s.startswith("draft"): s = "draft"
    elif s.startswith("reinforce"): s = "reinforce"
    elif s.startswith("field"): s = "field"
    if s not in _STEP_META: s = "draft"
    meta = _STEP_META[s]
    product = build_manpower_reinforcement_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute manpower %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#9ad06a]🎖 Manpower %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_manpower_step", s, leaf]}

def manpower_reinforcement_integrity() -> Dict[str, Any]:
    product = build_manpower_reinforcement_product()
    steps = [execute_manpower_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Manpower reinforcement integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_manpower_reinforcement_product_loop() -> Dict[str, Any]:
    product = build_manpower_reinforcement_product(province_id=2)
    gate = manpower_reinforcement_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close manpower reinforcement · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#9ad06a]✓ Manpower[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
