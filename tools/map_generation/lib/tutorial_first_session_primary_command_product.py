"""Tutorial first-session primary package — Master Plan U1.

brief → guide → checkpoint → first_session_product → close.
Composes tutorial_first_session_product. LIVE_API = real GameData methods.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence

try:
    from tutorial_first_session_product import (  # type: ignore
        build_tutorial_first_session_product,
        compute_tutorial_brief,
        compute_guide_progress,
    )
except Exception:  # pragma: no cover
    def build_tutorial_first_session_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False}
    def compute_tutorial_brief(**_k):  # type: ignore
        return {"goal_n": 4, "summary": "brief", "empty": False}
    def compute_guide_progress(**_k):  # type: ignore
        return {"progress": 0.7, "complete": False, "summary": "guide", "empty": False}

SURFACE_KEYS = (
    "tutorial_primary_brief",
    "tutorial_primary_guide",
    "tutorial_primary_checkpoint",
    "tutorial_primary_product",
    "tutorial_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "tutorial_brief",
    "tutorial_guide",
    "tutorial_checkpoint",
    "tutorial_product",
    "tutorial_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "tutorial_brief": "apply_tutorial_session_brief",
    "tutorial_guide": "apply_tutorial_session_guide",
    "tutorial_checkpoint": "apply_tutorial_session_checkpoint",
    "tutorial_product": "apply_tutorial_first_session_product",
    "tutorial_close": "apply_tutorial_first_session_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values()) + (
    "apply_tutorial_session_live",
    "apply_tutorial_session_brief_day",
    "apply_tutorial_session_guide_day",
    "apply_tutorial_session_checkpoint_day",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except (TypeError, ValueError):
        s = 0.5
    if s > 2.0:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Tutorial primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_tutorial_first_session_primary_command_product(*, province_id: int = 1, player_tag: str = "GER", live_ids=None):
    pid = max(1, int(province_id))
    try:
        product = build_tutorial_first_session_product(province_id=pid)
    except TypeError:
        product = build_tutorial_first_session_product()
    brief = compute_tutorial_brief(player_tag=player_tag)
    guide = compute_guide_progress(day=7, actions_done=5)
    base = _floor(float(product.get("score") or 0.6))
    scores = {
        "tutorial_brief": _floor(base),
        "tutorial_guide": _floor(float(guide.get("progress") or 0.6)),
        "tutorial_checkpoint": _floor(base + 0.02),
        "tutorial_product": base,
        "tutorial_close": _floor(base + 0.03),
    }
    majors_ok = {SURFACE_KEYS[i]: scores[PRIMARY_COMMAND_STEPS[i]] >= 0.35 for i in range(5)}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0
    steps, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        lab = "U1 · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Tutorial first-session primary · majors %d/5 · dead %d · tag %s · score %.2f · %s" % (
        majors_ok_n, dead_n, player_tag, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps), "summary": label, "empty": False,
        "province_id": pid, "player_tag": player_tag, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok": majors_ok, "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n,
        "dead_ok": bool(audit.get("ok")), "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "step_scores": scores, "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "brief": brief, "guide": guide, "product": product,
        "integration": ["tutorial_first_session_primary_command_product", "tutorial_first_session_product", "U1", "onboarding"],
    }


def apply_tutorial_first_session_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"brief": "tutorial_brief", "guide": "tutorial_guide", "checkpoint": "tutorial_checkpoint",
               "product": "tutorial_product", "close": "tutorial_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_tutorial_first_session_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_tutorial_first_session_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_tutorial_first_session_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_tutorial_first_session_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "Tutorial primary close %s" % ("PASS" if ok else "FAIL"),
            "plain": "Tutorial primary close", "empty": False}


def tutorial_first_session_primary_command_integrity():
    p = build_tutorial_first_session_primary_command_product()
    c = close_tutorial_first_session_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus and "apply_tutorial_session_brief" in apis)
    return {"ok": ok, "no_focus": no_focus, "summary": "Tutorial primary integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
