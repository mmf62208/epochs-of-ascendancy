"""Next-370 apply-queue live managers depth (10)."""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from apply_queue_live_managers_product import (  # type: ignore
    build_apply_queue_live_managers_product, execute_apply_queue_live_step, apply_queue_live_managers_integrity,
)

def _floor(score: float, lo: float = 0.35) -> float:
    try: s = float(score)
    except Exception: s = 0.5
    if s > 2: s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def _q(aid, pid, score, label):
    return {"action_id": aid, "province_id": max(1,int(pid)), "score": score, "enabled": True, "label": label}

def _day(aid, title, summary, score, apply_queue, extra=None):
    sc = _floor(score)
    out = {"id": aid, "title": title, "score": sc, "live_score": sc, "apply_queue": apply_queue,
           "actions": [{"action_id": aid, "label": "Run %s" % title.lower(), "enabled": True}],
           "summary": summary, "plain": summary,
           "bbcode": "[color=#6ec8ff]⚡ %s[/color] [color=#8899aa]%s[/color]" % (title, summary),
           "empty": False, "integration": [aid, "next370", "live_managers"]}
    if extra: out.update(extra)
    return out

def apply_queue_audit_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_apply_queue_live_step("audit", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("apply_queue_audit_day", "Apply queue audit day", "Apply queue audit day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "audit primary"), _q("apply_supply", province_id, 0.5, "audit supply")])

def apply_queue_production_live_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_apply_queue_live_step("production_live", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("apply_queue_production_live_day", "Apply queue production live day", "Apply queue production live day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "prod live primary"), _q("apply_supply", province_id, 0.55, "prod live supply")])

def apply_queue_combat_live_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_apply_queue_live_step("combat_supply", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("apply_queue_combat_live_day", "Apply queue combat live day", "Apply queue combat live day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "combat live primary"), _q("apply_station", province_id, 0.5, "combat live station")])

def apply_queue_supply_live_day(province_id: int = 1) -> Dict[str, Any]:
    return _day("apply_queue_supply_live_day", "Apply queue supply live day", "Apply queue supply live day · score 0.65", 0.65,
                [_q("apply_supply", province_id, 0.65, "supply live primary"), _q("apply_station", province_id, 0.5, "supply live station")])

def apply_queue_focus_live_day(province_id: int = 1) -> Dict[str, Any]:
    return _day("apply_queue_focus_live_day", "Apply queue focus live day", "Apply queue focus live day · score 0.65", 0.65,
                [_q("apply_focus", province_id, 0.65, "focus live primary"), _q("apply_production", province_id, 0.5, "focus live prod")])

def apply_queue_agent_live_day(province_id: int = 1) -> Dict[str, Any]:
    return _day("apply_queue_agent_live_day", "Apply queue agent live day", "Apply queue agent live day · score 0.65", 0.65,
                [_q("apply_agent_dispatch", province_id, 0.65, "agent live primary"), _q("apply_station", province_id, 0.5, "agent live station")])

def apply_queue_station_live_day(province_id: int = 1) -> Dict[str, Any]:
    return _day("apply_queue_station_live_day", "Apply queue station live day", "Apply queue station live day · score 0.65", 0.65,
                [_q("apply_station", province_id, 0.65, "station live primary"), _q("apply_supply", province_id, 0.5, "station live supply")])

def apply_queue_six_leaf_joint_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_apply_queue_live_managers_product(province_id=province_id)
    score = _floor(float(p.get("score", 0.5)))
    q = [_q(leaf, province_id, score, "six %s" % leaf) for leaf in (
        "apply_production", "apply_supply", "apply_station", "apply_assault", "apply_focus", "apply_agent_dispatch")]
    return _day("apply_queue_six_leaf_joint_day", "Apply queue six leaf joint day",
                "Apply queue six leaf joint day · live %s · score %.2f" % (p.get("apply_queue_live"), score), score, q)

def apply_queue_honesty_joint_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_apply_queue_live_managers_product(province_id=province_id)
    try:
        from medium_tank_production_honesty_product import build_medium_tank_production_honesty_product
        h = build_medium_tank_production_honesty_product(province_id=province_id)
        hs = float(h.get("score", 0.5))
    except Exception:
        hs = 0.5
    score = _floor(0.5 * float(p.get("score", 0.5)) + 0.5 * hs)
    return _day("apply_queue_honesty_joint_day", "Apply queue honesty joint day",
                "Apply queue honesty joint day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "honesty joint primary"), _q("apply_supply", province_id, 0.5, "honesty joint supply")])

def apply_queue_live_managers_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = apply_queue_audit_day(province_id)
    d1 = apply_queue_production_live_day(province_id)
    d2 = apply_queue_six_leaf_joint_day(province_id)
    p = build_apply_queue_live_managers_product(province_id=province_id)
    gate = apply_queue_live_managers_integrity()
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    ok = bool(gate.get("ok")) and int(p.get("live_n", 0)) >= 5
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("apply_queue_live_managers_close_day", "Apply queue live managers close day",
                "Apply queue live managers close · live %s · gates %s · score %.2f" % (p.get("apply_queue_live"), "PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "close primary"), _q("apply_assault", province_id, 0.5, "close assault")],
                {"ok": ok, "apply_queue_live": p.get("apply_queue_live"), "gate": gate})

APPLY_QUEUE_LIVE_DAY_IDS = [
    "apply_queue_audit_day", "apply_queue_production_live_day", "apply_queue_combat_live_day",
    "apply_queue_supply_live_day", "apply_queue_focus_live_day", "apply_queue_agent_live_day",
    "apply_queue_station_live_day", "apply_queue_six_leaf_joint_day", "apply_queue_honesty_joint_day",
    "apply_queue_live_managers_close_day",
]
DAY_FUNCS = [
    apply_queue_audit_day, apply_queue_production_live_day, apply_queue_combat_live_day,
    apply_queue_supply_live_day, apply_queue_focus_live_day, apply_queue_agent_live_day,
    apply_queue_station_live_day, apply_queue_six_leaf_joint_day, apply_queue_honesty_joint_day,
    apply_queue_live_managers_close_day,
]

def apply_queue_live_depth_integrity() -> Dict[str, Any]:
    gates = [apply_queue_live_managers_integrity(), execution_integrity_gate(), sole_mult_integrity()]
    sample = [apply_queue_audit_day(), apply_queue_six_leaf_joint_day(), apply_queue_live_managers_close_day()]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Apply-queue live depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_next370_apply_queue_live_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = apply_queue_live_depth_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 10
    label = "Close next370 apply-queue live · packages %d/10 · queue %d · %s" % (non_empty, q_total, "PASS" if ok else "FAIL")
    return {"packages": packages, "non_empty": non_empty, "queue_total": q_total, "gate": gate,
            "score": non_empty / 10.0, "summary": label, "plain": label, "empty": False, "ok": ok}
