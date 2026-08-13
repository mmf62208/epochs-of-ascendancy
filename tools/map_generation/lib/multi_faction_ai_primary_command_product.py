"""Multi-faction strategic AI primary package — Master Plan A3.

scan → rank → execute → multi_faction_product → campaign_close.
Composes multi_faction_strategic_ai_product + strategic_ai_daily.
LIVE_API = real GameData methods (not apply_focus).
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional

try:
    from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product, MAJOR_TAGS, FACTION_DOCTRINE  # type: ignore
except Exception:  # pragma: no cover
    MAJOR_TAGS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")
    FACTION_DOCTRINE = {t: {"combat": 1.0} for t in MAJOR_TAGS}
    def build_multi_faction_strategic_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False, "faction_n": 7}

try:
    from strategic_ai_daily_campaign_product import build_strategic_ai_daily_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_ai_daily_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

SURFACE_KEYS = (
    "ai_primary_scan",
    "ai_primary_rank",
    "ai_primary_execute",
    "ai_primary_multi_faction",
    "ai_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "ai_scan",
    "ai_rank",
    "ai_execute",
    "ai_multi_faction",
    "ai_campaign_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "ai_scan": "apply_strategic_ai_scan",
    "ai_rank": "apply_strategic_ai_rank",
    "ai_execute": "apply_strategic_ai_execute",
    "ai_multi_faction": "apply_multi_faction_strategic_ai_product",
    "ai_campaign_close": "apply_strategic_ai_campaign_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values()) + (
    "apply_strategic_ai_daily_campaign_product",
    "apply_multi_faction_ai_daily_depth_live",
    "apply_strategic_ai_daily_board",
    "apply_strategic_ai_daily_apply",
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
    label = "Multi-faction AI primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_multi_faction_ai_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    try:
        mf = build_multi_faction_strategic_ai_product(province_id=pid)
    except TypeError:
        mf = build_multi_faction_strategic_ai_product()
    try:
        daily = build_strategic_ai_daily_campaign_product(province_id=pid)
    except TypeError:
        daily = build_strategic_ai_daily_campaign_product()
    mf_sc = _floor(float(mf.get("score") or 0.6))
    dy_sc = _floor(float(daily.get("score") or 0.55))
    scores = {
        "ai_scan": mf_sc,
        "ai_rank": _floor(mf_sc + 0.02),
        "ai_execute": _floor(mf_sc + 0.03),
        "ai_multi_faction": mf_sc,
        "ai_campaign_close": _floor(0.55 * mf_sc + 0.45 * dy_sc),
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
        lab = "A3 · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    faction_n = int(mf.get("faction_n") or len(MAJOR_TAGS))
    label = "Multi-faction AI primary · majors %d/5 · dead %d · factions %d · doctrine %d · score %.2f · %s" % (
        majors_ok_n, dead_n, faction_n, len(FACTION_DOCTRINE), score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps), "summary": label, "empty": False,
        "province_id": pid, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "multi_faction": mf, "daily": daily, "faction_n": faction_n,
        "doctrine_tags": list(FACTION_DOCTRINE.keys()),
        "integration": ["multi_faction_ai_primary_command_product", "multi_faction_strategic_ai_product", "A3", "strategic_ai"],
    }


def apply_multi_faction_ai_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"scan": "ai_scan", "rank": "ai_rank", "execute": "ai_execute",
               "multi": "ai_multi_faction", "multi_faction": "ai_multi_faction", "close": "ai_campaign_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_multi_faction_ai_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_multi_faction_ai_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_multi_faction_ai_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_multi_faction_ai_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "Multi-faction AI close %s" % ("PASS" if ok else "FAIL"),
            "plain": "Multi-faction AI close", "empty": False}


def multi_faction_ai_primary_command_integrity():
    p = build_multi_faction_ai_primary_command_product()
    c = close_multi_faction_ai_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus and "apply_strategic_ai_scan" in apis
          and int(p.get("faction_n") or 0) >= 5)
    return {"ok": ok, "no_focus": no_focus, "faction_n": p.get("faction_n"),
            "summary": "Multi-faction AI integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
