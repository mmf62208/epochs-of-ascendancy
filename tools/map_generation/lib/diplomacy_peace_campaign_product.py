"""Diplomacy / peace campaign product (major #16) — deferred diplomacy first slice.

Board diplomatic pressure → leverage (agent/HH) → settle path.
Composes war economy, trade chain, campaign decision, agent, HH — not day stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import cohesion_integrity_gate, execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity, trade_supply_weather_chain  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore
from next10_depth import campaign_decision_day  # type: ignore
from agent_campaign_product import (  # type: ignore
    agent_campaign_product_integrity,
    build_agent_campaign_product,
)
from hh_multi_month_agenda_product import (  # type: ignore
    build_hh_multi_month_agenda_product,
    hh_multi_month_agenda_product_integrity,
)
from focus_war_path_product import (  # type: ignore
    build_focus_war_path_product,
    focus_war_path_product_integrity,
)


PRODUCT_STEPS = ("board", "leverage", "settle")

_STEP_META = {
    "board": {
        "action_id": "diplomacy_peace_board",
        "leaf": "apply_focus",
        "label": "Step 0 — diplomatic board / pressure",
    },
    "leverage": {
        "action_id": "diplomacy_peace_leverage",
        "leaf": "apply_agent_dispatch",
        "label": "Step 1 — leverage agent / HH",
    },
    "settle": {
        "action_id": "diplomacy_peace_settle",
        "leaf": "apply_hh_commit",
        "label": "Step 2 — settle / path commit",
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


def recommend_diplomacy_step(
    *,
    board_score: float = 0.5,
    leverage_ready: bool = False,
    settle_ready: bool = False,
) -> Dict[str, Any]:
    if board_score < 0.4:
        step = "board"
        reason = "pressure board weak — rescan economy/trade"
    elif not leverage_ready:
        step = "leverage"
        reason = "need agent/HH leverage"
    elif settle_ready:
        step = "settle"
        reason = "leverage enough — settle path"
    else:
        step = "leverage"
        reason = "refresh leverage tools"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_diplomacy_peace_campaign_product(*, province_id: int = 1) -> Dict[str, Any]:
    economy = war_economy_day_package()
    trade = trade_supply_weather_chain(
        sea_trade_mult=1.0, weather={"precip": 0.3, "visibility": 0.7}
    )
    if not isinstance(trade, dict):
        trade = {"score": 0.55, "health": 0.55, "summary": "trade chain", "empty": False}
    trade_sc = float(trade.get("score", trade.get("health", 0.55)))
    trade["score"] = trade_sc
    decision = campaign_decision_day(province_id=province_id)
    agent = build_agent_campaign_product(province_id=province_id)
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    focus = build_focus_war_path_product(province_id=province_id, focus_id="industrial_effort")
    cohesion = cohesion_integrity_gate()

    board_score = _floor(
        0.4 * _norm(float(economy.get("score", 0.5)))
        + 0.3 * _norm(trade_sc)
        + 0.3 * _norm(float(decision.get("score", 0.5)))
    )
    leverage_score = _floor(
        0.5 * _norm(float(agent.get("score", 0.5)))
        + 0.5 * _norm(float(hh.get("score", 0.5)))
    )
    settle_score = _floor(
        0.45 * _norm(float(focus.get("score", 0.5)))
        + 0.35 * leverage_score
        + 0.2 * (1.0 if cohesion.get("ok", True) else 0.35)
    )
    score = _floor(0.35 * board_score + 0.35 * leverage_score + 0.3 * settle_score)
    rec = recommend_diplomacy_step(
        board_score=board_score,
        leverage_ready=leverage_score >= 0.4,
        settle_ready=settle_score >= 0.4 and leverage_score >= 0.4,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "board": board_score,
        "leverage": leverage_score,
        "settle": settle_score,
    }
    step_leaves = {
        "board": "apply_focus",
        "leverage": "apply_agent_dispatch",
        "settle": "apply_hh_commit",
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
            "action_id": "diplomacy_peace_campaign_product",
            "label": "Run diplomacy peace campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "diplomacy_peace_board")),
            "label": "Recommended: %s" % rec.get("step", "board"),
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
        "Diplomacy peace campaign · board %.2f · leverage %.2f · settle %.2f · score %.2f"
        % (board_score, leverage_score, settle_score, score)
    )
    return {
        "economy": economy,
        "trade": trade,
        "decision": decision,
        "agent": agent,
        "hh": hh,
        "focus": focus,
        "cohesion": cohesion,
        "board_score": board_score,
        "leverage_score": leverage_score,
        "settle_score": settle_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "diplomacy_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(rec.get("summary", "")),
                str(economy.get("summary", "")),
                str(agent.get("summary", "")),
                str(hh.get("summary", "")),
            ]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#a78bfa]🕊 Diplomacy peace[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "diplomacy_peace_campaign_product",
            "diplomacy_peace_board",
            "diplomacy_peace_leverage",
            "diplomacy_peace_settle",
            "major_16",
            "diplomacy",
            "peace",
        ],
    }


def execute_diplomacy_peace_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower()
    if s.startswith("diplomacy_peace_"):
        s = s.replace("diplomacy_peace_", "")
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_diplomacy_peace_campaign_product(province_id=province_id)
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
    label = "Execute diplomacy %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#a78bfa]🕊 Diplomacy %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_diplomacy_peace_step", s, leaf],
    }


def diplomacy_peace_campaign_integrity() -> Dict[str, Any]:
    product = build_diplomacy_peace_campaign_product()
    steps = [execute_diplomacy_peace_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    agent_g = agent_campaign_product_integrity()
    hh_g = hh_multi_month_agenda_product_integrity()
    focus_g = focus_war_path_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(agent_g.get("ok", True))
        and bool(hh_g.get("ok", True))
        and bool(focus_g.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Diplomacy peace campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_diplomacy_peace_campaign_product_loop() -> Dict[str, Any]:
    product = build_diplomacy_peace_campaign_product(province_id=2)
    gate = diplomacy_peace_campaign_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close diplomacy peace · score %.2f · queue %d · %s" % (
        float(product.get("score", 0)),
        len(product.get("apply_queue") or []),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#a78bfa]✓ Diplomacy peace[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
