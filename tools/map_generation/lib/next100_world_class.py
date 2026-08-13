"""Next-100 world-class depth: 20 multi-system day packages.

1 best_assault_live_day · 2 best_station_live_day · 3 execute_one_live_day
4 basing_fuel_loop_day · 5 fleet_wx_package_day · 6 convoy_wx_window_day
7 focus_wx_score_day · 8 morale_wx_day · 9 campaign_risk_live_day
10 depot_wx_live_day · 11 daily_fleet_auto_day · 12 daily_combat_auto_day
13 daily_agent_auto_day · 14 daily_supply_auto_day · 15 basing_signals_day
16 basing_rates_day · 17 combat_wx_mult_day · 18 sea_zone_trade_day
19 hh_secondary_trail_day · 20 agent_campaign_live_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from theater_commander import (  # type: ignore
    apply_best_assault_package,
    apply_best_station_package,
    execute_one_order,
)
from gameplay_loops import basing_fleet_fuel_logistics  # type: ignore
from integrated_theater_ops import (  # type: ignore
    fleet_weather_mission_package,
    convoy_package_compose,
    theater_readiness_board,
    format_campaign_strip,
)
from theater_ops_polish import (  # type: ignore
    convoy_weather_window,
    focus_weather_aware_score,
    combat_morale_weather,
    campaign_day_risk,
    depot_weather_capacity,
    format_ops_dashboard,
)
from daily_command_tick import (  # type: ignore
    daily_fleet_auto_apply_plan,
    daily_combat_auto_apply_plan,
    daily_agent_auto_apply_plan,
    daily_supply_auto_apply_plan,
)
from naval_basing import basing_from_province_signals, basing_repair_refuel_rates  # type: ignore
from weather_effects import (  # type: ignore
    combat_weather_multiplier,
    production_weather_multiplier,
    air_sortie_readiness,
)
from sea_zone_control import apply_sea_zone_multiplier  # type: ignore
from map_next_list_helpers import pick_hh_secondary_action_class  # type: ignore
from hh_agenda_trail import append_hh_agenda_trail  # type: ignore
from campaign_cohesion import agent_campaign_response, combat_campaign_phase  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore


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
        "integration": list(integration or ["next100", "world_class"]),
    }
    if extra:
        # never overwrite day package action list
        extra = {k: v for k, v in extra.items() if k != "actions"}
        out.update(extra)
    return out


def _wx(weather: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    return dict(
        weather
        or {
            "visibility": 0.72,
            "precip_intensity": 0.28,
            "ground_state": "mud",
            "temp": 9.0,
            "sea_state": 0.35,
            "fog": 0.18,
        }
    )


def best_assault_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    pkg = apply_best_assault_package(weather=_wx(weather))
    score = _norm(float(pkg.get("score", 0.55)))
    phase = combat_campaign_phase(weather=_wx(weather))
    q = [
        _q("apply_assault", province_id, score, "best assault live primary"),
        _q("apply_supply", province_id, 0.5, "best assault live supply"),
    ]
    return _day(
        "best_assault_live_day",
        "Best assault live day",
        "Best assault live day · %s · phase %.2f · score %.2f"
        % (pkg.get("summary", "assault"), float(phase.get("score", 0)), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["assault", "live", "campaign"],
        {"package": pkg, "phase": phase},
    )


def best_station_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    pkg = apply_best_station_package(weather=_wx(weather))
    score = _norm(float(pkg.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "best station live primary"),
        _q("apply_supply", province_id, 0.5, "best station live supply"),
    ]
    return _day(
        "best_station_live_day",
        "Best station live day",
        "Best station live day · %s · score %.2f" % (pkg.get("summary", "station"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "station", "live"],
        {"package": pkg},
    )


def execute_one_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    order = execute_one_order(weather=_wx(weather))
    score = _norm(float(order.get("score", 0.7)))
    domain = str(order.get("domain", "supply"))
    primary = {
        "combat": "apply_assault",
        "fleet": "apply_station",
        "agent": "apply_agent_dispatch",
        "hh": "apply_hh_commit",
        "production": "apply_production",
    }.get(domain, "apply_supply")
    q = [
        _q(primary, province_id, score, "execute one live primary"),
        _q("apply_supply", province_id, 0.5, "execute one live secondary"),
    ]
    return _day(
        "execute_one_live_day",
        "Execute one live day",
        "Execute one live day · %s · score %.2f" % (order.get("summary", domain), score),
        score,
        q,
        "#ef8f6e",
        "▶",
        ["execute", "live", "order"],
        {"order": order},
    )


def basing_fuel_loop_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    rates = basing_repair_refuel_rates(level="port")
    score = _norm(float(fuel.get("logistics_score", fuel.get("fuel_level", 0.5))))
    q = [
        _q("apply_station", province_id, score, "basing fuel loop primary"),
        _q("apply_supply", province_id, 0.55, "basing fuel loop supply"),
    ]
    return _day(
        "basing_fuel_loop_day",
        "Basing fuel loop day",
        "Basing fuel loop day · %s · score %.2f" % (fuel.get("summary", "fuel"), score),
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["basing", "fuel", "fleet"],
        {"fuel": fuel, "rates": rates},
    )


def fleet_wx_package_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    pkg = fleet_weather_mission_package()
    readiness = theater_readiness_board(fleet_package=pkg, day_risk=campaign_day_risk(w, 3))
    score = _norm(0.55 if pkg.get("empty") else 0.7)
    if isinstance(pkg.get("available_strength"), (int, float)):
        score = _norm(float(pkg["available_strength"]) / 100.0 * 0.6 + 0.25)
    q = [
        _q("apply_station", province_id, score, "fleet wx package primary"),
        _q("apply_supply", province_id, 0.5, "fleet wx package supply"),
    ]
    return _day(
        "fleet_wx_package_day",
        "Fleet wx package day",
        "Fleet wx package day · %s · score %.2f" % (pkg.get("summary", "fleet+wx"), score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "weather", "mission"],
        {"package": pkg, "readiness": readiness},
    )


def convoy_wx_window_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    forecasts = [
        {"day": 0, "visibility": float(w.get("visibility", 0.7)), "precip_intensity": float(w.get("precip_intensity", 0.3))},
        {"day": 1, "visibility": 0.45, "precip_intensity": 0.65},
        {"day": 2, "visibility": 0.85, "precip_intensity": 0.15},
    ]
    window = convoy_weather_window(forecasts)
    convoy = convoy_package_compose(
        ["friendly", "contested", "contested"],
        available_fleet_strength=60.0,
        cargo_value=120.0,
        weather=w,
        forecasts=forecasts,
    )
    # derive score from window if available
    score = 0.6
    for key in ("score", "best_score", "window_score"):
        if window.get(key) is not None:
            score = _norm(float(window[key]))
            break
    if convoy.get("score") is not None:
        score = _norm(max(score, float(convoy["score"])))
    q = [
        _q("apply_station", province_id, score, "convoy wx window escort"),
        _q("apply_supply", province_id, 0.55, "convoy wx window cargo"),
    ]
    return _day(
        "convoy_wx_window_day",
        "Convoy wx window day",
        "Convoy wx window day · %s · score %.2f" % (window.get("summary", "window"), score),
        score,
        q,
        "#5ec8ff",
        "📦",
        ["convoy", "weather", "trade"],
        {"window": window, "convoy": convoy},
    )


def focus_wx_score_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    focus = focus_weather_aware_score(50.0, "industrial_effort", weather=_wx(weather))
    raw = float(focus.get("score", 50.0))
    score = _norm(raw / 100.0 if raw > 2.0 else raw)
    mut = production_priority_mutation()
    q = [
        _q("apply_focus", province_id, score, "focus wx score primary"),
        _q("apply_hh_commit", province_id, 0.5, "focus wx score hh"),
        _q("apply_production", province_id, 0.45, "focus wx production"),
    ]
    return _day(
        "focus_wx_score_day",
        "Focus wx score day",
        "Focus wx score day · %s · score %.2f" % (focus.get("summary", "focus"), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "weather", "hh"],
        {"focus": focus, "mutation": mut},
    )


def morale_wx_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    morale = combat_morale_weather(_wx(weather))
    mult = float(morale.get("morale_mult", morale.get("mult", 0.83)) or 0.83)
    score = _norm(mult)
    q = [
        _q("apply_assault", province_id, score, "morale wx primary"),
        _q("apply_supply", province_id, 0.5, "morale wx supply"),
    ]
    return _day(
        "morale_wx_day",
        "Morale wx day",
        "Morale wx day · %s · score %.2f" % (morale.get("summary", "morale"), score),
        score,
        q,
        "#ef8f6e",
        "♥",
        ["combat", "morale", "weather"],
        {"morale": morale},
    )


def campaign_risk_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 3,
) -> Dict[str, Any]:
    w = _wx(weather)
    risk = campaign_day_risk(w, month)
    dash = format_ops_dashboard(day_risk=risk)
    strip = format_campaign_strip(
        [
            {"label": risk.get("summary", "risk"), "score": float(risk.get("risk", risk.get("pressure", 0.5)) or 0.5)},
            {"label": "ops", "score": 0.55},
        ]
    )
    pressure = float(risk.get("risk", risk.get("pressure", 0.46)) or 0.46)
    if pressure > 2:
        pressure = pressure / 100.0
    score = _norm(1.0 - pressure)  # lower risk → higher actionable score for planning
    q = [
        _q("apply_station", province_id, score, "campaign risk live station"),
        _q("apply_supply", province_id, 0.5, "campaign risk live supply"),
        _q("apply_assault", province_id, 0.45, "campaign risk live assault"),
    ]
    return _day(
        "campaign_risk_live_day",
        "Campaign risk live day",
        "Campaign risk live day · %s · score %.2f" % (risk.get("summary", "risk"), score),
        score,
        q,
        "#e8c547",
        "⚠",
        ["campaign", "risk", "ops"],
        {"risk": risk, "dashboard": dash, "strip": strip},
    )


def depot_wx_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    depot = depot_weather_capacity(_wx(weather), base_capacity=100.0)
    cap = float(depot.get("capacity", depot.get("effective_capacity", 65)) or 65)
    score = _norm(cap / 100.0)
    q = [
        _q("apply_supply", province_id, score, "depot wx live primary"),
        _q("apply_production", province_id, 0.5, "depot wx live production"),
    ]
    return _day(
        "depot_wx_live_day",
        "Depot wx live day",
        "Depot wx live day · %s · score %.2f" % (depot.get("summary", "depot"), score),
        score,
        q,
        "#e8c547",
        "🏗",
        ["depot", "weather", "supply"],
        {"depot": depot},
    )


def daily_fleet_auto_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_fleet_auto_apply_plan()
    score = _norm(float(plan.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "daily fleet auto primary"),
        _q("apply_supply", province_id, 0.5, "daily fleet auto supply"),
    ]
    return _day(
        "daily_fleet_auto_day",
        "Daily fleet auto day",
        "Daily fleet auto day · %s · score %.2f" % (plan.get("summary", "fleet auto"), score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "auto", "daily"],
        {"plan": plan},
    )


def daily_combat_auto_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_combat_auto_apply_plan()
    score = _norm(float(plan.get("score", 0.4)))
    q = [
        _q("apply_assault", province_id, score, "daily combat auto primary"),
        _q("apply_supply", province_id, 0.5, "daily combat auto supply"),
    ]
    return _day(
        "daily_combat_auto_day",
        "Daily combat auto day",
        "Daily combat auto day · %s · score %.2f" % (plan.get("summary", "combat auto"), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "auto", "daily"],
        {"plan": plan},
    )


def daily_agent_auto_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_agent_auto_apply_plan()
    score = _norm(float(plan.get("score", 0.55)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "daily agent auto primary"),
        _q("apply_counterplay", province_id, 0.5, "daily agent auto counter"),
    ]
    return _day(
        "daily_agent_auto_day",
        "Daily agent auto day",
        "Daily agent auto day · %s · score %.2f" % (plan.get("summary", "agent auto"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "auto", "daily"],
        {"plan": plan},
    )


def daily_supply_auto_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_supply_auto_apply_plan()
    score = _norm(float(plan.get("score", 0.55)))
    q = [
        _q("apply_supply", province_id, score, "daily supply auto primary"),
        _q("apply_station", province_id, 0.5, "daily supply auto station"),
    ]
    return _day(
        "daily_supply_auto_day",
        "Daily supply auto day",
        "Daily supply auto day · %s · score %.2f" % (plan.get("summary", "supply auto"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "auto", "daily"],
        {"plan": plan},
    )


def basing_signals_day(province_id: int = 1) -> Dict[str, Any]:
    basing = basing_from_province_signals(
        {
            "is_coastal": True,
            "has_port": True,
            "port_tier": 2,
            "province_id": province_id,
            "has_naval_shipyard": False,
            "is_chokepoint": False,
        }
    )
    cap = float(basing.get("capacity", 8) or 0)
    score = _norm(0.4 + min(0.5, cap / 20.0))
    q = [
        _q("apply_station", province_id, score, "basing signals primary"),
        _q("apply_supply", province_id, 0.5, "basing signals supply"),
    ]
    return _day(
        "basing_signals_day",
        "Basing signals day",
        "Basing signals day · %s · score %.2f" % (basing.get("summary", "basing"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["basing", "signals"],
        {"basing": basing},
    )


def basing_rates_day(province_id: int = 1) -> Dict[str, Any]:
    rates = basing_repair_refuel_rates(level="port")
    refuel = float(rates.get("refuel_rate", rates.get("refuel", 0.25)) or 0.25)
    score = _norm(min(1.0, refuel * 2.5 + 0.25))
    q = [
        _q("apply_station", province_id, score, "basing rates primary"),
        _q("apply_supply", province_id, 0.5, "basing rates supply"),
    ]
    return _day(
        "basing_rates_day",
        "Basing rates day",
        "Basing rates day · %s · score %.2f" % (rates.get("summary", "rates"), score),
        score,
        q,
        "#5ec8ff",
        "🔧",
        ["basing", "repair", "refuel"],
        {"rates": rates},
    )


def combat_wx_mult_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    c_mult = float(combat_weather_multiplier(w))
    p_mult = float(production_weather_multiplier(w))
    sortie = air_sortie_readiness(w)
    score = _norm(c_mult)
    q = [
        _q("apply_assault", province_id, score, "combat wx mult primary"),
        _q("apply_production", province_id, _norm(p_mult), "combat wx mult production"),
        _q("apply_supply", province_id, 0.45, "combat wx mult supply"),
    ]
    return _day(
        "combat_wx_mult_day",
        "Combat wx mult day",
        "Combat wx mult day · combat ×%.2f · prod ×%.2f · sortie %s · score %.2f"
        % (c_mult, p_mult, sortie.get("summary", "?"), score),
        score,
        q,
        "#ef8f6e",
        "🌦",
        ["combat", "weather", "multiplier"],
        {"combat_mult": c_mult, "production_mult": p_mult, "sortie": sortie},
    )


def sea_zone_trade_day(province_id: int = 1, base: float = 100.0, mult: float = 1.15) -> Dict[str, Any]:
    adjusted = float(apply_sea_zone_multiplier(base, mult))
    score = _norm(adjusted / max(base, 1.0) * 0.6 + 0.2)
    q = [
        _q("apply_station", province_id, score, "sea zone trade primary"),
        _q("apply_supply", province_id, 0.55, "sea zone trade supply"),
    ]
    return _day(
        "sea_zone_trade_day",
        "Sea zone trade day",
        "Sea zone trade day · base %.0f ×%.2f → %.1f · score %.2f" % (base, mult, adjusted, score),
        score,
        q,
        "#5ec8ff",
        "🌊",
        ["sea_zone", "trade"],
        {"base": base, "multiplier": mult, "adjusted": adjusted},
    )


def hh_secondary_trail_day(province_id: int = 1, hand_influence: float = 0.55) -> Dict[str, Any]:
    primary = "sabotage"
    secondary = pick_hh_secondary_action_class(3, hand_influence, primary)
    trail = append_hh_agenda_trail(
        [],
        {
            "action_class": primary,
            "province_id": province_id,
            "influence": hand_influence,
            "year": 1936,
            "month": 3,
        },
    )
    trail2 = append_hh_agenda_trail(
        trail if isinstance(trail, list) else [],
        {
            "action_class": secondary,
            "province_id": province_id,
            "influence": hand_influence * 0.85,
            "year": 1936,
            "month": 3,
            "is_secondary": True,
        },
    )
    n = len(trail2) if isinstance(trail2, list) else 1
    score = _norm(0.5 + 0.1 * min(4, n))
    q = [
        _q("apply_hh_commit", province_id, score, "hh secondary trail primary"),
        _q("apply_counterplay", province_id, 0.55, "hh secondary trail counter"),
        _q("apply_agent_dispatch", province_id, 0.45, "hh secondary trail agents"),
    ]
    return _day(
        "hh_secondary_trail_day",
        "HH secondary trail day",
        "HH secondary trail day · primary %s · secondary %s · trail %d · score %.2f"
        % (primary, secondary, n, score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "secondary", "trail"],
        {"primary": primary, "secondary": secondary, "trail": trail2},
    )


def agent_campaign_live_day(province_id: int = 1) -> Dict[str, Any]:
    resp = agent_campaign_response(
        signal={"action_class": "sabotage", "influence": 0.55, "province_id": province_id},
        available_agents=5,
    )
    score = _norm(float(resp.get("score", 0.55)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent campaign live primary"),
        _q("apply_counterplay", province_id, 0.55, "agent campaign live counter"),
        _q("apply_hh_commit", province_id, 0.45, "agent campaign live hh"),
    ]
    return _day(
        "agent_campaign_live_day",
        "Agent campaign live day",
        "Agent campaign live day · %s · score %.2f" % (resp.get("summary", "agents"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "campaign", "live"],
        {"response": resp},
    )


WORLD_CLASS_DAY_IDS: List[str] = [
    "best_assault_live_day",
    "best_station_live_day",
    "execute_one_live_day",
    "basing_fuel_loop_day",
    "fleet_wx_package_day",
    "convoy_wx_window_day",
    "focus_wx_score_day",
    "morale_wx_day",
    "campaign_risk_live_day",
    "depot_wx_live_day",
    "daily_fleet_auto_day",
    "daily_combat_auto_day",
    "daily_agent_auto_day",
    "daily_supply_auto_day",
    "basing_signals_day",
    "basing_rates_day",
    "combat_wx_mult_day",
    "sea_zone_trade_day",
    "hh_secondary_trail_day",
    "agent_campaign_live_day",
]


DAY_FUNCS = [
    best_assault_live_day,
    best_station_live_day,
    execute_one_live_day,
    basing_fuel_loop_day,
    fleet_wx_package_day,
    convoy_wx_window_day,
    focus_wx_score_day,
    morale_wx_day,
    campaign_risk_live_day,
    depot_wx_live_day,
    daily_fleet_auto_day,
    daily_combat_auto_day,
    daily_agent_auto_day,
    daily_supply_auto_day,
    basing_signals_day,
    basing_rates_day,
    combat_wx_mult_day,
    sea_zone_trade_day,
    hh_secondary_trail_day,
    agent_campaign_live_day,
]


def world_class_integrity() -> Dict[str, Any]:
    """Light multi-system integrity: execute-one + agent response + basing signals."""
    order = execute_one_order()
    agent = agent_campaign_response()
    basing = basing_from_province_signals(
        {"is_coastal": True, "has_port": True, "port_tier": 2, "province_id": 1}
    )
    ok = (not order.get("empty", False)) and (not agent.get("empty", False)) and bool(basing)
    return {
        "ok": ok,
        "order_score": float(order.get("score", 0)),
        "agent_score": float(agent.get("score", 0)),
        "basing": basing.get("summary", basing.get("level", "")),
        "summary": "World-class integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next100_world_class_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    wx_days = {
        "best_assault_live_day",
        "best_station_live_day",
        "execute_one_live_day",
        "fleet_wx_package_day",
        "convoy_wx_window_day",
        "focus_wx_score_day",
        "morale_wx_day",
        "campaign_risk_live_day",
        "depot_wx_live_day",
        "combat_wx_mult_day",
    }
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in wx_days:
                packages[name] = fn(weather=w)
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = world_class_integrity()
    label = "Close next100 world-class · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next100 world-class[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
