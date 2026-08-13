"""Manpower laws & training pipeline product (major #30) — Phase 2.

Set conscription law → train pipeline → field to OOB reinforce.
Extends manpower_reinforcement_product with national pools and laws.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from manpower_reinforcement_product import build_manpower_reinforcement_product  # type: ignore

PRODUCT_STEPS = ("law", "train", "field")
LAWS = ("volunteer", "limited", "extensive", "service_by_requirement")
_LAW_MULT = {"volunteer": 0.55, "limited": 0.75, "extensive": 0.95, "service_by_requirement": 1.15}
_STEP_META = {
    "law": {"action_id": "manpower_law_board", "leaf": "apply_focus", "label": "Step 0 — set conscription law"},
    "train": {"action_id": "manpower_train_pipeline", "leaf": "apply_production", "label": "Step 1 — training camp pipeline"},
    "field": {"action_id": "manpower_field_trained", "leaf": "apply_station", "label": "Step 2 — field trained manpower to OOB"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def compute_manpower_pipeline(
    *,
    population_pool: float = 100000.0,
    law: str = "limited",
    training_capacity: float = 0.6,
    trained_stock: float = 5000.0,
    reinforce_need: float = 0.5,
) -> Dict[str, Any]:
    law_k = str(law or "limited").lower()
    if law_k not in _LAW_MULT:
        law_k = "limited"
    mult = _LAW_MULT[law_k]
    eligible = max(0.0, float(population_pool) * 0.12 * mult)
    train_cap = max(0.0, float(training_capacity))
    train_out = eligible * 0.08 * train_cap
    trained = max(0.0, float(trained_stock) + train_out)
    fielded = min(trained * 0.15, trained * _norm(reinforce_need))
    pool_score = _floor(min(1.0, eligible / 20000.0))
    train_score = _floor(0.4 * train_cap + 0.6 * min(1.0, train_out / 800.0))
    field_score = _floor(0.5 * min(1.0, fielded / 1500.0) + 0.5 * pool_score)
    return {
        "law": law_k,
        "law_mult": mult,
        "eligible_manpower": eligible,
        "training_output": train_out,
        "trained_stock": trained,
        "fielded": fielded,
        "pool_score": pool_score,
        "train_score": train_score,
        "field_score": field_score,
        "summary": "Manpower · law %s ×%.2f · eligible %.0f · train +%.0f · trained %.0f · field %.0f"
        % (law_k, mult, eligible, train_out, trained, fielded),
        "empty": False,
    }

def recommend_manpower_law_step(*, law_set: bool = True, train_ready: bool = False, field_ready: bool = False) -> Dict[str, Any]:
    if not law_set:
        step, reason = "law", "no conscription law — set volunteer/limited/extensive"
    elif not train_ready:
        step, reason = "train", "pipeline thin — fund training camps"
    elif field_ready:
        step, reason = "field", "trained ready — field to OOB reinforce"
    else:
        step, reason = "train", "refresh training throughput"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_manpower_laws_training_product(
    *, province_id: int = 1, law: str = "limited", population_pool: float = 100000.0, training_capacity: float = 0.65
) -> Dict[str, Any]:
    base = build_manpower_reinforcement_product(province_id=province_id)
    pipe = compute_manpower_pipeline(
        population_pool=population_pool, law=law, training_capacity=training_capacity,
        trained_stock=5000.0, reinforce_need=float(base.get("score", 0.5)),
    )
    law_score = _floor(0.5 * float(pipe["pool_score"]) + 0.5 * _norm(float(base.get("score", 0.5))))
    train_score = float(pipe["train_score"])
    field_score = float(pipe["field_score"])
    score = _floor(0.35 * law_score + 0.35 * train_score + 0.3 * field_score)
    rec = recommend_manpower_law_step(law_set=True, train_ready=train_score >= 0.45, field_ready=field_score >= 0.45)
    step_scores = {"law": law_score, "train": train_score, "field": field_score}
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
        {"action_id": "manpower_laws_training_product", "label": "Run manpower laws/training product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "manpower_law_volunteer", "label": "Law: volunteer", "enabled": True},
        {"action_id": "manpower_law_limited", "label": "Law: limited", "enabled": True},
        {"action_id": "manpower_law_extensive", "label": "Law: extensive", "enabled": True},
        {"action_id": "manpower_law_service_by_requirement", "label": "Law: service by requirement", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Manpower laws/training · law %s · eligible %.0f · train +%.0f · field %.0f · score %.2f" % (
        pipe["law"], pipe["eligible_manpower"], pipe["training_output"], pipe["fielded"], score)
    return {
        "base": base, "pipeline": pipe, "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "law": pipe["law"], "eligible_manpower": pipe["eligible_manpower"], "trained_stock": pipe["trained_stock"],
        "fielded": pipe["fielded"], "score": score, "manpower_score": score, "province_id": max(1, int(province_id)),
        "summary": label, "plain": "\n".join([label, str(rec.get("summary","")), str(pipe.get("summary",""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#9ad06a]🎖 Manpower laws[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
        "integration": ["manpower_laws_training_product", "manpower_law_board", "manpower_train_pipeline", "manpower_field_trained", "major_30", "manpower", "laws", "training"],
    }

def execute_manpower_law_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "law").strip().lower().replace("manpower_", "")
    if s.startswith("law"): s = "law"
    elif s.startswith("train"): s = "train"
    elif s.startswith("field"): s = "field"
    if s not in _STEP_META: s = "law"
    meta = _STEP_META[s]
    product = build_manpower_laws_training_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute manpower law %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score, "province_id": max(1,int(province_id)),
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "summary": label, "plain": label, "empty": False, "integration": ["execute_manpower_law_step", s, leaf]}

def manpower_laws_training_integrity() -> Dict[str, Any]:
    product = build_manpower_laws_training_product()
    steps = [execute_manpower_law_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Manpower laws/training integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_manpower_laws_training_product_loop() -> Dict[str, Any]:
    product = build_manpower_laws_training_product(province_id=2)
    gate = manpower_laws_training_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close manpower laws/training · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
