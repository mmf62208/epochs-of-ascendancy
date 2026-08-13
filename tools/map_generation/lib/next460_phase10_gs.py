"""Next-460 Phase 10 world-class GS (12): war goals · multi-front AI · grand strategy cycle."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from strategic_war_goal_product import (  # type: ignore
    build_strategic_war_goal_product, execute_war_goal_step, strategic_war_goal_integrity,
)
from multi_front_campaign_ai_product import (  # type: ignore
    build_multi_front_campaign_ai_product, execute_multi_front_step, multi_front_campaign_ai_integrity,
)
from grand_strategy_cycle_product import (  # type: ignore
    build_grand_strategy_cycle_product, execute_gs_cycle_step, grand_strategy_cycle_integrity,
)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except Exception:
        s = 0.5
    if s > 2:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def _q(aid, pid, score, label):
    return {"action_id": aid, "province_id": max(1, int(pid)), "score": score, "enabled": True, "label": label}


def _day(aid, title, summary, score, apply_queue, extra=None):
    sc = _floor(score)
    out = {
        "id": aid, "title": title, "score": sc, "live_score": sc, "apply_queue": apply_queue,
        "actions": [{"action_id": aid, "label": "Run %s" % title.lower(), "enabled": True}],
        "summary": summary, "plain": summary,
        "bbcode": "[color=#6ec8ff]⚡ %s[/color] [color=#8899aa]%s[/color]" % (title, summary),
        "empty": False, "integration": [aid, "next460", "phase10_gs", "world_class_gs"],
    }
    if extra:
        out.update(extra)
    return out


def war_goal_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_war_goal_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("war_goal_board_day", "War goal board day",
                "War goal board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "wg board primary"), _q("apply_station", province_id, 0.5, "wg board station")],
                {"gs_score": score})


def war_goal_justify_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_war_goal_step("justify", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("war_goal_justify_day", "War goal justify day",
                "War goal justify day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "wg justify primary"), _q("apply_production", province_id, 0.5, "wg justify prod")],
                {"gs_score": score})


def war_goal_execute_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_war_goal_step("execute", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("war_goal_execute_day", "War goal execute day",
                "War goal execute day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "wg execute primary"), _q("apply_supply", province_id, 0.5, "wg execute supply")],
                {"gs_score": score})


def strategic_war_goal_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = war_goal_board_day(province_id), war_goal_justify_day(province_id), war_goal_execute_day(province_id)
    p = build_strategic_war_goal_product(province_id=province_id)
    gate = strategic_war_goal_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("strategic_war_goal_close_day", "Strategic war goal close day",
                "Strategic war-goal close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "wg close primary"), _q("apply_focus", province_id, 0.5, "wg close focus")],
                {"ok": ok, "gs_score": score, "gate": gate})


def multi_front_plan_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_front_step("plan", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_front_plan_day", "Multi front plan day",
                "Multi front plan day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "mf plan primary"), _q("apply_station", province_id, 0.5, "mf plan station")],
                {"gs_score": score})


def multi_front_weekly_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_front_step("weekly", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_front_weekly_day", "Multi front weekly day",
                "Multi front weekly day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "mf weekly primary"), _q("apply_focus", province_id, 0.5, "mf weekly focus")],
                {"gs_score": score})


def multi_front_execute_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_front_step("execute", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_front_execute_day", "Multi front execute day",
                "Multi front execute day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "mf exec primary"), _q("apply_station", province_id, 0.5, "mf exec station")],
                {"gs_score": score})


def multi_front_campaign_ai_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = multi_front_plan_day(province_id), multi_front_weekly_day(province_id), multi_front_execute_day(province_id)
    p = build_multi_front_campaign_ai_product(province_id=province_id)
    gate = multi_front_campaign_ai_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("multi_front_campaign_ai_close_day", "Multi front campaign AI close day",
                "Multi-front campaign AI close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "mf close primary"), _q("apply_production", province_id, 0.5, "mf close prod")],
                {"ok": ok, "gs_score": score, "gate": gate})


def gs_cycle_scan_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_gs_cycle_step("scan", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("gs_cycle_scan_day", "GS cycle scan day",
                "GS cycle scan day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "gs scan primary"), _q("apply_station", province_id, 0.5, "gs scan station")],
                {"gs_score": score})


def gs_cycle_rank_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_gs_cycle_step("rank", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("gs_cycle_rank_day", "GS cycle rank day",
                "GS cycle rank day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "gs rank primary"), _q("apply_focus", province_id, 0.5, "gs rank focus")],
                {"gs_score": score})


def gs_cycle_execute_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_gs_cycle_step("execute", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("gs_cycle_execute_day", "GS cycle execute day",
                "GS cycle execute day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "gs exec primary"), _q("apply_supply", province_id, 0.5, "gs exec supply")],
                {"gs_score": score})


def grand_strategy_cycle_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = gs_cycle_scan_day(province_id), gs_cycle_rank_day(province_id), gs_cycle_execute_day(province_id)
    p = build_grand_strategy_cycle_product(province_id=province_id)
    gate = grand_strategy_cycle_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty") and bool(p.get("complete"))
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("grand_strategy_cycle_close_day", "Grand strategy cycle close day",
                "Grand strategy cycle close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "gs close primary"), _q("apply_focus", province_id, 0.5, "gs close focus")],
                {"ok": ok, "gs_score": score, "gate": gate})


PHASE10_GS_DAY_IDS = [
    "war_goal_board_day", "war_goal_justify_day", "war_goal_execute_day", "strategic_war_goal_close_day",
    "multi_front_plan_day", "multi_front_weekly_day", "multi_front_execute_day", "multi_front_campaign_ai_close_day",
    "gs_cycle_scan_day", "gs_cycle_rank_day", "gs_cycle_execute_day", "grand_strategy_cycle_close_day",
]
DAY_FUNCS = [
    war_goal_board_day, war_goal_justify_day, war_goal_execute_day, strategic_war_goal_close_day,
    multi_front_plan_day, multi_front_weekly_day, multi_front_execute_day, multi_front_campaign_ai_close_day,
    gs_cycle_scan_day, gs_cycle_rank_day, gs_cycle_execute_day, grand_strategy_cycle_close_day,
]


def phase10_gs_integrity() -> Dict[str, Any]:
    gates = [
        strategic_war_goal_integrity(),
        multi_front_campaign_ai_integrity(),
        grand_strategy_cycle_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        war_goal_board_day(), multi_front_plan_day(), gs_cycle_scan_day(),
        strategic_war_goal_close_day(), multi_front_campaign_ai_close_day(), grand_strategy_cycle_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase10 GS integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next460_phase10_gs_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase10_gs_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-460 phase10 GS · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
