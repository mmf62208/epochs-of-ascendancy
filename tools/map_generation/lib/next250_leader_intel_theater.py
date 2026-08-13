"""Next-250 leader/formation · intel/counterintel · theater daily multi-province (20).

A) Leader/formation wartime command (1–7)
B) Intel/counterintel response (8–14)
C) Theater daily multi-province command (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from gameplay_loops import leader_weather_assign, sole_mult_integrity  # type: ignore
from campaign_cohesion import leader_campaign_assign  # type: ignore
from logistics_day_depth import leader_formation_station_day  # type: ignore
from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from agent_campaign_day import agent_response_day  # type: ignore
from integrated_theater_ops import counter_ops_board  # type: ignore
from gameplay_loops import counter_ops_execute_order  # type: ignore
from map_next_list_helpers import apply_hh_counterplay  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from theater_commander import theater_daily_brief  # type: ignore
from ops_depth import multi_province_live_plan  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from daily_command_tick import multi_province_day_plan  # type: ignore


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


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
    color: str = "#5ec8ff",
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
        "integration": list(integration or ["next250", "leader_intel_theater"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.7,
        "precip": 0.3,
        "precip_intensity": 0.3,
        "ground_state": "mud",
        "wind": 0.25,
        "temperature_c": 8.0,
    }


def _sig(province_id: int = 1) -> Dict[str, Any]:
    return {
        "action_class": "sabotage",
        "threat": 0.55,
        "influence": 0.55,
        "province_id": province_id,
        "active": True,
    }


def _stations(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "basing_level": "port", "fuel_level": 0.65, "zone_relation": "friendly"},
        {"province_id": province_id + 1, "basing_level": "anchorage", "fuel_level": 0.5, "zone_relation": "contested"},
    ]


# A) Leader / formation


def leader_assign_depth_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign(leader_skill=0.65, weather=_wx())
    wx = leader_weather_assign(0.65, weather=_wx())
    score = _norm(
        0.55 * float(assign.get("score", 0.6))
        + 0.45 * float(wx.get("effective_move", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "leader assign depth station"),
        _q("apply_assault", province_id, 0.55, "leader assign depth assault"),
    ]
    return _day(
        "leader_assign_depth_day",
        "Leader assign depth day",
        "Leader assign depth · campaign · weather · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "★",
        ["leader", "assign", "depth"],
        {"assign": assign, "weather": wx, "leader_score": score},
    )


def formation_ready_depth_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    assign = leader_campaign_assign(leader_skill=0.6, weather=_wx())
    score = _norm(
        0.5 * float(equip.get("score", 0.55)) + 0.5 * float(assign.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, float(equip.get("score", score)), "formation ready depth production"),
        _q("apply_station", province_id, score, "formation ready depth station"),
        _q("apply_supply", province_id, 0.5, "formation ready depth supply"),
    ]
    return _day(
        "formation_ready_depth_day",
        "Formation ready depth day",
        "Formation ready depth · equip · leader · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🛡",
        ["formation", "ready", "depth"],
        {"equip": equip, "assign": assign, "leader_score": score},
    )


def leader_weather_depth_day(province_id: int = 1) -> Dict[str, Any]:
    wx = leader_weather_assign(0.7, weather=_wx(), armored=True)
    assign = leader_campaign_assign(leader_skill=0.7, weather=_wx(), armored=True)
    score = _norm(
        0.55 * float(wx.get("effective_move", 0.55))
        + 0.45 * float(assign.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "leader weather depth station"),
        _q("apply_supply", province_id, 0.5, "leader weather depth supply"),
        _q("apply_assault", province_id, 0.45, "leader weather depth assault"),
    ]
    return _day(
        "leader_weather_depth_day",
        "Leader weather depth day",
        "Leader weather depth · move · assign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🌦",
        ["leader", "weather", "depth"],
        {"weather": wx, "assign": assign, "leader_score": score},
    )


def formation_station_depth_day(province_id: int = 1) -> Dict[str, Any]:
    station = leader_formation_station_day(
        _stations(province_id), weather=_wx(), leader_skill=0.6, fuel_level=0.6
    )
    assign = leader_campaign_assign(leader_skill=0.6, weather=_wx())
    score = _norm(
        0.55 * float(station.get("score", 0.55) if not station.get("empty") else 0.45)
        + 0.45 * float(assign.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "formation station depth primary"),
        _q("apply_supply", province_id, 0.55, "formation station depth supply"),
    ]
    return _day(
        "formation_station_depth_day",
        "Formation station depth day",
        "Formation station depth · station · leader · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "⚓",
        ["formation", "station", "depth"],
        {"station": station, "assign": assign, "leader_score": score},
    )


def leader_formation_joint_depth_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign(leader_skill=0.65, weather=_wx())
    equip = medium_horizon_equip_plan()
    station = leader_formation_station_day(
        _stations(province_id), weather=_wx(), leader_skill=0.65
    )
    score = _norm(
        0.35 * float(assign.get("score", 0.55))
        + 0.35 * float(equip.get("score", 0.55))
        + 0.3 * float(station.get("score", 0.55) if not station.get("empty") else 0.45)
    )
    q = [
        _q("apply_station", province_id, score, "leader formation joint depth station"),
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "leader formation joint depth production"),
        _q("apply_assault", province_id, 0.5, "leader formation joint depth assault"),
    ]
    return _day(
        "leader_formation_joint_depth_day",
        "Leader formation joint depth day",
        "Leader formation joint depth · assign · equip · station · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["leader", "formation", "joint"],
        {"assign": assign, "equip": equip, "station": station, "leader_score": score},
    )


def oob_leader_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    assign = leader_campaign_assign(leader_skill=0.55, weather=_wx(), armored=True)
    score = _norm(
        0.55 * float(equip.get("score", 0.55)) + 0.45 * float(assign.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "oob leader production"),
        _q("apply_station", province_id, 0.55, "oob leader station"),
        _q("apply_supply", province_id, 0.45, "oob leader supply"),
    ]
    return _day(
        "oob_leader_ops_day",
        "OOB leader ops day",
        "OOB leader · equip · assign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◎",
        ["oob", "leader", "ops"],
        {"equip": equip, "assign": assign, "leader_score": score},
    )


def leader_formation_close_depth_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign(leader_skill=0.65, weather=_wx())
    equip = medium_horizon_equip_plan()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(assign.get("score", 0.55))
        + 0.35 * float(equip.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "leader formation close depth station"),
        _q("apply_production", province_id, 0.55, "leader formation close depth production"),
        _q("apply_supply", province_id, 0.45, "leader formation close depth supply"),
    ]
    return _day(
        "leader_formation_close_depth_day",
        "Leader formation close depth day",
        "Leader formation close depth · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#c084fc",
        "✓",
        ["leader", "formation", "close"],
        {"assign": assign, "equip": equip, "gate": gate, "ok": ok, "leader_score": score},
    )


# B) Intel / counterintel


def intel_counter_depth_day(province_id: int = 1) -> Dict[str, Any]:
    board = counter_ops_board(_sig(province_id), network_strength=0.35, available_agents=4)
    order = counter_ops_execute_order(_sig(province_id))
    score = _norm(
        0.55 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.45 * (0.65 if not bool(order.get("empty", True)) else 0.3)
    )
    q = [
        _q("apply_counterplay", province_id, score, "intel counter depth primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "intel counter depth agents"),
    ]
    return _day(
        "intel_counter_depth_day",
        "Intel counter depth day",
        "Intel counter depth · board · execute · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "🛡",
        ["intel", "counter", "depth"],
        {"board": board, "order": order, "intel_score": score},
    )


def hh_counterplay_depth_day(province_id: int = 1) -> Dict[str, Any]:
    counter = apply_hh_counterplay(0.55, _sig(province_id))
    board = counter_ops_board(_sig(province_id))
    score = _norm(
        0.55
        + float(counter.get("reduction", 0.12) or 0.12) * 0.5
        + 0.1 * (0.2 if not bool(board.get("empty", True)) else 0.0)
    )
    q = [
        _q("apply_counterplay", province_id, score, "hh counterplay depth primary"),
        _q("apply_hh_commit", province_id, 0.5, "hh counterplay depth commit"),
        _q("apply_agent_dispatch", province_id, 0.45, "hh counterplay depth agents"),
    ]
    return _day(
        "hh_counterplay_depth_day",
        "HH counterplay depth day",
        "HH counterplay depth · reduction · board · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "◈",
        ["hh", "counterplay", "depth"],
        {"counter": counter, "board": board, "intel_score": score},
    )


def agent_response_depth_day(province_id: int = 1) -> Dict[str, Any]:
    resp = agent_response_day(
        _sig(province_id), available_agents=5, network_strength=0.35, province_id=province_id
    )
    esc = plan_agent_escalation(_sig(province_id), network_strength=0.35, available_agents=5)
    score = _norm(
        0.55 * float(resp.get("score", 0.55))
        + 0.45 * (0.55 + 0.1 * float(esc.get("level", 1) or 1) / 3.0)
    )
    q = list(resp.get("apply_queue") or [])[:2]
    if not q:
        q = [
            _q("apply_agent_dispatch", province_id, score, "agent response depth primary"),
            _q("apply_counterplay", province_id, 0.5, "agent response depth counter"),
        ]
    return _day(
        "agent_response_depth_day",
        "Agent response depth day",
        "Agent response depth · response · escal · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "🕵",
        ["agent", "response", "depth"],
        {"response": resp, "escalation": esc, "intel_score": score},
    )


def trail_intel_ops_day(province_id: int = 1) -> Dict[str, Any]:
    esc = plan_agent_escalation(_sig(province_id), available_agents=4)
    cov = plan_agent_coverage(
        [
            {"province_id": province_id, "threat": 0.6, "action_class": "sabotage"},
            {"province_id": province_id + 1, "threat": 0.4, "action_class": "influence"},
        ],
        available_agents=4,
        network_strength=0.35,
    )
    counter = apply_hh_counterplay(0.5, _sig(province_id))
    score = _norm(
        0.4 * (0.55 + 0.1 * float(esc.get("level", 1) or 1) / 3.0)
        + 0.3 * float(cov.get("score", cov.get("coverage", 0.6)) or 0.6)
        + 0.3 * (0.55 + float(counter.get("reduction", 0.12) or 0.12) * 0.4)
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "trail intel agents"),
        _q("apply_counterplay", province_id, 0.55, "trail intel counter"),
        _q("apply_hh_commit", province_id, 0.45, "trail intel hh"),
    ]
    return _day(
        "trail_intel_ops_day",
        "Trail intel ops day",
        "Trail intel · escal · coverage · counter · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "📜",
        ["intel", "trail", "ops"],
        {"escalation": esc, "coverage": cov, "counter": counter, "intel_score": score},
    )


def counterintel_board_ops_day(province_id: int = 1) -> Dict[str, Any]:
    board = counter_ops_board(_sig(province_id), network_strength=0.3, available_agents=5)
    order = counter_ops_execute_order(_sig(province_id), network_strength=0.3, available_agents=5)
    cov = plan_agent_coverage(
        [{"province_id": province_id, "threat": 0.55, "action_class": "sabotage"}],
        available_agents=5,
    )
    score = _norm(
        0.4 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.3 * (0.65 if not bool(order.get("empty", True)) else 0.3)
        + 0.3 * float(cov.get("score", 0.6) or 0.6)
    )
    q = [
        _q("apply_counterplay", province_id, score, "counterintel board primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "counterintel board agents"),
        _q("apply_hh_commit", province_id, 0.45, "counterintel board hh"),
    ]
    return _day(
        "counterintel_board_ops_day",
        "Counterintel board ops day",
        "Counterintel board · board · execute · cover · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "🗺",
        ["intel", "counterintel", "board"],
        {"board": board, "order": order, "coverage": cov, "intel_score": score},
    )


def intel_response_joint_day(province_id: int = 1) -> Dict[str, Any]:
    resp = agent_response_day(_sig(province_id), province_id=province_id)
    board = counter_ops_board(_sig(province_id))
    counter = apply_hh_counterplay(0.55, _sig(province_id))
    score = _norm(
        0.4 * float(resp.get("score", 0.55))
        + 0.3 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.3 * (0.55 + float(counter.get("reduction", 0.12) or 0.12) * 0.4)
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "intel response joint agents"),
        _q("apply_counterplay", province_id, 0.55, "intel response joint counter"),
        _q("apply_hh_commit", province_id, 0.5, "intel response joint hh"),
    ]
    return _day(
        "intel_response_joint_day",
        "Intel response joint day",
        "Intel response joint · agent · board · counter · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "◈",
        ["intel", "response", "joint"],
        {"response": resp, "board": board, "counter": counter, "intel_score": score},
    )


def intel_counter_close_day(province_id: int = 1) -> Dict[str, Any]:
    board = counter_ops_board(_sig(province_id))
    resp = agent_response_day(_sig(province_id), province_id=province_id)
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.35 * float(resp.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_counterplay", province_id, score, "intel counter close primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "intel counter close agents"),
        _q("apply_hh_commit", province_id, 0.45, "intel counter close hh"),
    ]
    return _day(
        "intel_counter_close_day",
        "Intel counter close day",
        "Intel counter close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#a78bfa",
        "✓",
        ["intel", "counter", "close"],
        {"board": board, "response": resp, "gate": gate, "ok": ok, "intel_score": score},
    )


# C) Theater daily multi-province


def theater_daily_depth_day(province_id: int = 1) -> Dict[str, Any]:
    brief = theater_daily_brief(weather=_wx(), trail=[{"class": "intel", "influence": 0.4}], month=6)
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx(), max_provinces=4
    )
    score = _norm(
        0.55 * float(brief.get("score", 0.55))
        + 0.45 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "theater daily depth station"),
        _q("apply_supply", province_id, 0.55, "theater daily depth supply"),
        _q("apply_assault", province_id, 0.45, "theater daily depth assault"),
    ]
    return _day(
        "theater_daily_depth_day",
        "Theater daily depth day",
        "Theater daily depth · brief · multi-province · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["theater", "daily", "depth"],
        {"brief": brief, "plan": plan, "theater_score": score},
    )


def multi_province_rank_depth_day(province_id: int = 1) -> Dict[str, Any]:
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2, province_id + 3],
        weather=_wx(),
        max_provinces=4,
        country_tag="GER",
    )
    day = multi_province_day_plan(
        province_ids=[province_id, province_id + 1, province_id + 2],
        weather=_wx(),
        max_provinces=3,
    )
    score = _norm(
        0.55 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.45 * float(day.get("score", 0.55) if not day.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "multi province rank depth station"),
        _q("apply_supply", province_id, 0.55, "multi province rank depth supply"),
        _q("apply_assault", province_id, 0.45, "multi province rank depth assault"),
    ]
    return _day(
        "multi_province_rank_depth_day",
        "Multi province rank depth day",
        "Multi-province rank depth · live · day plan · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◆",
        ["theater", "multi_province", "rank"],
        {"plan": plan, "day": day, "theater_score": score},
    )


def daily_auto_depth_day(province_id: int = 1) -> Dict[str, Any]:
    brief = theater_daily_brief(weather=_wx(), month=6)
    plan = multi_province_live_plan([province_id, province_id + 1], weather=_wx())
    score = _norm(
        0.55 * float(brief.get("score", 0.55))
        + 0.45 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "daily auto depth station"),
        _q("apply_supply", province_id, 0.55, "daily auto depth supply"),
        _q("apply_production", province_id, 0.45, "daily auto depth production"),
        _q("apply_assault", province_id, 0.4, "daily auto depth assault"),
    ]
    return _day(
        "daily_auto_depth_day",
        "Daily auto depth day",
        "Daily auto depth · brief · multi · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["theater", "daily", "auto"],
        {"brief": brief, "plan": plan, "theater_score": score},
    )


def theater_brief_ops_day(province_id: int = 1) -> Dict[str, Any]:
    brief = theater_daily_brief(
        weather=_wx(),
        trail=[{"class": "sabotage", "influence": 0.5, "province_id": province_id}],
        month=6,
    )
    score = _norm(float(brief.get("score", 0.55)))
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "theater brief station"),
        _q("apply_supply", province_id, 0.55, "theater brief supply"),
        _q("apply_focus", province_id, 0.45, "theater brief focus"),
    ]
    return _day(
        "theater_brief_ops_day",
        "Theater brief ops day",
        "Theater brief · %s · score %.2f" % (brief.get("summary", "brief")[:40], score),
        score,
        q,
        "#5ec8ff",
        "📋",
        ["theater", "brief", "ops"],
        {"brief": brief, "theater_score": score},
    )


def multi_province_command_day(province_id: int = 1) -> Dict[str, Any]:
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx(), max_provinces=4
    )
    brief = theater_daily_brief(weather=_wx(), month=6)
    day = multi_province_day_plan(
        province_ids=[province_id, province_id + 1], weather=_wx(), max_provinces=2
    )
    score = _norm(
        0.4 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.3 * float(brief.get("score", 0.55))
        + 0.3 * float(day.get("score", 0.55) if not day.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "multi province command station"),
        _q("apply_supply", province_id, 0.55, "multi province command supply"),
        _q("apply_assault", province_id, 0.5, "multi province command assault"),
        _q("apply_production", province_id, 0.4, "multi province command production"),
    ]
    return _day(
        "multi_province_command_day",
        "Multi province command day",
        "Multi-province command · live · brief · day · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⚔",
        ["theater", "multi_province", "command"],
        {"plan": plan, "brief": brief, "day": day, "theater_score": score},
    )


def leader_intel_theater_close_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign(leader_skill=0.65, weather=_wx())
    board = counter_ops_board(_sig(province_id))
    brief = theater_daily_brief(weather=_wx(), month=6)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(assign.get("score", 0.55))
        + 0.25 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.25 * float(brief.get("score", 0.55))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, float(assign.get("score", 0.55)), "close leader station"),
        _q("apply_counterplay", province_id, 0.55, "close intel counter"),
        _q("apply_assault", province_id, float(brief.get("score", 0.55)), "close theater assault"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "leader_intel_theater_close_day",
        "Leader intel theater close day",
        "Leader intel theater close · leader · intel · theater · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["leader", "intel", "theater", "close"],
        {
            "assign": assign,
            "board": board,
            "brief": brief,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


LEADER_INTEL_THEATER_DAY_IDS: List[str] = [
    "leader_assign_depth_day",
    "formation_ready_depth_day",
    "leader_weather_depth_day",
    "formation_station_depth_day",
    "leader_formation_joint_depth_day",
    "oob_leader_ops_day",
    "leader_formation_close_depth_day",
    "intel_counter_depth_day",
    "hh_counterplay_depth_day",
    "agent_response_depth_day",
    "trail_intel_ops_day",
    "counterintel_board_ops_day",
    "intel_response_joint_day",
    "intel_counter_close_day",
    "theater_daily_depth_day",
    "multi_province_rank_depth_day",
    "daily_auto_depth_day",
    "theater_brief_ops_day",
    "multi_province_command_day",
    "leader_intel_theater_close_day",
]


DAY_FUNCS = [
    leader_assign_depth_day,
    formation_ready_depth_day,
    leader_weather_depth_day,
    formation_station_depth_day,
    leader_formation_joint_depth_day,
    oob_leader_ops_day,
    leader_formation_close_depth_day,
    intel_counter_depth_day,
    hh_counterplay_depth_day,
    agent_response_depth_day,
    trail_intel_ops_day,
    counterintel_board_ops_day,
    intel_response_joint_day,
    intel_counter_close_day,
    theater_daily_depth_day,
    multi_province_rank_depth_day,
    daily_auto_depth_day,
    theater_brief_ops_day,
    multi_province_command_day,
    leader_intel_theater_close_day,
]


def leader_intel_theater_integrity() -> Dict[str, Any]:
    assign = leader_campaign_assign(leader_skill=0.65, weather=_wx())
    board = counter_ops_board(_sig(1))
    brief = theater_daily_brief(weather=_wx(), month=6)
    gate = execution_integrity_gate()
    ok = (
        float(assign.get("score", 0)) > 0.0
        and not bool(board.get("empty", True))
        and float(brief.get("score", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "leader_score": float(assign.get("score", 0)),
        "intel_ok": not bool(board.get("empty", True)),
        "theater_score": float(brief.get("score", 0)),
        "gate": gate,
        "summary": "Leader-intel-theater integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next250_leader_intel_theater_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = leader_intel_theater_integrity()
    label = "Close next250 leader-intel-theater · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if gate.get("ok") and non_empty >= 20 else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next250 leader-intel-theater[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
