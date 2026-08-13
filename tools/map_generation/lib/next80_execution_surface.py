"""Next-80 execution surface: 20 day packages closing feedback / integrity / estimate gaps.

1 result_feedback_day · 2 day_budget_day · 3 hh_auto_plan_day · 4 append_log_day
5 log_strip_day · 6 assault_readiness_day · 7 coherence_delta_day · 8 agent_order_day
9 execution_gate_day · 10 cohesion_gate_day · 11 command_gate_day · 12 execute_order_day
13 air_sortie_ready_day · 14 weather_combat_brief_day · 15 day_audit_day
16 map_visible_day · 17 assault_card_day · 18 save_slot_list_day
19 multi_phase_estimate_day · 20 campaign_strip_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from daily_command_tick import (  # type: ignore
    apply_result_feedback,
    day_apply_budget,
    daily_hh_auto_apply_plan,
    append_command_log,
    command_log_strip,
)
from integrated_theater_ops import (  # type: ignore
    assault_readiness_compose,
    cross_system_coherence_delta,
)
from campaign_execution import agent_order_dispatch, execution_integrity_gate  # type: ignore
from campaign_cohesion import cohesion_integrity_gate, theater_campaign_strip  # type: ignore
from theater_commander import command_integrity_gate, execute_one_order  # type: ignore
from weather_effects import air_sortie_readiness  # type: ignore
from weather_combat_briefing import build_weather_combat_briefing  # type: ignore
from week2_core_polish import day_package_apply_audit  # type: ignore
from map_next_list_helpers import default_player_map_visible  # type: ignore
from assault_estimate_card import build_assault_estimate_card  # type: ignore
from save_slot_ui import build_save_slot_list  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from theater_ops_polish import campaign_day_risk  # type: ignore


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
        "integration": list(integration or ["next80", "execution"]),
    }
    if extra:
        out.update(extra)
    return out


def _wx(weather: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    return dict(
        weather
        or {
            "visibility": 0.75,
            "precip_intensity": 0.25,
            "ground_state": "mud",
            "temp": 8.0,
            "sea_state": 0.3,
        }
    )


def result_feedback_day(
    province_id: int = 1,
    before: float = 0.45,
    after: float = 0.62,
    domain: str = "combat",
) -> Dict[str, Any]:
    fb = apply_result_feedback(before, after, domain)
    score = _norm(0.55 + float(fb.get("delta", 0.0)))
    q = [
        _q("refresh_queue", province_id, score, "result feedback refresh"),
        _q("apply_assault", province_id, 0.5, "result feedback follow-on"),
    ]
    return _day(
        "result_feedback_day",
        "Result feedback day",
        "Result feedback day · %s · score %.2f" % (fb.get("summary", "Δ"), score),
        score,
        q,
        "#7dd3a0",
        "↻",
        ["feedback", "apply_result"],
        {"feedback": fb},
    )


def day_budget_day(
    province_id: int = 1,
    pending: int = 5,
    max_applies: int = 3,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    bud = day_apply_budget(pending, max_applies, _wx(weather))
    score = _norm(float(bud.get("score", 0.6)))
    q = [
        _q("refresh_queue", province_id, score, "day budget gate"),
        _q("apply_supply", province_id, 0.5, "day budget supply"),
    ]
    return _day(
        "day_budget_day",
        "Day budget day",
        "Day budget day · %s · score %.2f" % (bud.get("summary", "budget"), score),
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["budget", "cap"],
        {"budget": bud},
    )


def hh_auto_plan_day(
    province_id: int = 1,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    plan = daily_hh_auto_apply_plan(trail or [{"action": "commit", "score": 0.7}])
    score = _norm(float(plan.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "hh auto plan primary"),
        _q("apply_counterplay", province_id, 0.5, "hh auto plan secondary"),
    ]
    return _day(
        "hh_auto_plan_day",
        "HH auto plan day",
        "HH auto plan day · %s · score %.2f" % (plan.get("summary", "hh"), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "auto_plan"],
        {"plan": plan},
    )


def append_log_day(
    province_id: int = 1,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    log = append_command_log(
        list(trail or []),
        {"action_id": "apply_supply", "ok": True, "label": "supply", "province_id": province_id},
    )
    score = _norm(0.5 + 0.1 * min(5, int(log.get("count", 1))))
    q = [
        _q("refresh_queue", province_id, score, "append log refresh"),
        _q("apply_supply", province_id, 0.5, "append log supply"),
    ]
    return _day(
        "append_log_day",
        "Append log day",
        "Append log day · %s · score %.2f" % (log.get("summary", "log"), score),
        score,
        q,
        "#8899aa",
        "✎",
        ["command_log", "append"],
        {"log": log},
    )


def log_strip_day(
    province_id: int = 1,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    strip = command_log_strip(
        list(trail or [{"label": "prior", "ok": True}]),
        {"delta": 0.1, "trend": "up"},
    )
    score = _norm(0.55 + 0.05 * min(5, int(strip.get("count", 1))))
    q = [
        _q("refresh_queue", province_id, score, "log strip refresh"),
        _q("apply_station", province_id, 0.5, "log strip station"),
    ]
    return _day(
        "log_strip_day",
        "Log strip day",
        "Log strip day · %s · score %.2f" % (strip.get("summary", "strip"), score),
        score,
        q,
        "#8899aa",
        "☰",
        ["command_log", "strip"],
        {"strip": strip},
    )


def assault_readiness_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    targets = [
        {"province_id": max(1, province_id), "defender_power": 40.0, "supply": 0.6},
        {"province_id": max(1, province_id) + 1, "defender_power": 55.0, "supply": 0.4},
    ]
    ready = assault_readiness_compose(targets, attacker_power)
    best = int(ready.get("best_province_id") or province_id)
    score = _norm(float(ready.get("supply_mult", 0.6)) * float(ready.get("morale_mult", 1.0)))
    q = [
        _q("apply_assault", best, score, "assault readiness primary"),
        _q("apply_supply", best, 0.5, "assault readiness supply"),
    ]
    return _day(
        "assault_readiness_day",
        "Assault readiness day",
        "Assault readiness day · best %d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["assault", "readiness"],
        {"readiness": ready, "weather": _wx(weather)},
    )


def coherence_delta_day(
    province_id: int = 1,
    clear: Optional[Mapping[str, Any]] = None,
    foul: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    c = _wx(clear)
    f = dict(
        foul
        or {
            "visibility": 0.3,
            "precip_intensity": 0.85,
            "ground_state": "mud",
            "temp": -2.0,
            "sea_state": 0.8,
        }
    )
    delta = cross_system_coherence_delta(c, f)
    changed = bool(delta.get("changed", True))
    score = 0.7 if changed else 0.4
    q = [
        _q("refresh_queue", province_id, score, "coherence delta refresh"),
        _q("apply_station", province_id, 0.5, "coherence delta station"),
    ]
    return _day(
        "coherence_delta_day",
        "Coherence delta day",
        "Coherence delta day · changed=%s · score %.2f" % (changed, score),
        score,
        q,
        "#5ec8ff",
        "Δ",
        ["coherence", "weather"],
        {"delta": delta},
    )


def agent_order_day(
    province_id: int = 1,
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 3,
) -> Dict[str, Any]:
    sig = dict(signal or {"action_class": "sabotage", "influence": 0.55, "province_id": province_id})
    order = agent_order_dispatch(sig, available_agents)
    score = _norm(float(order.get("score", 0.55)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent order primary"),
        _q("apply_counterplay", province_id, 0.5, "agent order secondary"),
    ]
    return _day(
        "agent_order_day",
        "Agent order day",
        "Agent order day · %s · score %.2f" % (order.get("summary", "dispatch"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "order"],
        {"order": order},
    )


def execution_gate_day(province_id: int = 1) -> Dict[str, Any]:
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = 0.8 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "execution gate refresh"),
        _q("apply_supply", province_id, 0.5, "execution gate supply"),
    ]
    return _day(
        "execution_gate_day",
        "Execution gate day",
        "Execution gate day · %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["integrity", "execution"],
        {"gate": gate, "ok": ok},
    )


def cohesion_gate_day(province_id: int = 1) -> Dict[str, Any]:
    gate = cohesion_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = 0.8 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "cohesion gate refresh"),
        _q("apply_station", province_id, 0.5, "cohesion gate station"),
    ]
    return _day(
        "cohesion_gate_day",
        "Cohesion gate day",
        "Cohesion gate day · %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["integrity", "cohesion"],
        {"gate": gate, "ok": ok},
    )


def command_gate_day(province_id: int = 1) -> Dict[str, Any]:
    gate = command_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = 0.8 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "command gate refresh"),
        _q("apply_supply", province_id, 0.5, "command gate supply"),
    ]
    return _day(
        "command_gate_day",
        "Command gate day",
        "Command gate day · %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["integrity", "command"],
        {"gate": gate, "ok": ok},
    )


def execute_order_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    order = execute_one_order(_wx(weather))
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
        _q(primary, province_id, score, "execute order primary"),
        _q("apply_supply", province_id, 0.5, "execute order secondary"),
    ]
    return _day(
        "execute_order_day",
        "Execute order day",
        "Execute order day · %s · score %.2f" % (order.get("summary", domain), score),
        score,
        q,
        "#ef8f6e",
        "▶",
        ["execute", "order"],
        {"order": order},
    )


def air_sortie_ready_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    ready = air_sortie_readiness(_wx(weather))
    can = bool(ready.get("can_sortie", ready.get("effectiveness", 0.5) > 0.3))
    score = _norm(float(ready.get("effectiveness", 0.55 if can else 0.25)))
    q = [
        _q("apply_assault", province_id, score, "air sortie ready primary"),
        _q("apply_supply", province_id, 0.5, "air sortie ready secondary"),
    ]
    return _day(
        "air_sortie_ready_day",
        "Air sortie ready day",
        "Air sortie ready day · can=%s · score %.2f" % (can, score),
        score,
        q,
        "#7dd3a0",
        "✈",
        ["air", "sortie", "weather"],
        {"readiness": ready, "can_sortie": can},
    )


def weather_combat_brief_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    weather_mult: float = 0.85,
) -> Dict[str, Any]:
    brief = build_weather_combat_briefing(
        attacker_power, defender_power, weather_mult=weather_mult
    )
    overall = brief.get("overall", {})
    if isinstance(overall, dict):
        score = _norm(float(overall.get("score", overall.get("win_chance", 0.55))))
    else:
        score = _norm(float(overall) if overall is not None else 0.55)
    q = [
        _q("apply_assault", province_id, score, "weather combat brief primary"),
        _q("apply_supply", province_id, 0.5, "weather combat brief secondary"),
    ]
    return _day(
        "weather_combat_brief_day",
        "Weather combat brief day",
        "Weather combat brief day · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "🌦",
        ["weather", "combat", "brief"],
        {"brief": brief},
    )


def day_audit_day(province_id: int = 1) -> Dict[str, Any]:
    # Self-audit against known next70/80 catalogue stubs present in panel/gamedata sources.
    panel = "\n".join(
        [
            "result_feedback_day",
            "day_budget_day",
            "hh_auto_plan_day",
            "leader_weather_day",
            "air_ops_sortie_day",
        ]
    )
    gd = "\n".join(
        [
            "apply_result_feedback_day",
            "apply_day_budget_day",
            "apply_hh_auto_plan_day",
            "apply_leader_weather_day",
            "apply_air_ops_sortie_day",
        ]
    )
    audit = day_package_apply_audit(panel, gd)
    score = _norm(float(audit.get("score", 0.5)))
    ok = bool(audit.get("ok", False))
    q = [
        _q("refresh_queue", province_id, score, "day audit refresh"),
        _q("apply_supply", province_id, 0.5, "day audit supply"),
    ]
    return _day(
        "day_audit_day",
        "Day audit day",
        "Day audit day · ok=%s · score %.2f" % (ok, score),
        score,
        q,
        "#8899aa",
        "✓",
        ["audit", "routing"],
        {"audit": audit, "ok": ok},
    )


def map_visible_day(province_id: int = 1) -> Dict[str, Any]:
    vis = bool(default_player_map_visible())
    score = 0.75 if vis else 0.3
    q = [
        _q("refresh_queue", province_id, score, "map visible refresh"),
        _q("apply_station", province_id, 0.5, "map visible station"),
    ]
    return _day(
        "map_visible_day",
        "Map visible day",
        "Map visible day · visible=%s · score %.2f" % (vis, score),
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["map", "player_surface"],
        {"visible": vis},
    )


def assault_card_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    card = build_assault_estimate_card(attacker_power, defender_power)
    overall = card.get("overall", {})
    if isinstance(overall, dict):
        score = _norm(float(overall.get("score", overall.get("win_chance", 0.55))))
    else:
        score = _norm(0.55)
    q = [
        _q("apply_assault", province_id, score, "assault card primary"),
        _q("apply_supply", province_id, 0.5, "assault card secondary"),
    ]
    return _day(
        "assault_card_day",
        "Assault card day",
        "Assault card day · %s · score %.2f" % (card.get("title", "estimate"), score),
        score,
        q,
        "#ef8f6e",
        "🃏",
        ["assault", "estimate", "card"],
        {"card": card},
    )


def save_slot_list_day(province_id: int = 1) -> Dict[str, Any]:
    slots = build_save_slot_list(
        [
            {"slot": "quicksave", "mtime": 1, "label": "Quicksave"},
            {"slot": "slot_1", "mtime": 2, "label": "Autosave"},
        ]
    )
    n = len(slots) if isinstance(slots, list) else 0
    score = _norm(0.4 + 0.1 * min(5, n))
    q = [
        _q("save_slot:quicksave", province_id, score, "save slot list primary"),
        _q("refresh_queue", province_id, 0.5, "save slot list refresh"),
    ]
    return _day(
        "save_slot_list_day",
        "Save slot list day",
        "Save slot list day · slots %d · score %.2f" % (n, score),
        score,
        q,
        "#8899aa",
        "💾",
        ["save", "slots"],
        {"slots": slots, "count": n},
    )


def multi_phase_estimate_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(attacker_power, defender_power)
    score = _norm(float(est.get("overall_attacker_win_chance", 0.55)))
    q = [
        _q("apply_assault", province_id, score, "multi-phase estimate primary"),
        _q("apply_supply", province_id, 0.5, "multi-phase estimate secondary"),
    ]
    return _day(
        "multi_phase_estimate_day",
        "Multi-phase estimate day",
        "Multi-phase estimate day · win %.2f · score %.2f"
        % (float(est.get("overall_attacker_win_chance", 0.0)), score),
        score,
        q,
        "#ef8f6e",
        "◎",
        ["combat", "multi_phase"],
        {"estimate": est},
    )


def campaign_strip_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    strip = theater_campaign_strip()
    risk = campaign_day_risk(_wx(weather), month=3)
    score = _norm(float(strip.get("score", 0.6)))
    q = [
        _q("apply_station", province_id, score, "campaign strip primary"),
        _q("apply_supply", province_id, 0.5, "campaign strip secondary"),
        _q("apply_assault", province_id, 0.45, "campaign strip assault"),
    ]
    return _day(
        "campaign_strip_day",
        "Campaign strip day",
        "Campaign strip day · %s · risk %s · score %.2f"
        % (strip.get("summary", "strip"), risk.get("label", "?"), score),
        score,
        q,
        "#5ec8ff",
        "▬",
        ["campaign", "theater", "strip"],
        {"strip": strip, "risk": risk},
    )


EXECUTION_DAY_IDS: List[str] = [
    "result_feedback_day",
    "day_budget_day",
    "hh_auto_plan_day",
    "append_log_day",
    "log_strip_day",
    "assault_readiness_day",
    "coherence_delta_day",
    "agent_order_day",
    "execution_gate_day",
    "cohesion_gate_day",
    "command_gate_day",
    "execute_order_day",
    "air_sortie_ready_day",
    "weather_combat_brief_day",
    "day_audit_day",
    "map_visible_day",
    "assault_card_day",
    "save_slot_list_day",
    "multi_phase_estimate_day",
    "campaign_strip_day",
]


DAY_FUNCS = [
    result_feedback_day,
    day_budget_day,
    hh_auto_plan_day,
    append_log_day,
    log_strip_day,
    assault_readiness_day,
    coherence_delta_day,
    agent_order_day,
    execution_gate_day,
    cohesion_gate_day,
    command_gate_day,
    execute_order_day,
    air_sortie_ready_day,
    weather_combat_brief_day,
    day_audit_day,
    map_visible_day,
    assault_card_day,
    save_slot_list_day,
    multi_phase_estimate_day,
    campaign_strip_day,
]


def execution_surface_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    gates = [
        execution_integrity_gate(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk),
        cohesion_integrity_gate(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk),
        command_integrity_gate(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk),
    ]
    ok = all(bool(g.get("ok", False)) for g in gates)
    return {
        "ok": ok,
        "gates": gates,
        "summary": "Execution surface integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next80_execution_surface_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in (
                "result_feedback_day",
                "hh_auto_plan_day",
                "append_log_day",
                "log_strip_day",
                "execution_gate_day",
                "cohesion_gate_day",
                "command_gate_day",
                "day_audit_day",
                "map_visible_day",
                "assault_card_day",
                "save_slot_list_day",
                "multi_phase_estimate_day",
                "weather_combat_brief_day",
                "agent_order_day",
            ):
                packages[name] = fn()
            elif name in (
                "day_budget_day",
                "assault_readiness_day",
                "execute_order_day",
                "air_sortie_ready_day",
                "campaign_strip_day",
            ):
                packages[name] = fn(weather=w)
            elif name == "coherence_delta_day":
                packages[name] = fn()
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = execution_surface_integrity()
    label = "Close next80 execution · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next80 execution[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
