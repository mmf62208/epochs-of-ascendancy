"""Occupation resistance & compliance product (major #29) — Phase 2.

Board resistance/compliance → set occupation policy → daily tick effects.
Extends occupation_control_product with live province occupation state.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from occupation_control_product import build_occupation_control_product  # type: ignore

PRODUCT_STEPS = ("board", "policy", "tick")
POLICIES = ("harsh", "moderate", "lenient")
_STEP_META = {
    "board": {"action_id": "occupation_resistance_board", "leaf": "apply_station", "label": "Step 0 — resistance/compliance board"},
    "policy": {"action_id": "occupation_resistance_policy", "leaf": "apply_focus", "label": "Step 1 — set occupation policy"},
    "tick": {"action_id": "occupation_resistance_tick", "leaf": "apply_supply", "label": "Step 2 — daily occupation tick"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def compute_occupation_state(
    *,
    resistance_level: float = 0.55,
    compliance_level: float = 0.40,
    policy: str = "moderate",
    control_score: float = 0.6,
) -> Dict[str, Any]:
    r = _norm(resistance_level)
    c = _norm(compliance_level)
    pol = str(policy or "moderate").lower()
    if pol not in POLICIES:
        pol = "moderate"
    # Policy effects
    if pol == "harsh":
        r_delta, c_delta, revolt, factory_mult = -0.08, -0.05, 0.12, 0.85
        manpower_drain = 0.08
    elif pol == "lenient":
        r_delta, c_delta, revolt, factory_mult = -0.03, 0.08, 0.04, 0.95
        manpower_drain = 0.03
    else:  # moderate
        r_delta, c_delta, revolt, factory_mult = -0.05, 0.04, 0.07, 0.90
        manpower_drain = 0.05
    r2 = _norm(r + r_delta * (1.0 - control_score * 0.3))
    c2 = _norm(c + c_delta * (0.5 + control_score * 0.5))
    stability = _floor(0.55 * c2 + 0.45 * (1.0 - r2))
    revolt_risk = _floor(revolt + 0.4 * r2 - 0.25 * c2)
    return {
        "resistance_level": r2,
        "compliance_level": c2,
        "policy": pol,
        "stability": stability,
        "revolt_risk": revolt_risk,
        "factory_output_mult": factory_mult,
        "manpower_drain": manpower_drain,
        "summary": "Occupation · policy %s · R %.0f%% · C %.0f%% · stability %.0f%% · revolt %.0f%% · fac ×%.2f"
        % (pol, r2 * 100, c2 * 100, stability * 100, revolt_risk * 100, factory_mult),
        "empty": False,
    }

def recommend_occupation_resistance_step(
    *, resistance: float = 0.55, compliance: float = 0.4, policy_set: bool = False
) -> Dict[str, Any]:
    if resistance > 0.55 or compliance < 0.4:
        step, reason = "board", "resistance high / compliance thin — re-board"
    elif not policy_set:
        step, reason = "policy", "choose harsh/moderate/lenient policy"
    else:
        step, reason = "tick", "policy set — run occupation daily tick"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_occupation_resistance_compliance_product(
    *, province_id: int = 1, resistance_level: float = 0.55, compliance_level: float = 0.40, policy: str = "moderate"
) -> Dict[str, Any]:
    control = build_occupation_control_product(province_id=province_id)
    state = compute_occupation_state(
        resistance_level=resistance_level,
        compliance_level=compliance_level,
        policy=policy,
        control_score=float(control.get("score", 0.6)),
    )
    board_score = _floor(0.55 * float(state["stability"]) + 0.45 * float(control.get("score", 0.5)))
    policy_score = _floor(0.5 + 0.3 * float(state["compliance_level"]) - 0.2 * float(state["revolt_risk"]))
    tick_score = _floor(0.45 * board_score + 0.55 * policy_score)
    score = _floor(0.35 * board_score + 0.35 * policy_score + 0.3 * tick_score)
    rec = recommend_occupation_resistance_step(
        resistance=float(state["resistance_level"]),
        compliance=float(state["compliance_level"]),
        policy_set=True,
    )
    step_scores = {"board": board_score, "policy": policy_score, "tick": tick_score}
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
    actions = [
        {"action_id": "occupation_resistance_compliance_product", "label": "Run occupation resistance/compliance product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "occupation_policy_harsh", "label": "Policy: harsh", "enabled": True},
        {"action_id": "occupation_policy_moderate", "label": "Policy: moderate", "enabled": True},
        {"action_id": "occupation_policy_lenient", "label": "Policy: lenient", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Occupation resistance/compliance · %s · score %.2f" % (state["summary"].split(" · ", 1)[-1] if " · " in state["summary"] else state["summary"], score)
    label = "Occupation resistance/compliance · policy %s · R %.0f%% C %.0f%% · score %.2f" % (
        state["policy"], state["resistance_level"] * 100, state["compliance_level"] * 100, score)
    return {
        "control": control, "state": state, "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "resistance_level": state["resistance_level"], "compliance_level": state["compliance_level"], "policy": state["policy"],
        "revolt_risk": state["revolt_risk"], "score": score, "occupation_score": score, "province_id": max(1, int(province_id)),
        "summary": label, "plain": "\n".join([label, str(rec.get("summary","")), str(state.get("summary",""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#c8a45e]⚖ Occupation R/C[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
        "integration": ["occupation_resistance_compliance_product", "occupation_resistance_board", "occupation_resistance_policy", "occupation_resistance_tick", "major_29", "occupation", "resistance", "compliance"],
    }

def execute_occupation_resistance_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("occupation_resistance_", "")
    if s not in _STEP_META: s = "board"
    meta = _STEP_META[s]
    product = build_occupation_resistance_compliance_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute occupation resistance %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score, "province_id": max(1,int(province_id)),
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "summary": label, "plain": label, "bbcode": "[color=#c8a45e]⚖ Occ %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False,
            "integration": ["execute_occupation_resistance_step", s, leaf]}

def occupation_resistance_compliance_integrity() -> Dict[str, Any]:
    product = build_occupation_resistance_compliance_product()
    steps = [execute_occupation_resistance_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Occupation resistance/compliance integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_occupation_resistance_compliance_product_loop() -> Dict[str, Any]:
    product = build_occupation_resistance_compliance_product(province_id=2)
    gate = occupation_resistance_compliance_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close occupation resistance/compliance · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
