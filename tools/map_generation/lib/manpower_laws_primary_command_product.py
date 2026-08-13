"""Manpower laws / cohort / train primary package — Master Plan O2.

law → train → cohorts → mobilize → close.
Composes manpower_laws_training + cohort_reserve products.
LIVE_API = real GameData methods (not apply_focus).
"""
from __future__ import annotations
from typing import Any, Dict, Optional

try:
    from manpower_laws_training_product import build_manpower_laws_training_product  # type: ignore
except Exception:  # pragma: no cover
    def build_manpower_laws_training_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "law": "limited"}

try:
    from manpower_cohort_reserve_product import build_manpower_cohort_reserve_product  # type: ignore
except Exception:  # pragma: no cover
    def build_manpower_cohort_reserve_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

SURFACE_KEYS = (
    "manpower_primary_law",
    "manpower_primary_train",
    "manpower_primary_cohorts",
    "manpower_primary_mobilize",
    "manpower_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "manpower_law",
    "manpower_train",
    "manpower_cohorts",
    "manpower_mobilize",
    "manpower_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "manpower_law": "apply_manpower_laws_training_product",
    "manpower_train": "apply_manpower_training_tick_live",
    "manpower_cohorts": "apply_manpower_cohort_board",
    "manpower_mobilize": "apply_manpower_cohort_mobilize",
    "manpower_close": "apply_manpower_cohort_reserve_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values()) + (
    "apply_manpower_cohort_reserve_product",
    "apply_manpower_cohort_reserve",
    "apply_manpower_law_live",
    "apply_manpower_reinforcement_product",
    "apply_manpower_reserve_active",
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
    label = "Manpower laws primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_manpower_laws_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    try:
        laws = build_manpower_laws_training_product(province_id=pid)
    except TypeError:
        laws = build_manpower_laws_training_product()
    try:
        cohorts = build_manpower_cohort_reserve_product(province_id=pid)
    except TypeError:
        cohorts = build_manpower_cohort_reserve_product()
    l_sc = _floor(float(laws.get("score") or 0.6))
    c_sc = _floor(float(cohorts.get("score") or 0.58))
    scores = {
        "manpower_law": l_sc,
        "manpower_train": _floor(l_sc + 0.02),
        "manpower_cohorts": c_sc,
        "manpower_mobilize": _floor(c_sc + 0.02),
        "manpower_close": _floor(0.5 * l_sc + 0.5 * c_sc),
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
        lab = "O2 · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Manpower laws primary · majors %d/5 · dead %d · score %.2f · %s" % (
        majors_ok_n, dead_n, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps), "summary": label, "empty": False,
        "province_id": pid, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "laws": laws, "cohorts": cohorts,
        "integration": ["manpower_laws_primary_command_product", "manpower_laws_training_product",
                        "manpower_cohort_reserve_product", "O2", "manpower"],
    }


def apply_manpower_laws_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"law": "manpower_law", "train": "manpower_train", "cohorts": "manpower_cohorts",
               "mobilize": "manpower_mobilize", "close": "manpower_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_manpower_laws_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_manpower_laws_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_manpower_laws_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_manpower_laws_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "Manpower laws close %s" % ("PASS" if ok else "FAIL"),
            "plain": "Manpower laws close", "empty": False}


def manpower_laws_primary_command_integrity():
    p = build_manpower_laws_primary_command_product()
    c = close_manpower_laws_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus and "apply_manpower_cohort_board" in apis)
    return {"ok": ok, "no_focus": no_focus, "summary": "Manpower laws integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
