"""Intelligence network product (major #19) — world-class intel spine.

Coverage board → counterintel → HH/agent counterplay joint.
Composes agent campaign, counterintel board, HH multi-month.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from agent_campaign_product import (  # type: ignore
    agent_campaign_product_integrity,
    build_agent_campaign_product,
    execute_agent_product_step,
)
from next250_leader_intel_theater import counterintel_board_ops_day  # type: ignore
from hh_multi_month_agenda_product import (  # type: ignore
    build_hh_multi_month_agenda_product,
    hh_multi_month_agenda_product_integrity,
)
from diplomacy_peace_campaign_product import build_diplomacy_peace_campaign_product  # type: ignore


PRODUCT_STEPS = ("coverage", "counterintel", "counterplay")

_STEP_META = {
    "coverage": {
        "action_id": "intel_network_coverage",
        "leaf": "apply_agent_dispatch",
        "label": "Step 0 — coverage / agent board",
    },
    "counterintel": {
        "action_id": "intel_network_counterintel",
        "leaf": "apply_agent_dispatch",
        "label": "Step 1 — counterintel board",
    },
    "counterplay": {
        "action_id": "intel_network_counterplay",
        "leaf": "apply_hh_commit",
        "label": "Step 2 — HH/agent counterplay",
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


def recommend_intel_step(
    *,
    coverage_score: float = 0.5,
    counter_score: float = 0.5,
    counterplay_ready: bool = False,
) -> Dict[str, Any]:
    if coverage_score < 0.45:
        step = "coverage"
        reason = "coverage thin — dispatch agents"
    elif counter_score < 0.45:
        step = "counterintel"
        reason = "counterintel pressure high"
    elif counterplay_ready:
        step = "counterplay"
        reason = "ready for HH/agent counterplay"
    else:
        step = "counterintel"
        reason = "refresh counterintel"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_intelligence_network_product(*, province_id: int = 1) -> Dict[str, Any]:
    agent = build_agent_campaign_product(province_id=province_id)
    dispatch = execute_agent_product_step("dispatch", province_id)
    counter = counterintel_board_ops_day(province_id)
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    diplo = build_diplomacy_peace_campaign_product(province_id=province_id)

    coverage_score = _floor(
        0.55 * _norm(float(agent.get("score", 0.5)))
        + 0.45 * _norm(float(dispatch.get("score", 0.5)))
    )
    counter_score = _floor(_norm(float(counter.get("score", 0.5))))
    counterplay_score = _floor(
        0.5 * _norm(float(hh.get("score", 0.5)))
        + 0.3 * coverage_score
        + 0.2 * _norm(float(diplo.get("leverage_score", diplo.get("score", 0.5))))
    )
    score = _floor(0.35 * coverage_score + 0.35 * counter_score + 0.3 * counterplay_score)
    rec = recommend_intel_step(
        coverage_score=coverage_score,
        counter_score=counter_score,
        counterplay_ready=counterplay_score >= 0.45 and coverage_score >= 0.4,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "coverage": coverage_score,
        "counterintel": counter_score,
        "counterplay": counterplay_score,
    }
    step_leaves = {
        "coverage": "apply_agent_dispatch",
        "counterintel": "apply_agent_dispatch",
        "counterplay": "apply_hh_commit",
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = step_leaves[step]
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · score %.2f" % (lab, sc)
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
            "action_id": "intelligence_network_product",
            "label": "Run intelligence network product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "intel_network_coverage")),
            "label": "Recommended: %s" % rec.get("step", "coverage"),
            "enabled": True,
        },
        {
            "action_id": "agent_campaign_product",
            "label": "Open agent campaign product",
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
        "Intelligence network · coverage %.2f · counter %.2f · counterplay %.2f · score %.2f"
        % (coverage_score, counter_score, counterplay_score, score)
    )
    return {
        "agent": agent,
        "dispatch": dispatch,
        "counter": counter,
        "hh": hh,
        "diplo": diplo,
        "coverage_score": coverage_score,
        "counter_score": counter_score,
        "counterplay_score": counterplay_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "intel_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [label, str(rec.get("summary", "")), str(agent.get("summary", "")), str(counter.get("summary", ""))]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#c084fc]🕵 Intelligence network[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "intelligence_network_product",
            "intel_network_coverage",
            "intel_network_counterintel",
            "intel_network_counterplay",
            "major_19",
            "intelligence",
            "intel",
        ],
    }


def execute_intel_network_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "coverage").strip().lower()
    if s.startswith("intel_network_"):
        s = s.replace("intel_network_", "")
    if s not in _STEP_META:
        s = "coverage"
    meta = _STEP_META[s]
    product = build_intelligence_network_product(province_id=province_id)
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
    label = "Execute intel network %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]🕵 Intel %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_intel_network_step", s, leaf],
    }


def intelligence_network_product_integrity() -> Dict[str, Any]:
    product = build_intelligence_network_product()
    steps = [execute_intel_network_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    agent_g = agent_campaign_product_integrity()
    hh_g = hh_multi_month_agenda_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(agent_g.get("ok", True))
        and bool(hh_g.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Intelligence network integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_intelligence_network_product_loop() -> Dict[str, Any]:
    product = build_intelligence_network_product(province_id=2)
    gate = intelligence_network_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close intelligence network · score %.2f · %s" % (
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]✓ Intelligence network[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
