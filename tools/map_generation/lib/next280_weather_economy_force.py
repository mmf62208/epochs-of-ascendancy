"""Next-280 weather operational pressure · war-economy/trade sustain · force readiness (20).

A) Weather operational pressure (1–7)
B) War-economy / trade-sealane wartime sustain (8–14)
C) Force readiness / reinforce product surface (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from weather_ops_polish import weather_pressure_index  # type: ignore
from theater_ops_polish import campaign_day_risk  # type: ignore
from weather_crisis_day import weather_crisis_day  # type: ignore
from gameplay_loops import (  # type: ignore
    move_path_ops_loop,
    sealane_joint_health,
    sole_mult_integrity,
    reinforced_assault_loop,
)
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore
from integrated_theater_ops import convoy_package_compose, theater_readiness_board  # type: ignore
from live_mutation import production_priority_mutation, supply_route_mutation  # type: ignore
from force_readiness_day import force_readiness_day, theater_readiness_day  # type: ignore
from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore


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
        "integration": list(integration or ["next280", "weather_economy_force"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.55,
        "precip": 0.55,
        "precip_intensity": 0.55,
        "ground_state": "mud",
        "wind": 0.4,
        "temperature_c": 2.0,
    }


def _zones() -> List[str]:
    return ["friendly", "contested", "hostile"]


def _targets(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "defender_power": 70.0, "defender_supply": 0.8},
        {"province_id": province_id + 1, "defender_power": 55.0, "defender_supply": 0.7},
    ]


# A) Weather operational pressure


def weather_pressure_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    risk = campaign_day_risk(_wx(), month=11)
    p = float(pressure.get("pressure", 0.5))
    score = _floor(0.55 * (1.0 - p) + 0.45 * (1.0 - float(risk.get("risk", p))))
    q = [
        _q("apply_supply", province_id, score, "weather pressure depth supply"),
        _q("apply_station", province_id, 0.5, "weather pressure depth station"),
        _q("apply_focus", province_id, 0.45, "weather pressure depth focus"),
    ]
    return _day(
        "weather_pressure_depth_day",
        "Weather pressure depth day",
        "Weather pressure depth · pressure %.0f%% · score %.2f" % (p * 100.0, score),
        score,
        q,
        "#94a3b8",
        "🌪",
        ["weather", "pressure", "depth"],
        {"pressure": pressure, "risk": risk, "weather_score": score},
    )


def foul_combat_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    wmult = float(pressure.get("combat_mult", 0.7))
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=wmult)
    overall = float(est.get("overall_attacker_win_chance", 0.4))
    score = _floor(0.55 * overall + 0.45 * wmult)
    q = [
        _q("apply_assault", province_id, score, "foul combat ops assault"),
        _q("apply_supply", province_id, 0.55, "foul combat ops supply"),
        _q("apply_station", province_id, 0.45, "foul combat ops station"),
    ]
    return _day(
        "foul_combat_ops_day",
        "Foul combat ops day",
        "Foul combat ops · wx combat ×%.2f · overall %.0f%% · score %.2f"
        % (wmult, overall * 100.0, score),
        score,
        q,
        "#94a3b8",
        "⚔",
        ["weather", "combat", "foul"],
        {"pressure": pressure, "estimate": est, "weather_score": score},
    )


def weather_logistics_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    supply = supply_route_mutation(weather=_wx(), basing_level="port")
    smult = float(pressure.get("supply_mult", 0.65))
    score = _floor(0.5 * smult + 0.5 * float(supply.get("score", 0.4)))
    q = [
        _q("apply_supply", province_id, score, "weather logistics depth supply"),
        _q("apply_station", province_id, 0.5, "weather logistics depth station"),
        _q("apply_production", province_id, 0.4, "weather logistics depth production"),
    ]
    return _day(
        "weather_logistics_depth_day",
        "Weather logistics depth day",
        "Weather logistics depth · supply ×%.2f · route · score %.2f" % (smult, score),
        score,
        q,
        "#94a3b8",
        "📦",
        ["weather", "logistics", "depth"],
        {"pressure": pressure, "supply": supply, "weather_score": score},
    )


def weather_move_depth_day(province_id: int = 1) -> Dict[str, Any]:
    path = move_path_ops_loop(base_move_cost=1.0, weather=_wx(), supply_health=0.85)
    pressure = weather_pressure_index(_wx())
    move_mult = float(pressure.get("move_mult", path.get("weather_move_mult", 0.75)))
    # lower path cost is better → invert around 1.0
    path_cost = float(path.get("path_cost", 1.5))
    path_score = _norm(1.0 / max(0.5, path_cost))
    score = _floor(0.55 * move_mult + 0.45 * path_score)
    q = [
        _q("apply_station", province_id, score, "weather move depth station"),
        _q("apply_supply", province_id, 0.5, "weather move depth supply"),
        _q("apply_focus", province_id, 0.45, "weather move depth focus"),
    ]
    return _day(
        "weather_move_depth_day",
        "Weather move depth day",
        "Weather move depth · move ×%.2f · path cost %.2f · score %.2f"
        % (move_mult, path_cost, score),
        score,
        q,
        "#94a3b8",
        "🥾",
        ["weather", "move", "depth"],
        {"path": path, "pressure": pressure, "weather_score": score},
    )


def weather_crisis_depth_day(province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    risk = campaign_day_risk(_wx(), month=11)
    score = _floor(
        0.55 * float(crisis.get("score", 0.4)) + 0.45 * (1.0 - float(risk.get("risk", 0.5)))
    )
    q = list(crisis.get("apply_queue") or [])
    if len(q) < 1:
        q = [
            _q("apply_supply", province_id, score, "weather crisis depth supply"),
            _q("apply_station", province_id, 0.5, "weather crisis depth station"),
        ]
    return _day(
        "weather_crisis_depth_day",
        "Weather crisis depth day",
        "Weather crisis depth · crisis · day risk · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "⚠",
        ["weather", "crisis", "depth"],
        {"crisis": crisis, "risk": risk, "weather_score": score},
    )


def weather_pressure_joint_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    path = move_path_ops_loop(weather=_wx())
    supply = supply_route_mutation(weather=_wx())
    p = float(pressure.get("pressure", 0.5))
    score = _floor(
        0.3 * (1.0 - p)
        + 0.25 * float(crisis.get("score", 0.4))
        + 0.25 * float(pressure.get("combat_mult", 0.7))
        + 0.2 * float(supply.get("score", 0.4))
    )
    q = [
        _q("apply_supply", province_id, score, "weather pressure joint supply"),
        _q("apply_station", province_id, 0.55, "weather pressure joint station"),
        _q("apply_assault", province_id, 0.45, "weather pressure joint assault"),
        _q("apply_focus", province_id, 0.4, "weather pressure joint focus"),
    ]
    return _day(
        "weather_pressure_joint_day",
        "Weather pressure joint day",
        "Weather pressure joint · pressure · crisis · path · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "◈",
        ["weather", "pressure", "joint"],
        {
            "pressure": pressure,
            "crisis": crisis,
            "path": path,
            "supply": supply,
            "weather_score": score,
        },
    )


def weather_ops_close_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    crisis = weather_crisis_day(weather=_wx(), province_id=province_id)
    gate = execution_integrity_gate(weather_mult=float(pressure.get("combat_mult", 0.8)))
    ok = bool(gate.get("ok", False))
    score = _floor(
        0.35 * (1.0 - float(pressure.get("pressure", 0.5)))
        + 0.35 * float(crisis.get("score", 0.4))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, score, "weather ops close depth supply"),
        _q("apply_station", province_id, 0.55, "weather ops close depth station"),
        _q("apply_focus", province_id, 0.45, "weather ops close depth focus"),
    ]
    return _day(
        "weather_ops_close_depth_day",
        "Weather ops close depth day",
        "Weather ops close depth · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#94a3b8",
        "✓",
        ["weather", "ops", "close"],
        {
            "pressure": pressure,
            "crisis": crisis,
            "gate": gate,
            "ok": ok,
            "weather_score": score,
        },
    )


# B) War-economy / trade-sealane sustain


def trade_pressure_depth_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(_zones(), sea_trade_mult=1.0, weather=_wx(), available_fleet=50.0)
    trade = sealane.get("trade") if isinstance(sealane.get("trade"), dict) else {}
    health = float(trade.get("health", sealane.get("score", 0.4)))
    score = _floor(0.6 * health + 0.4 * float(sealane.get("score", health)))
    q = [
        _q("apply_supply", province_id, score, "trade pressure depth supply"),
        _q("apply_production", province_id, 0.55, "trade pressure depth production"),
        _q("apply_station", province_id, 0.45, "trade pressure depth station"),
    ]
    return _day(
        "trade_pressure_depth_day",
        "Trade pressure depth day",
        "Trade pressure depth · health ×%.2f · sealane · score %.2f" % (health, score),
        score,
        q,
        "#fbbf24",
        "📦",
        ["economy", "trade", "pressure"],
        {"sealane": sealane, "trade": trade, "economy_score": score},
    )


def sealane_health_depth_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(_zones(), sea_trade_mult=1.1, weather=_wx(), available_fleet=60.0)
    convoy = convoy_package_compose(_zones(), available_fleet_strength=60.0, weather=_wx())
    score = _floor(
        0.55 * float(sealane.get("score", 0.35))
        + 0.45 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.4)
    )
    q = [
        _q("apply_station", province_id, score, "sealane health depth station"),
        _q("apply_supply", province_id, 0.55, "sealane health depth supply"),
        _q("apply_focus", province_id, 0.45, "sealane health depth focus"),
    ]
    return _day(
        "sealane_health_depth_day",
        "Sealane health depth day",
        "Sealane health depth · sealane · convoy · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "🌊",
        ["economy", "sealane", "health"],
        {"sealane": sealane, "convoy": convoy, "economy_score": score},
    )


def war_economy_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    economy = war_economy_day_package(weather=_wx())
    prod = production_priority_mutation(weather=_wx())
    score = _floor(
        0.55 * float(economy.get("score", 0.55)) + 0.45 * float(prod.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "war economy sustain production"),
        _q("apply_supply", province_id, 0.55, "war economy sustain supply"),
        _q("apply_station", province_id, 0.45, "war economy sustain station"),
    ]
    return _day(
        "war_economy_sustain_day",
        "War economy sustain day",
        "War economy sustain · package · production · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "🏭",
        ["economy", "war", "sustain"],
        {"economy": economy, "production": prod, "economy_score": score},
    )


def stockpile_economy_depth_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    prod = production_priority_mutation(weather=_wx(), base_output=1.05)
    economy = war_economy_day_package(weather=_wx())
    score = _floor(
        0.35 * float(equip.get("score", 0.55))
        + 0.35 * float(prod.get("score", 0.55))
        + 0.3 * float(economy.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "stockpile economy depth production"),
        _q("apply_supply", province_id, 0.55, "stockpile economy depth supply"),
        _q("apply_station", province_id, 0.4, "stockpile economy depth station"),
    ]
    return _day(
        "stockpile_economy_depth_day",
        "Stockpile economy depth day",
        "Stockpile economy depth · equip · prod · economy · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "📦",
        ["economy", "stockpile", "depth"],
        {"equip": equip, "production": prod, "economy": economy, "economy_score": score},
    )


def convoy_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(_zones(), available_fleet_strength=70.0, weather=_wx())
    economy = war_economy_day_package(weather=_wx())
    sealane = sealane_joint_health(_zones(), weather=_wx(), available_fleet=50.0)
    score = _floor(
        0.35 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.4)
        + 0.35 * float(economy.get("score", 0.55))
        + 0.3 * float(sealane.get("score", 0.35))
    )
    q = [
        _q("apply_supply", province_id, score, "convoy economy joint supply"),
        _q("apply_station", province_id, 0.55, "convoy economy joint station"),
        _q("apply_production", province_id, 0.5, "convoy economy joint production"),
    ]
    return _day(
        "convoy_economy_joint_day",
        "Convoy economy joint day",
        "Convoy economy joint · convoy · economy · sealane · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "◈",
        ["economy", "convoy", "joint"],
        {
            "convoy": convoy,
            "economy": economy,
            "sealane": sealane,
            "economy_score": score,
        },
    )


def trade_sealane_joint_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(_zones(), sea_trade_mult=1.05, weather=_wx(), available_fleet=55.0)
    supply = supply_route_mutation(weather=_wx(), basing_level="port", sea_mult=1.05)
    sole = sole_mult_integrity()
    score = _floor(
        0.4 * float(sealane.get("score", 0.35))
        + 0.35 * float(supply.get("score", 0.4))
        + 0.25 * (0.75 if sole.get("integrity_ok", True) else 0.3)
    )
    q = [
        _q("apply_supply", province_id, score, "trade sealane joint supply"),
        _q("apply_station", province_id, 0.55, "trade sealane joint station"),
        _q("apply_production", province_id, 0.45, "trade sealane joint production"),
        _q("apply_focus", province_id, 0.4, "trade sealane joint focus"),
    ]
    return _day(
        "trade_sealane_joint_day",
        "Trade sealane joint day",
        "Trade sealane joint · sealane · supply · sole · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "🌊",
        ["economy", "trade", "sealane", "joint"],
        {
            "sealane": sealane,
            "supply": supply,
            "sole": sole,
            "economy_score": score,
        },
    )


def war_economy_close_depth_day(province_id: int = 1) -> Dict[str, Any]:
    economy = war_economy_day_package(weather=_wx())
    sealane = sealane_joint_health(_zones(), weather=_wx(), available_fleet=50.0)
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _floor(
        0.35 * float(economy.get("score", 0.55))
        + 0.35 * float(sealane.get("score", 0.35))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, score, "war economy close depth production"),
        _q("apply_supply", province_id, 0.55, "war economy close depth supply"),
        _q("apply_station", province_id, 0.45, "war economy close depth station"),
    ]
    return _day(
        "war_economy_close_depth_day",
        "War economy close depth day",
        "War economy close depth · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#fbbf24",
        "✓",
        ["economy", "war", "close"],
        {
            "economy": economy,
            "sealane": sealane,
            "gate": gate,
            "ok": ok,
            "economy_score": score,
        },
    )


# C) Force readiness / reinforce


def force_ready_surface_day(province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day(weather=_wx(), province_id=province_id)
    theater = theater_readiness_day(weather=_wx(), province_id=province_id)
    score = _floor(
        0.55 * float(ready.get("score", 0.5)) + 0.45 * float(theater.get("score", 0.45))
    )
    q = list(ready.get("apply_queue") or [])
    if len(q) < 1:
        q = [
            _q("apply_station", province_id, score, "force ready surface station"),
            _q("apply_supply", province_id, 0.55, "force ready surface supply"),
        ]
    return _day(
        "force_ready_surface_day",
        "Force ready surface day",
        "Force ready surface · force · theater · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🛡",
        ["force", "readiness", "surface"],
        {"readiness": ready, "theater": theater, "force_score": score},
    )


def formation_equip_depth_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    ready = force_readiness_day(weather=_wx(), province_id=province_id)
    score = _floor(
        0.55 * float(equip.get("score", 0.55)) + 0.45 * float(ready.get("score", 0.5))
    )
    q = [
        _q("apply_production", province_id, score, "formation equip depth production"),
        _q("apply_station", province_id, 0.55, "formation equip depth station"),
        _q("apply_supply", province_id, 0.5, "formation equip depth supply"),
    ]
    return _day(
        "formation_equip_depth_day",
        "Formation equip depth day",
        "Formation equip depth · equip · readiness · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "⚙",
        ["force", "formation", "equip"],
        {"equip": equip, "readiness": ready, "force_score": score},
    )


def reinforce_stockpile_depth_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan(infantry_stock=4.0, tank_stock=0.0, tank_line_progress=0.2)
    prod = production_priority_mutation(weather=_wx())
    ready = force_readiness_day(weather=_wx(), province_id=province_id, force_strength=75.0)
    score = _floor(
        0.4 * float(equip.get("score", 0.55))
        + 0.3 * float(prod.get("score", 0.55))
        + 0.3 * float(ready.get("score", 0.5))
    )
    q = [
        _q("apply_production", province_id, score, "reinforce stockpile depth production"),
        _q("apply_supply", province_id, 0.55, "reinforce stockpile depth supply"),
        _q("apply_station", province_id, 0.5, "reinforce stockpile depth station"),
    ]
    return _day(
        "reinforce_stockpile_depth_day",
        "Reinforce stockpile depth day",
        "Reinforce stockpile depth · equip · prod · ready · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "↑",
        ["force", "reinforce", "stockpile"],
        {
            "equip": equip,
            "production": prod,
            "readiness": ready,
            "force_score": score,
        },
    )


def readiness_board_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day(weather=_wx(), province_id=province_id)
    risk = campaign_day_risk(_wx(), month=11)
    board = theater_readiness_board(day_risk=risk)
    score = _floor(
        0.5 * float(ready.get("score", 0.5))
        + 0.3 * (0.65 if not bool(board.get("empty", True)) else 0.35)
        + 0.2 * (1.0 - float(risk.get("risk", 0.5)))
    )
    q = [
        _q("apply_station", province_id, score, "readiness board ops station"),
        _q("apply_supply", province_id, 0.55, "readiness board ops supply"),
        _q("apply_focus", province_id, 0.45, "readiness board ops focus"),
    ]
    return _day(
        "readiness_board_ops_day",
        "Readiness board ops day",
        "Readiness board ops · force · board · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "📋",
        ["force", "readiness", "board"],
        {"readiness": ready, "board": board, "risk": risk, "force_score": score},
    )


def force_reinforce_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day(weather=_wx(), province_id=province_id)
    equip = medium_horizon_equip_plan()
    assault = reinforced_assault_loop(
        _targets(province_id), attacker_power=100.0, attacker_supply=0.85, weather=_wx(), month=11
    )
    score = _floor(
        0.35 * float(ready.get("score", 0.5))
        + 0.35 * float(equip.get("score", 0.55))
        + 0.3 * float(assault.get("score", 0.4))
    )
    q = [
        _q("apply_station", province_id, score, "force reinforce joint station"),
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "force reinforce joint production"),
        _q("apply_assault", province_id, float(assault.get("score", 0.4)), "force reinforce joint assault"),
        _q("apply_supply", province_id, 0.5, "force reinforce joint supply"),
    ]
    return _day(
        "force_reinforce_joint_day",
        "Force reinforce joint day",
        "Force reinforce joint · ready · equip · assault · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["force", "reinforce", "joint"],
        {
            "readiness": ready,
            "equip": equip,
            "assault": assault,
            "force_score": score,
        },
    )


def weather_economy_force_close_day(province_id: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    economy = war_economy_day_package(weather=_wx())
    ready = force_readiness_day(weather=_wx(), province_id=province_id)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop(weather=_wx(), province_id=province_id)
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * (1.0 - float(pressure.get("pressure", 0.5)))
        + 0.25 * float(economy.get("score", 0.55))
        + 0.25 * float(ready.get("score", 0.5))
        + 0.25 * (0.8 if ok else 0.3)
    )
    score = _floor(score)
    q = [
        _q("apply_supply", province_id, 0.55, "close weather supply"),
        _q("apply_production", province_id, float(economy.get("score", 0.55)), "close economy production"),
        _q("apply_station", province_id, float(ready.get("score", 0.5)), "close force station"),
        _q("apply_assault", province_id, 0.45, "close assault"),
    ]
    return _day(
        "weather_economy_force_close_day",
        "Weather economy force close day",
        "Weather economy force close · wx · economy · force · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["weather", "economy", "force", "close"],
        {
            "pressure": pressure,
            "economy": economy,
            "readiness": ready,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "weather_score": 1.0 - float(pressure.get("pressure", 0.5)),
            "economy_score": float(economy.get("score", 0.55)),
            "force_score": float(ready.get("score", 0.5)),
        },
    )


WEATHER_ECONOMY_FORCE_DAY_IDS: List[str] = [
    "weather_pressure_depth_day",
    "foul_combat_ops_day",
    "weather_logistics_depth_day",
    "weather_move_depth_day",
    "weather_crisis_depth_day",
    "weather_pressure_joint_day",
    "weather_ops_close_depth_day",
    "trade_pressure_depth_day",
    "sealane_health_depth_day",
    "war_economy_sustain_day",
    "stockpile_economy_depth_day",
    "convoy_economy_joint_day",
    "trade_sealane_joint_day",
    "war_economy_close_depth_day",
    "force_ready_surface_day",
    "formation_equip_depth_day",
    "reinforce_stockpile_depth_day",
    "readiness_board_ops_day",
    "force_reinforce_joint_day",
    "weather_economy_force_close_day",
]

DAY_FUNCS = [
    weather_pressure_depth_day,
    foul_combat_ops_day,
    weather_logistics_depth_day,
    weather_move_depth_day,
    weather_crisis_depth_day,
    weather_pressure_joint_day,
    weather_ops_close_depth_day,
    trade_pressure_depth_day,
    sealane_health_depth_day,
    war_economy_sustain_day,
    stockpile_economy_depth_day,
    convoy_economy_joint_day,
    trade_sealane_joint_day,
    war_economy_close_depth_day,
    force_ready_surface_day,
    formation_equip_depth_day,
    reinforce_stockpile_depth_day,
    readiness_board_ops_day,
    force_reinforce_joint_day,
    weather_economy_force_close_day,
]


def weather_economy_force_integrity() -> Dict[str, Any]:
    pressure = weather_pressure_index(_wx())
    economy = war_economy_day_package(weather=_wx())
    ready = force_readiness_day(weather=_wx())
    gate = execution_integrity_gate()
    ok = (
        float(pressure.get("pressure", 0)) >= 0.0
        and float(economy.get("score", 0)) > 0.0
        and float(ready.get("score", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "weather_pressure": float(pressure.get("pressure", 0)),
        "economy_score": float(economy.get("score", 0)),
        "force_score": float(ready.get("score", 0)),
        "gate": gate,
        "summary": "Weather-economy-force integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next280_weather_economy_force_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = weather_economy_force_integrity()
    label = "Close next280 weather-economy-force · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next280 weather-economy-force[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
