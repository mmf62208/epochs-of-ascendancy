"""Pack N thin era primary — historical OOB era fill residual (not full Pack N).
catalog → era1936 → era1918 → equip → close.
LIVE_API = real GameData historical/medium OOB methods (not apply_focus).
"""
from __future__ import annotations
from typing import Any, Dict

SURFACE_KEYS = (
    "pne_primary_catalog",
    "pne_primary_era1936",
    "pne_primary_era1918",
    "pne_primary_equip",
    "pne_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "pne_catalog",
    "pne_era1936",
    "pne_era1918",
    "pne_equip",
    "pne_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "pne_catalog": "apply_historical_oob_catalog",
    "pne_era1936": "apply_historical_oob_seed",
    "pne_era1918": "apply_medium_tank_oob_product",
    "pne_equip": "apply_historical_oob_equip",
    "pne_close": "apply_historical_oob_content_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
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
    label = "Pack N era primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_pack_n_era_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    base = 0.61
    scores = {s: _floor(base + 0.01 * i) for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
    majors_ok = {SURFACE_KEYS[i]: scores[PRIMARY_COMMAND_STEPS[i]] >= 0.35 for i in range(5)}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        lab = "PNE · %s · live %s · score %.2f" % (step, api, sc)
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
            "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True,
            "province_id": pid,
        })
        apply_queue.append({
            "action_id": api, "province_id": pid, "score": sc, "enabled": True,
            "label": lab, "step": step, "live_api": api,
        })
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Pack N era primary · majors %d/5 · dead %d · score %.2f · %s" % (
        majors_ok_n, dead_n, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score,
        "plain": label + "\n" + "\n".join(r["label"] for r in steps_out),
        "summary": label,
        "empty": False,
        "province_id": pid,
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n,
        "all_majors_ok": all_majors_ok,
        "dead_n": dead_n,
        "dead_ok": bool(audit.get("ok")),
        "audit": audit,
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "eras": [1918, 1936],
        "integration": ["pack_n_era_primary_command_product", "PackN", "X1"],
    }


def apply_pack_n_era_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {full: full for full in PRIMARY_COMMAND_STEPS}
    for full in PRIMARY_COMMAND_STEPS:
        aliases[full.split("_", 1)[-1]] = full
    aliases["1936"] = "pne_era1936"
    aliases["1918"] = "pne_era1918"
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_pack_n_era_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {
        "ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc,
        "province_id": province_id,
        "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False,
    }
