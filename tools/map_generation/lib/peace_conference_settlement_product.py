"""Peace conference settlement product (major #31) — Phase 2.

End-war board → set demands (annex/puppet/reparations/zones) → apply settlement.
Extends diplomacy_peace_campaign_product with map-mutating settlement package.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from diplomacy_peace_campaign_product import build_diplomacy_peace_campaign_product  # type: ignore

PRODUCT_STEPS = ("board", "demands", "settle")
DEMAND_TYPES = ("annex", "puppet", "reparations", "occupation_zone")
_STEP_META = {
    "board": {"action_id": "peace_conference_board", "leaf": "apply_focus", "label": "Step 0 — end-war conference board"},
    "demands": {"action_id": "peace_conference_demands", "leaf": "apply_production", "label": "Step 1 — set demands package"},
    "settle": {"action_id": "peace_conference_settle", "leaf": "apply_assault", "label": "Step 2 — apply settlement to map"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def build_demands_package(
    *,
    annex: bool = True,
    puppet: bool = False,
    reparations: float = 0.35,
    occupation_zone: bool = True,
    winner_leverage: float = 0.65,
) -> Dict[str, Any]:
    lev = _norm(winner_leverage)
    rep = _norm(reparations)
    weight = 0.0
    items: List[Dict[str, Any]] = []
    if annex:
        items.append({"type": "annex", "cost": 0.35, "prestige": 0.25})
        weight += 0.35
    if puppet:
        items.append({"type": "puppet", "cost": 0.25, "prestige": 0.15})
        weight += 0.25
    if rep > 0.05:
        items.append({"type": "reparations", "amount": rep, "cost": 0.15 * rep, "prestige": 0.1 * rep})
        weight += 0.15 * rep
    if occupation_zone:
        items.append({"type": "occupation_zone", "cost": 0.2, "prestige": 0.12})
        weight += 0.2
    feasibility = _floor(lev / max(0.25, weight + 0.15))
    ai_accept = _floor(0.4 * lev + 0.35 * feasibility + 0.25 * (1.0 - weight * 0.5))
    return {
        "items": items,
        "demand_weight": weight,
        "feasibility": feasibility,
        "ai_accept": ai_accept,
        "winner_leverage": lev,
        "summary": "Demands · items %d · weight %.2f · feasibility %.0f%% · AI accept %.0f%%"
        % (len(items), weight, feasibility * 100, ai_accept * 100),
        "empty": False,
    }

def recommend_peace_conference_step(
    *, board_ready: bool = True, demands_ready: bool = False, settle_ready: bool = False
) -> Dict[str, Any]:
    if not board_ready:
        step, reason = "board", "war not ended — open conference board"
    elif not demands_ready:
        step, reason = "demands", "set annex/puppet/reparations/zones"
    elif settle_ready:
        step, reason = "settle", "package ready — apply settlement"
    else:
        step, reason = "demands", "refine demands for AI accept"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_peace_conference_settlement_product(
    *, province_id: int = 1, winner_tag: str = "GER", loser_tag: str = "FRA", winner_leverage: float = 0.7
) -> Dict[str, Any]:
    diplo = build_diplomacy_peace_campaign_product(province_id=province_id)
    demands = build_demands_package(winner_leverage=winner_leverage)
    board_score = _floor(0.55 * _norm(float(diplo.get("score", 0.5))) + 0.45 * _norm(winner_leverage))
    demands_score = _floor(0.5 * float(demands["feasibility"]) + 0.5 * float(demands["ai_accept"]))
    settle_score = _floor(0.4 * board_score + 0.6 * demands_score)
    score = _floor(0.35 * board_score + 0.35 * demands_score + 0.3 * settle_score)
    rec = recommend_peace_conference_step(
        board_ready=True,
        demands_ready=demands_score >= 0.4,
        settle_ready=demands_score >= 0.45 and board_score >= 0.45,
    )
    step_scores = {"board": board_score, "demands": demands_score, "settle": settle_score}
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
        {"action_id": "peace_conference_settlement_product", "label": "Run peace conference settlement product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "peace_demand_annex", "label": "Demand: annex", "enabled": True},
        {"action_id": "peace_demand_puppet", "label": "Demand: puppet", "enabled": True},
        {"action_id": "peace_demand_reparations", "label": "Demand: reparations", "enabled": True},
        {"action_id": "peace_demand_occupation_zone", "label": "Demand: occupation zone", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Peace conference · %s→%s · leverage %.0f%% · AI accept %.0f%% · score %.2f" % (
        winner_tag, loser_tag, float(winner_leverage) * 100, float(demands["ai_accept"]) * 100, score)
    return {
        "diplo": diplo, "demands": demands, "winner_tag": winner_tag, "loser_tag": loser_tag,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "ai_accept": demands["ai_accept"], "feasibility": demands["feasibility"],
        "score": score, "peace_score": score, "province_id": max(1, int(province_id)),
        "summary": label, "plain": "\n".join([label, str(rec.get("summary","")), str(demands.get("summary",""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e0c06a]🕊 Peace conference[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
        "integration": ["peace_conference_settlement_product", "peace_conference_board", "peace_conference_demands", "peace_conference_settle", "major_31", "peace", "conference", "settlement"],
    }

def execute_peace_conference_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("peace_conference_", "")
    if s not in _STEP_META: s = "board"
    meta = _STEP_META[s]
    product = build_peace_conference_settlement_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute peace conference %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score, "province_id": max(1,int(province_id)),
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "summary": label, "plain": label, "empty": False, "integration": ["execute_peace_conference_step", s, leaf]}

def peace_conference_settlement_integrity() -> Dict[str, Any]:
    product = build_peace_conference_settlement_product()
    steps = [execute_peace_conference_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Peace conference settlement integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_peace_conference_settlement_product_loop() -> Dict[str, Any]:
    product = build_peace_conference_settlement_product(province_id=2)
    gate = peace_conference_settlement_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close peace conference settlement · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
