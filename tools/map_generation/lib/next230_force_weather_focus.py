"""Next-230 force readiness/multi-front supply · weather×campaign crisis · strategic focus (20).

A) Force readiness / multi-front supply (1–7)
B) Weather×campaign crisis (8–14)
C) Strategic continuity / focus (15–20)

1 force_readiness_depth_day · 2 multi_front_supply_depth_day · 3 depot_route_ops_day
4 force_posture_depth_day · 5 front_supply_rank_day · 6 force_supply_joint_day
7 force_supply_close_day · 8 weather_pressure_ops_day · 9 campaign_crisis_ops_day
10 prod_weather_crisis_day · 11 combat_weather_ops_day · 12 weather_crisis_brief_day
13 weather_campaign_joint_day · 14 weather_crisis_close_day · 15 focus_war_path_ops_day
16 strategic_strip_depth_day · 17 strategic_continuity_depth_day · 18 war_cabinet_pulse_ops_day
19 focus_continuity_joint_day · 20 force_weather_focus_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from gameplay_loops import force_supply_posture, war_path_urgency, sole_mult_integrity  # type: ignore
from weather_ops_polish import weather_pressure_index  # type: ignore
from theater_ops_polish import campaign_day_risk, depot_weather_capacity  # type: ignore
from campaign_cohesion import (  # type: ignore
    production_campaign_risk,
    focus_war_path_board,
    force_posture_board,
)
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from integrated_theater_ops import war_cabinet_board  # type: ignore
from weather_crisis_day import weather_crisis_day  # type: ignore
from ops_depth import multi_province_live_plan  # type: ignore
from live_mutation import supply_route_mutation  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore


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
        "integration": list(integration or ["next230", "force_weather_focus"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.65,
        "precip_intensity": 0.45,
        "precip": 0.45,
        "ground_state": "mud",
        "wind": 0.35,
        "temperature_c": 4.0,
    }


def _fronts(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "defender_power": 45.0, "supply": 0.6, "id": province_id, "power": 40},
        {"province_id": province_id + 1, "defender_power": 55.0, "supply": 0.5, "id": province_id + 1, "power": 35},
        {"province_id": province_id + 2, "defender_power": 40.0, "supply": 0.7, "id": province_id + 2, "power": 50},
    ]


# A) Force readiness / multi-front supply


def force_readiness_depth_day(province_id: int = 1) -> Dict[str, Any]:
    posture = force_supply_posture(70.0, 0.85, weather=_wx())
    board = force_posture_board(70.0, 0.85, weather=_wx(), fronts=_fronts(province_id))
    score = _norm(
        0.55 * float(posture.get("posture", 0.5))
        + 0.45 * float(board.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "force readiness depth station"),
        _q("apply_supply", province_id, 0.55, "force readiness depth supply"),
    ]
    return _day(
        "force_readiness_depth_day",
        "Force readiness depth day",
        "Force readiness depth · posture · board · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "🛡",
        ["force", "readiness", "depth"],
        {"posture": posture, "board": board, "posture_score": score},
    )


def multi_front_supply_depth_day(province_id: int = 1) -> Dict[str, Any]:
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2],
        weather=_wx(),
        max_provinces=4,
        country_tag="GER",
    )
    posture = force_supply_posture(60.0, 0.75, weather=_wx())
    score = _norm(
        0.5 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.5 * float(posture.get("posture", 0.5))
    )
    q = [
        _q("apply_supply", province_id, score, "multi front supply depth primary"),
        _q("apply_station", province_id, 0.55, "multi front supply depth station"),
        _q("apply_assault", province_id, 0.4, "multi front supply depth assault"),
    ]
    return _day(
        "multi_front_supply_depth_day",
        "Multi front supply depth day",
        "Multi-front supply depth · live plan · posture · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "🗺",
        ["force", "multi_front", "supply"],
        {"plan": plan, "posture": posture, "supply_score": score},
    )


def depot_route_ops_day(province_id: int = 1) -> Dict[str, Any]:
    depot = depot_weather_capacity(_wx(), base_capacity=100.0)
    route = supply_route_mutation()
    score = _norm(
        0.5 * float(depot.get("capacity", depot.get("score", 80.0)) if float(depot.get("capacity", 80) or 80) <= 2 else float(depot.get("capacity", 80)) / 120.0)
        + 0.5 * float(route.get("score", 0.55))
    )
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_supply", province_id, score, "depot route supply"),
        _q("apply_production", province_id, 0.5, "depot route production"),
    ]
    return _day(
        "depot_route_ops_day",
        "Depot route ops day",
        "Depot route · capacity · mutation · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "📦",
        ["force", "depot", "route"],
        {"depot": depot, "route": route, "supply_score": score},
    )


def force_posture_depth_day(province_id: int = 1) -> Dict[str, Any]:
    board = force_posture_board(80.0, 0.9, weather=_wx(), fronts=_fronts(province_id))
    posture = force_supply_posture(80.0, 0.9, weather=_wx())
    score = _norm(
        0.5 * float(board.get("score", 0.55)) + 0.5 * float(posture.get("posture", 0.5))
    )
    q = [
        _q("apply_station", province_id, score, "force posture depth station"),
        _q("apply_supply", province_id, 0.55, "force posture depth supply"),
        _q("apply_assault", province_id, 0.45, "force posture depth assault"),
    ]
    return _day(
        "force_posture_depth_day",
        "Force posture depth day",
        "Force posture depth · board · force×supply · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "◆",
        ["force", "posture", "depth"],
        {"board": board, "posture": posture, "posture_score": score},
    )


def front_supply_rank_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = rank_assault_targets(_fronts(province_id), attacker_power=100.0, attacker_supply=0.8)
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx(), max_provinces=3
    )
    best = float((ranked.get("best") or {}).get("overall", ranked.get("score", 0.55)) or 0.55)
    score = _norm(0.55 * best + 0.45 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4))
    q = [
        _q("apply_assault", province_id, score, "front supply rank assault"),
        _q("apply_supply", province_id, 0.55, "front supply rank supply"),
    ]
    return _day(
        "front_supply_rank_day",
        "Front supply rank day",
        "Front supply rank · assault · live plan · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "⚔",
        ["force", "front", "rank"],
        {"ranked": ranked, "plan": plan, "supply_score": score},
    )


def force_supply_joint_day(province_id: int = 1) -> Dict[str, Any]:
    posture = force_supply_posture(75.0, 0.8, weather=_wx())
    depot = depot_weather_capacity(_wx(), 100.0)
    plan = multi_province_live_plan([province_id, province_id + 1], weather=_wx())
    cap = float(depot.get("capacity", 80) or 80)
    cap_n = cap / 120.0 if cap > 2 else cap
    score = _norm(
        0.4 * float(posture.get("posture", 0.5))
        + 0.3 * cap_n
        + 0.3 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
    )
    q = [
        _q("apply_supply", province_id, score, "force supply joint supply"),
        _q("apply_station", province_id, 0.55, "force supply joint station"),
        _q("apply_production", province_id, 0.45, "force supply joint production"),
    ]
    return _day(
        "force_supply_joint_day",
        "Force supply joint day",
        "Force supply joint · posture · depot · front · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "◈",
        ["force", "supply", "joint"],
        {"posture": posture, "depot": depot, "plan": plan, "supply_score": score},
    )


def force_supply_close_day(province_id: int = 1) -> Dict[str, Any]:
    posture = force_supply_posture(70.0, 0.85, weather=_wx())
    board = force_posture_board(70.0, 0.85, weather=_wx())
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(posture.get("posture", 0.5))
        + 0.35 * float(board.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, score, "force supply close supply"),
        _q("apply_station", province_id, 0.55, "force supply close station"),
        _q("apply_assault", province_id, 0.4, "force supply close assault"),
    ]
    return _day(
        "force_supply_close_day",
        "Force supply close day",
        "Force supply close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#94a3b8",
        "✓",
        ["force", "supply", "close"],
        {"posture": posture, "board": board, "gate": gate, "ok": ok, "posture_score": score},
    )


# B) Weather×campaign crisis


def weather_pressure_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    risk = campaign_day_risk(_wx(), month=3)
    score = _norm(
        0.5 * (1.0 - float(pressure.get("pressure", 0.3)))
        + 0.5 * (1.0 - float(risk.get("risk", 0.3)))
    )
    q = [
        _q("apply_supply", province_id, score, "weather pressure supply"),
        _q("apply_station", province_id, 0.5, "weather pressure station"),
        _q("apply_production", province_id, 0.45, "weather pressure production"),
    ]
    return _day(
        "weather_pressure_ops_day",
        "Weather pressure ops day",
        "Weather pressure · %s · score %.2f" % (pressure.get("summary", "pressure"), score),
        score,
        q,
        "#38bdf8",
        "🌪",
        ["weather", "pressure", "ops"],
        {"pressure": pressure, "risk": risk, "weather_score": score},
    )


def campaign_crisis_ops_day(province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    risk = campaign_day_risk(_wx(), month=11)
    score = _norm(
        0.55 * float(crisis.get("score", 0.55))
        + 0.45 * (1.0 - float(risk.get("risk", 0.35)))
    )
    q = [
        _q("apply_supply", province_id, score, "campaign crisis supply"),
        _q("apply_station", province_id, 0.55, "campaign crisis station"),
        _q("apply_assault", province_id, 0.4, "campaign crisis assault"),
    ]
    return _day(
        "campaign_crisis_ops_day",
        "Campaign crisis ops day",
        "Campaign crisis · weather crisis · day risk · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "⚠",
        ["weather", "campaign", "crisis"],
        {"crisis": crisis, "risk": risk, "weather_score": score},
    )


def prod_weather_crisis_day(province_id: int = 1) -> Dict[str, Any]:
    prod = production_campaign_risk(weather=_wx())
    pressure = weather_pressure_index(_wx())
    score = _norm(
        0.55 * (1.0 - float(prod.get("risk", 0.3)))
        + 0.45 * (1.0 - float(pressure.get("pressure", 0.3)))
    )
    q = [
        _q("apply_production", province_id, score, "prod weather crisis production"),
        _q("apply_supply", province_id, 0.55, "prod weather crisis supply"),
    ]
    return _day(
        "prod_weather_crisis_day",
        "Prod weather crisis day",
        "Prod weather crisis · campaign risk · pressure · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "🏭",
        ["weather", "production", "crisis"],
        {"prod": prod, "pressure": pressure, "weather_score": score},
    )


def combat_weather_ops_day(province_id: int = 1) -> Dict[str, Any]:
    risk = campaign_day_risk(_wx(), month=2)
    pressure = weather_pressure_index(_wx())
    ranked = rank_assault_targets(_fronts(province_id), attacker_power=100.0, attacker_supply=0.7)
    win = float((ranked.get("best") or {}).get("overall", 0.5) or 0.5)
    score = _norm(
        0.4 * win
        + 0.3 * (1.0 - float(risk.get("risk", 0.3)))
        + 0.3 * float(pressure.get("combat_mult", 0.7))
    )
    q = [
        _q("apply_assault", province_id, score, "combat weather assault"),
        _q("apply_supply", province_id, 0.55, "combat weather supply"),
        _q("apply_station", province_id, 0.45, "combat weather station"),
    ]
    return _day(
        "combat_weather_ops_day",
        "Combat weather ops day",
        "Combat weather · risk · pressure · front · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "⚔",
        ["weather", "combat", "ops"],
        {"risk": risk, "pressure": pressure, "ranked": ranked, "weather_score": score},
    )


def weather_crisis_brief_day(province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    pressure = weather_pressure_index(_wx())
    depot = depot_weather_capacity(_wx(), 100.0)
    score = _norm(
        0.4 * float(crisis.get("score", 0.55))
        + 0.3 * (1.0 - float(pressure.get("pressure", 0.3)))
        + 0.3 * 0.6
    )
    q = [
        _q("apply_supply", province_id, score, "weather crisis brief supply"),
        _q("apply_station", province_id, 0.5, "weather crisis brief station"),
        _q("apply_production", province_id, 0.45, "weather crisis brief production"),
    ]
    return _day(
        "weather_crisis_brief_day",
        "Weather crisis brief day",
        "Weather crisis brief · crisis · pressure · depot · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "📋",
        ["weather", "crisis", "brief"],
        {"crisis": crisis, "pressure": pressure, "depot": depot, "weather_score": score},
    )


def weather_campaign_joint_day(province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    risk = campaign_day_risk(_wx(), month=6)
    prod = production_campaign_risk(weather=_wx())
    score = _norm(
        0.4 * float(crisis.get("score", 0.55))
        + 0.3 * (1.0 - float(risk.get("risk", 0.3)))
        + 0.3 * (1.0 - float(prod.get("risk", 0.3)))
    )
    q = [
        _q("apply_supply", province_id, score, "weather campaign joint supply"),
        _q("apply_production", province_id, 0.55, "weather campaign joint production"),
        _q("apply_station", province_id, 0.5, "weather campaign joint station"),
        _q("apply_assault", province_id, 0.4, "weather campaign joint assault"),
    ]
    return _day(
        "weather_campaign_joint_day",
        "Weather campaign joint day",
        "Weather campaign joint · crisis · risk · prod · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "◈",
        ["weather", "campaign", "joint"],
        {"crisis": crisis, "risk": risk, "prod": prod, "weather_score": score},
    )


def weather_crisis_close_day(province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    pressure = weather_pressure_index(_wx())
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(crisis.get("score", 0.55))
        + 0.35 * (1.0 - float(pressure.get("pressure", 0.3)))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, score, "weather crisis close supply"),
        _q("apply_station", province_id, 0.55, "weather crisis close station"),
        _q("apply_production", province_id, 0.45, "weather crisis close production"),
    ]
    return _day(
        "weather_crisis_close_day",
        "Weather crisis close day",
        "Weather crisis close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#38bdf8",
        "✓",
        ["weather", "crisis", "close"],
        {"crisis": crisis, "pressure": pressure, "gate": gate, "ok": ok, "weather_score": score},
    )


# C) Strategic continuity / focus


def focus_war_path_ops_day(province_id: int = 1) -> Dict[str, Any]:
    board = focus_war_path_board(
        weather=_wx(),
        focus_id="military_buildup",
        focus_base=70.0,
        trail=[{"class": "sabotage", "influence": 0.55}],
    )
    war = war_path_urgency(
        focus_id="military_buildup",
        focus_base=70.0,
        trail=[{"class": "sabotage", "influence": 0.55}],
    )
    score = _norm(
        0.55 * float(board.get("score", 0.55))
        + 0.45 * float(war.get("urgency", 0.5))
    )
    q = [
        _q("apply_focus", province_id, score, "focus war path focus"),
        _q("apply_production", province_id, 0.55, "focus war path production"),
        _q("apply_assault", province_id, 0.45, "focus war path assault"),
    ]
    return _day(
        "focus_war_path_ops_day",
        "Focus war path ops day",
        "Focus war path · board · urgency · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🎯",
        ["focus", "war_path", "ops"],
        {"board": board, "war_path": war, "focus_score": score},
    )


def strategic_strip_depth_day(province_id: int = 1) -> Dict[str, Any]:
    board = focus_war_path_board(weather=_wx(), focus_id="industrial_effort", focus_base=60.0)
    cabinet = war_cabinet_board(focus_id="industrial_effort", focus_base=60.0, weather=_wx())
    score = _norm(
        0.55 * float(board.get("score", 0.55))
        + 0.45 * (0.65 if not bool(cabinet.get("empty", False)) else 0.4)
    )
    q = [
        _q("apply_focus", province_id, score, "strategic strip depth focus"),
        _q("apply_production", province_id, 0.55, "strategic strip depth production"),
        _q("apply_station", province_id, 0.45, "strategic strip depth station"),
    ]
    return _day(
        "strategic_strip_depth_day",
        "Strategic strip depth day",
        "Strategic strip depth · war path · cabinet · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "📜",
        ["strategic", "strip", "depth"],
        {"board": board, "cabinet": cabinet, "focus_score": score},
    )


def strategic_continuity_depth_day(province_id: int = 1) -> Dict[str, Any]:
    board = focus_war_path_board(
        weather=_wx(), focus_id="military_buildup", focus_base=65.0
    )
    war = war_path_urgency(
        focus_id="military_buildup",
        focus_base=65.0,
        trail=[{"class": "economic_pressure", "influence": 0.5}],
    )
    cabinet = war_cabinet_board(focus_id="military_buildup", focus_base=65.0, weather=_wx())
    score = _norm(
        0.4 * float(board.get("score", 0.55))
        + 0.3 * float(war.get("urgency", 0.5))
        + 0.3 * (0.65 if not bool(cabinet.get("empty", False)) else 0.4)
    )
    q = [
        _q("apply_focus", province_id, score, "strategic continuity depth focus"),
        _q("apply_production", province_id, 0.55, "strategic continuity depth production"),
        _q("apply_supply", province_id, 0.5, "strategic continuity depth supply"),
    ]
    return _day(
        "strategic_continuity_depth_day",
        "Strategic continuity depth day",
        "Strategic continuity depth · path · urgency · cabinet · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "∞",
        ["strategic", "continuity", "depth"],
        {"board": board, "war_path": war, "cabinet": cabinet, "focus_score": score},
    )


def war_cabinet_pulse_ops_day(province_id: int = 1) -> Dict[str, Any]:
    cabinet = war_cabinet_board(
        focus_id="military_buildup",
        focus_base=70.0,
        weather=_wx(),
        signal={"action_class": "sabotage", "threat": 0.55, "province_id": province_id},
        trail=[{"class": "sabotage", "influence": 0.5, "province_id": province_id}],
    )
    board = focus_war_path_board(weather=_wx(), focus_id="military_buildup", focus_base=70.0)
    score = _norm(
        0.55 * (0.7 if not bool(cabinet.get("empty", False)) else 0.35)
        + 0.45 * float(board.get("score", 0.55))
    )
    q = [
        _q("apply_focus", province_id, score, "war cabinet pulse focus"),
        _q("apply_hh_commit", province_id, 0.5, "war cabinet pulse hh"),
        _q("apply_agent_dispatch", province_id, 0.45, "war cabinet pulse agents"),
    ]
    return _day(
        "war_cabinet_pulse_ops_day",
        "War cabinet pulse ops day",
        "War cabinet pulse · cabinet · path · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "war_cabinet", "pulse"],
        {"cabinet": cabinet, "board": board, "focus_score": score},
    )


def focus_continuity_joint_day(province_id: int = 1) -> Dict[str, Any]:
    board = focus_war_path_board(weather=_wx(), focus_id="industrial_effort", focus_base=60.0)
    war = war_path_urgency(focus_id="industrial_effort", focus_base=60.0, trail=[{"class": "intel", "influence": 0.45}])
    cabinet = war_cabinet_board(focus_id="industrial_effort", focus_base=60.0, weather=_wx())
    score = _norm(
        0.35 * float(board.get("score", 0.55))
        + 0.35 * float(war.get("urgency", 0.5))
        + 0.3 * (0.65 if not bool(cabinet.get("empty", False)) else 0.4)
    )
    q = [
        _q("apply_focus", province_id, score, "focus continuity joint focus"),
        _q("apply_production", province_id, 0.55, "focus continuity joint production"),
        _q("apply_station", province_id, 0.5, "focus continuity joint station"),
    ]
    return _day(
        "focus_continuity_joint_day",
        "Focus continuity joint day",
        "Focus continuity joint · path · urgency · cabinet · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["focus", "continuity", "joint"],
        {"board": board, "war_path": war, "cabinet": cabinet, "focus_score": score},
    )


def force_weather_focus_close_day(province_id: int = 1) -> Dict[str, Any]:
    posture = force_supply_posture(70.0, 0.85, weather=_wx())
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    board = focus_war_path_board(weather=_wx(), focus_id="military_buildup", focus_base=70.0)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(posture.get("posture", 0.5))
        + 0.25 * float(crisis.get("score", 0.55))
        + 0.25 * float(board.get("score", 0.55))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, float(posture.get("posture", 0.55)), "close force supply"),
        _q("apply_station", province_id, float(crisis.get("score", 0.55)), "close weather station"),
        _q("apply_focus", province_id, float(board.get("score", 0.55)), "close focus"),
        _q("apply_production", province_id, 0.45, "close production"),
    ]
    return _day(
        "force_weather_focus_close_day",
        "Force weather focus close day",
        "Force weather focus close · force · weather · focus · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["force", "weather", "focus", "close"],
        {
            "posture": posture,
            "crisis": crisis,
            "board": board,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


FORCE_WEATHER_FOCUS_DAY_IDS: List[str] = [
    "force_readiness_depth_day",
    "multi_front_supply_depth_day",
    "depot_route_ops_day",
    "force_posture_depth_day",
    "front_supply_rank_day",
    "force_supply_joint_day",
    "force_supply_close_day",
    "weather_pressure_ops_day",
    "campaign_crisis_ops_day",
    "prod_weather_crisis_day",
    "combat_weather_ops_day",
    "weather_crisis_brief_day",
    "weather_campaign_joint_day",
    "weather_crisis_close_day",
    "focus_war_path_ops_day",
    "strategic_strip_depth_day",
    "strategic_continuity_depth_day",
    "war_cabinet_pulse_ops_day",
    "focus_continuity_joint_day",
    "force_weather_focus_close_day",
]


DAY_FUNCS = [
    force_readiness_depth_day,
    multi_front_supply_depth_day,
    depot_route_ops_day,
    force_posture_depth_day,
    front_supply_rank_day,
    force_supply_joint_day,
    force_supply_close_day,
    weather_pressure_ops_day,
    campaign_crisis_ops_day,
    prod_weather_crisis_day,
    combat_weather_ops_day,
    weather_crisis_brief_day,
    weather_campaign_joint_day,
    weather_crisis_close_day,
    focus_war_path_ops_day,
    strategic_strip_depth_day,
    strategic_continuity_depth_day,
    war_cabinet_pulse_ops_day,
    focus_continuity_joint_day,
    force_weather_focus_close_day,
]


def force_weather_focus_integrity() -> Dict[str, Any]:
    posture = force_supply_posture(70.0, 0.85, weather=_wx())
    crisis = weather_crisis_day(weather=_wx(), province_id=1)
    board = focus_war_path_board(weather=_wx(), focus_id="military_buildup", focus_base=70.0)
    gate = execution_integrity_gate()
    ok = (
        float(posture.get("posture", 0)) > 0.0
        and not bool(crisis.get("empty", False))
        and float(board.get("score", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "posture": float(posture.get("posture", 0)),
        "crisis_score": float(crisis.get("score", 0)),
        "focus_score": float(board.get("score", 0)),
        "gate": gate,
        "summary": "Force-weather-focus integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next230_force_weather_focus_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = force_weather_focus_integrity()
    label = "Close next230 force-weather-focus · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next230 force-weather-focus[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
