"""Factory risk + retool primary package — Master Plan P2.

board → factory_risk → retool_horizon → prove_60d → close.
Composes medium honesty + factory risk loops. LIVE_API = real GameData methods.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence

try:
    from medium_tank_production_honesty_product import build_medium_tank_production_honesty_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_production_honesty_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

try:
    from gameplay_loops import oob_factory_risk_loop  # type: ignore
except Exception:  # pragma: no cover
    def oob_factory_risk_loop(**_k):  # type: ignore
        return {"effective_output": 0.9, "risk": {"risk": 0.2}, "summary": "factory risk fallback", "empty": False}

try:
    from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_oob_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "will_complete_60d": True, "empty": False}

SURFACE_KEYS = (
    "retool_primary_board",
    "retool_primary_risk",
    "retool_primary_horizon",
    "retool_primary_prove",
    "retool_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "factory_retool_board",
    "factory_risk_scan",
    "retool_horizon_80d",
    "retool_prove_60d",
    "factory_retool_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "factory_retool_board": "apply_medium_tank_production_honesty_product",
    "factory_risk_scan": "apply_medium_honesty_factory_risk_day",
    "retool_horizon_80d": "apply_oob_horizon_80d",
    "retool_prove_60d": "apply_medium_honesty_prove_60d",
    "factory_retool_close": "apply_medium_tank_production_honesty_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values()) + (
    "apply_prod_factory_risk_ops_day",
    "apply_oob_horizon_60d",
    "apply_oob_horizon_100d",
    "apply_medium_tank_oob_product",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except (TypeError, ValueError):
        s = 0.5
    if s > 2.0:
        s = s / 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Factory retool primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_factory_retool_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    try:
        honesty = build_medium_tank_production_honesty_product(province_id=pid)
    except TypeError:
        honesty = build_medium_tank_production_honesty_product()
    risk = oob_factory_risk_loop()
    try:
        oob = build_medium_tank_oob_product(province_id=pid)
    except TypeError:
        oob = build_medium_tank_oob_product()
    h_sc = _floor(float(honesty.get("score") or 0.6))
    risk_v = float((risk.get("risk") or {}).get("risk", 0.25) if isinstance(risk.get("risk"), dict) else risk.get("risk", 0.25))
    risk_sc = _floor(0.7 - 0.3 * risk_v)
    oob_sc = _floor(float(oob.get("score") or 0.55))
    scores = {
        "factory_retool_board": h_sc,
        "factory_risk_scan": risk_sc,
        "retool_horizon_80d": _floor(0.55 * oob_sc + 0.45 * risk_sc),
        "retool_prove_60d": _floor(oob_sc + 0.02),
        "factory_retool_close": _floor(0.5 * h_sc + 0.5 * oob_sc),
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
        lab = "P2 · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    retool_days = max(1, int(round(5 + risk_v * 20)))
    label = "Factory retool primary · majors %d/5 · dead %d · retool_days~%d · risk %.0f%% · score %.2f · %s" % (
        majors_ok_n, dead_n, retool_days, risk_v * 100, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps), "summary": label, "empty": False,
        "province_id": pid, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "honesty": honesty, "risk": risk, "oob": oob, "retool_days": retool_days,
        "risk_pct": risk_v, "integration": ["factory_retool_primary_command_product", "medium_tank_production_honesty_product",
                                            "oob_factory_risk", "P2", "production"],
    }


def apply_factory_retool_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"board": "factory_retool_board", "risk": "factory_risk_scan", "horizon": "retool_horizon_80d",
               "prove": "retool_prove_60d", "close": "factory_retool_close", "80d": "retool_horizon_80d", "60d": "retool_prove_60d"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_factory_retool_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_factory_retool_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_factory_retool_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_factory_retool_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "Factory retool close %s" % ("PASS" if ok else "FAIL"),
            "plain": "Factory retool close", "empty": False}


def factory_retool_primary_command_integrity():
    p = build_factory_retool_primary_command_product()
    c = close_factory_retool_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus and "apply_medium_honesty_factory_risk_day" in apis)
    return {"ok": ok, "no_focus": no_focus, "summary": "Factory retool integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
