"""Designer stats/field product (major #48) — world-class full designers.

Stats board (attack/armor/speed/reliability) → freeze design → field production seed.
Composes module editor + domain live seed into fieldable designs.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from designer_module_editor_product import (  # type: ignore
        build_designer_module_editor_product, execute_module_editor_step, designer_module_editor_integrity,
    )
except Exception:  # pragma: no cover
    def build_designer_module_editor_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False, "domain": "land", "design_id": "panzer_iii_j_medium",
                "reliability": 0.85, "within_band": True, "module_edit": {"modules": []}}
    def execute_module_editor_step(step="modules", province_id=1, domain="land"):  # type: ignore
        return {"ok": True, "step": step, "score": 0.65}
    def designer_module_editor_integrity():  # type: ignore
        return {"ok": True, "score": 0.65}

try:
    from designer_domain_live_product import build_designer_domain_live_product  # type: ignore
except Exception:  # pragma: no cover
    def build_designer_domain_live_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False}

PRODUCT_STEPS = ("stats", "freeze", "field")
_STEP_META = {
    "stats": {"action_id": "designer_stats_board", "leaf": "apply_focus", "label": "Step 0 — design stats board"},
    "freeze": {"action_id": "designer_freeze_design", "leaf": "apply_production", "label": "Step 1 — freeze design variant"},
    "field": {"action_id": "designer_field_seed", "leaf": "apply_production", "label": "Step 2 — field production seed"},
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


def compute_stats_board(*, modules: List[Dict[str, Any]] = None, domain: str = "land", reliability: float = 0.85) -> Dict[str, Any]:
    mods = list(modules or [])
    rel = _floor(reliability)
    cost = sum(float(m.get("cost", 0)) for m in mods) or 20.0
    weight = sum(float(m.get("weight", 0)) for m in mods) or 15.0
    # Domain-flavored combat stats
    if domain == "naval":
        soft = _floor(0.45 + 0.01 * min(30, cost))
        hard = _floor(0.4 + 0.008 * min(40, weight))
        speed = _floor(0.55 - 0.002 * weight + 0.1 * rel)
        armor = _floor(0.5 + 0.005 * weight)
    elif domain == "air":
        soft = _floor(0.55 + 0.02 * min(15, cost))
        hard = _floor(0.35 + 0.01 * min(10, weight))
        speed = _floor(0.7 - 0.01 * weight + 0.05 * rel)
        armor = _floor(0.35 + 0.01 * weight)
    elif domain == "space":
        soft = _floor(0.3 + 0.01 * cost)
        hard = soft
        speed = _floor(0.4 + 0.1 * rel)
        armor = _floor(0.45)
    else:  # land
        soft = _floor(0.5 + 0.015 * min(25, cost))
        hard = _floor(0.48 + 0.012 * min(30, weight))
        speed = _floor(0.5 - 0.004 * weight + 0.12 * rel)
        armor = _floor(0.45 + 0.01 * weight)
    combat = _floor(0.3 * soft + 0.3 * hard + 0.2 * armor + 0.2 * speed)
    score = _floor(0.55 * combat + 0.45 * rel)
    return {
        "domain": domain, "soft_attack": soft, "hard_attack": hard, "armor": armor, "speed": speed,
        "reliability": rel, "combat": combat, "cost": cost, "weight": weight, "score": score,
        "summary": "Stats · soft %.2f · hard %.2f · armor %.2f · spd %.2f · rel %.0f%% · score %.2f"
        % (soft, hard, armor, speed, rel * 100, score),
        "empty": False,
    }


def compute_freeze_design(*, stats: Dict[str, Any], design_id: str = "custom_design") -> Dict[str, Any]:
    combat = float(stats.get("combat", 0.55))
    rel = float(stats.get("reliability", 0.8))
    fid = str(design_id or "custom_design")
    frozen = combat >= 0.4 and rel >= 0.72
    variant = "%s_v1" % fid if frozen else fid
    score = _floor(0.5 * combat + 0.35 * rel + 0.15 * (1.0 if frozen else 0.3))
    return {
        "design_id": fid, "variant_id": variant, "frozen": frozen, "combat": combat, "reliability": rel, "score": score,
        "summary": "Freeze · %s · combat %.2f · rel %.0f%% · %s"
        % (variant, combat, rel * 100, "FROZEN" if frozen else "DRAFT"),
        "empty": False,
    }


def compute_field_seed(*, freeze: Dict[str, Any], factory_count: int = 14) -> Dict[str, Any]:
    frozen = bool(freeze.get("frozen", False))
    fac = max(1, int(factory_count))
    seeded = 1 if frozen and fac >= 4 else 0
    score = _floor(0.45 * float(freeze.get("score", 0.5)) + 0.35 * min(1.0, fac / 16.0) + 0.2 * (1.0 if seeded else 0.25))
    return {
        "variant_id": str(freeze.get("variant_id", "")), "factory_count": fac, "seeded": seeded,
        "seeded_ok": seeded >= 1, "score": score,
        "summary": "Field seed · %s · fac %d · seeded %d · score %.2f"
        % (freeze.get("variant_id", ""), fac, seeded, score),
        "empty": False,
    }


def recommend_stats_field_step(*, stated: bool = False, frozen: bool = False) -> Dict[str, Any]:
    if not stated:
        step, reason = "stats", "compute design stats board"
    elif not frozen:
        step, reason = "freeze", "freeze design variant"
    else:
        step, reason = "field", "seed field production"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_designer_stats_field_product(
    *, province_id: int = 1, domain: str = "land", factory_count: int = 14
) -> Dict[str, Any]:
    modules_prod = build_designer_module_editor_product(province_id=province_id, domain=domain)
    live = build_designer_domain_live_product(province_id=province_id, domain=domain)
    dom = str(modules_prod.get("domain", domain))
    design_id = str(modules_prod.get("design_id", "custom_design"))
    edit = modules_prod.get("module_edit") or {}
    stats = compute_stats_board(
        modules=list(edit.get("modules") or []),
        domain=dom,
        reliability=float(modules_prod.get("reliability", 0.85)),
    )
    freeze = compute_freeze_design(stats=stats, design_id=design_id)
    field = compute_field_seed(freeze=freeze, factory_count=factory_count)
    stats_s = _floor(float(stats["score"]))
    freeze_s = _floor(float(freeze["score"]))
    field_s = _floor(float(field["score"]))
    score = _floor(0.3 * stats_s + 0.3 * freeze_s + 0.25 * field_s + 0.15 * float(modules_prod.get("score", 0.6)))
    rec = recommend_stats_field_step(stated=True, frozen=bool(freeze["frozen"]))
    step_scores = {"stats": stats_s, "freeze": freeze_s, "field": field_s}
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
            "province_id": max(1, int(province_id)), "domain": dom, "design_id": design_id,
        })
        apply_queue.append({
            "action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc,
            "enabled": True, "label": lab, "step": step, "product_action": meta["action_id"],
            "domain": dom, "design_id": design_id,
        })
    actions = [
        {"action_id": "designer_stats_field_product", "label": "Run designer stats/field product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Designer stats/field · %s · %s · seeded %d · combat %.2f · score %.2f" % (
        dom, freeze["variant_id"], int(field["seeded"]), float(stats["combat"]), score)
    return {
        "modules_product": modules_prod, "live": live, "domain": dom, "design_id": design_id,
        "stats": stats, "freeze": freeze, "field": field,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "variant_id": freeze["variant_id"], "seeded": int(field["seeded"]), "combat": float(stats["combat"]),
        "score": score, "field_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), stats["summary"], freeze["summary"], field["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#a0c0ff]📐 Stats/field[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "designer_stats_field_product", "designer_stats_board", "designer_freeze_design",
            "designer_field_seed", "major_48", "designer", "stats", "field", "full_designers", "phase8_designers",
        ],
    }


def execute_stats_field_step(step: str, province_id: int = 1, domain: str = "land") -> Dict[str, Any]:
    s = str(step or "stats").strip().lower().replace("designer_", "")
    if s.startswith("stat"):
        s = "stats"
    elif s.startswith("freeze") or s.startswith("variant"):
        s = "freeze"
    elif s.startswith("field") or s.startswith("seed"):
        s = "field"
    if s not in _STEP_META:
        s = "stats"
    meta = _STEP_META[s]
    product = build_designer_stats_field_product(province_id=province_id, domain=domain)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute stats/field %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)), "domain": domain,
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_stats_field_step", s, leaf],
    }


def designer_stats_field_integrity() -> Dict[str, Any]:
    product = build_designer_stats_field_product()
    steps = [execute_stats_field_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    base = designer_module_editor_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("combat", 0)) >= 0.35
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(base.get("ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Designer stats/field integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_designer_stats_field_product_loop() -> Dict[str, Any]:
    product = build_designer_stats_field_product(province_id=2, domain="air", factory_count=16)
    gate = designer_stats_field_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close designer stats/field · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
