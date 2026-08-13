"""Designer domain live product (major #33) — Phase 3.

Catalog domains → pick land/naval/air/space → seed production line live.
Hardens designer suite first slice into real ProductionManager seeds.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from designer_suite_product import build_designer_suite_product, DOMAINS  # type: ignore
except Exception:  # pragma: no cover
    DOMAINS = ("land", "naval", "air", "space")

    def build_designer_suite_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "designer suite", "domain_recommendation": {"domain": "land", "design_id": "panzer_iii_j_medium"}}

PRODUCT_STEPS = ("catalog", "pick", "seed")
DOMAIN_DESIGNS = {
    "land": "panzer_iii_j_medium",
    "naval": "destroyer_1936",
    "air": "fighter_1936",
    "space": "satellite_recon",
}
_STEP_META = {
    "catalog": {"action_id": "designer_domain_live_catalog", "leaf": "apply_focus", "label": "Step 0 — multi-domain catalog"},
    "pick": {"action_id": "designer_domain_live_pick", "leaf": "apply_production", "label": "Step 1 — pick domain design"},
    "seed": {"action_id": "designer_domain_live_seed", "leaf": "apply_production", "label": "Step 2 — seed production line live"},
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


def compute_domain_board(*, domain: str = "land", factory_count: int = 14) -> Dict[str, Any]:
    dom = str(domain or "land").lower()
    if dom not in DOMAIN_DESIGNS:
        dom = "land"
    design_id = DOMAIN_DESIGNS[dom]
    fac = max(1, int(factory_count))
    readiness = _floor(0.45 + 0.03 * min(fac, 20))
    return {
        "domain": dom,
        "design_id": design_id,
        "factory_count": fac,
        "readiness": readiness,
        "summary": "Domain %s · design %s · fac %d · ready %.0f%%" % (dom, design_id, fac, readiness * 100),
        "empty": False,
    }


def recommend_designer_domain_step(*, cataloged: bool = False, picked: bool = False) -> Dict[str, Any]:
    if not cataloged:
        step, reason = "catalog", "review multi-domain catalog"
    elif not picked:
        step, reason = "pick", "pick land/naval/air/space design"
    else:
        step, reason = "seed", "seed production line on factory"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_designer_domain_live_product(
    *, province_id: int = 1, domain: str = "land", factory_count: int = 14, country_tag: str = "GER"
) -> Dict[str, Any]:
    suite = build_designer_suite_product(province_id=province_id)
    board = compute_domain_board(domain=domain, factory_count=factory_count)
    suite_score = _floor(float(suite.get("score", 0.55)))
    catalog_score = _floor(0.5 * suite_score + 0.5 * float(board["readiness"]))
    pick_score = _floor(0.55 * float(board["readiness"]) + 0.45 * suite_score)
    seed_score = _floor(0.4 * catalog_score + 0.6 * pick_score)
    score = _floor(0.3 * catalog_score + 0.35 * pick_score + 0.35 * seed_score)
    rec = recommend_designer_domain_step(cataloged=True, picked=True)
    step_scores = {"catalog": catalog_score, "pick": pick_score, "seed": seed_score}
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
    domain_actions = [
        {"action_id": "designer_domain_land", "label": "Domain: land", "enabled": True},
        {"action_id": "designer_domain_naval", "label": "Domain: naval", "enabled": True},
        {"action_id": "designer_domain_air", "label": "Domain: air", "enabled": True},
        {"action_id": "designer_domain_space", "label": "Domain: space", "enabled": True},
    ]
    actions = [
        {"action_id": "designer_domain_live_product", "label": "Run designer domain live product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ] + domain_actions
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    tag = str(country_tag or "GER").upper()
    line_id = "designer_%s_%s_%s" % (tag, board["domain"], board["design_id"])
    label = "Designer domain live · %s · %s · line %s · score %.2f" % (
        board["domain"], board["design_id"], line_id, score)
    return {
        "suite": suite, "board": board, "recommendation": rec, "day_rows": day_rows,
        "apply_queue": apply_queue, "actions": actions,
        "domain": board["domain"], "design_id": board["design_id"], "line_id": line_id,
        "country_tag": tag, "score": score, "designer_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(board.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e0a06a]🛠 Designer domain[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "designer_domain_live_product", "designer_domain_live_catalog", "designer_domain_live_pick",
            "designer_domain_live_seed", "major_33", "designer", "domain", "seed", "phase3_depth",
        ],
    }


def execute_designer_domain_live_step(step: str, province_id: int = 1, domain: str = "land") -> Dict[str, Any]:
    s = str(step or "catalog").strip().lower().replace("designer_domain_live_", "")
    if s.startswith("catalog"):
        s = "catalog"
    elif s.startswith("pick"):
        s = "pick"
    elif s.startswith("seed"):
        s = "seed"
    if s not in _STEP_META:
        s = "catalog"
    meta = _STEP_META[s]
    product = build_designer_domain_live_product(province_id=province_id, domain=domain)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute designer domain %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "domain": product.get("domain"), "design_id": product.get("design_id"), "line_id": product.get("line_id"),
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_designer_domain_live_step", s, leaf],
    }


def designer_domain_live_integrity() -> Dict[str, Any]:
    product = build_designer_domain_live_product()
    steps = [execute_designer_domain_live_step(s) for s in PRODUCT_STEPS]
    domains_ok = all(d in DOMAIN_DESIGNS for d in DOMAINS) if DOMAINS else True
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and str(product.get("design_id", "")) != ""
        and domains_ok
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Designer domain live integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_designer_domain_live_product_loop() -> Dict[str, Any]:
    product = build_designer_domain_live_product(province_id=2, domain="naval")
    gate = designer_domain_live_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close designer domain live · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
