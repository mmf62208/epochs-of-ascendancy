"""Next-150 weather–ops, war-economy, map-feedback/intel (20 packages).

A) Weather–ops continuity (1–7)
B) Strategic / war-economy surface (8–14)
C) Map-feedback / intel-counterplay (15–20)

1 combat_wx_ops_day · 2 prod_wx_ops_day · 3 air_sortie_wx_day · 4 morale_wx_ops_day
5 convoy_wx_ops_day · 6 daylight_wx_ops_day · 7 weather_ops_close_day
8 war_economy_ops_day · 9 prod_campaign_ops_day · 10 focus_wx_ops_day
11 focus_mut_ops_day · 12 supply_economy_ops_day · 13 depot_economy_ops_day
14 war_economy_close_day · 15 intel_counter_ops_day · 16 agent_intel_ops_day
17 hh_counter_ops_day · 18 map_effect_ops_day · 19 coherence_intel_day
20 weather_economy_intel_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from weather_effects import (  # type: ignore
    combat_weather_multiplier,
    production_weather_multiplier,
    air_sortie_readiness,
)
from theater_ops_polish import (  # type: ignore
    campaign_day_risk,
    combat_morale_weather,
    production_weather_alert,
    depot_weather_capacity,
    convoy_weather_window,
    daylight_combat_mod,
    focus_weather_aware_score,
)
from weather_forecast import weather_aware_phase_ribbon  # type: ignore
from weather_ops_polish import coastal_fog_naval_gate  # type: ignore
from integrated_theater_ops import (  # type: ignore
    cross_system_coherence_delta,
    fleet_weather_mission_package,
    assault_readiness_compose,
)
from live_mutation import (  # type: ignore
    focus_mutation_path,
    production_priority_mutation,
    supply_route_mutation,
    next_day_mutation_feedback,
)
from map_next_list_helpers import (  # type: ignore
    apply_hh_counterplay,
    pick_hh_action_class,
    pick_hh_secondary_action_class,
)
from agent_mission_priority import rank_agent_missions  # type: ignore
from campaign_cohesion import agent_campaign_response, production_campaign_risk  # type: ignore
from gameplay_loops import sole_mult_integrity, counter_ops_execute_order  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore


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
        "integration": list(integration or ["next150", "weather_economy_intel"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx(weather: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    return dict(
        weather
        or {
            "visibility": 0.68,
            "precip_intensity": 0.35,
            "ground_state": "mud",
            "temp": 6.0,
            "sea_state": 0.4,
            "fog": 0.3,
        }
    )


# A) Weather–ops


def combat_wx_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    mult = float(combat_weather_multiplier(w))
    ribbon = weather_aware_phase_ribbon(100.0, 80.0, mult)
    est = estimate_multi_phase_combat(100.0, 80.0)
    score = _norm(mult * float(est.get("overall_attacker_win_chance", 0.5)))
    q = [
        _q("apply_assault", province_id, score, "combat wx ops primary"),
        _q("apply_supply", province_id, 0.5, "combat wx ops supply"),
    ]
    return _day(
        "combat_wx_ops_day",
        "Combat wx ops day",
        "Combat wx ops day · mult ×%.2f · win %.2f · score %.2f"
        % (mult, float(est.get("overall_attacker_win_chance", 0)), score),
        score,
        q,
        "#ef8f6e",
        "🌦",
        ["weather", "combat", "ops"],
        {"mult": mult, "ribbon": ribbon, "estimate": est},
    )


def prod_wx_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    mult = float(production_weather_multiplier(w))
    alert = production_weather_alert(w)
    mut = production_priority_mutation()
    score = _norm(0.5 * mult + 0.5 * float(mut.get("score", 0.7)))
    q = [
        _q("apply_production", province_id, score, "prod wx ops primary"),
        _q("apply_supply", province_id, 0.5, "prod wx ops supply"),
    ]
    return _day(
        "prod_wx_ops_day",
        "Prod wx ops day",
        "Prod wx ops day · mult ×%.2f · mut %.2f · score %.2f"
        % (mult, float(mut.get("score", 0)), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["weather", "production", "ops"],
        {"mult": mult, "alert": alert, "mutation": mut},
    )


def air_sortie_wx_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    ready = air_sortie_readiness(w)
    score = _norm(float(ready.get("effectiveness", 0.5) or 0.5))
    q = [
        _q("apply_assault", province_id, score, "air sortie wx primary"),
        _q("apply_supply", province_id, 0.5, "air sortie wx supply"),
    ]
    return _day(
        "air_sortie_wx_day",
        "Air sortie wx day",
        "Air sortie wx day · %s · score %.2f" % (ready.get("summary", "sortie"), score),
        score,
        q,
        "#7dd3a0",
        "✈",
        ["weather", "air", "ops"],
        {"readiness": ready},
    )


def morale_wx_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    morale = combat_morale_weather(w)
    mult = float(morale.get("morale_mult", morale.get("mult", 0.83)) or 0.83)
    score = _norm(mult)
    q = [
        _q("apply_assault", province_id, score, "morale wx ops primary"),
        _q("apply_supply", province_id, 0.5, "morale wx ops supply"),
    ]
    return _day(
        "morale_wx_ops_day",
        "Morale wx ops day",
        "Morale wx ops day · %s · score %.2f" % (morale.get("summary", "morale"), score),
        score,
        q,
        "#ef8f6e",
        "♥",
        ["weather", "morale", "ops"],
        {"morale": morale, "mult": mult},
    )


def convoy_wx_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    forecasts = [
        {"day": 0, "visibility": float(w.get("visibility", 0.7)), "precip_intensity": float(w.get("precip_intensity", 0.3))},
        {"day": 1, "visibility": 0.4, "precip_intensity": 0.7},
        {"day": 2, "visibility": 0.85, "precip_intensity": 0.15},
    ]
    window = convoy_weather_window(forecasts)
    fleet = fleet_weather_mission_package()
    score = 0.65
    for key in ("score", "best_score", "window_score"):
        if window.get(key) is not None:
            score = _norm(float(window[key]))
            break
    q = [
        _q("apply_station", province_id, score, "convoy wx ops escort"),
        _q("apply_supply", province_id, 0.55, "convoy wx ops cargo"),
    ]
    return _day(
        "convoy_wx_ops_day",
        "Convoy wx ops day",
        "Convoy wx ops day · %s · score %.2f" % (window.get("summary", "window"), score),
        score,
        q,
        "#5ec8ff",
        "📦",
        ["weather", "convoy", "ops"],
        {"window": window, "fleet": fleet},
    )


def daylight_wx_ops_day(province_id: int = 1, month: int = 6) -> Dict[str, Any]:
    dl = daylight_combat_mod(month)
    score = _norm(float(dl.get("combat_mult", 1.0)) / 1.2)
    q = [
        _q("apply_assault", province_id, score, "daylight wx ops primary"),
        _q("apply_supply", province_id, 0.5, "daylight wx ops supply"),
    ]
    return _day(
        "daylight_wx_ops_day",
        "Daylight wx ops day",
        "Daylight wx ops day · %s · score %.2f" % (dl.get("summary", "daylight"), score),
        score,
        q,
        "#7dd3a0",
        "☀",
        ["weather", "daylight", "ops"],
        {"daylight": dl},
    )


def weather_ops_close_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    c_mult = float(combat_weather_multiplier(w))
    p_mult = float(production_weather_multiplier(w))
    risk = campaign_day_risk(w, month=3)
    fog = coastal_fog_naval_gate(w) if True else {}
    try:
        fog = coastal_fog_naval_gate(w)
    except TypeError:
        try:
            fog = coastal_fog_naval_gate(weather=w)
        except TypeError:
            fog = {}
    score = _norm(0.4 * c_mult + 0.3 * p_mult + 0.3 * float(fog.get("ops_mult", 0.6) or 0.6))
    q = [
        _q("apply_assault", province_id, c_mult, "weather ops close assault"),
        _q("apply_production", province_id, p_mult, "weather ops close production"),
        _q("apply_station", province_id, 0.5, "weather ops close station"),
    ]
    return _day(
        "weather_ops_close_day",
        "Weather ops close day",
        "Weather ops close day · combat ×%.2f · prod ×%.2f · score %.2f"
        % (c_mult, p_mult, score),
        score,
        q,
        "#5ec8ff",
        "∞",
        ["weather", "ops", "close"],
        {"combat_mult": c_mult, "production_mult": p_mult, "risk": risk, "fog": fog},
    )


# B) War-economy / strategic


def war_economy_ops_day(province_id: int = 1) -> Dict[str, Any]:
    prod = production_priority_mutation()
    supply = supply_route_mutation()
    loop = close_the_loop()
    score = _norm(0.5 * float(prod.get("score", 0.7)) + 0.5 * float(supply.get("score", 0.5)))
    q = [
        _q("apply_production", province_id, float(prod.get("score", score)), "war economy production"),
        _q("apply_supply", province_id, float(supply.get("score", score)), "war economy supply"),
        _q("apply_station", province_id, 0.45, "war economy station"),
    ]
    return _day(
        "war_economy_ops_day",
        "War economy ops day",
        "War economy ops day · prod · supply · close · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "💰",
        ["war_economy", "strategic", "ops"],
        {"production": prod, "supply": supply, "loop": loop},
    )


def prod_campaign_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    risk = production_campaign_risk(weather=_wx(weather))
    mut = production_priority_mutation()
    raw = float(risk.get("score", risk.get("risk", 0.0)) or 0.0)
    score = _norm(max(float(mut.get("score", 0.7)), 1.0 - (raw if raw <= 1 else raw / 100.0)))
    q = [
        _q("apply_production", province_id, score, "prod campaign ops primary"),
        _q("apply_supply", province_id, 0.5, "prod campaign ops supply"),
    ]
    return _day(
        "prod_campaign_ops_day",
        "Prod campaign ops day",
        "Prod campaign ops day · %s · score %.2f" % (risk.get("summary", "risk"), score),
        score,
        q,
        "#e8c547",
        "⚠",
        ["production", "campaign", "economy"],
        {"risk": risk, "mutation": mut},
    )


def focus_wx_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    focus = focus_weather_aware_score(50.0, "industrial_effort", weather=_wx(weather))
    raw = float(focus.get("score", 50.0))
    score = _norm(raw / 100.0 if raw > 2.0 else raw)
    q = [
        _q("apply_focus", province_id, score, "focus wx ops primary"),
        _q("apply_hh_commit", province_id, 0.5, "focus wx ops hh"),
        _q("apply_production", province_id, 0.45, "focus wx ops production"),
    ]
    return _day(
        "focus_wx_ops_day",
        "Focus wx ops day",
        "Focus wx ops day · %s · score %.2f" % (focus.get("summary", "focus"), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "weather", "strategic"],
        {"focus": focus},
    )


def focus_mut_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = focus_mutation_path()
    score = _norm(float(mut.get("score", 0.5)))
    q = [
        _q("apply_focus", province_id, score, "focus mut ops primary"),
        _q("apply_hh_commit", province_id, 0.5, "focus mut ops hh"),
    ]
    return _day(
        "focus_mut_ops_day",
        "Focus mut ops day",
        "Focus mut ops day · %s · score %.2f" % (mut.get("summary", "mut"), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "mutation", "strategic"],
        {"mutation": mut},
    )


def supply_economy_ops_day(province_id: int = 1) -> Dict[str, Any]:
    supply = supply_route_mutation()
    sole = sole_mult_integrity()
    score = _norm(float(supply.get("score", 0.55)))
    q = [
        _q("apply_supply", province_id, score, "supply economy ops primary"),
        _q("apply_station", province_id, 0.5, "supply economy ops station"),
    ]
    return _day(
        "supply_economy_ops_day",
        "Supply economy ops day",
        "Supply economy ops day · %s · score %.2f" % (supply.get("summary", "supply"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "economy", "ops"],
        {"supply": supply, "sole": sole},
    )


def depot_economy_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    depot = depot_weather_capacity(_wx(weather), base_capacity=100.0)
    prod = production_priority_mutation()
    cap = float(depot.get("capacity", 65) or 65)
    score = _norm(0.5 * (cap / 100.0) + 0.5 * float(prod.get("score", 0.7)))
    q = [
        _q("apply_supply", province_id, _norm(cap / 100.0), "depot economy supply"),
        _q("apply_production", province_id, float(prod.get("score", 0.7)), "depot economy production"),
    ]
    return _day(
        "depot_economy_ops_day",
        "Depot economy ops day",
        "Depot economy ops day · cap %.0f · score %.2f" % (cap, score),
        score,
        q,
        "#e8c547",
        "🏗",
        ["depot", "economy", "ops"],
        {"depot": depot, "production": prod},
    )


def war_economy_close_day(province_id: int = 1) -> Dict[str, Any]:
    prod = production_priority_mutation()
    supply = supply_route_mutation()
    focus = focus_mutation_path()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(prod.get("score", 0.5))
        + 0.3 * float(supply.get("score", 0.5))
        + 0.2 * float(focus.get("score", 0.5))
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, float(prod.get("score", score)), "war economy close prod"),
        _q("apply_supply", province_id, float(supply.get("score", score)), "war economy close supply"),
        _q("apply_focus", province_id, float(focus.get("score", score)), "war economy close focus"),
    ]
    return _day(
        "war_economy_close_day",
        "War economy close day",
        "War economy close day · prod · supply · focus · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["war_economy", "close", "strategic"],
        {"production": prod, "supply": supply, "focus": focus, "gate": gate, "ok": ok},
    )


# C) Map-feedback / intel


def intel_counter_ops_day(province_id: int = 1) -> Dict[str, Any]:
    counter = apply_hh_counterplay(
        0.55, {"action_class": "sabotage", "province_id": province_id, "influence": 0.55}
    )
    order = counter_ops_execute_order(
        {"action_class": "sabotage", "influence": 0.55, "province_id": province_id}
    )
    score = _norm(0.5 + float(counter.get("reduction", 0.12) or 0.12) + 0.2 * float(order.get("score", 0.5) if isinstance(order.get("score"), (int, float)) else 0.5))
    q = [
        _q("apply_counterplay", province_id, score, "intel counter ops primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "intel counter ops agents"),
    ]
    return _day(
        "intel_counter_ops_day",
        "Intel counter ops day",
        "Intel counter ops day · %s · score %.2f" % (counter.get("label", "counter"), score),
        score,
        q,
        "#c084fc",
        "🛡",
        ["intel", "counterplay", "ops"],
        {"counter": counter, "order": order},
    )


def agent_intel_ops_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    resp = agent_campaign_response(
        signal={"action_class": "sabotage", "influence": 0.55, "province_id": province_id},
        available_agents=5,
    )
    score = _norm(
        max(
            float(missions.get("best_score", 0.6) or 0.6) if float(missions.get("best_score", 0.6) or 0.6) <= 1 else float(missions.get("best_score", 60)) / 100.0,
            float(resp.get("score", 0.55)),
        )
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent intel ops primary"),
        _q("apply_counterplay", province_id, 0.5, "agent intel ops counter"),
        _q("apply_hh_commit", province_id, 0.45, "agent intel ops hh"),
    ]
    return _day(
        "agent_intel_ops_day",
        "Agent intel ops day",
        "Agent intel ops day · missions · campaign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "intel", "ops"],
        {"missions": missions, "response": resp},
    )


def hh_counter_ops_day(province_id: int = 1) -> Dict[str, Any]:
    primary = pick_hh_action_class(3, 0.55)
    secondary = pick_hh_secondary_action_class(3, 0.55, primary)
    counter = apply_hh_counterplay(
        0.55, {"action_class": primary, "province_id": province_id, "influence": 0.55}
    )
    score = _norm(0.55 + float(counter.get("reduction", 0.12) or 0.12))
    q = [
        _q("apply_hh_commit", province_id, score, "hh counter ops commit"),
        _q("apply_counterplay", province_id, 0.6, "hh counter ops counter"),
    ]
    return _day(
        "hh_counter_ops_day",
        "HH counter ops day",
        "HH counter ops day · %s→%s · score %.2f" % (primary, secondary, score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "counterplay", "intel"],
        {"primary": primary, "secondary": secondary, "counter": counter},
    )


def map_effect_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fb = next_day_mutation_feedback(0.4, 0.7, "map_effect", "apply_assault")
    ready = assault_readiness_compose(
        [{"province_id": province_id, "defender_power": 45, "supply": 0.6}],
        100.0,
    )
    score = _norm(0.55 + 0.15)
    q = [
        _q("apply_assault", province_id, score, "map effect ops assault"),
        _q("refresh_queue", province_id, 0.5, "map effect ops refresh"),
        _q("apply_supply", province_id, 0.45, "map effect ops supply"),
    ]
    return _day(
        "map_effect_ops_day",
        "Map effect ops day",
        "Map effect ops day · feedback · readiness · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["map", "feedback", "effect"],
        {"feedback": fb, "readiness": ready},
    )


def coherence_intel_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = _wx(weather)
    foul = dict(clear)
    foul["visibility"] = 0.3
    foul["precip_intensity"] = 0.9
    foul["sea_state"] = 0.85
    delta = cross_system_coherence_delta(clear, foul)
    score = 0.7 if delta.get("changed", True) else 0.4
    q = [
        _q("refresh_queue", province_id, score, "coherence intel refresh"),
        _q("apply_station", province_id, 0.55, "coherence intel station"),
        _q("apply_agent_dispatch", province_id, 0.5, "coherence intel agents"),
    ]
    return _day(
        "coherence_intel_day",
        "Coherence intel day",
        "Coherence intel day · changed=%s · score %.2f"
        % (bool(delta.get("changed", True)), score),
        score,
        q,
        "#5ec8ff",
        "Δ",
        ["coherence", "intel", "weather"],
        {"delta": delta},
    )


def weather_economy_intel_close_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    c_mult = float(combat_weather_multiplier(w))
    prod = production_priority_mutation()
    counter = apply_hh_counterplay(
        0.55, {"action_class": "sabotage", "province_id": province_id}
    )
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * c_mult
        + 0.25 * float(prod.get("score", 0.5))
        + 0.25 * (0.55 + float(counter.get("reduction", 0.12) or 0.12))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, c_mult, "close weather combat"),
        _q("apply_production", province_id, float(prod.get("score", 0.7)), "close economy production"),
        _q("apply_counterplay", province_id, 0.55, "close intel counter"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "weather_economy_intel_close_day",
        "Weather economy intel close day",
        "Weather economy intel close day · wx · economy · intel · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["weather", "economy", "intel", "close"],
        {
            "combat_mult": c_mult,
            "production": prod,
            "counter": counter,
            "gate": gate,
            "sole": sole,
            "ok": ok,
        },
    )


WEATHER_ECONOMY_INTEL_DAY_IDS: List[str] = [
    "combat_wx_ops_day",
    "prod_wx_ops_day",
    "air_sortie_wx_day",
    "morale_wx_ops_day",
    "convoy_wx_ops_day",
    "daylight_wx_ops_day",
    "weather_ops_close_day",
    "war_economy_ops_day",
    "prod_campaign_ops_day",
    "focus_wx_ops_day",
    "focus_mut_ops_day",
    "supply_economy_ops_day",
    "depot_economy_ops_day",
    "war_economy_close_day",
    "intel_counter_ops_day",
    "agent_intel_ops_day",
    "hh_counter_ops_day",
    "map_effect_ops_day",
    "coherence_intel_day",
    "weather_economy_intel_close_day",
]


DAY_FUNCS = [
    combat_wx_ops_day,
    prod_wx_ops_day,
    air_sortie_wx_day,
    morale_wx_ops_day,
    convoy_wx_ops_day,
    daylight_wx_ops_day,
    weather_ops_close_day,
    war_economy_ops_day,
    prod_campaign_ops_day,
    focus_wx_ops_day,
    focus_mut_ops_day,
    supply_economy_ops_day,
    depot_economy_ops_day,
    war_economy_close_day,
    intel_counter_ops_day,
    agent_intel_ops_day,
    hh_counter_ops_day,
    map_effect_ops_day,
    coherence_intel_day,
    weather_economy_intel_close_day,
]


def weather_economy_intel_integrity() -> Dict[str, Any]:
    w = _wx()
    c = float(combat_weather_multiplier(w))
    p = production_priority_mutation()
    counter = apply_hh_counterplay(0.55, {"action_class": "sabotage", "province_id": 1})
    gate = execution_integrity_gate()
    ok = (
        c > 0.0
        and not bool(p.get("empty", False))
        and bool(counter)
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "combat_mult": c,
        "production_score": float(p.get("score", 0)),
        "counter": counter.get("label", ""),
        "gate": gate,
        "summary": "Weather-economy-intel integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next150_weather_economy_intel_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    wx_days = {
        "combat_wx_ops_day",
        "prod_wx_ops_day",
        "air_sortie_wx_day",
        "morale_wx_ops_day",
        "convoy_wx_ops_day",
        "weather_ops_close_day",
        "prod_campaign_ops_day",
        "focus_wx_ops_day",
        "depot_economy_ops_day",
        "coherence_intel_day",
        "weather_economy_intel_close_day",
    }
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in wx_days:
                packages[name] = fn(weather=w)
            elif name == "daylight_wx_ops_day":
                packages[name] = fn(month=6)
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = weather_economy_intel_integrity()
    label = "Close next150 weather-economy-intel · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next150 weather-economy-intel[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
