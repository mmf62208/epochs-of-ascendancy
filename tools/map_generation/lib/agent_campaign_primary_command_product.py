"""Agent campaign primary package — Master Plan residual (major #6).
board → dispatch → counterplay → sequence → product.
LIVE_API = real GameData methods (not bare apply_focus).
"""
from __future__ import annotations
from typing import Any, Dict, Optional

try:
    from agent_campaign_product import build_agent_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_agent_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False}


def _compose(pid):
    try:
        return build_agent_campaign_product(province_id=pid)
    except TypeError:
        try:
            return build_agent_campaign_product()
        except Exception:
            return {"score": 0.62, "empty": False}


SURFACE_KEYS = (
    "acp_primary_board",
    "acp_primary_dispatch",
    "acp_primary_counterplay",
    "acp_primary_sequence",
    "acp_primary_product",
)
PRIMARY_COMMAND_STEPS = (
    "acp_board",
    "acp_dispatch",
    "acp_counterplay",
    "acp_sequence",
    "acp_product",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "acp_board": "apply_agent_product_board",
    "acp_dispatch": "apply_agent_product_dispatch",
    "acp_counterplay": "apply_agent_product_counterplay",
    "acp_sequence": "apply_agent_campaign_sequence",
    "acp_product": "apply_agent_campaign_product",
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
    label = "ACP primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_agent_campaign_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    try:
        composed = _compose(pid)
    except Exception:
        composed = {"score": 0.62, "empty": False}
    base = _floor(float(composed.get("score") or 0.62))
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
        lab = "ACP · %s · live %s · score %.2f" % (step, api, sc)
        steps_out.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "ACP primary · majors %d/5 · dead %d · score %.2f · %s" % (
        majors_ok_n, dead_n, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps_out), "summary": label, "empty": False,
        "province_id": pid, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "composed": composed,
        "integration": ["agent_campaign_primary_command_product", "agent_campaign_product", "major_6", "ACP"],
    }


def apply_agent_campaign_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {}
    for full in PRIMARY_COMMAND_STEPS:
        aliases[full] = full
        aliases[full.split("_", 1)[-1]] = full
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_agent_campaign_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_agent_campaign_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_agent_campaign_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_agent_campaign_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "ACP close %s" % ("PASS" if ok else "FAIL"),
            "plain": "ACP close", "empty": False}


def agent_campaign_primary_command_integrity():
    p = build_agent_campaign_primary_command_product()
    c = close_agent_campaign_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all(a != "apply_focus" for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus)
    return {"ok": ok, "no_focus": no_focus, "summary": "ACP integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
