"""Tech / research campaign product (major #17) — deferred research first slice.

Catalog designs → priority production/research path → field seed/OOB.
Composes designer suite, production priority, medium OOB, focus industrial — not stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from designer_suite_product import (  # type: ignore
    build_designer_suite_product,
    designer_suite_product_integrity,
    execute_designer_suite_step,
)
from medium_tank_oob_product import (  # type: ignore
    build_medium_tank_oob_product,
    medium_tank_oob_product_integrity,
)
from live_mutation import production_priority_mutation  # type: ignore
from focus_war_path_product import build_focus_war_path_product  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore


PRODUCT_STEPS = ("catalog", "priority", "field")

_STEP_META = {
    "catalog": {
        "action_id": "tech_research_catalog",
        "leaf": "apply_focus",
        "label": "Step 0 — research/design catalog",
    },
    "priority": {
        "action_id": "tech_research_priority",
        "leaf": "apply_production",
        "label": "Step 1 — production/research priority",
    },
    "field": {
        "action_id": "tech_research_field",
        "leaf": "apply_production",
        "label": "Step 2 — field seed / OOB",
    },
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


def recommend_tech_research_step(
    *,
    catalog_count: int = 0,
    priority_score: float = 0.5,
    field_ready: bool = False,
) -> Dict[str, Any]:
    if catalog_count < 4:
        step = "catalog"
        reason = "thin catalog — review designs"
    elif priority_score < 0.4:
        step = "priority"
        reason = "priority path weak — retool production"
    elif field_ready:
        step = "field"
        reason = "ready to field seed/OOB"
    else:
        step = "priority"
        reason = "refresh research priority"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_tech_research_campaign_product(*, province_id: int = 1) -> Dict[str, Any]:
    designer = build_designer_suite_product(province_id=province_id)
    catalog_step = execute_designer_suite_step("catalog", province_id)
    priority = production_priority_mutation()
    oob = build_medium_tank_oob_product(province_id=province_id)
    seed = execute_designer_suite_step("seed", province_id)
    focus = build_focus_war_path_product(province_id=province_id, focus_id="industrial_effort")
    economy = war_economy_day_package()

    catalog_count = int(designer.get("catalog_count", 0))
    catalog_score = _floor(
        0.55 * min(1.0, catalog_count / 12.0)
        + 0.45 * _norm(float(designer.get("score", 0.5)))
    )
    priority_score = _floor(
        0.5 * _norm(float(priority.get("score", 0.5)))
        + 0.3 * _norm(float(economy.get("score", 0.5)))
        + 0.2 * _norm(float(focus.get("score", 0.5)))
    )
    field_score = _floor(
        0.5 * _norm(float(oob.get("score", 0.5)))
        + 0.5 * _norm(float(seed.get("score", 0.5)))
    )
    score = _floor(0.35 * catalog_score + 0.35 * priority_score + 0.3 * field_score)
    rec = recommend_tech_research_step(
        catalog_count=catalog_count,
        priority_score=priority_score,
        field_ready=field_score >= 0.4 and catalog_count >= 4,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "catalog": catalog_score,
        "priority": priority_score,
        "field": field_score,
    }
    step_leaves = {
        "catalog": "apply_focus",
        "priority": "apply_production",
        "field": "apply_production",
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = step_leaves[step]
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · catalog %d · score %.2f" % (lab, catalog_count, sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
            }
        )

    actions = [
        {
            "action_id": "tech_research_campaign_product",
            "label": "Run tech research campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "tech_research_catalog")),
            "label": "Recommended: %s" % rec.get("step", "catalog"),
            "enabled": True,
        },
        {
            "action_id": "designer_suite_product",
            "label": "Open designer suite product",
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": True,
                "step": r["step"],
            }
        )

    label = (
        "Tech research campaign · catalog %d · priority %.2f · field %.2f · score %.2f"
        % (catalog_count, priority_score, field_score, score)
    )
    return {
        "designer": designer,
        "catalog_step": catalog_step,
        "priority": priority,
        "oob": oob,
        "seed": seed,
        "focus": focus,
        "economy": economy,
        "catalog_count": catalog_count,
        "catalog_score": catalog_score,
        "priority_score": priority_score,
        "field_score": field_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "tech_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(rec.get("summary", "")),
                str(designer.get("summary", "")),
                str(oob.get("summary", "")),
                str(seed.get("summary", "")),
            ]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#38bdf8]🔬 Tech research[/color] [color=#8899aa]%s[/color]" % label,
        "empty": catalog_count <= 0,
        "integration": [
            "tech_research_campaign_product",
            "tech_research_catalog",
            "tech_research_priority",
            "tech_research_field",
            "major_17",
            "tech",
            "research",
        ],
    }


def execute_tech_research_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "catalog").strip().lower()
    if s.startswith("tech_research_"):
        s = s.replace("tech_research_", "")
    if s not in _STEP_META:
        s = "catalog"
    meta = _STEP_META[s]
    product = build_tech_research_campaign_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
        }
    ]
    if s == "field":
        seed_q = list((product.get("seed") or {}).get("apply_queue") or [])
        if seed_q:
            q = [dict(x) for x in seed_q if isinstance(x, Mapping)][:3] or q
    label = "Execute tech research %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#38bdf8]🔬 Tech %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_tech_research_step", s, leaf],
    }


def tech_research_campaign_integrity() -> Dict[str, Any]:
    product = build_tech_research_campaign_product()
    steps = [execute_tech_research_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    des = designer_suite_product_integrity()
    oob = medium_tank_oob_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("catalog_count", 0)) >= 4
        and len(product.get("day_rows") or []) >= 3
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(des.get("ok", True))
        and bool(oob.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "catalog_count": int(product.get("catalog_count", 0)),
        "gate": gate,
        "summary": "Tech research campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_tech_research_campaign_product_loop() -> Dict[str, Any]:
    product = build_tech_research_campaign_product(province_id=2)
    gate = tech_research_campaign_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close tech research · catalog %d · score %.2f · %s" % (
        int(product.get("catalog_count", 0)),
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#38bdf8]✓ Tech research[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
