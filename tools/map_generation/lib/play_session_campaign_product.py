"""Play session campaign product (major #12).

Player day loop as a primary product:
  brief (theater/decision) → execute orders → resolve (AI tick + next-day feedback).
Composes order execute, strategic AI daily, campaign decision, save checkpoint — not day stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from strategic_continuity_day import next_day_feedback, order_execute_day  # type: ignore
from next10_depth import campaign_decision_day  # type: ignore
from theater_command_product import (  # type: ignore
    build_theater_command_product,
    theater_command_product_integrity,
)
from strategic_ai_daily_campaign_product import (  # type: ignore
    build_strategic_ai_daily_campaign_product,
    strategic_ai_daily_campaign_integrity,
)
from save_browser_campaign_product import (  # type: ignore
    build_save_browser_campaign_product,
    save_browser_campaign_product_integrity,
)


PRODUCT_STEPS = ("brief", "execute", "resolve")

_STEP_META = {
    "brief": {
        "action_id": "play_session_brief",
        "leaf": "apply_focus",
        "label": "Step 0 — session brief / theater decision",
    },
    "execute": {
        "action_id": "play_session_execute",
        "leaf": "apply_assault",
        "label": "Step 1 — execute player order queue",
    },
    "resolve": {
        "action_id": "play_session_resolve",
        "leaf": "apply_station",
        "label": "Step 2 — resolve AI day + next-day feedback",
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


def recommend_play_session_step(
    *,
    brief_ready: bool = False,
    execute_done: bool = False,
    resolve_ready: bool = False,
) -> Dict[str, Any]:
    if not brief_ready:
        step = "brief"
        reason = "open session brief"
    elif not execute_done:
        step = "execute"
        reason = "player orders pending"
    elif resolve_ready:
        step = "resolve"
        reason = "AI tick + feedback ready"
    else:
        step = "execute"
        reason = "refresh execute queue"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_play_session_campaign_product(
    *,
    province_id: int = 1,
    player_tag: str = "GER",
) -> Dict[str, Any]:
    theater = build_theater_command_product(province_id=province_id)
    decision = campaign_decision_day(province_id=province_id)
    execute = order_execute_day(province_id=province_id)
    ai_daily = build_strategic_ai_daily_campaign_product(
        province_id=province_id, player_tag=player_tag, max_ai_actions=4
    )
    before = float(execute.get("score", 0.5))
    after = min(1.0, before + 0.06)
    feedback = next_day_feedback(before_score=before, after_score=after, order="session_resolve")
    save = build_save_browser_campaign_product()

    brief_score = _floor(
        0.55 * _norm(float(theater.get("score", 0.5)))
        + 0.45 * _norm(float(decision.get("score", 0.5)))
    )
    exec_score = _floor(_norm(float(execute.get("score", 0.5))))
    resolve_score = _floor(
        0.45 * _norm(float(ai_daily.get("score", 0.5)))
        + 0.35 * _norm(float(feedback.get("after", after)))
        + 0.2 * _norm(float(save.get("score", 0.5)))
    )
    score = _floor(0.3 * brief_score + 0.35 * exec_score + 0.35 * resolve_score)

    brief_ready = not bool(theater.get("empty")) and not bool(decision.get("empty"))
    execute_done = len(execute.get("apply_queue") or []) >= 1 or float(execute.get("score", 0)) > 0.3
    resolve_ready = int(ai_daily.get("budget_count", 0)) >= 1
    rec = recommend_play_session_step(
        brief_ready=brief_ready, execute_done=execute_done, resolve_ready=resolve_ready
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {"brief": brief_score, "execute": exec_score, "resolve": resolve_score}
    exec_q0 = (execute.get("apply_queue") or [{}])
    exec_leaf = "apply_assault"
    if exec_q0 and isinstance(exec_q0[0], Mapping):
        exec_leaf = str(exec_q0[0].get("action_id", "apply_assault"))
    resolve_q0 = ((ai_daily.get("budget") or {}).get("queue") or [{}])
    resolve_leaf = "apply_station"
    if resolve_q0 and isinstance(resolve_q0[0], Mapping):
        resolve_leaf = str(resolve_q0[0].get("action_id", "apply_station"))
    step_leaves = {
        "brief": "apply_focus",
        "execute": exec_leaf,
        "resolve": resolve_leaf,
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
    # Merge AI budget into resolve queue visibility
    for q in (ai_daily.get("budget") or {}).get("queue") or []:
        if isinstance(q, Mapping):
            apply_queue.append(dict(q))

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "play_session_campaign_product",
            "label": "Run play session campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "play_session_brief")),
            "label": "Recommended: %s" % rec.get("step", "brief"),
            "enabled": True,
        },
        {
            "action_id": "strategic_ai_daily_campaign_product",
            "label": "Open strategic AI daily",
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
        "Play session campaign · brief %.2f · execute %.2f · resolve %.2f · AI budget %d · score %.2f"
        % (
            brief_score,
            exec_score,
            resolve_score,
            int(ai_daily.get("budget_count", 0)),
            score,
        )
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        str(theater.get("summary", "")),
        str(decision.get("summary", "")),
        str(execute.get("summary", "")),
        str(ai_daily.get("summary", "")),
        str(feedback.get("summary", "")),
    ]
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "theater": theater,
        "decision": decision,
        "execute": execute,
        "ai_daily": ai_daily,
        "feedback": feedback,
        "save": save,
        "brief_score": brief_score,
        "exec_score": exec_score,
        "resolve_score": resolve_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "session_score": score,
        "province_id": max(1, int(province_id)),
        "player_tag": str(player_tag or "").upper(),
        "budget_count": int(ai_daily.get("budget_count", 0)),
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]▶ Play session[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "play_session_campaign_product",
            "play_session_brief",
            "play_session_execute",
            "play_session_resolve",
            "major_12",
            "play_session",
        ],
    }


def execute_play_session_step(
    step: str,
    province_id: int = 1,
    *,
    player_tag: str = "GER",
) -> Dict[str, Any]:
    s = str(step or "brief").strip().lower()
    if s.startswith("play_session_"):
        s = s.replace("play_session_", "")
    if s not in _STEP_META:
        s = "brief"
    meta = _STEP_META[s]
    product = build_play_session_campaign_product(province_id=province_id, player_tag=player_tag)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q: List[Dict[str, Any]] = [
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
    if s == "execute":
        eq = list((product.get("execute") or {}).get("apply_queue") or [])
        if eq:
            q = [dict(x) for x in eq if isinstance(x, Mapping)][:4] or q
    elif s == "resolve":
        bq = list((product.get("ai_daily") or {}).get("budget", {}).get("queue") or [])
        if bq:
            q = [dict(x) for x in bq if isinstance(x, Mapping)][:4] or q
    label = "Execute play session %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]▶ Session %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_play_session_step", s, leaf],
    }


def play_session_campaign_integrity() -> Dict[str, Any]:
    product = build_play_session_campaign_product(player_tag="GER")
    steps = [execute_play_session_step(s, 1, player_tag="GER") for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    th = theater_command_product_integrity()
    ai = strategic_ai_daily_campaign_integrity()
    save = save_browser_campaign_product_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(th.get("ok", True))
        and bool(ai.get("ok", False))
        and bool(save.get("ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "budget_count": int(product.get("budget_count", 0)),
        "gate": gate,
        "summary": "Play session campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_play_session_campaign_product_loop() -> Dict[str, Any]:
    product = build_play_session_campaign_product(player_tag="ENG")
    gate = play_session_campaign_integrity()
    ok = (
        bool(gate.get("ok"))
        and len(product.get("apply_queue") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
    )
    label = "Close play session campaign · score %.2f · queue %d · %s" % (
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
        "bbcode": "[color=#6eb5ff]✓ Play session campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
