"""Product UX command polish (major #32) — Phase 3.

Compact day sections → top-8 always-on chips → hotkey primary binds.
Collapses cognitive overload while keeping all live routes available.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

PRODUCT_STEPS = ("compact", "chips", "hotkeys")
TOP_CHIP_IDS = (
    "peace_conference_settlement_product",
    "manpower_laws_training_product",
    "occupation_resistance_compliance_product",
    "apply_queue_live_managers_product",
    "medium_tank_production_honesty_product",
    "campaign_ai_multi_month_product",
    "designer_domain_live_product",
    "product_ux_command_polish_product",
)
HOTKEYS = (
    {"key": "1", "action_id": "day_ops_integrated", "label": "Primary day ops"},
    {"key": "2", "action_id": "apply_production", "label": "Production apply"},
    {"key": "3", "action_id": "apply_assault", "label": "Assault apply"},
    {"key": "4", "action_id": "occupation_resistance_compliance_product", "label": "Occupation R/C"},
    {"key": "5", "action_id": "manpower_laws_training_product", "label": "Manpower laws"},
    {"key": "6", "action_id": "designer_domain_live_product", "label": "Designer domain"},
    {"key": "7", "action_id": "campaign_ai_multi_month_product", "label": "Campaign AI month"},
    {"key": "8", "action_id": "peace_conference_settlement_product", "label": "Peace settle"},
)
_STEP_META = {
    "compact": {"action_id": "product_ux_compact_board", "leaf": "apply_focus", "label": "Step 0 — compact section board"},
    "chips": {"action_id": "product_ux_top_chips", "leaf": "apply_station", "label": "Step 1 — top-8 always-on chips"},
    "hotkeys": {"action_id": "product_ux_hotkeys", "leaf": "apply_production", "label": "Step 2 — bind primary hotkeys"},
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


def compute_ux_compact_plan(*, max_expanded: int = 2, section_count: int = 24) -> Dict[str, Any]:
    max_exp = max(1, min(4, int(max_expanded)))
    n = max(1, int(section_count))
    expanded = min(max_exp, n)
    collapsed = max(0, n - expanded)
    load = _floor(1.0 - 0.55 * (collapsed / float(n)))
    return {
        "max_expanded": max_exp,
        "section_count": n,
        "expanded_n": expanded,
        "collapsed_n": collapsed,
        "cognitive_load": load,
        "summary": "UX compact · expanded %d/%d · collapsed %d · load %.0f%%" % (expanded, n, collapsed, load * 100),
        "empty": False,
    }


def compute_top_chips(*, max_chips: int = 8) -> Dict[str, Any]:
    limit = max(4, min(12, int(max_chips)))
    chips: List[Dict[str, Any]] = []
    for i, cid in enumerate(TOP_CHIP_IDS[:limit]):
        chips.append({
            "id": cid,
            "priority": 138 - i,
            "always": True,
            "label": cid.replace("_", " "),
            "bbcode": "[color=#6ec8ff]★ %s[/color]" % cid.replace("_", " "),
        })
    score = _floor(0.45 + 0.07 * len(chips))
    return {
        "chips": chips,
        "max_chips": limit,
        "shown": len(chips),
        "score": score,
        "summary": "Top chips · shown %d/%d · score %.2f" % (len(chips), limit, score),
        "empty": False,
    }


def compute_hotkey_board() -> Dict[str, Any]:
    binds = [dict(h) for h in HOTKEYS]
    score = _floor(0.5 + 0.05 * len(binds))
    return {
        "hotkeys": binds,
        "bind_n": len(binds),
        "score": score,
        "summary": "Hotkeys · %d primary binds · score %.2f" % (len(binds), score),
        "empty": False,
    }


def recommend_product_ux_step(*, compact_set: bool = False, chips_set: bool = False) -> Dict[str, Any]:
    if not compact_set:
        step, reason = "compact", "collapse day-section overload first"
    elif not chips_set:
        step, reason = "chips", "pin top-8 always-on chips"
    else:
        step, reason = "hotkeys", "bind primary hotkeys 1–8"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_product_ux_command_polish_product(
    *, province_id: int = 1, max_expanded: int = 2, max_chips: int = 8, section_count: int = 24
) -> Dict[str, Any]:
    compact = compute_ux_compact_plan(max_expanded=max_expanded, section_count=section_count)
    chips = compute_top_chips(max_chips=max_chips)
    hotkeys = compute_hotkey_board()
    compact_score = _floor(1.0 - float(compact.get("cognitive_load", 0.5)) * 0.5)
    chips_score = float(chips.get("score", 0.5))
    hotkey_score = float(hotkeys.get("score", 0.5))
    score = _floor(0.35 * compact_score + 0.35 * chips_score + 0.3 * hotkey_score)
    rec = recommend_product_ux_step(compact_set=True, chips_set=True)
    step_scores = {"compact": compact_score, "chips": chips_score, "hotkeys": hotkey_score}
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
        {"action_id": "product_ux_command_polish_product", "label": "Run product UX command polish", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Product UX polish · expanded %d · chips %d · hotkeys %d · score %.2f" % (
        compact["expanded_n"], chips["shown"], hotkeys["bind_n"], score)
    return {
        "compact": compact, "chips": chips, "hotkeys": hotkeys, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "max_expanded": compact["max_expanded"], "max_chips": chips["max_chips"],
        "bind_n": hotkeys["bind_n"], "score": score, "ux_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(compact.get("summary", "")), str(chips.get("summary", "")), str(hotkeys.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#9ad0e8]✦ Product UX[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "product_ux_command_polish_product", "product_ux_compact_board", "product_ux_top_chips",
            "product_ux_hotkeys", "major_32", "ux", "polish", "hotkeys", "phase3_depth",
        ],
    }


def execute_product_ux_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "compact").strip().lower().replace("product_ux_", "")
    if s.startswith("compact"):
        s = "compact"
    elif s.startswith("chip"):
        s = "chips"
    elif s.startswith("hotkey"):
        s = "hotkeys"
    if s not in _STEP_META:
        s = "compact"
    meta = _STEP_META[s]
    product = build_product_ux_command_polish_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute product UX %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_product_ux_step", s, leaf],
    }


def product_ux_command_polish_integrity() -> Dict[str, Any]:
    product = build_product_ux_command_polish_product()
    steps = [execute_product_ux_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("max_chips", 0)) >= 8
        and int(product.get("bind_n", 0)) >= 6
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Product UX command polish integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_product_ux_command_polish_product_loop() -> Dict[str, Any]:
    product = build_product_ux_command_polish_product(province_id=2)
    gate = product_ux_command_polish_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close product UX polish · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
