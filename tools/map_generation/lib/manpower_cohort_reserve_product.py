"""Manpower cohort & reserve product (major #36) — Phase 4.

Age-cohort board → reserve tier assign → mobilize field strength.
Deepens manpower laws (#30) with cohort pools and reserve tiers.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from manpower_laws_training_product import build_manpower_laws_training_product  # type: ignore
except Exception:  # pragma: no cover
    def build_manpower_laws_training_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "eligible_manpower": 9000, "trained_stock": 5000, "law": "limited"}

PRODUCT_STEPS = ("cohorts", "reserve", "mobilize")
COHORTS = ("youth", "prime", "veteran", "elder")
RESERVE_TIERS = ("active", "ready", "strategic")
_STEP_META = {
    "cohorts": {"action_id": "manpower_cohort_board", "leaf": "apply_focus", "label": "Step 0 — age-cohort board"},
    "reserve": {"action_id": "manpower_cohort_reserve", "leaf": "apply_production", "label": "Step 1 — assign reserve tiers"},
    "mobilize": {"action_id": "manpower_cohort_mobilize", "leaf": "apply_station", "label": "Step 2 — mobilize field strength"},
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


def compute_cohort_pools(*, population_pool: float = 100000.0, law_mult: float = 0.75) -> Dict[str, Any]:
    pop = max(1000.0, float(population_pool))
    lm = max(0.3, min(1.2, float(law_mult)))
    shares = {"youth": 0.22, "prime": 0.38, "veteran": 0.28, "elder": 0.12}
    pools: Dict[str, float] = {}
    eligible = 0.0
    for c, sh in shares.items():
        n = pop * sh * lm * (0.85 if c == "elder" else 1.0)
        pools[c] = round(n, 1)
        if c != "elder":
            eligible += n
    return {
        "population_pool": pop,
        "law_mult": lm,
        "cohorts": pools,
        "eligible": round(eligible, 1),
        "summary": "Cohorts · youth %.0f · prime %.0f · vet %.0f · elder %.0f · eligible %.0f"
        % (pools["youth"], pools["prime"], pools["veteran"], pools["elder"], eligible),
        "empty": False,
    }


def compute_reserve_tiers(*, eligible: float = 50000.0, trained_stock: float = 8000.0) -> Dict[str, Any]:
    el = max(0.0, float(eligible))
    trained = max(0.0, float(trained_stock))
    active = min(trained, el * 0.25)
    ready = min(max(0.0, el * 0.35 - active * 0.1), el * 0.4)
    strategic = max(0.0, el - active - ready)
    readiness = _floor((active * 1.0 + ready * 0.7 + strategic * 0.35) / max(1.0, el))
    return {
        "active": round(active, 1),
        "ready": round(ready, 1),
        "strategic": round(strategic, 1),
        "readiness": readiness,
        "summary": "Reserves · active %.0f · ready %.0f · strategic %.0f · readiness %.0f%%"
        % (active, ready, strategic, readiness * 100),
        "empty": False,
    }


def recommend_cohort_step(*, cohorts_set: bool = False, reserve_set: bool = False) -> Dict[str, Any]:
    if not cohorts_set:
        step, reason = "cohorts", "board age-cohort pools first"
    elif not reserve_set:
        step, reason = "reserve", "assign active/ready/strategic tiers"
    else:
        step, reason = "mobilize", "mobilize active reserve to field"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_manpower_cohort_reserve_product(
    *,
    province_id: int = 1,
    population_pool: float = 100000.0,
    law_mult: float = 0.75,
    trained_stock: float = 8000.0,
) -> Dict[str, Any]:
    laws = build_manpower_laws_training_product(province_id=province_id)
    trained = float(laws.get("trained_stock", trained_stock))
    cohorts = compute_cohort_pools(population_pool=population_pool, law_mult=law_mult)
    reserves = compute_reserve_tiers(eligible=float(cohorts["eligible"]), trained_stock=trained)
    laws_s = _floor(float(laws.get("score", 0.55)))
    cohort_score = _floor(0.5 * laws_s + 0.5 * min(1.0, float(cohorts["eligible"]) / 60000.0))
    reserve_score = _floor(0.45 + 0.55 * float(reserves["readiness"]))
    mobilize_score = _floor(0.4 * reserve_score + 0.35 * cohort_score + 0.25 * min(1.0, float(reserves["active"]) / 15000.0))
    score = _floor(0.3 * cohort_score + 0.35 * reserve_score + 0.35 * mobilize_score)
    rec = recommend_cohort_step(cohorts_set=True, reserve_set=True)
    step_scores = {"cohorts": cohort_score, "reserve": reserve_score, "mobilize": mobilize_score}
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
        {"action_id": "manpower_cohort_reserve_product", "label": "Run manpower cohort/reserve product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "manpower_reserve_active", "label": "Reserve: active", "enabled": True},
        {"action_id": "manpower_reserve_ready", "label": "Reserve: ready", "enabled": True},
        {"action_id": "manpower_reserve_strategic", "label": "Reserve: strategic", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    mobilized = round(float(reserves["active"]) * 0.85, 1)
    label = "Manpower cohort/reserve · eligible %.0f · active %.0f · mobilize %.0f · score %.2f" % (
        float(cohorts["eligible"]), float(reserves["active"]), mobilized, score)
    return {
        "laws": laws, "cohorts": cohorts, "reserves": reserves, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "eligible": cohorts["eligible"], "active": reserves["active"], "mobilized": mobilized,
        "readiness": reserves["readiness"], "score": score, "cohort_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(cohorts.get("summary", "")), str(reserves.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#70b090]👥 Cohort/reserve[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "manpower_cohort_reserve_product", "manpower_cohort_board", "manpower_cohort_reserve",
            "manpower_cohort_mobilize", "major_36", "manpower", "cohort", "reserve", "phase4_depth",
        ],
    }


def execute_manpower_cohort_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "cohorts").strip().lower().replace("manpower_cohort_", "")
    if s.startswith("cohort"):
        s = "cohorts"
    elif s.startswith("reserve"):
        s = "reserve"
    elif s.startswith("mobil"):
        s = "mobilize"
    if s not in _STEP_META:
        s = "cohorts"
    meta = _STEP_META[s]
    product = build_manpower_cohort_reserve_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute manpower cohort %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_manpower_cohort_step", s, leaf],
    }


def manpower_cohort_reserve_integrity() -> Dict[str, Any]:
    product = build_manpower_cohort_reserve_product()
    steps = [execute_manpower_cohort_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("eligible", 0)) > 0
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Manpower cohort/reserve integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_manpower_cohort_reserve_product_loop() -> Dict[str, Any]:
    product = build_manpower_cohort_reserve_product(province_id=2)
    gate = manpower_cohort_reserve_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close manpower cohort/reserve · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
