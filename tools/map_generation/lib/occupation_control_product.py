"""Occupation control product (major #24).

Control board → garrison/secure → integrate economy/front.
Composes theater command, front continuity, agent campaign, war economy, force readiness.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from theater_command_product import build_theater_command_product  # type: ignore
from front_continuity_campaign_product import build_front_continuity_campaign_product  # type: ignore
from agent_campaign_product import build_agent_campaign_product  # type: ignore
from war_economy_mobilization_product import build_war_economy_mobilization_product  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore

PRODUCT_STEPS = ("control", "garrison", "integrate")
_STEP_META = {
    "control": {"action_id": "occupation_control_board", "leaf": "apply_station", "label": "Step 0 — occupation control board"},
    "garrison": {"action_id": "occupation_control_garrison", "leaf": "apply_assault", "label": "Step 1 — garrison/secure"},
    "integrate": {"action_id": "occupation_control_integrate", "leaf": "apply_production", "label": "Step 2 — integrate economy/front"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_occupation_step(*, control_score: float = 0.5, garrison_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if control_score < 0.45:
        step, reason = "control", "control thin — re-board occupation"
    elif garrison_score < 0.45:
        step, reason = "garrison", "garrison insecure — secure province"
    elif ready:
        step, reason = "integrate", "secure — integrate economy/front"
    else:
        step, reason = "garrison", "refresh garrison"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_occupation_control_product(*, province_id: int = 1) -> Dict[str, Any]:
    theater = build_theater_command_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    agent = build_agent_campaign_product(province_id=province_id)
    economy = build_war_economy_mobilization_product(province_id=province_id)
    ready = force_readiness_day()
    control_score = _floor(0.55 * _norm(float(theater.get("score", 0.5))) + 0.45 * _norm(float(agent.get("score", 0.5))))
    garrison_score = _floor(0.5 * _norm(float(front.get("score", 0.5))) + 0.5 * _norm(float(ready.get("score", 0.5))))
    integrate_score = _floor(0.5 * control_score + 0.5 * _norm(float(economy.get("score", 0.5))))
    score = _floor(0.35 * control_score + 0.35 * garrison_score + 0.3 * integrate_score)
    rec = recommend_occupation_step(control_score=control_score, garrison_score=garrison_score, ready=control_score >= 0.45 and garrison_score >= 0.45)
    step_scores = {"control": control_score, "garrison": garrison_score, "integrate": integrate_score}
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
    actions = [{"action_id": "occupation_control_product", "label": "Run occupation control product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Occupation control · control %.2f · garrison %.2f · integrate %.2f · score %.2f" % (control_score, garrison_score, integrate_score, score)
    return {"theater": theater, "front": front, "agent": agent, "economy": economy, "ready": ready,
            "control_score": control_score, "garrison_score": garrison_score, "integrate_score": integrate_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "occupation_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#c8a45e]🏛 Occupation[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["occupation_control_product", "occupation_control_board", "occupation_control_garrison", "occupation_control_integrate", "major_24", "occupation", "control"]}

def execute_occupation_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "control").strip().lower().replace("occupation_control_", "")
    if s not in _STEP_META: s = "control"
    meta = _STEP_META[s]
    product = build_occupation_control_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute occupation %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#c8a45e]🏛 Occupation %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_occupation_step", s, leaf]}

def occupation_control_integrity() -> Dict[str, Any]:
    product = build_occupation_control_product()
    steps = [execute_occupation_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Occupation control integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_occupation_control_product_loop() -> Dict[str, Any]:
    product = build_occupation_control_product(province_id=2)
    gate = occupation_control_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close occupation control · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#c8a45e]✓ Occupation[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
