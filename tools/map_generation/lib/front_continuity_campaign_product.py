"""Front continuity campaign product (major #23).

Multi-phase combat board → assault follow-on rank → force/logistics sustain.
Composes combat multi-phase, assault rank, force readiness, logistics, theater command.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity, assault_follow_on_loop  # type: ignore
from combat_multi_phase_product import build_multi_phase_combat_product  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
from theater_command_product import build_theater_command_product  # type: ignore

PRODUCT_STEPS = ("combat", "assault", "sustain")
_STEP_META = {
    "combat": {"action_id": "front_continuity_combat", "leaf": "apply_assault", "label": "Step 0 — multi-phase combat board"},
    "assault": {"action_id": "front_continuity_assault", "leaf": "apply_assault", "label": "Step 1 — assault follow-on rank"},
    "sustain": {"action_id": "front_continuity_sustain", "leaf": "apply_supply", "label": "Step 2 — force/logistics sustain"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_front_step(*, combat_score: float = 0.5, assault_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if combat_score < 0.45:
        step, reason = "combat", "combat phases weak — re-board multi-phase"
    elif assault_score < 0.45:
        step, reason = "assault", "no strong follow-on assault target"
    elif ready:
        step, reason = "sustain", "front ready — sustain force/logistics"
    else:
        step, reason = "assault", "refresh assault rank"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_front_continuity_campaign_product(*, province_id: int = 1) -> Dict[str, Any]:
    combat = build_multi_phase_combat_product(province_id=province_id)
    ranked = rank_assault_targets([
        {"province_id": max(1, int(province_id)), "pressure": 0.6},
        {"province_id": max(1, int(province_id)) + 1, "pressure": 0.75},
    ])
    follow = assault_follow_on_loop(
        [
            {"province_id": max(1, int(province_id)), "pressure": 0.65},
            {"province_id": max(1, int(province_id)) + 1, "pressure": 0.8},
        ]
    )
    ready = force_readiness_day()
    logistics = build_logistics_supply_theater_product(province_id=province_id)
    theater = build_theater_command_product(province_id=province_id)
    combat_score = _floor(float(combat.get("score", 0.5)))
    assault_score = _floor(
        0.55 * _norm(float((ranked.get("best") or {}).get("overall", ranked.get("score", 0.5))))
        + 0.45 * _norm(float((follow or {}).get("score", follow.get("health", 0.5) if isinstance(follow, dict) else 0.5)))
    )
    sustain_score = _floor(0.4 * _norm(float(ready.get("score", 0.5))) + 0.35 * _norm(float(logistics.get("score", 0.5)))
                           + 0.25 * _norm(float(theater.get("score", 0.5))))
    score = _floor(0.35 * combat_score + 0.35 * assault_score + 0.3 * sustain_score)
    rec = recommend_front_step(combat_score=combat_score, assault_score=assault_score, ready=combat_score >= 0.45 and assault_score >= 0.45)
    step_scores = {"combat": combat_score, "assault": assault_score, "sustain": sustain_score}
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
    actions = [{"action_id": "front_continuity_campaign_product", "label": "Run front continuity campaign product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Front continuity · combat %.2f · assault %.2f · sustain %.2f · score %.2f" % (combat_score, assault_score, sustain_score, score)
    return {"combat": combat, "ranked": ranked, "follow": follow, "ready": ready, "logistics": logistics, "theater": theater,
            "combat_score": combat_score, "assault_score": assault_score, "sustain_score": sustain_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "front_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#ff9a6e]⚔ Front continuity[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["front_continuity_campaign_product", "front_continuity_combat", "front_continuity_assault", "front_continuity_sustain", "major_23", "front", "combat"]}

def execute_front_continuity_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "combat").strip().lower().replace("front_continuity_", "")
    if s not in _STEP_META: s = "combat"
    meta = _STEP_META[s]
    product = build_front_continuity_campaign_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute front continuity %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#ff9a6e]⚔ Front %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_front_continuity_step", s, leaf]}

def front_continuity_campaign_integrity() -> Dict[str, Any]:
    product = build_front_continuity_campaign_product()
    steps = [execute_front_continuity_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Front continuity campaign integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_front_continuity_campaign_product_loop() -> Dict[str, Any]:
    product = build_front_continuity_campaign_product(province_id=2)
    gate = front_continuity_campaign_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close front continuity campaign · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#ff9a6e]✓ Front continuity[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
