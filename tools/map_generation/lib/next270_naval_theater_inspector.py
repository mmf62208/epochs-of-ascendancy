"""Next-270 naval basing sustain · theater multi-day continuity · inspector decision-strip (20).

A) Naval basing sustain (1–7)
B) Theater multi-day campaign continuity (8–14)
C) Inspector decision-strip product surface (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from naval_basing import basing_from_province_signals, basing_repair_refuel_rates  # type: ignore
from gameplay_loops import (  # type: ignore
    basing_fleet_fuel_logistics,
    basing_repair_weather_loop,
    sole_mult_integrity,
)
from fleet_task_group import compose_task_group  # type: ignore
from logistics_day_depth import leader_formation_station_day  # type: ignore
from campaign_execution import (  # type: ignore
    naval_order_package,
    fleet_order_execute,
    execution_decision_strip,
    execution_integrity_gate,
    close_the_loop,
)
from campaign_cohesion import (  # type: ignore
    naval_campaign_package,
    campaign_decision_strip,
    theater_campaign_strip,
)
from integrated_theater_ops import convoy_package_compose  # type: ignore
from theater_commander import theater_daily_brief, player_order_surface_strip  # type: ignore
from ops_depth import multi_province_live_plan, multi_province_daily_tick_plan, order_panel_actions  # type: ignore
from daily_command_tick import multi_province_day_plan  # type: ignore
from theater_ops_polish import campaign_day_risk  # type: ignore
from map_polish_pilots import inspector_section_collapse  # type: ignore


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
    return s if s >= lo else max(lo, s + 0.25)


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
        "integration": list(integration or ["next270", "naval_theater_inspector"]),
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
    return basing_from_province_signals(
        {
            "province_id": province_id,
            "is_coastal": True,
            "has_port": True,
            "name": "Port %d" % province_id,
            "port_tier": 2,
        }
    )


def _orders() -> List[Dict[str, Any]]:
    return [
        {"summary": "station basing", "score": 0.7, "empty": False, "order": "STATION"},
        {"summary": "supply fuel", "score": 0.65, "empty": False, "order": "SUPPLY"},
        {"summary": "fleet patrol", "score": 0.6, "empty": False, "order": "FLEET"},
    ]


# A) Naval basing sustain


def naval_basing_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    sig = _sig(province_id)
    rates = basing_repair_refuel_rates(sig)
    fuel = basing_fleet_fuel_logistics(
        basing_level=str(sig.get("level", "port")), fuel_level=0.55, weather=_wx()
    )
    score = _floor(
        0.4 * (0.35 + 2.0 * float(rates.get("refuel_rate", 0.1)))
        + 0.35 * float(fuel.get("logistics_score", 0.2))
        + 0.25 * (0.7 if rates.get("can_service") else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "naval basing sustain station"),
        _q("apply_supply", province_id, 0.55, "naval basing sustain supply"),
    ]
    return _day(
        "naval_basing_sustain_day",
        "Naval basing sustain day",
        "Naval basing sustain · %s · refuel · logistics · score %.2f"
        % (str(sig.get("level", "port")), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["naval", "basing", "sustain"],
        {"signals": sig, "rates": rates, "fuel": fuel, "basing_score": score},
    )


def port_fuel_depth_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics(
        basing_level="port", fuel_level=0.45, weather=_wx(), mission="patrol"
    )
    ncp = naval_campaign_package(basing_level="port", fuel_level=0.45, weather=_wx())
    score = _floor(
        0.5 * float(fuel.get("logistics_score", 0.2))
        + 0.5 * float(ncp.get("score", 0.55))
    )
    q = [
        _q("apply_supply", province_id, score, "port fuel depth supply"),
        _q("apply_station", province_id, 0.55, "port fuel depth station"),
        _q("apply_production", province_id, 0.4, "port fuel depth production"),
    ]
    return _day(
        "port_fuel_depth_day",
        "Port fuel depth day",
        "Port fuel depth · logistics · campaign · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["naval", "port", "fuel"],
        {"fuel": fuel, "campaign": ncp, "basing_score": score},
    )


def basing_repair_depth_day(province_id: int = 1) -> Dict[str, Any]:
    rates = basing_repair_refuel_rates(_sig(province_id))
    repair = basing_repair_weather_loop(basing_level="port", weather=_wx())
    score = _floor(
        0.45 * (0.3 + 4.0 * float(rates.get("repair_org_rate", 0.03)))
        + 0.35 * (0.3 + 4.0 * float(repair.get("repair_org_rate", 0.03)))
        + 0.2 * float(rates.get("refuel_rate", 0.2))
    )
    q = [
        _q("apply_station", province_id, score, "basing repair depth station"),
        _q("apply_supply", province_id, 0.55, "basing repair depth supply"),
    ]
    return _day(
        "basing_repair_depth_day",
        "Basing repair depth day",
        "Basing repair depth · rates · weather loop · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🛠",
        ["naval", "basing", "repair"],
        {"rates": rates, "repair": repair, "basing_score": score},
    )


def fleet_task_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group(
        available_strength=100.0, mission="patrol", zone_relation="contested", escort_need=0.3
    )
    fleet = fleet_order_execute(basing_level="port", fuel_level=0.55)
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.55, weather=_wx())
    score = _floor(
        0.4 * (0.55 if not bool(tg.get("empty", False)) else 0.3)
        + 0.35 * float(fleet.get("score", 0.5))
        + 0.25 * float(fuel.get("logistics_score", 0.2))
    )
    q = [
        _q("apply_station", province_id, score, "fleet task sustain station"),
        _q("apply_supply", province_id, 0.5, "fleet task sustain supply"),
        _q("apply_focus", province_id, 0.45, "fleet task sustain focus"),
    ]
    return _day(
        "fleet_task_sustain_day",
        "Fleet task sustain day",
        "Fleet task sustain · task group · fleet order · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["naval", "fleet", "task"],
        {"task_group": tg, "fleet": fleet, "fuel": fuel, "basing_score": score},
    )


def convoy_basing_joint_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(
        ["friendly", "contested", "hostile"],
        available_fleet_strength=80.0,
        cargo_value=100.0,
        weather=_wx(),
    )
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.5, weather=_wx())
    ncp = naval_campaign_package(basing_level="port", fuel_level=0.5, weather=_wx())
    score = _floor(
        0.35 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.4)
        + 0.3 * float(fuel.get("logistics_score", 0.2))
        + 0.35 * float(ncp.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "convoy basing joint station"),
        _q("apply_supply", province_id, 0.55, "convoy basing joint supply"),
        _q("apply_assault", province_id, 0.4, "convoy basing joint assault"),
    ]
    return _day(
        "convoy_basing_joint_day",
        "Convoy basing joint day",
        "Convoy basing joint · convoy · fuel · campaign · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◈",
        ["naval", "convoy", "basing", "joint"],
        {"convoy": convoy, "fuel": fuel, "campaign": ncp, "basing_score": score},
    )


def naval_logistics_depth_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.6, weather=_wx())
    order = naval_order_package(basing_level="port", fuel_level=0.6)
    station = leader_formation_station_day(
        [
            {"province_id": province_id, "basing_level": "port", "fuel_level": 0.6},
            {"province_id": province_id + 1, "basing_level": "anchorage", "fuel_level": 0.5},
        ],
        weather=_wx(),
        leader_skill=0.6,
        fuel_level=0.6,
    )
    score = _floor(
        0.4 * float(order.get("score", 0.5))
        + 0.3 * float(fuel.get("logistics_score", 0.2))
        + 0.3 * float(station.get("score", 0.4) if not station.get("empty") else 0.35)
    )
    q = [
        _q("apply_station", province_id, score, "naval logistics depth station"),
        _q("apply_supply", province_id, 0.55, "naval logistics depth supply"),
        _q("apply_production", province_id, 0.4, "naval logistics depth production"),
    ]
    return _day(
        "naval_logistics_depth_day",
        "Naval logistics depth day",
        "Naval logistics depth · order · fuel · station · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["naval", "logistics", "depth"],
        {"fuel": fuel, "order": order, "station": station, "basing_score": score},
    )


def naval_basing_close_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.55, weather=_wx())
    ncp = naval_campaign_package(basing_level="port", fuel_level=0.55, weather=_wx())
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _floor(
        0.3 * float(fuel.get("logistics_score", 0.2))
        + 0.3 * float(ncp.get("score", 0.55))
        + 0.4 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "naval basing close station"),
        _q("apply_supply", province_id, 0.55, "naval basing close supply"),
        _q("apply_focus", province_id, 0.45, "naval basing close focus"),
    ]
    return _day(
        "naval_basing_close_day",
        "Naval basing close day",
        "Naval basing close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["naval", "basing", "close"],
        {
            "fuel": fuel,
            "campaign": ncp,
            "gate": gate,
            "sole": sole,
            "ok": ok,
            "basing_score": score,
        },
    )


# B) Theater multi-day continuity


def multi_day_theater_depth_day(province_id: int = 1) -> Dict[str, Any]:
    brief = theater_daily_brief(weather=_wx(), month=6)
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx(), max_provinces=4
    )
    day = multi_province_day_plan(
        province_ids=[province_id, province_id + 1], weather=_wx(), max_provinces=2
    )
    score = _norm(
        0.35 * float(brief.get("score", 0.55))
        + 0.35 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.3 * float(day.get("score", 0.55) if not day.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "multi day theater depth station"),
        _q("apply_supply", province_id, 0.55, "multi day theater depth supply"),
        _q("apply_assault", province_id, 0.45, "multi day theater depth assault"),
    ]
    return _day(
        "multi_day_theater_depth_day",
        "Multi day theater depth day",
        "Multi-day theater depth · brief · live · day · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "🗺",
        ["theater", "multi_day", "depth"],
        {"brief": brief, "plan": plan, "day": day, "theater_score": score},
    )


def theater_campaign_continuity_day(province_id: int = 1) -> Dict[str, Any]:
    strip = theater_campaign_strip(weather=_wx(), month=6, basing_level="port", fuel_level=0.6)
    brief = theater_daily_brief(weather=_wx(), month=6)
    score = _norm(
        0.55 * float(strip.get("score", 0.55)) + 0.45 * float(brief.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "theater campaign continuity station"),
        _q("apply_supply", province_id, 0.55, "theater campaign continuity supply"),
        _q("apply_assault", province_id, 0.45, "theater campaign continuity assault"),
    ]
    return _day(
        "theater_campaign_continuity_day",
        "Theater campaign continuity day",
        "Theater campaign continuity · strip · brief · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "📋",
        ["theater", "campaign", "continuity"],
        {"strip": strip, "brief": brief, "theater_score": score},
    )


def campaign_day_chain_day(province_id: int = 1) -> Dict[str, Any]:
    risk = campaign_day_risk(_wx(), month=6)
    tick = multi_province_daily_tick_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx(), max_provinces=3
    )
    day = multi_province_day_plan(
        province_ids=[province_id, province_id + 1], weather=_wx()
    )
    score = _norm(
        0.35 * (1.0 - float(risk.get("risk", 0.4)))
        + 0.35 * float(tick.get("score", 0.55) if not tick.get("empty") else 0.4)
        + 0.3 * float(day.get("score", 0.55) if not day.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "campaign day chain station"),
        _q("apply_supply", province_id, 0.55, "campaign day chain supply"),
        _q("apply_assault", province_id, 0.5, "campaign day chain assault"),
        _q("apply_focus", province_id, 0.4, "campaign day chain focus"),
    ]
    return _day(
        "campaign_day_chain_day",
        "Campaign day chain day",
        "Campaign day chain · risk · tick · day · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "⛓",
        ["theater", "campaign", "chain"],
        {"risk": risk, "tick": tick, "day": day, "theater_score": score},
    )


def theater_session_ops_day(province_id: int = 1) -> Dict[str, Any]:
    brief = theater_daily_brief(weather=_wx(), month=6)
    surface = player_order_surface_strip(weather=_wx())
    score = _floor(
        0.55 * float(brief.get("score", 0.55))
        + 0.45 * (0.55 + 0.05 * min(6, int(surface.get("count", 0))))
    )
    q = [
        _q("apply_station", province_id, score, "theater session ops station"),
        _q("apply_supply", province_id, 0.5, "theater session ops supply"),
        _q("refresh_queue", province_id, 0.45, "theater session ops refresh"),
    ]
    return _day(
        "theater_session_ops_day",
        "Theater session ops day",
        "Theater session ops · brief · surface · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "◎",
        ["theater", "session", "ops"],
        {"brief": brief, "surface": surface, "theater_score": score},
    )


def daily_theater_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    tick = multi_province_daily_tick_plan(
        [province_id, province_id + 1], weather=_wx(), max_provinces=2
    )
    brief = theater_daily_brief(weather=_wx(), month=6)
    score = _norm(
        0.55 * float(tick.get("score", 0.55) if not tick.get("empty") else 0.4)
        + 0.45 * float(brief.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "daily theater sustain station"),
        _q("apply_supply", province_id, 0.55, "daily theater sustain supply"),
        _q("apply_production", province_id, 0.4, "daily theater sustain production"),
    ]
    return _day(
        "daily_theater_sustain_day",
        "Daily theater sustain day",
        "Daily theater sustain · tick · brief · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "⏱",
        ["theater", "daily", "sustain"],
        {"tick": tick, "brief": brief, "theater_score": score},
    )


def theater_continuity_joint_day(province_id: int = 1) -> Dict[str, Any]:
    strip = theater_campaign_strip(weather=_wx(), month=6)
    plan = multi_province_live_plan(
        [province_id, province_id + 1, province_id + 2], weather=_wx()
    )
    brief = theater_daily_brief(weather=_wx(), month=6)
    risk = campaign_day_risk(_wx(), month=6)
    score = _norm(
        0.3 * float(strip.get("score", 0.55))
        + 0.25 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.25 * float(brief.get("score", 0.55))
        + 0.2 * (1.0 - float(risk.get("risk", 0.4)))
    )
    q = [
        _q("apply_station", province_id, score, "theater continuity joint station"),
        _q("apply_supply", province_id, 0.55, "theater continuity joint supply"),
        _q("apply_assault", province_id, 0.5, "theater continuity joint assault"),
        _q("apply_focus", province_id, 0.4, "theater continuity joint focus"),
    ]
    return _day(
        "theater_continuity_joint_day",
        "Theater continuity joint day",
        "Theater continuity joint · strip · plan · brief · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "◈",
        ["theater", "continuity", "joint"],
        {
            "strip": strip,
            "plan": plan,
            "brief": brief,
            "risk": risk,
            "theater_score": score,
        },
    )


def theater_campaign_depth_close_day(province_id: int = 1) -> Dict[str, Any]:
    strip = theater_campaign_strip(weather=_wx(), month=6)
    plan = multi_province_live_plan([province_id, province_id + 1], weather=_wx())
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(strip.get("score", 0.55))
        + 0.35 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "theater campaign depth close station"),
        _q("apply_supply", province_id, 0.55, "theater campaign depth close supply"),
        _q("apply_assault", province_id, 0.45, "theater campaign depth close assault"),
    ]
    return _day(
        "theater_campaign_depth_close_day",
        "Theater campaign depth close day",
        "Theater campaign depth close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#7dd3a0",
        "✓",
        ["theater", "campaign", "close"],
        {"strip": strip, "plan": plan, "gate": gate, "ok": ok, "theater_score": score},
    )


# C) Inspector decision-strip


def inspector_decision_depth_day(province_id: int = 1) -> Dict[str, Any]:
    strip = execution_decision_strip(_orders())
    collapse = inspector_section_collapse(
        [
            {"id": "decision", "title": "Decision", "score": 0.65, "expanded": True},
            {"id": "basing", "title": "Basing", "score": 0.55, "expanded": False},
            {"id": "theater", "title": "Theater", "score": 0.5, "expanded": True},
        ]
    )
    score = _floor(0.5 + 0.05 * min(6, int(strip.get("count", 0))) + 0.03 * min(4, int(collapse.get("expanded_count", 0))))
    q = [
        _q("refresh_queue", province_id, score, "inspector decision depth refresh"),
        _q("apply_station", province_id, 0.55, "inspector decision depth station"),
        _q("apply_focus", province_id, 0.45, "inspector decision depth focus"),
    ]
    return _day(
        "inspector_decision_depth_day",
        "Inspector decision depth day",
        "Inspector decision depth · strip · collapse · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["inspector", "decision", "depth"],
        {"strip": strip, "collapse": collapse, "inspector_score": score},
    )


def decision_strip_depth_day(province_id: int = 1) -> Dict[str, Any]:
    campaign = campaign_decision_strip(
        [
            {"summary": "theater rank", "score": 0.7},
            {"summary": "naval sustain", "score": 0.65},
            {"summary": "session apply", "score": 0.75},
        ]
    )
    exec_strip = execution_decision_strip(_orders())
    score = _floor(
        0.5
        + 0.05 * min(6, int(campaign.get("count", 0)))
        + 0.04 * min(6, int(exec_strip.get("count", 0)))
    )
    q = [
        _q("refresh_queue", province_id, score, "decision strip depth refresh"),
        _q("apply_station", province_id, 0.55, "decision strip depth station"),
        _q("apply_production", province_id, 0.5, "decision strip depth production"),
    ]
    return _day(
        "decision_strip_depth_day",
        "Decision strip depth day",
        "Decision strip depth · campaign · exec · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["inspector", "decision", "strip"],
        {"campaign_strip": campaign, "exec_strip": exec_strip, "inspector_score": score},
    )


def insight_strip_depth_day(province_id: int = 1) -> Dict[str, Any]:
    surface = player_order_surface_strip(weather=_wx())
    panel = order_panel_actions(weather=_wx(), province_id=province_id)
    score = _floor(
        0.45 * (0.55 + 0.05 * min(6, int(surface.get("count", 0))))
        + 0.55 * float(panel.get("score", 0.55))
    )
    q = [
        _q("refresh_queue", province_id, score, "insight strip depth refresh"),
        _q("apply_station", province_id, 0.55, "insight strip depth station"),
        _q("apply_supply", province_id, 0.45, "insight strip depth supply"),
    ]
    return _day(
        "insight_strip_depth_day",
        "Insight strip depth day",
        "Insight strip depth · surface · panel · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◎",
        ["inspector", "insight", "strip"],
        {"surface": surface, "panel": panel, "inspector_score": score},
    )


def province_decision_joint_day(province_id: int = 1) -> Dict[str, Any]:
    strip = execution_decision_strip(_orders())
    plan = multi_province_live_plan([province_id, province_id + 1], weather=_wx())
    surface = player_order_surface_strip(weather=_wx())
    score = _floor(
        0.35 * (0.5 + 0.05 * min(6, int(strip.get("count", 0))))
        + 0.35 * float(plan.get("score", 0.55) if not plan.get("empty") else 0.4)
        + 0.3 * (0.55 + 0.04 * min(6, int(surface.get("count", 0))))
    )
    q = [
        _q("apply_station", province_id, score, "province decision joint station"),
        _q("apply_supply", province_id, 0.55, "province decision joint supply"),
        _q("apply_focus", province_id, 0.45, "province decision joint focus"),
        _q("refresh_queue", province_id, 0.4, "province decision joint refresh"),
    ]
    return _day(
        "province_decision_joint_day",
        "Province decision joint day",
        "Province decision joint · strip · plan · surface · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["inspector", "province", "decision", "joint"],
        {"strip": strip, "plan": plan, "surface": surface, "inspector_score": score},
    )


def inspector_campaign_ops_day(province_id: int = 1) -> Dict[str, Any]:
    campaign = campaign_decision_strip(
        [
            {"summary": "campaign board", "score": 0.7},
            {"summary": "order queue", "score": 0.65},
        ]
    )
    panel = order_panel_actions(weather=_wx(), province_id=province_id)
    collapse = inspector_section_collapse(
        [
            {"id": "campaign", "title": "Campaign", "score": 0.7, "expanded": True},
            {"id": "orders", "title": "Orders", "score": 0.6, "expanded": True},
        ]
    )
    score = _floor(
        0.4 * (0.5 + 0.05 * min(6, int(campaign.get("count", 0))))
        + 0.4 * float(panel.get("score", 0.55))
        + 0.2 * (0.5 + 0.05 * min(4, int(collapse.get("expanded_count", 0))))
    )
    q = [
        _q("refresh_queue", province_id, score, "inspector campaign ops refresh"),
        _q("apply_station", province_id, 0.55, "inspector campaign ops station"),
        _q("apply_production", province_id, 0.45, "inspector campaign ops production"),
    ]
    return _day(
        "inspector_campaign_ops_day",
        "Inspector campaign ops day",
        "Inspector campaign ops · decision · panel · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "📋",
        ["inspector", "campaign", "ops"],
        {
            "campaign_strip": campaign,
            "panel": panel,
            "collapse": collapse,
            "inspector_score": score,
        },
    )


def theater_naval_inspector_close_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.55, weather=_wx())
    brief = theater_daily_brief(weather=_wx(), month=6)
    strip = execution_decision_strip(_orders())
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop(weather=_wx(), province_id=province_id, basing_level="port", fuel_level=0.55)
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * _floor(float(fuel.get("logistics_score", 0.2)))
        + 0.25 * float(brief.get("score", 0.55))
        + 0.25 * (0.5 + 0.05 * min(6, int(strip.get("count", 0))))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, float(fuel.get("logistics_score", 0.4) or 0.4), "close naval station"),
        _q("apply_assault", province_id, float(brief.get("score", 0.55)), "close theater assault"),
        _q("refresh_queue", province_id, 0.5, "close inspector refresh"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "theater_naval_inspector_close_day",
        "Theater naval inspector close day",
        "Theater naval inspector close · basing · theater · strip · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["naval", "theater", "inspector", "close"],
        {
            "fuel": fuel,
            "brief": brief,
            "strip": strip,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "basing_score": _floor(float(fuel.get("logistics_score", 0.2))),
            "theater_score": float(brief.get("score", 0.55)),
            "inspector_score": 0.5 + 0.05 * min(6, int(strip.get("count", 0))),
        },
    )


NAVAL_THEATER_INSPECTOR_DAY_IDS: List[str] = [
    "naval_basing_sustain_day",
    "port_fuel_depth_day",
    "basing_repair_depth_day",
    "fleet_task_sustain_day",
    "convoy_basing_joint_day",
    "naval_logistics_depth_day",
    "naval_basing_close_day",
    "multi_day_theater_depth_day",
    "theater_campaign_continuity_day",
    "campaign_day_chain_day",
    "theater_session_ops_day",
    "daily_theater_sustain_day",
    "theater_continuity_joint_day",
    "theater_campaign_depth_close_day",
    "inspector_decision_depth_day",
    "decision_strip_depth_day",
    "insight_strip_depth_day",
    "province_decision_joint_day",
    "inspector_campaign_ops_day",
    "theater_naval_inspector_close_day",
]

DAY_FUNCS = [
    naval_basing_sustain_day,
    port_fuel_depth_day,
    basing_repair_depth_day,
    fleet_task_sustain_day,
    convoy_basing_joint_day,
    naval_logistics_depth_day,
    naval_basing_close_day,
    multi_day_theater_depth_day,
    theater_campaign_continuity_day,
    campaign_day_chain_day,
    theater_session_ops_day,
    daily_theater_sustain_day,
    theater_continuity_joint_day,
    theater_campaign_depth_close_day,
    inspector_decision_depth_day,
    decision_strip_depth_day,
    insight_strip_depth_day,
    province_decision_joint_day,
    inspector_campaign_ops_day,
    theater_naval_inspector_close_day,
]


def naval_theater_inspector_integrity() -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics(basing_level="port", fuel_level=0.55, weather=_wx())
    brief = theater_daily_brief(weather=_wx(), month=6)
    strip = execution_decision_strip(_orders())
    gate = execution_integrity_gate()
    ok = (
        not bool(fuel.get("empty", False))
        and float(brief.get("score", 0)) > 0.0
        and int(strip.get("count", 0)) > 0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "basing_score": float(fuel.get("logistics_score", 0)),
        "theater_score": float(brief.get("score", 0)),
        "inspector_count": int(strip.get("count", 0)),
        "gate": gate,
        "summary": "Naval-theater-inspector integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next270_naval_theater_inspector_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = naval_theater_inspector_integrity()
    label = "Close next270 naval-theater-inspector · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next270 naval-theater-inspector[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
