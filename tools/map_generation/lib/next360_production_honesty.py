"""Next-360 medium production honesty depth (10).

Major #27 windows + unit stats + joints + close.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from medium_tank_production_honesty_product import (  # type: ignore
    build_medium_tank_production_honesty_product,
    execute_medium_honesty_step,
    medium_tank_production_honesty_integrity,
)

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def _q(aid: str, province_id: int, score: float, label: str) -> Dict[str, Any]:
    return {"action_id": aid, "province_id": max(1, int(province_id)), "score": score, "enabled": True, "label": label}

def _day(aid: str, title: str, summary: str, score: float, apply_queue: List, extra: Dict = None) -> Dict[str, Any]:
    sc = _floor(score)
    out = {
        "id": aid, "title": title, "score": sc, "honesty_score": sc, "apply_queue": apply_queue,
        "actions": [{"action_id": aid, "label": "Run %s" % title.lower(), "enabled": True}],
        "summary": summary, "plain": summary,
        "bbcode": "[color=#c8e06a]🛡 %s[/color] [color=#8899aa]%s[/color]" % (title, summary),
        "empty": False, "integration": [aid, "next360", "production_honesty"],
    }
    if extra: out.update(extra)
    return out

def medium_honesty_60d_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_medium_honesty_step("prove_60d", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("medium_honesty_60d_day", "Medium honesty 60d day",
        "Medium honesty 60d day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "60d primary"), _q("apply_station", province_id, 0.5, "60d station")])

def medium_honesty_80d_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_medium_honesty_step("prove_80d", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("medium_honesty_80d_day", "Medium honesty 80d day",
        "Medium honesty 80d day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "80d primary"), _q("apply_station", province_id, 0.5, "80d station")])

def medium_honesty_100d_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_medium_honesty_step("prove_100d", province_id)
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(e.get("score", 0.5))) + 0.45 * _norm(float(p.get("score", 0.5))))
    return _day("medium_honesty_100d_day", "Medium honesty 100d day",
        "Medium honesty 100d day · complete=%d · score %.2f" % (int(p.get("medium_tank_complete", 0)), score), score,
        [_q("apply_supply", province_id, score, "100d primary"), _q("apply_production", province_id, 0.5, "100d prod")],
        {"medium_tank_complete": int(p.get("medium_tank_complete", 0))})

def medium_honesty_unit_stats_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    sheet = p.get("unit_sheet") or {}
    score = _floor(0.5 * _norm(float(p.get("score", 0.5))) + 0.5 * (0.7 if sheet.get("will_complete") else 0.4))
    return _day("medium_honesty_unit_stats_day", "Medium honesty unit stats day",
        "Medium honesty unit stats · crew %d · rel %.0f%% · score %.2f" % (int(sheet.get("crew_required", 5)), float(sheet.get("reliability", 0.7))*100, score), score,
        [_q("apply_production", province_id, score, "stats primary"), _q("apply_station", province_id, 0.5, "stats station")])

def medium_honesty_factory_risk_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    score = _floor(float(p.get("score", 0.5)))
    return _day("medium_honesty_factory_risk_day", "Medium honesty factory risk day",
        "Medium honesty factory risk day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "risk primary"), _q("apply_station", province_id, 0.5, "risk station")])

def medium_honesty_stockpile_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(p.get("score", 0.5))) + 0.45 * float(int(p.get("medium_tank_complete", 0))))
    return _day("medium_honesty_stockpile_day", "Medium honesty stockpile day",
        "Medium honesty stockpile day · complete=%d · score %.2f" % (int(p.get("medium_tank_complete", 0)), score), score,
        [_q("apply_supply", province_id, score, "stock primary"), _q("apply_production", province_id, 0.5, "stock prod")])

def medium_honesty_readiness_joint_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    score = _floor(0.6 * _norm(float(p.get("score", 0.5))) + 0.4 * 0.58)
    return _day("medium_honesty_readiness_joint_day", "Medium honesty readiness joint day",
        "Medium honesty readiness joint day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "ready joint primary"), _q("apply_production", province_id, 0.5, "ready joint prod")])

def medium_honesty_manpower_joint_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    try:
        from manpower_reinforcement_product import build_manpower_reinforcement_product
        mp = build_manpower_reinforcement_product(province_id=province_id)
        mps = float(mp.get("score", 0.5))
    except Exception:
        mps = 0.5
    score = _floor(0.5 * _norm(float(p.get("score", 0.5))) + 0.5 * _norm(mps))
    return _day("medium_honesty_manpower_joint_day", "Medium honesty manpower joint day",
        "Medium honesty manpower joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "mp joint primary"), _q("apply_focus", province_id, 0.5, "mp joint focus")])

def medium_honesty_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    try:
        from war_economy_mobilization_product import build_war_economy_mobilization_product
        e = build_war_economy_mobilization_product(province_id=province_id)
        es = float(e.get("score", 0.5))
    except Exception:
        es = 0.5
    score = _floor(0.5 * _norm(float(p.get("score", 0.5))) + 0.5 * _norm(es))
    return _day("medium_honesty_economy_joint_day", "Medium honesty economy joint day",
        "Medium honesty economy joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "econ joint primary"), _q("apply_focus", province_id, 0.5, "econ joint focus")])

def medium_tank_production_honesty_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = medium_honesty_60d_day(province_id)
    d1 = medium_honesty_80d_day(province_id)
    d2 = medium_honesty_100d_day(province_id)
    p = build_medium_tank_production_honesty_product(province_id=province_id)
    gate = medium_tank_production_honesty_integrity()
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    ok = bool(gate.get("ok")) and int(p.get("medium_tank_complete", 0)) >= 1
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("medium_tank_production_honesty_close_day", "Medium tank production honesty close day",
        "Medium tank production honesty close · complete=%d · gates %s · score %.2f" % (int(p.get("medium_tank_complete", 0)), "PASS" if ok else "FAIL", score), score,
        [_q("apply_production", province_id, score, "close primary"), _q("apply_supply", province_id, 0.5, "close supply")],
        {"ok": ok, "medium_tank_complete": int(p.get("medium_tank_complete", 0)), "gate": gate})

PRODUCTION_HONESTY_DAY_IDS = [
    "medium_honesty_60d_day", "medium_honesty_80d_day", "medium_honesty_100d_day",
    "medium_honesty_unit_stats_day", "medium_honesty_factory_risk_day", "medium_honesty_stockpile_day",
    "medium_honesty_readiness_joint_day", "medium_honesty_manpower_joint_day", "medium_honesty_economy_joint_day",
    "medium_tank_production_honesty_close_day",
]
DAY_FUNCS = [
    medium_honesty_60d_day, medium_honesty_80d_day, medium_honesty_100d_day,
    medium_honesty_unit_stats_day, medium_honesty_factory_risk_day, medium_honesty_stockpile_day,
    medium_honesty_readiness_joint_day, medium_honesty_manpower_joint_day, medium_honesty_economy_joint_day,
    medium_tank_production_honesty_close_day,
]

def production_honesty_integrity() -> Dict[str, Any]:
    gates = [medium_tank_production_honesty_integrity(), execution_integrity_gate(), sole_mult_integrity()]
    sample = [medium_honesty_60d_day(), medium_honesty_100d_day(), medium_tank_production_honesty_close_day()]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Production honesty integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_next360_production_honesty_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = production_honesty_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 10
    label = "Close next360 production honesty · packages %d/10 · queue %d · %s" % (non_empty, q_total, "PASS" if ok else "FAIL")
    return {"packages": packages, "non_empty": non_empty, "queue_total": q_total, "gate": gate,
            "score": non_empty / 10.0, "summary": label, "plain": label, "empty": False, "ok": ok}
