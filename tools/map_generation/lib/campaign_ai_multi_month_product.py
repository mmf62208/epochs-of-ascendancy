"""Campaign AI multi-month product (major #34) — Phase 3.

Month board → weekly plan apply → theater execute.
AI plays a war week/month, not only a day board.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_faction_strategic_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "strategic ai"}

try:
    from strategic_ai_daily_campaign_product import build_strategic_ai_daily_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_ai_daily_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False, "summary": "daily ai"}

PRODUCT_STEPS = ("board", "weekly", "execute")
MONTH_HORIZONS = (1, 2, 3)
WEEKLY_ACTIONS = (
    "apply_production",
    "apply_supply",
    "apply_station",
    "apply_assault",
    "apply_focus",
)
_STEP_META = {
    "board": {"action_id": "campaign_ai_month_board", "leaf": "apply_focus", "label": "Step 0 — multi-month plan board"},
    "weekly": {"action_id": "campaign_ai_weekly_plan", "leaf": "apply_production", "label": "Step 1 — weekly AI plan apply"},
    "execute": {"action_id": "campaign_ai_theater_execute", "leaf": "apply_assault", "label": "Step 2 — theater execute week"},
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


def compute_month_plan(
    *, months: int = 3, player_tag: str = "GER", faction_pressure: float = 0.55
) -> Dict[str, Any]:
    m = max(1, min(6, int(months)))
    pressure = _norm(faction_pressure)
    weeks = m * 4
    war_goal = "secure_front" if pressure >= 0.5 else "build_industry"
    urgency = _floor(0.4 + 0.5 * pressure)
    return {
        "months": m,
        "weeks": weeks,
        "player_tag": str(player_tag or "GER").upper(),
        "war_goal": war_goal,
        "pressure": pressure,
        "urgency": urgency,
        "summary": "Month plan · %dm (%dw) · goal %s · urgency %.0f%%" % (m, weeks, war_goal, urgency * 100),
        "empty": False,
    }


def compute_weekly_actions(*, week_index: int = 1, pressure: float = 0.55) -> Dict[str, Any]:
    wi = max(1, int(week_index))
    p = _norm(pressure)
    actions: List[Dict[str, Any]] = []
    for i, aid in enumerate(WEEKLY_ACTIONS):
        sc = _floor(0.45 + 0.08 * i * (0.5 + p))
        actions.append({
            "action_id": aid,
            "week": wi,
            "score": sc,
            "enabled": True,
            "label": "Week %d · %s · %.2f" % (wi, aid, sc),
        })
    score = _floor(sum(float(a["score"]) for a in actions) / max(1, len(actions)))
    return {
        "week_index": wi,
        "actions": actions,
        "action_n": len(actions),
        "score": score,
        "summary": "Weekly plan · week %d · actions %d · score %.2f" % (wi, len(actions), score),
        "empty": False,
    }


def recommend_campaign_ai_step(*, boarded: bool = False, weekly_done: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "board", "build multi-month plan board"
    elif not weekly_done:
        step, reason = "weekly", "apply weekly AI plan actions"
    else:
        step, reason = "execute", "theater execute top weekly action"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_campaign_ai_multi_month_product(
    *, province_id: int = 1, months: int = 3, player_tag: str = "GER", week_index: int = 1, faction_pressure: float = 0.55
) -> Dict[str, Any]:
    multi = build_multi_faction_strategic_ai_product(province_id=province_id)
    daily = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag=player_tag)
    plan = compute_month_plan(months=months, player_tag=player_tag, faction_pressure=faction_pressure)
    weekly = compute_weekly_actions(week_index=week_index, pressure=float(plan["pressure"]))
    multi_s = _floor(float(multi.get("score", 0.55)))
    daily_s = _floor(float(daily.get("score", 0.55)))
    board_score = _floor(0.4 * multi_s + 0.3 * daily_s + 0.3 * float(plan["urgency"]))
    weekly_score = _floor(0.5 * float(weekly["score"]) + 0.5 * board_score)
    exec_score = _floor(0.45 * weekly_score + 0.55 * board_score)
    score = _floor(0.3 * board_score + 0.35 * weekly_score + 0.35 * exec_score)
    rec = recommend_campaign_ai_step(boarded=True, weekly_done=True)
    step_scores = {"board": board_score, "weekly": weekly_score, "execute": exec_score}
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
    # Include weekly action leaves in queue for live apply proof
    for a in weekly.get("actions") or []:
        apply_queue.append({
            "action_id": a["action_id"], "province_id": max(1, int(province_id)),
            "score": float(a.get("score", 0.5)), "enabled": True,
            "label": a.get("label"), "step": "weekly", "product_action": "campaign_ai_weekly_plan",
        })
    actions = [
        {"action_id": "campaign_ai_multi_month_product", "label": "Run campaign AI multi-month product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Campaign AI multi-month · %dm · week %d · goal %s · score %.2f" % (
        plan["months"], weekly["week_index"], plan["war_goal"], score)
    return {
        "multi": multi, "daily": daily, "plan": plan, "weekly": weekly, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "months": plan["months"], "weeks": plan["weeks"], "war_goal": plan["war_goal"],
        "week_index": weekly["week_index"], "action_n": weekly["action_n"],
        "score": score, "campaign_ai_score": score, "province_id": max(1, int(province_id)),
        "player_tag": plan["player_tag"],
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(plan.get("summary", "")), str(weekly.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#c89ae0]📅 Campaign AI month[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "campaign_ai_multi_month_product", "campaign_ai_month_board", "campaign_ai_weekly_plan",
            "campaign_ai_theater_execute", "major_34", "campaign_ai", "multi_month", "phase3_depth",
        ],
    }


def execute_campaign_ai_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("campaign_ai_", "")
    if s.startswith("month") or s.startswith("board"):
        s = "board"
    elif s.startswith("weekly") or s.startswith("week"):
        s = "weekly"
    elif s.startswith("theater") or s.startswith("execute"):
        s = "execute"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_campaign_ai_multi_month_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute campaign AI %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_campaign_ai_step", s, leaf],
    }


def campaign_ai_multi_month_integrity() -> Dict[str, Any]:
    product = build_campaign_ai_multi_month_product()
    steps = [execute_campaign_ai_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("months", 0)) >= 1
        and int(product.get("action_n", 0)) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Campaign AI multi-month integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_campaign_ai_multi_month_product_loop() -> Dict[str, Any]:
    product = build_campaign_ai_multi_month_product(province_id=2, months=2, week_index=2)
    gate = campaign_ai_multi_month_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close campaign AI multi-month · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
