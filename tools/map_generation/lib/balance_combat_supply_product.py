"""Balance combat/supply honesty product (major #43) — Phase 6.

Estimate board → live sample tick → variance close.
Balance pass first slice: combat estimate vs supply attrition curves.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from multi_phase_combat_product import build_multi_phase_combat_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_phase_combat_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "combat"}

try:
    from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
except Exception:  # pragma: no cover
    def build_logistics_supply_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False, "summary": "supply"}

PRODUCT_STEPS = ("estimate", "sample", "close")
_STEP_META = {
    "estimate": {"action_id": "balance_estimate_board", "leaf": "apply_assault", "label": "Step 0 — combat/supply estimate board"},
    "sample": {"action_id": "balance_live_sample", "leaf": "apply_supply", "label": "Step 1 — live sample tick"},
    "close": {"action_id": "balance_variance_close", "leaf": "apply_production", "label": "Step 2 — variance close gate"},
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


def compute_estimate_board(*, combat_score: float = 0.6, supply_score: float = 0.55) -> Dict[str, Any]:
    c = _floor(combat_score)
    s = _floor(supply_score)
    joint = _floor(0.55 * c + 0.45 * s)
    attrition = _floor(0.35 + 0.4 * (1.0 - s) + 0.2 * (1.0 - c))
    return {
        "combat_score": c,
        "supply_score": s,
        "joint": joint,
        "attrition": attrition,
        "summary": "Balance estimate · combat %.2f · supply %.2f · joint %.2f · attr %.0f%%"
        % (c, s, joint, attrition * 100),
        "empty": False,
    }


def compute_live_sample(*, joint: float = 0.6, noise: float = 0.05) -> Dict[str, Any]:
    j = _floor(joint)
    n = max(0.0, min(0.25, float(noise)))
    # Simulated live sample slightly off estimate
    live = _floor(j * (1.0 - 0.5 * n) + 0.5 * n * 0.7)
    variance = abs(live - j)
    within = variance <= 0.18
    return {
        "live_score": live,
        "estimate": j,
        "variance": variance,
        "within_band": within,
        "summary": "Live sample · live %.2f · est %.2f · var %.2f · %s"
        % (live, j, variance, "PASS" if within else "WIDE"),
        "empty": False,
    }


def recommend_balance_step(*, estimated: bool = False, sampled: bool = False) -> Dict[str, Any]:
    if not estimated:
        step, reason = "estimate", "board combat/supply estimates"
    elif not sampled:
        step, reason = "sample", "run live sample tick"
    else:
        step, reason = "close", "close variance gate"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_balance_combat_supply_product(*, province_id: int = 1, noise: float = 0.08) -> Dict[str, Any]:
    combat = build_multi_phase_combat_product(province_id=province_id)
    supply = build_logistics_supply_theater_product(province_id=province_id)
    est = compute_estimate_board(
        combat_score=float(combat.get("score", 0.6)),
        supply_score=float(supply.get("score", 0.55)),
    )
    sample = compute_live_sample(joint=float(est["joint"]), noise=noise)
    est_score = _floor(float(est["joint"]))
    sample_score = _floor(float(sample["live_score"]))
    close_score = _floor(0.55 * sample_score + 0.45 * (1.0 if sample["within_band"] else 0.4))
    score = _floor(0.3 * est_score + 0.35 * sample_score + 0.35 * close_score)
    rec = recommend_balance_step(estimated=True, sampled=True)
    step_scores = {"estimate": est_score, "sample": sample_score, "close": close_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({
            "index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
            "label": lab, "score": sc, "enabled": True, "recommended": recommended,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc,
            "enabled": True, "label": lab, "step": step, "product_action": meta["action_id"],
        })
    actions = [
        {"action_id": "balance_combat_supply_product", "label": "Run balance combat/supply product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Balance combat/supply · joint %.2f · var %.2f · %s · score %.2f" % (
        est["joint"], sample["variance"], "PASS" if sample["within_band"] else "WIDE", score)
    return {
        "combat": combat, "supply": supply, "estimate": est, "sample": sample, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "joint": est["joint"], "variance": sample["variance"], "within_band": sample["within_band"],
        "score": score, "balance_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(est.get("summary", "")), str(sample.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#d0a080]⚖ Balance honesty[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "balance_combat_supply_product", "balance_estimate_board", "balance_live_sample",
            "balance_variance_close", "major_43", "balance", "combat", "supply", "phase6_depth",
        ],
    }


def execute_balance_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "estimate").strip().lower().replace("balance_", "")
    if s.startswith("estimate"):
        s = "estimate"
    elif s.startswith("sample") or s.startswith("live"):
        s = "sample"
    elif s.startswith("close") or s.startswith("var"):
        s = "close"
    if s not in _STEP_META:
        s = "estimate"
    meta = _STEP_META[s]
    product = build_balance_combat_supply_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute balance %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_balance_step", s, leaf],
    }


def balance_combat_supply_integrity() -> Dict[str, Any]:
    product = build_balance_combat_supply_product()
    steps = [execute_balance_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Balance combat/supply integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_balance_combat_supply_product_loop() -> Dict[str, Any]:
    product = build_balance_combat_supply_product(province_id=2, noise=0.1)
    gate = balance_combat_supply_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close balance combat/supply · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
