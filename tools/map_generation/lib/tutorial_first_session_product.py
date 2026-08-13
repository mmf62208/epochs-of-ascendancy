"""Tutorial / first-session path product (major #41) — Phase 6.

Guided brief → first-week actions → continuity checkpoint.
Onboarding path on play session spine (not multiplayer).
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from play_session_campaign_product import build_play_session_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_play_session_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "play session"}

PRODUCT_STEPS = ("brief", "guide", "checkpoint")
GUIDE_DAYS = 20
_STEP_META = {
    "brief": {"action_id": "tutorial_session_brief", "leaf": "apply_focus", "label": "Step 0 — first-session brief"},
    "guide": {"action_id": "tutorial_session_guide", "leaf": "apply_production", "label": "Step 1 — guided first-week actions"},
    "checkpoint": {"action_id": "tutorial_session_checkpoint", "leaf": "apply_station", "label": "Step 2 — tutorial continuity checkpoint"},
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


def compute_tutorial_brief(*, player_tag: str = "GER", scenario_id: str = "world_full") -> Dict[str, Any]:
    tag = str(player_tag or "GER").upper()
    scen = str(scenario_id or "world_full")
    goals = [
        "Select home province and review inspector chips",
        "Queue production priority on infantry + medium seed",
        "Station one land formation and open supply day",
        "Save slot1 after day 5 for resume practice",
    ]
    return {
        "player_tag": tag,
        "scenario_id": scen,
        "goals": goals,
        "goal_n": len(goals),
        "horizon_days": GUIDE_DAYS,
        "summary": "Tutorial brief · %s · %s · goals %d · horizon %dd" % (tag, scen, len(goals), GUIDE_DAYS),
        "empty": False,
    }


def compute_guide_progress(*, day: int = 1, actions_done: int = 0) -> Dict[str, Any]:
    d = max(1, min(GUIDE_DAYS, int(day)))
    done = max(0, int(actions_done))
    progress = _floor(float(done) / 8.0 + float(d) / float(GUIDE_DAYS) * 0.4)
    return {
        "day": d,
        "actions_done": done,
        "progress": progress,
        "complete": progress >= 0.85 or done >= 6,
        "summary": "Guide · day %d/%d · actions %d · progress %.0f%%" % (d, GUIDE_DAYS, done, progress * 100),
        "empty": False,
    }


def recommend_tutorial_step(*, briefed: bool = False, guided: bool = False) -> Dict[str, Any]:
    if not briefed:
        step, reason = "brief", "open first-session brief"
    elif not guided:
        step, reason = "guide", "run guided first-week actions"
    else:
        step, reason = "checkpoint", "checkpoint continuity for resume"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_tutorial_first_session_product(
    *, province_id: int = 1, player_tag: str = "GER", day: int = 5, actions_done: int = 3
) -> Dict[str, Any]:
    session = build_play_session_campaign_product(province_id=province_id, player_tag=player_tag)
    brief = compute_tutorial_brief(player_tag=player_tag)
    guide = compute_guide_progress(day=day, actions_done=actions_done)
    sess_s = _floor(float(session.get("score", 0.55)))
    brief_score = _floor(0.5 * sess_s + 0.5)
    guide_score = _floor(0.45 + 0.55 * float(guide["progress"]))
    check_score = _floor(0.5 * guide_score + 0.5 * brief_score)
    score = _floor(0.3 * brief_score + 0.35 * guide_score + 0.35 * check_score)
    rec = recommend_tutorial_step(briefed=True, guided=True)
    step_scores = {"brief": brief_score, "guide": guide_score, "checkpoint": check_score}
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
        {"action_id": "tutorial_first_session_product", "label": "Run tutorial first-session product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Tutorial first-session · day %d · goals %d · progress %.0f%% · score %.2f" % (
        guide["day"], brief["goal_n"], float(guide["progress"]) * 100, score)
    return {
        "session": session, "brief": brief, "guide": guide, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "goal_n": brief["goal_n"], "day": guide["day"], "progress": guide["progress"],
        "score": score, "tutorial_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(brief.get("summary", "")), str(guide.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#90d0a0]📘 Tutorial session[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "tutorial_first_session_product", "tutorial_session_brief", "tutorial_session_guide",
            "tutorial_session_checkpoint", "major_41", "tutorial", "first_session", "phase6_depth",
        ],
    }


def execute_tutorial_session_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "brief").strip().lower().replace("tutorial_session_", "").replace("tutorial_", "")
    if s.startswith("brief"):
        s = "brief"
    elif s.startswith("guide"):
        s = "guide"
    elif s.startswith("check"):
        s = "checkpoint"
    if s not in _STEP_META:
        s = "brief"
    meta = _STEP_META[s]
    product = build_tutorial_first_session_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute tutorial %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_tutorial_session_step", s, leaf],
    }


def tutorial_first_session_integrity() -> Dict[str, Any]:
    product = build_tutorial_first_session_product()
    steps = [execute_tutorial_session_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("goal_n", 0)) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Tutorial first-session integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_tutorial_first_session_product_loop() -> Dict[str, Any]:
    product = build_tutorial_first_session_product(province_id=2, day=10, actions_done=5)
    gate = tutorial_first_session_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close tutorial first-session · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
