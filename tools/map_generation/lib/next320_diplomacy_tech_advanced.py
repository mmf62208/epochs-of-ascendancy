"""Next-320 diplomacy / tech / advanced deferred pillars (20).

A) Diplomacy peace advanced (1–7) — major #16 depth
B) Tech research advanced (8–14) — major #17 depth
C) Joint session / AI / designer / naval / focus close (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from diplomacy_peace_campaign_product import (  # type: ignore
    build_diplomacy_peace_campaign_product,
    diplomacy_peace_campaign_integrity,
    execute_diplomacy_peace_step,
)
from tech_research_campaign_product import (  # type: ignore
    build_tech_research_campaign_product,
    execute_tech_research_step,
    tech_research_campaign_integrity,
)
from focus_war_path_product import build_focus_war_path_product  # type: ignore
from naval_multi_phase_campaign_product import build_naval_multi_phase_campaign_product  # type: ignore
from air_ops_campaign_product import build_air_ops_campaign_product  # type: ignore
from play_session_campaign_product import build_play_session_campaign_product  # type: ignore
from strategic_ai_daily_campaign_product import build_strategic_ai_daily_campaign_product  # type: ignore
from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
from designer_suite_product import build_designer_suite_product  # type: ignore
from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
from agent_campaign_product import build_agent_campaign_product  # type: ignore
from hh_multi_month_agenda_product import build_hh_multi_month_agenda_product  # type: ignore
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
        "integration": list(integration or ["next320", "diplomacy_tech"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


# A) Diplomacy

def diplomacy_board_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_diplomacy_peace_campaign_product(province_id=province_id)
    score = _floor(float(p.get("board_score", p.get("score", 0.5))))
    return _day("diplomacy_board_advanced_day", "Diplomacy board advanced day",
        "Diplomacy board advanced · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "diplo board"), _q("apply_production", province_id, 0.5, "diplo economy")],
        "#a78bfa", "🕊", ["diplomacy", "board", "advanced"],
        {"product": p, "diplomacy_score": score})


def diplomacy_leverage_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_diplomacy_peace_step("leverage", province_id)
    agent = build_agent_campaign_product(province_id=province_id)
    score = _floor(0.55 * float(e.get("score", 0.5)) + 0.45 * float(agent.get("score", 0.5)))
    return _day("diplomacy_leverage_advanced_day", "Diplomacy leverage advanced day",
        "Diplomacy leverage advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_agent_dispatch", province_id, score, "diplo leverage")],
        "#a78bfa", "🕊", ["diplomacy", "leverage", "advanced"],
        {"step": e, "agent": agent, "diplomacy_score": score})


def diplomacy_settle_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_diplomacy_peace_step("settle", province_id)
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    score = _floor(0.55 * float(e.get("score", 0.5)) + 0.45 * float(hh.get("score", 0.5)))
    return _day("diplomacy_settle_advanced_day", "Diplomacy settle advanced day",
        "Diplomacy settle advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_hh_commit", province_id, score, "diplo settle")],
        "#a78bfa", "🕊", ["diplomacy", "settle", "advanced"],
        {"step": e, "hh": hh, "diplomacy_score": score})


def diplomacy_trade_pressure_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_diplomacy_peace_campaign_product(province_id=province_id)
    trade = p.get("trade") or {}
    score = _floor(0.6 * float(p.get("board_score", 0.5)) + 0.4 * _norm(float(trade.get("score", trade.get("health", 0.5)))))
    return _day("diplomacy_trade_pressure_day", "Diplomacy trade pressure day",
        "Diplomacy trade pressure · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "trade pressure supply"), _q("apply_focus", province_id, 0.5, "trade pressure focus")],
        "#a78bfa", "📦", ["diplomacy", "trade", "pressure"],
        {"product": p, "diplomacy_score": score})


def diplomacy_agent_hh_joint_day(province_id: int = 1) -> Dict[str, Any]:
    agent = build_agent_campaign_product(province_id=province_id)
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    score = _floor(0.5 * float(agent.get("score", 0.5)) + 0.5 * float(hh.get("score", 0.5)))
    return _day("diplomacy_agent_hh_joint_day", "Diplomacy agent HH joint day",
        "Diplomacy agent HH joint · score %.2f" % score, score,
        [_q("apply_agent_dispatch", province_id, score, "diplo agent"), _q("apply_hh_commit", province_id, 0.55, "diplo HH")],
        "#a78bfa", "🕵", ["diplomacy", "agent", "hh", "joint"],
        {"agent": agent, "hh": hh, "diplomacy_score": score})


def diplomacy_focus_peace_joint_day(province_id: int = 1) -> Dict[str, Any]:
    diplo = build_diplomacy_peace_campaign_product(province_id=province_id)
    focus = build_focus_war_path_product(province_id=province_id)
    score = _floor(0.55 * float(diplo.get("score", 0.5)) + 0.45 * float(focus.get("score", 0.5)))
    return _day("diplomacy_focus_peace_joint_day", "Diplomacy focus peace joint day",
        "Diplomacy focus peace joint · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "peace focus"), _q("apply_hh_commit", province_id, 0.5, "peace commit")],
        "#a78bfa", "◆", ["diplomacy", "focus", "joint"],
        {"diplo": diplo, "focus": focus, "diplomacy_score": score})


def diplomacy_peace_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [diplomacy_board_advanced_day(province_id), diplomacy_leverage_advanced_day(province_id),
            diplomacy_settle_advanced_day(province_id), diplomacy_trade_pressure_day(province_id),
            diplomacy_agent_hh_joint_day(province_id), diplomacy_focus_peace_joint_day(province_id)]
    gate = diplomacy_peace_campaign_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("diplomacy_peace_close_day", "Diplomacy peace close day",
        "Diplomacy peace close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score), score,
        [_q("apply_focus", province_id, score, "diplo close"), _q("apply_hh_commit", province_id, 0.5, "diplo close commit")],
        "#5ec8ff", "✓", ["diplomacy", "peace", "close"],
        {"packages": days, "gate": gate, "ok": ok, "diplomacy_score": score})


# B) Tech

def tech_catalog_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(float(p.get("catalog_score", p.get("score", 0.5))))
    return _day("tech_catalog_advanced_day", "Tech catalog advanced day",
        "Tech catalog advanced · catalog %d · score %.2f" % (int(p.get("catalog_count", 0)), score), score,
        [_q("apply_focus", province_id, score, "tech catalog"), _q("apply_production", province_id, 0.5, "tech review")],
        "#38bdf8", "🔬", ["tech", "catalog", "advanced"],
        {"product": p, "tech_score": score})


def tech_priority_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tech_research_step("priority", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tech_priority_advanced_day", "Tech priority advanced day",
        "Tech priority advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_production", province_id, score, "tech priority")],
        "#38bdf8", "🔬", ["tech", "priority", "advanced"],
        {"step": e, "tech_score": score})


def tech_field_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tech_research_step("field", province_id)
    oob = build_medium_tank_oob_product(province_id=province_id)
    score = _floor(0.55 * float(e.get("score", 0.5)) + 0.45 * float(oob.get("score", 0.5)))
    return _day("tech_field_advanced_day", "Tech field advanced day",
        "Tech field advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_production", province_id, score, "tech field")],
        "#38bdf8", "🔬", ["tech", "field", "advanced"],
        {"step": e, "oob": oob, "tech_score": score})


def tech_designer_joint_day(province_id: int = 1) -> Dict[str, Any]:
    tech = build_tech_research_campaign_product(province_id=province_id)
    des = build_designer_suite_product(province_id=province_id)
    score = _floor(0.55 * float(tech.get("score", 0.5)) + 0.45 * float(des.get("score", 0.5)))
    return _day("tech_designer_joint_day", "Tech designer joint day",
        "Tech designer joint · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "tech designer seed"), _q("apply_focus", province_id, 0.5, "tech designer focus")],
        "#f0b429", "⚙", ["tech", "designers", "joint"],
        {"tech": tech, "designer": des, "tech_score": score})


def tech_oob_fielding_joint_day(province_id: int = 1) -> Dict[str, Any]:
    tech = build_tech_research_campaign_product(province_id=province_id)
    oob = build_medium_tank_oob_product(province_id=province_id)
    score = _floor(0.5 * float(tech.get("field_score", tech.get("score", 0.5))) + 0.5 * float(oob.get("score", 0.5)))
    return _day("tech_oob_fielding_joint_day", "Tech OOB fielding joint day",
        "Tech OOB fielding joint · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "OOB fielding"), _q("apply_supply", province_id, 0.5, "OOB supply")],
        "#f0b429", "🏭", ["tech", "oob", "joint"],
        {"tech": tech, "oob": oob, "tech_score": score})


def tech_industry_focus_joint_day(province_id: int = 1) -> Dict[str, Any]:
    tech = build_tech_research_campaign_product(province_id=province_id)
    focus = build_focus_war_path_product(province_id=province_id, focus_id="industrial_effort")
    score = _floor(0.55 * float(tech.get("score", 0.5)) + 0.45 * float(focus.get("score", 0.5)))
    return _day("tech_industry_focus_joint_day", "Tech industry focus joint day",
        "Tech industry focus joint · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "industry focus tech"), _q("apply_production", province_id, 0.55, "industry tech prod")],
        "#38bdf8", "◆", ["tech", "focus", "industry", "joint"],
        {"tech": tech, "focus": focus, "tech_score": score})


def tech_research_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [tech_catalog_advanced_day(province_id), tech_priority_advanced_day(province_id),
            tech_field_advanced_day(province_id), tech_designer_joint_day(province_id),
            tech_oob_fielding_joint_day(province_id), tech_industry_focus_joint_day(province_id)]
    gate = tech_research_campaign_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("tech_research_close_day", "Tech research close day",
        "Tech research close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score), score,
        [_q("apply_production", province_id, score, "tech close"), _q("apply_focus", province_id, 0.5, "tech close focus")],
        "#5ec8ff", "✓", ["tech", "research", "close"],
        {"packages": days, "gate": gate, "ok": ok, "tech_score": score})


# C) Joint advanced

def diplomacy_tech_joint_day(province_id: int = 1) -> Dict[str, Any]:
    d = build_diplomacy_peace_campaign_product(province_id=province_id)
    t = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(d.get("score", 0.5)) + 0.5 * float(t.get("score", 0.5)))
    return _day("diplomacy_tech_joint_day", "Diplomacy tech joint day",
        "Diplomacy tech joint · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "diplo tech focus"), _q("apply_production", province_id, 0.55, "diplo tech prod")],
        "#6eb5ff", "★", ["diplomacy", "tech", "joint"],
        {"diplo": d, "tech": t, "campaign_score": score})


def tech_ai_research_joint_day(province_id: int = 1) -> Dict[str, Any]:
    t = build_tech_research_campaign_product(province_id=province_id)
    ai = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag="GER")
    score = _floor(0.55 * float(t.get("score", 0.5)) + 0.45 * float(ai.get("score", 0.5)))
    return _day("tech_ai_research_joint_day", "Tech AI research joint day",
        "Tech AI research joint · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "AI research prod"), _q("apply_focus", province_id, 0.5, "AI research focus")],
        "#6eb5ff", "♟", ["tech", "ai", "joint"],
        {"tech": t, "ai": ai, "campaign_score": score})


def diplomacy_naval_air_joint_day(province_id: int = 1) -> Dict[str, Any]:
    d = build_diplomacy_peace_campaign_product(province_id=province_id)
    n = build_naval_multi_phase_campaign_product(province_id=province_id)
    a = build_air_ops_campaign_product(province_id=province_id)
    score = _floor(0.35 * float(d.get("score", 0.5)) + 0.35 * float(n.get("score", 0.5)) + 0.3 * float(a.get("score", 0.5)))
    return _day("diplomacy_naval_air_joint_day", "Diplomacy naval air joint day",
        "Diplomacy naval air joint · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "joint station"), _q("apply_focus", province_id, 0.5, "joint focus")],
        "#0ea5e9", "⚓", ["diplomacy", "naval", "air", "joint"],
        {"diplo": d, "naval": n, "air": a, "campaign_score": score})


def session_diplomacy_tech_joint_day(province_id: int = 1) -> Dict[str, Any]:
    s = build_play_session_campaign_product(province_id=province_id, player_tag="GER")
    d = build_diplomacy_peace_campaign_product(province_id=province_id)
    t = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(0.4 * float(s.get("score", 0.5)) + 0.3 * float(d.get("score", 0.5)) + 0.3 * float(t.get("score", 0.5)))
    return _day("session_diplomacy_tech_joint_day", "Session diplomacy tech joint day",
        "Session diplomacy tech joint · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "session diplo tech"), _q("apply_production", province_id, 0.5, "session tech prod")],
        "#6eb5ff", "▶", ["session", "diplomacy", "tech", "joint"],
        {"session": s, "diplo": d, "tech": t, "session_score": score})


def multi_faction_diplo_tech_day(province_id: int = 1) -> Dict[str, Any]:
    board = build_multi_faction_strategic_ai_product(province_id=province_id)
    d = build_diplomacy_peace_campaign_product(province_id=province_id)
    t = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(0.4 * float(board.get("score", 0.5)) + 0.3 * float(d.get("score", 0.5)) + 0.3 * float(t.get("score", 0.5)))
    return _day("multi_faction_diplo_tech_day", "Multi faction diplo tech day",
        "Multi faction diplo tech · majors %d · score %.2f" % (int(board.get("faction_count", 0)), score), score,
        [_q("apply_focus", province_id, score, "faction diplo tech"), _q("apply_station", province_id, 0.5, "faction station")],
        "#6eb5ff", "♟", ["strategic_ai", "diplomacy", "tech"],
        {"board": board, "diplo": d, "tech": t, "ai_score": score})


def diplomacy_tech_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        diplomacy_peace_close_day(province_id),
        tech_research_close_day(province_id),
        diplomacy_tech_joint_day(province_id),
        tech_ai_research_joint_day(province_id),
        session_diplomacy_tech_joint_day(province_id),
        multi_faction_diplo_tech_day(province_id),
    ]
    gates = {
        "diplo": diplomacy_peace_campaign_integrity(),
        "tech": tech_research_campaign_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 6
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("diplomacy_tech_campaign_close_day", "Diplomacy tech campaign close day",
        "Diplomacy tech campaign close · pillars %d/6 · gates %s · score %.2f"
        % (non_empty, "PASS" if ok else "FAIL", score), score,
        [_q("apply_focus", province_id, score, "close focus"), _q("apply_production", province_id, 0.55, "close production"),
         _q("apply_hh_commit", province_id, 0.5, "close HH"), _q("apply_agent_dispatch", province_id, 0.45, "close agent")],
        "#5ec8ff", "✓", ["diplomacy", "tech", "close", "next320"],
        {"pillars": pillars, "gates": gates, "ok": ok, "campaign_score": score})


DIPLOMACY_TECH_DAY_IDS = [
    "diplomacy_board_advanced_day",
    "diplomacy_leverage_advanced_day",
    "diplomacy_settle_advanced_day",
    "diplomacy_trade_pressure_day",
    "diplomacy_agent_hh_joint_day",
    "diplomacy_focus_peace_joint_day",
    "diplomacy_peace_close_day",
    "tech_catalog_advanced_day",
    "tech_priority_advanced_day",
    "tech_field_advanced_day",
    "tech_designer_joint_day",
    "tech_oob_fielding_joint_day",
    "tech_industry_focus_joint_day",
    "tech_research_close_day",
    "diplomacy_tech_joint_day",
    "tech_ai_research_joint_day",
    "diplomacy_naval_air_joint_day",
    "session_diplomacy_tech_joint_day",
    "multi_faction_diplo_tech_day",
    "diplomacy_tech_campaign_close_day",
]

DAY_FUNCS = [
    diplomacy_board_advanced_day,
    diplomacy_leverage_advanced_day,
    diplomacy_settle_advanced_day,
    diplomacy_trade_pressure_day,
    diplomacy_agent_hh_joint_day,
    diplomacy_focus_peace_joint_day,
    diplomacy_peace_close_day,
    tech_catalog_advanced_day,
    tech_priority_advanced_day,
    tech_field_advanced_day,
    tech_designer_joint_day,
    tech_oob_fielding_joint_day,
    tech_industry_focus_joint_day,
    tech_research_close_day,
    diplomacy_tech_joint_day,
    tech_ai_research_joint_day,
    diplomacy_naval_air_joint_day,
    session_diplomacy_tech_joint_day,
    multi_faction_diplo_tech_day,
    diplomacy_tech_campaign_close_day,
]


def diplomacy_tech_advanced_integrity() -> Dict[str, Any]:
    diplo = diplomacy_peace_campaign_integrity()
    tech = tech_research_campaign_integrity()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    sample = [
        diplomacy_board_advanced_day(),
        tech_catalog_advanced_day(),
        diplomacy_tech_joint_day(),
        diplomacy_tech_campaign_close_day(),
    ]
    ok = (
        bool(diplo.get("ok"))
        and bool(tech.get("ok"))
        and bool(gate.get("ok"))
        and bool(sole.get("integrity_ok", True))
        and all(not s.get("empty") for s in sample)
    )
    return {
        "ok": ok,
        "diplo_ok": bool(diplo.get("ok")),
        "tech_ok": bool(tech.get("ok")),
        "gate": gate,
        "summary": "Diplomacy-tech advanced integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next320_diplomacy_tech_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = diplomacy_tech_advanced_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next320 diplomacy-tech · packages %d/20 · queue %d · %s" % (
        non_empty, q_total, "PASS" if ok else "FAIL"
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next320 diplomacy-tech[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
