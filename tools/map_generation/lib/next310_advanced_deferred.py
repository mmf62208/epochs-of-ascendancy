"""Next-310 advanced deferred pillars (20).

A) Focus / war path advanced (1–7) — major #14 depth
B) Naval multi-phase / fleet combat advanced (8–14) — major #15 depth
C) Designer / AI multi-day / session advanced close (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from focus_war_path_product import (  # type: ignore
    build_focus_war_path_product,
    execute_focus_war_step,
    focus_war_path_product_integrity,
)
from naval_multi_phase_campaign_product import (  # type: ignore
    build_naval_multi_phase_campaign_product,
    execute_naval_phase_step,
    naval_multi_phase_campaign_integrity,
)
from designer_suite_product import (  # type: ignore
    build_designer_suite_product,
    designer_suite_product_integrity,
    execute_designer_suite_step,
)
from multi_faction_strategic_ai_product import (  # type: ignore
    build_multi_faction_strategic_ai_product,
    multi_faction_strategic_ai_integrity,
)
from strategic_ai_daily_campaign_product import (  # type: ignore
    build_strategic_ai_daily_campaign_product,
    strategic_ai_daily_campaign_integrity,
)
from play_session_campaign_product import (  # type: ignore
    build_play_session_campaign_product,
    play_session_campaign_integrity,
)
from air_ops_campaign_product import (  # type: ignore
    air_ops_campaign_integrity,
    build_air_ops_campaign_product,
)
from fleet_multi_day_autonomy_product import build_fleet_multi_day_autonomy_product  # type: ignore
from combat_multi_phase_product import build_multi_phase_combat_product  # type: ignore
from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


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
    return s if s >= lo else max(lo, min(1.0, s + 0.25))


def _q(aid: str, pid: int, score: float, label: str) -> Dict[str, Any]:
    return {
        "action_id": aid,
        "province_id": max(1, int(pid)),
        "score": float(score),
        "enabled": True,
        "label": label,
    }


def _day(
    action_id: str,
    title: str,
    summary: str,
    score: float,
    apply_queue: List[Dict[str, Any]],
    color: str = "#6eb5ff",
    marker: str = "★",
    integration: Optional[List[str]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": "Run %s" % title, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]"
        % (color, marker, title, summary),
        "empty": False,
        "integration": list(integration or ["next310", "advanced_deferred"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


# A) Focus advanced


def focus_pick_board_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_focus_war_path_product(province_id=province_id)
    score = _floor(float(p.get("pick_score", p.get("score", 0.5))))
    return _day(
        "focus_pick_board_advanced_day",
        "Focus pick board advanced day",
        "Focus pick board advanced · %s · score %.2f" % (p.get("focus_id"), score),
        score,
        [_q("apply_focus", province_id, score, "focus pick board"), _q("apply_production", province_id, 0.5, "focus industry")],
        "#c084fc",
        "◆",
        ["focus", "pick", "advanced"],
        {"product": p, "focus_score": score},
    )


def focus_war_path_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_focus_war_path_product(province_id=province_id)
    e = execute_focus_war_step("war_path", province_id)
    score = _floor(0.55 * float(p.get("path_score", 0.5)) + 0.45 * float(e.get("score", 0.5)))
    return _day(
        "focus_war_path_advanced_day",
        "Focus war path advanced day",
        "Focus war path advanced · score %.2f" % score,
        score,
        list(e.get("apply_queue") or [])[:3] or [_q("apply_focus", province_id, score, "focus war path")],
        "#c084fc",
        "◆",
        ["focus", "war_path", "advanced"],
        {"product": p, "focus_score": score},
    )


def focus_commit_execute_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_focus_war_step("commit", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "focus_commit_execute_advanced_day",
        "Focus commit execute advanced day",
        "Focus commit execute advanced · score %.2f" % score,
        score,
        list(e.get("apply_queue") or [])[:3] or [_q("apply_hh_commit", province_id, score, "focus commit")],
        "#c084fc",
        "◆",
        ["focus", "commit", "advanced"],
        {"step": e, "focus_score": score},
    )


def focus_naval_effort_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_focus_war_path_product(province_id=province_id, focus_id="naval_effort")
    score = _floor(float(p.get("score", 0.5)))
    return _day(
        "focus_naval_effort_advanced_day",
        "Focus naval effort advanced day",
        "Focus naval effort advanced · focus %s · score %.2f" % (p.get("focus_id"), score),
        score,
        [_q("apply_focus", province_id, score, "naval effort focus"), _q("apply_station", province_id, 0.55, "naval effort fleet")],
        "#c084fc",
        "◆",
        ["focus", "naval", "advanced"],
        {"product": p, "focus_score": score},
    )


def focus_industry_army_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ind = build_focus_war_path_product(province_id=province_id, focus_id="industrial_effort")
    oob = build_medium_tank_oob_product(province_id=province_id)
    score = _floor(0.5 * float(ind.get("score", 0.5)) + 0.5 * float(oob.get("score", 0.5)))
    return _day(
        "focus_industry_army_joint_day",
        "Focus industry army joint day",
        "Focus industry army joint · score %.2f" % score,
        score,
        [_q("apply_focus", province_id, score, "industry focus"), _q("apply_production", province_id, 0.55, "army production")],
        "#c084fc",
        "◆",
        ["focus", "industry", "joint"],
        {"focus": ind, "oob": oob, "focus_score": score},
    )


def focus_air_effort_joint_day(province_id: int = 1) -> Dict[str, Any]:
    air_f = build_focus_war_path_product(province_id=province_id, focus_id="air_effort")
    air = build_air_ops_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(air_f.get("score", 0.5)) + 0.5 * float(air.get("score", 0.5)))
    return _day(
        "focus_air_effort_joint_day",
        "Focus air effort joint day",
        "Focus air effort joint · score %.2f" % score,
        score,
        [_q("apply_focus", province_id, score, "air effort focus"), _q("apply_assault", province_id, 0.5, "air support assault")],
        "#c084fc",
        "◆",
        ["focus", "air", "joint"],
        {"focus": air_f, "air": air, "focus_score": score},
    )


def focus_war_path_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        focus_pick_board_advanced_day(province_id),
        focus_war_path_advanced_day(province_id),
        focus_commit_execute_advanced_day(province_id),
        focus_naval_effort_advanced_day(province_id),
        focus_industry_army_joint_day(province_id),
        focus_air_effort_joint_day(province_id),
    ]
    gate = focus_war_path_product_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day(
        "focus_war_path_close_day",
        "Focus war path close day",
        "Focus war path close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score),
        score,
        [_q("apply_focus", province_id, score, "focus close"), _q("apply_hh_commit", province_id, 0.5, "focus close commit")],
        "#5ec8ff",
        "✓",
        ["focus", "war_path", "close"],
        {"packages": days, "gate": gate, "ok": ok, "focus_score": score},
    )


# B) Naval advanced


def naval_posture_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_naval_multi_phase_campaign_product(province_id=province_id)
    e = execute_naval_phase_step("posture", province_id)
    score = _floor(0.55 * float(p.get("posture_score", 0.5)) + 0.45 * float(e.get("score", 0.5)))
    return _day(
        "naval_posture_advanced_day",
        "Naval posture advanced day",
        "Naval posture advanced · score %.2f" % score,
        score,
        list(e.get("apply_queue") or [])[:3] or [_q("apply_station", province_id, score, "naval posture")],
        "#0ea5e9",
        "⚓",
        ["naval", "posture", "advanced"],
        {"product": p, "naval_score": score},
    )


def naval_escort_phase_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_naval_phase_step("escort", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "naval_escort_phase_advanced_day",
        "Naval escort phase advanced day",
        "Naval escort phase advanced · score %.2f" % score,
        score,
        list(e.get("apply_queue") or [])[:3] or [_q("apply_station", province_id, score, "naval escort")],
        "#0ea5e9",
        "🛡",
        ["naval", "escort", "advanced"],
        {"step": e, "naval_score": score},
    )


def naval_strike_phase_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_naval_phase_step("strike", province_id)
    combat = build_multi_phase_combat_product(province_id=province_id)
    score = _floor(0.55 * float(e.get("score", 0.5)) + 0.45 * float(combat.get("score", 0.5)))
    return _day(
        "naval_strike_phase_advanced_day",
        "Naval strike phase advanced day",
        "Naval strike phase advanced · score %.2f" % score,
        score,
        [_q("apply_assault", province_id, score, "naval strike"), _q("apply_station", province_id, 0.5, "naval hold")],
        "#0ea5e9",
        "⚔",
        ["naval", "strike", "advanced"],
        {"step": e, "combat": combat, "naval_score": score},
    )


def naval_fleet_fuel_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    low = build_naval_multi_phase_campaign_product(province_id=province_id, fuel_level=0.4)
    high = build_naval_multi_phase_campaign_product(province_id=province_id, fuel_level=0.85)
    score = _floor(0.45 * float(low.get("score", 0.5)) + 0.55 * float(high.get("score", 0.5)))
    return _day(
        "naval_fleet_fuel_advanced_day",
        "Naval fleet fuel advanced day",
        "Naval fleet fuel advanced · low %.2f · high %.2f · score %.2f"
        % (float(low.get("score", 0)), float(high.get("score", 0)), score),
        score,
        [_q("apply_station", province_id, score, "refuel station"), _q("apply_supply", province_id, 0.55, "fuel supply")],
        "#0ea5e9",
        "⛽",
        ["naval", "fuel", "advanced"],
        {"low": low, "high": high, "naval_score": score},
    )


def naval_fleet_autonomy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    fleet = build_fleet_multi_day_autonomy_product(province_id=province_id)
    naval = build_naval_multi_phase_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(fleet.get("score", 0.5)) + 0.5 * float(naval.get("score", 0.5)))
    return _day(
        "naval_fleet_autonomy_joint_day",
        "Naval fleet autonomy joint day",
        "Naval fleet autonomy joint · score %.2f" % score,
        score,
        [_q("apply_station", province_id, score, "fleet autonomy joint"), _q("apply_focus", province_id, 0.45, "fleet focus")],
        "#0ea5e9",
        "⚓",
        ["naval", "fleet", "joint"],
        {"fleet": fleet, "naval": naval, "naval_score": score},
    )


def naval_air_joint_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    naval = build_naval_multi_phase_campaign_product(province_id=province_id)
    air = build_air_ops_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(naval.get("score", 0.5)) + 0.5 * float(air.get("score", 0.5)))
    return _day(
        "naval_air_joint_advanced_day",
        "Naval air joint advanced day",
        "Naval air joint advanced · score %.2f" % score,
        score,
        [_q("apply_station", province_id, score, "naval air station"), _q("apply_assault", province_id, 0.5, "naval air assault")],
        "#0ea5e9",
        "✈",
        ["naval", "air", "joint"],
        {"naval": naval, "air": air, "naval_score": score},
    )


def naval_multi_phase_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        naval_posture_advanced_day(province_id),
        naval_escort_phase_advanced_day(province_id),
        naval_strike_phase_advanced_day(province_id),
        naval_fleet_fuel_advanced_day(province_id),
        naval_fleet_autonomy_joint_day(province_id),
        naval_air_joint_advanced_day(province_id),
    ]
    gate = naval_multi_phase_campaign_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day(
        "naval_multi_phase_close_day",
        "Naval multi-phase close day",
        "Naval multi-phase close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score),
        score,
        [_q("apply_station", province_id, score, "naval close station"), _q("apply_assault", province_id, 0.5, "naval close strike")],
        "#5ec8ff",
        "✓",
        ["naval", "multi_phase", "close"],
        {"packages": days, "gate": gate, "ok": ok, "naval_score": score},
    )


# C) Designer / AI multi-day / session advanced


def designer_domain_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    des = build_designer_suite_product(province_id=province_id)
    score = _floor(float(des.get("score", 0.5)))
    return _day(
        "designer_domain_advanced_day",
        "Designer domain advanced day",
        "Designer domain advanced · catalog %d · score %.2f"
        % (int(des.get("catalog_count", 0)), score),
        score,
        [_q("apply_production", province_id, score, "designer domain production"), _q("apply_focus", province_id, 0.5, "designer focus")],
        "#f0b429",
        "⚙",
        ["designers", "domain", "advanced"],
        {"designer": des, "industry_score": score},
    )


def designer_seed_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    seed = execute_designer_suite_step("seed", province_id)
    score = _floor(float(seed.get("score", 0.5)))
    return _day(
        "designer_seed_advanced_day",
        "Designer seed advanced day",
        "Designer seed advanced · score %.2f" % score,
        score,
        list(seed.get("apply_queue") or [])[:3] or [_q("apply_production", province_id, score, "designer seed")],
        "#f0b429",
        "⚙",
        ["designers", "seed", "advanced"],
        {"seed": seed, "industry_score": score},
    )


def strategic_ai_multi_day_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    board = build_multi_faction_strategic_ai_product(province_id=province_id)
    d1 = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag="GER", max_ai_actions=3)
    d2 = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag="GER", max_ai_actions=4)
    score = _floor(
        0.4 * float(board.get("score", 0.5))
        + 0.3 * float(d1.get("score", 0.5))
        + 0.3 * float(d2.get("score", 0.5))
    )
    return _day(
        "strategic_ai_multi_day_advanced_day",
        "Strategic AI multi-day advanced day",
        "Strategic AI multi-day advanced · budget %d/%d · score %.2f"
        % (int(d1.get("budget_count", 0)), int(d2.get("budget_count", 0)), score),
        score,
        [_q("apply_focus", province_id, score, "AI multi-day focus"), _q("apply_station", province_id, 0.55, "AI multi-day station")],
        "#6eb5ff",
        "♟",
        ["strategic_ai", "multi_day", "advanced"],
        {"board": board, "day1": d1, "day2": d2, "ai_score": score},
    )


def designer_ai_industry_joint_day(province_id: int = 1) -> Dict[str, Any]:
    des = build_designer_suite_product(province_id=province_id)
    oob = build_medium_tank_oob_product(province_id=province_id)
    ai = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag="USA")
    score = _floor(
        0.35 * float(des.get("score", 0.5))
        + 0.35 * float(oob.get("score", 0.5))
        + 0.3 * float(ai.get("score", 0.5))
    )
    return _day(
        "designer_ai_industry_joint_day",
        "Designer AI industry joint day",
        "Designer AI industry joint · score %.2f" % score,
        score,
        [_q("apply_production", province_id, score, "designer AI production"), _q("apply_focus", province_id, 0.5, "designer AI focus")],
        "#f0b429",
        "🏭",
        ["designers", "ai", "industry", "joint"],
        {"designer": des, "oob": oob, "ai": ai, "industry_score": score},
    )


def play_session_advanced_joint_day(province_id: int = 1) -> Dict[str, Any]:
    sess = build_play_session_campaign_product(province_id=province_id, player_tag="GER")
    focus = build_focus_war_path_product(province_id=province_id)
    naval = build_naval_multi_phase_campaign_product(province_id=province_id)
    score = _floor(
        0.4 * float(sess.get("score", 0.5))
        + 0.3 * float(focus.get("score", 0.5))
        + 0.3 * float(naval.get("score", 0.5))
    )
    return _day(
        "play_session_advanced_joint_day",
        "Play session advanced joint day",
        "Play session advanced joint · session %.2f · focus %.2f · naval %.2f · score %.2f"
        % (float(sess.get("score", 0)), float(focus.get("score", 0)), float(naval.get("score", 0)), score),
        score,
        [_q("apply_focus", province_id, score, "session advanced focus"), _q("apply_station", province_id, 0.5, "session advanced naval")],
        "#6eb5ff",
        "▶",
        ["play_session", "advanced", "joint"],
        {"session": sess, "focus": focus, "naval": naval, "session_score": score},
    )


def advanced_deferred_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        focus_war_path_close_day(province_id),
        naval_multi_phase_close_day(province_id),
        designer_domain_advanced_day(province_id),
        strategic_ai_multi_day_advanced_day(province_id),
        designer_ai_industry_joint_day(province_id),
        play_session_advanced_joint_day(province_id),
    ]
    gates = {
        "focus": focus_war_path_product_integrity(),
        "naval": naval_multi_phase_campaign_integrity(),
        "designers": designer_suite_product_integrity(),
        "ai": strategic_ai_daily_campaign_integrity(),
        "board": multi_faction_strategic_ai_integrity(),
        "session": play_session_campaign_integrity(),
        "air": air_ops_campaign_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 6
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day(
        "advanced_deferred_campaign_close_day",
        "Advanced deferred campaign close day",
        "Advanced deferred campaign close · pillars %d/6 · gates %s · score %.2f"
        % (non_empty, "PASS" if ok else "FAIL", score),
        score,
        [
            _q("apply_focus", province_id, score, "advanced close focus"),
            _q("apply_production", province_id, 0.55, "advanced close production"),
            _q("apply_station", province_id, 0.5, "advanced close naval"),
            _q("apply_assault", province_id, 0.45, "advanced close combat"),
        ],
        "#5ec8ff",
        "✓",
        ["advanced", "deferred", "close", "next310"],
        {"pillars": pillars, "gates": gates, "ok": ok, "campaign_score": score},
    )


ADVANCED_DEFERRED_DAY_IDS = [
    "focus_pick_board_advanced_day",
    "focus_war_path_advanced_day",
    "focus_commit_execute_advanced_day",
    "focus_naval_effort_advanced_day",
    "focus_industry_army_joint_day",
    "focus_air_effort_joint_day",
    "focus_war_path_close_day",
    "naval_posture_advanced_day",
    "naval_escort_phase_advanced_day",
    "naval_strike_phase_advanced_day",
    "naval_fleet_fuel_advanced_day",
    "naval_fleet_autonomy_joint_day",
    "naval_air_joint_advanced_day",
    "naval_multi_phase_close_day",
    "designer_domain_advanced_day",
    "designer_seed_advanced_day",
    "strategic_ai_multi_day_advanced_day",
    "designer_ai_industry_joint_day",
    "play_session_advanced_joint_day",
    "advanced_deferred_campaign_close_day",
]

DAY_FUNCS = [
    focus_pick_board_advanced_day,
    focus_war_path_advanced_day,
    focus_commit_execute_advanced_day,
    focus_naval_effort_advanced_day,
    focus_industry_army_joint_day,
    focus_air_effort_joint_day,
    focus_war_path_close_day,
    naval_posture_advanced_day,
    naval_escort_phase_advanced_day,
    naval_strike_phase_advanced_day,
    naval_fleet_fuel_advanced_day,
    naval_fleet_autonomy_joint_day,
    naval_air_joint_advanced_day,
    naval_multi_phase_close_day,
    designer_domain_advanced_day,
    designer_seed_advanced_day,
    strategic_ai_multi_day_advanced_day,
    designer_ai_industry_joint_day,
    play_session_advanced_joint_day,
    advanced_deferred_campaign_close_day,
]


def advanced_deferred_integrity() -> Dict[str, Any]:
    focus = focus_war_path_product_integrity()
    naval = naval_multi_phase_campaign_integrity()
    des = designer_suite_product_integrity()
    ai = strategic_ai_daily_campaign_integrity()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    sample = [
        focus_pick_board_advanced_day(),
        naval_posture_advanced_day(),
        designer_domain_advanced_day(),
        advanced_deferred_campaign_close_day(),
    ]
    ok = (
        bool(focus.get("ok"))
        and bool(naval.get("ok"))
        and bool(des.get("ok"))
        and bool(ai.get("ok"))
        and bool(gate.get("ok"))
        and bool(sole.get("integrity_ok", True))
        and all(not s.get("empty") for s in sample)
    )
    return {
        "ok": ok,
        "focus_ok": bool(focus.get("ok")),
        "naval_ok": bool(naval.get("ok")),
        "designers_ok": bool(des.get("ok")),
        "ai_ok": bool(ai.get("ok")),
        "gate": gate,
        "summary": "Advanced deferred integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next310_advanced_deferred_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = advanced_deferred_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next310 advanced deferred · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if ok else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next310 advanced deferred[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
