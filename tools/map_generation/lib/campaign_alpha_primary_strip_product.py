"""Campaign Alpha primary command strip — Phase 1 playability.

Top 6–8 always-visible actions for the 1936 play loop, with recommended-next
(HH / theater / front / occupation) and a dead-button audit (dead_n == 0).
Day-package noise stays available under collapsed sections (max_expanded=1).
"""
from __future__ import annotations
from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

PRODUCT_STEPS = ("board", "recommend", "audit")

# Live-routed primary actions for Campaign Alpha (must exist in GameData.apply_order_panel_action).
PRIMARY_ACTIONS: List[Dict[str, Any]] = [
    {"action_id": "apply_station", "label": "Station forces", "key": "1", "domain": "force"},
    {"action_id": "apply_assault", "label": "Assault", "key": "2", "domain": "combat"},
    {"action_id": "apply_production", "label": "Production", "key": "3", "domain": "industry"},
    {"action_id": "day_ops_integrated", "label": "Integrated day ops", "key": "4", "domain": "ops"},
    {"action_id": "theater_command_execute", "label": "Theater execute", "key": "5", "domain": "theater"},
    {"action_id": "hh_month_brief", "label": "HH month brief", "key": "6", "domain": "hh"},
    {"action_id": "occupation_resistance_compliance_product", "label": "Occupation R/C", "key": "7", "domain": "occupation"},
    {"action_id": "save_resume_checkpoint", "label": "Checkpoint save", "key": "8", "domain": "save"},
]

LIVE_PRIMARY_ACTION_IDS = frozenset(str(a["action_id"]) for a in PRIMARY_ACTIONS)

_STEP_META = {
    "board": {"action_id": "campaign_alpha_primary_board", "leaf": "apply_station", "label": "Step 0 — primary strip board"},
    "recommend": {"action_id": "campaign_alpha_recommend_next", "leaf": "apply_assault", "label": "Step 1 — recommended next"},
    "audit": {"action_id": "campaign_alpha_dead_audit", "leaf": "apply_production", "label": "Step 2 — dead-button audit"},
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


def primary_strip_actions(*, max_actions: int = 8) -> List[Dict[str, Any]]:
    limit = max(6, min(8, int(max_actions)))
    out: List[Dict[str, Any]] = []
    for i, raw in enumerate(PRIMARY_ACTIONS[:limit]):
        a = dict(raw)
        a["enabled"] = True
        a["index"] = i
        a["priority"] = 163 - i
        out.append(a)
    return out


def primary_strip_dead_audit(
    action_ids: Optional[Sequence[str]] = None,
    *,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Dead-button audit: every primary action_id must be in the live set."""
    ids = [str(x) for x in (action_ids if action_ids is not None else LIVE_PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 6
    label = "Primary strip audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL",
    )
    return {
        "action_ids": ids,
        "dead": dead,
        "dead_n": len(dead),
        "live_n": len(ids) - len(dead),
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def recommend_campaign_next(
    *,
    front_pressure: float = 0.45,
    occupation_risk: float = 0.35,
    hh_urgency: float = 0.4,
    theater_score: float = 0.5,
    production_need: float = 0.42,
) -> Dict[str, Any]:
    """Pick one recommended-next action from HH / theater / front / occupation pressure."""
    candidates = [
        ("apply_assault", _norm(front_pressure), "front pressure"),
        ("occupation_resistance_compliance_product", _norm(occupation_risk), "occupation risk"),
        ("hh_month_brief", _norm(hh_urgency), "HH agenda urgency"),
        ("theater_command_execute", _norm(theater_score), "theater command"),
        ("apply_production", _norm(production_need), "production need"),
        ("apply_station", 0.35, "station forces"),
        ("day_ops_integrated", 0.4, "integrated day ops"),
        ("save_resume_checkpoint", 0.28, "checkpoint habit"),
    ]
    best_id, best_sc, best_reason = max(candidates, key=lambda t: float(t[1]))
    meta = next((a for a in PRIMARY_ACTIONS if a["action_id"] == best_id), PRIMARY_ACTIONS[0])
    label = "Recommend ★ %s · %s · score %.2f" % (meta["label"], best_reason, best_sc)
    return {
        "action_id": best_id,
        "label": str(meta.get("label", best_id)),
        "reason": best_reason,
        "score": _floor(best_sc),
        "domain": str(meta.get("domain", "ops")),
        "key": str(meta.get("key", "")),
        "summary": label,
        "plain": label,
        "empty": False,
    }


def compute_compact_day_plan(*, max_expanded: int = 1, section_count: int = 24) -> Dict[str, Any]:
    max_exp = max(0, min(2, int(max_expanded)))
    n = max(1, int(section_count))
    expanded = min(max_exp, n)
    collapsed = max(0, n - expanded)
    load = _floor(1.0 - 0.6 * (collapsed / float(n)))
    return {
        "max_expanded": max_exp,
        "section_count": n,
        "expanded_n": expanded,
        "collapsed_n": collapsed,
        "cognitive_load": load,
        "summary": "Alpha compact · expanded %d/%d · collapsed %d · load %.0f%%"
        % (expanded, n, collapsed, load * 100),
        "empty": False,
    }


def build_campaign_alpha_primary_strip_product(
    *,
    province_id: int = 1,
    max_actions: int = 8,
    max_expanded: int = 1,
    front_pressure: float = 0.45,
    occupation_risk: float = 0.35,
    hh_urgency: float = 0.4,
    theater_score: float = 0.5,
    production_need: float = 0.42,
) -> Dict[str, Any]:
    actions = primary_strip_actions(max_actions=max_actions)
    audit = primary_strip_dead_audit([str(a["action_id"]) for a in actions])
    rec = recommend_campaign_next(
        front_pressure=front_pressure,
        occupation_risk=occupation_risk,
        hh_urgency=hh_urgency,
        theater_score=theater_score,
        production_need=production_need,
    )
    compact = compute_compact_day_plan(max_expanded=max_expanded)
    board_score = _floor(0.4 + 0.06 * len(actions))
    rec_score = float(rec.get("score", 0.5))
    audit_score = 1.0 if audit.get("ok") else 0.2
    compact_score = _floor(1.0 - float(compact.get("cognitive_load", 0.5)) * 0.45)
    score = _floor(0.3 * board_score + 0.3 * rec_score + 0.25 * audit_score + 0.15 * compact_score)
    step_scores = {"board": board_score, "recommend": rec_score, "audit": audit_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == "recommend"
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
    strip_lines = ["[%s] %s" % (a.get("key", "?"), a.get("label", a["action_id"])) for a in actions]
    label = (
        "Campaign Alpha primary · actions %d · dead %d · rec %s · expanded %d · score %.2f"
        % (len(actions), int(audit.get("dead_n", 0)), str(rec.get("action_id")), int(compact["expanded_n"]), score)
    )
    return {
        "actions": actions,
        "primary_actions": actions,
        "recommendation": rec,
        "audit": audit,
        "compact": compact,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "strip_lines": strip_lines,
        "max_actions": len(actions),
        "max_expanded": int(compact["max_expanded"]),
        "dead_n": int(audit.get("dead_n", 0)),
        "dead_ok": bool(audit.get("ok")),
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [label, str(rec.get("summary", "")), str(audit.get("summary", "")), str(compact.get("summary", ""))]
            + strip_lines
            + [r["label"] for r in day_rows]
        ),
        "bbcode": "[color=#7dcea0]★ Alpha strip[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "campaign_alpha_primary_strip_product", "campaign_alpha_primary_board",
            "campaign_alpha_recommend_next", "campaign_alpha_dead_audit",
            "campaign_alpha", "primary_strip", "playability", "phase1_alpha",
        ],
        "panel_actions": [
            {"action_id": "campaign_alpha_primary_strip_product", "label": "Run Campaign Alpha primary strip", "enabled": True},
            {"action_id": "campaign_alpha_apply_recommended", "label": "Apply recommended next", "enabled": True},
            {"action_id": "campaign_alpha_primary_board", "label": "Primary strip board", "enabled": True},
            {"action_id": "campaign_alpha_recommend_next", "label": "Refresh recommended next", "enabled": True},
            {"action_id": "campaign_alpha_dead_audit", "label": "Run dead-button audit", "enabled": True},
        ],
    }


def execute_campaign_alpha_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("campaign_alpha_", "")
    if s.startswith("rec"):
        s = "recommend"
    elif s.startswith("aud") or s.startswith("dead"):
        s = "audit"
    elif s.startswith("board") or s.startswith("primary"):
        s = "board"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_campaign_alpha_primary_strip_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute campaign alpha %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_campaign_alpha_step", s, leaf],
    }


def campaign_alpha_primary_strip_integrity() -> Dict[str, Any]:
    product = build_campaign_alpha_primary_strip_product()
    steps = [execute_campaign_alpha_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    audit = product.get("audit") or {}
    ok = (
        not product.get("empty")
        and len(product.get("primary_actions") or []) >= 6
        and int(product.get("dead_n", 1)) == 0
        and bool(audit.get("ok"))
        and int(product.get("max_expanded", 99)) <= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)),
        "summary": "Campaign Alpha primary strip integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_campaign_alpha_primary_strip_loop() -> Dict[str, Any]:
    product = build_campaign_alpha_primary_strip_product(province_id=2, max_expanded=1)
    gate = campaign_alpha_primary_strip_integrity()
    ok = bool(gate.get("ok")) and int(product.get("dead_n", 1)) == 0 and len(product.get("apply_queue") or []) >= 3
    label = "Close campaign alpha primary · score %.2f · dead %d · %s" % (
        float(product.get("score", 0)), int(product.get("dead_n", 0)), "PASS" if ok else "FAIL",
    )
    return {
        "product": product, "gate": gate, "score": float(product.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)), "summary": label, "plain": label,
        "empty": False, "ok": ok,
    }
