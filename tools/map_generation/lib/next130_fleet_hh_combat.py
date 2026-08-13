"""Next-130 fleet AI / HH agenda / combat inspector loops (20 packages).

A) Fleet AI / naval ops (1–7)
B) HH agenda / agent path (8–14)
C) Combat multi-phase / inspector surface (15–20)

1 fleet_ai_task_day · 2 fleet_wx_ops_day · 3 basing_fuel_ops_day · 4 naval_phase_ops_day
5 coastal_fog_ops_day · 6 fleet_station_mut_day · 7 naval_task_mut_day
8 hh_agenda_pick_day · 9 hh_agenda_actions_day · 10 hh_order_path_day
11 theater_hh_path_day · 12 hh_trail_ops_day · 13 agent_mission_ops_day
14 agent_campaign_ops_day · 15 combat_inspect_stack_day · 16 phase_ribbon_inspect_day
17 joint_timeline_inspect_day · 18 assault_rank_inspect_day · 19 combat_campaign_ops_day
20 fleet_hh_combat_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from fleet_task_group import compose_task_group  # type: ignore
from integrated_theater_ops import fleet_weather_mission_package  # type: ignore
from gameplay_loops import basing_fleet_fuel_logistics, agenda_execute_pick  # type: ignore
from naval_basing import basing_repair_refuel_rates, compute_naval_basing  # type: ignore
from day_ops_depth import estimate_naval_multi_phase  # type: ignore
from weather_ops_polish import coastal_fog_naval_gate  # type: ignore
from live_mutation import fleet_station_mutation, naval_task_mutation  # type: ignore
from campaign_execution import hh_order_commit  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore
from hh_agenda_trail import append_hh_agenda_trail  # type: ignore
from map_next_list_helpers import apply_hh_counterplay, pick_hh_secondary_action_class  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from campaign_cohesion import agent_campaign_response, combat_campaign_phase  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from assault_estimate_card import build_assault_estimate_card  # type: ignore
from weather_forecast import weather_aware_phase_ribbon  # type: ignore
from theater_day_depth import joint_combat_timeline  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from ops_depth import combat_phase_depth, combat_phase_order_strip  # type: ignore
from theater_commander import theater_hh_auto_commit, theater_combat_auto_command  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from campaign_execution import execution_integrity_gate  # type: ignore


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
        "integration": list(integration or ["next130", "fleet_hh_combat"]),
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
            "visibility": 0.72,
            "precip_intensity": 0.28,
            "ground_state": "mud",
            "temp": 9.0,
            "sea_state": 0.35,
            "fog": 0.35,
        }
    )


def _trail(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {
            "action": "commit",
            "action_class": "influence",
            "score": 0.72,
            "province_id": province_id,
            "influence": 0.55,
            "year": 1936,
            "month": 3,
        }
    ]


# A) Fleet AI / naval ops


def fleet_ai_task_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group()
    mut = fleet_station_mutation()
    score = _norm(0.5 * (0.7 if not tg.get("empty") else 0.3) + 0.5 * float(mut.get("score", 0.45)))
    q = [
        _q("apply_station", province_id, score, "fleet ai task primary"),
        _q("apply_supply", province_id, 0.5, "fleet ai task supply"),
    ]
    return _day(
        "fleet_ai_task_day",
        "Fleet AI task day",
        "Fleet AI task day · TG+station mut · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "ai", "task_group"],
        {"task_group": tg, "mutation": mut},
    )


def fleet_wx_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = fleet_weather_mission_package()
    tg = compose_task_group()
    score = 0.7 if not pkg.get("empty") else 0.45
    q = [
        _q("apply_station", province_id, score, "fleet wx ops primary"),
        _q("apply_supply", province_id, 0.5, "fleet wx ops supply"),
    ]
    return _day(
        "fleet_wx_ops_day",
        "Fleet wx ops day",
        "Fleet wx ops day · %s · score %.2f" % (pkg.get("summary", "fleet+wx"), score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "weather", "ops"],
        {"package": pkg, "task_group": tg},
    )


def basing_fuel_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    rates = basing_repair_refuel_rates(level="port")
    basing = compute_naval_basing(
        province_id=province_id,
        is_coastal=True,
        has_port=True,
        port_tier=2,
        domain="coastal_land",
        in_sea_zone=True,
    )
    score = _norm(float(fuel.get("logistics_score", fuel.get("fuel_level", 0.5)) or 0.5))
    if score < 0.3:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "basing fuel ops primary"),
        _q("apply_supply", province_id, 0.55, "basing fuel ops supply"),
    ]
    return _day(
        "basing_fuel_ops_day",
        "Basing fuel ops day",
        "Basing fuel ops day · %s · score %.2f" % (fuel.get("summary", "fuel"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["basing", "fuel", "fleet"],
        {"fuel": fuel, "rates": rates, "basing": basing},
    )


def naval_phase_ops_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_naval_multi_phase(85.0, 65.0)
    score = _norm(float(est.get("overall", est.get("score", 0.6))))
    q = [
        _q("apply_station", province_id, score, "naval phase ops primary"),
        _q("apply_assault", province_id, 0.5, "naval phase ops assault"),
    ]
    return _day(
        "naval_phase_ops_day",
        "Naval phase ops day",
        "Naval phase ops day · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◎",
        ["naval", "multi_phase", "ops"],
        {"estimate": est},
    )


def coastal_fog_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    w["fog"] = max(float(w.get("fog", 0.35)), 0.45)
    w["visibility"] = min(float(w.get("visibility", 0.5)), 0.45)
    try:
        gate = coastal_fog_naval_gate(w)
    except TypeError:
        gate = coastal_fog_naval_gate(weather=w)
    score = _norm(float(gate.get("ops_mult", 0.6)))
    q = [
        _q("apply_station", province_id, score, "coastal fog ops primary"),
        _q("apply_supply", province_id, 0.5, "coastal fog ops supply"),
    ]
    return _day(
        "coastal_fog_ops_day",
        "Coastal fog ops day",
        "Coastal fog ops day · %s · score %.2f" % (gate.get("summary", "fog"), score),
        score,
        q,
        "#8899aa",
        "🌫",
        ["fleet", "fog", "weather"],
        {"gate": gate},
    )


def fleet_station_mut_day(province_id: int = 1) -> Dict[str, Any]:
    mut = fleet_station_mutation()
    score = _norm(float(mut.get("score", 0.45)))
    q = [
        _q("apply_station", province_id, score, "fleet station mut primary"),
        _q("apply_supply", province_id, 0.5, "fleet station mut supply"),
    ]
    return _day(
        "fleet_station_mut_day",
        "Fleet station mut day",
        "Fleet station mut day · %s · score %.2f" % (mut.get("summary", "mut"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "mutation", "station"],
        {"mutation": mut},
    )


def naval_task_mut_day(province_id: int = 1) -> Dict[str, Any]:
    mut = naval_task_mutation()
    score = _norm(float(mut.get("score", 0.47)))
    q = [
        _q("apply_station", province_id, score, "naval task mut primary"),
        _q("apply_supply", province_id, 0.5, "naval task mut supply"),
    ]
    return _day(
        "naval_task_mut_day",
        "Naval task mut day",
        "Naval task mut day · %s · score %.2f" % (mut.get("summary", "mut"), score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["naval", "mutation", "task"],
        {"mutation": mut},
    )


# B) HH / agent path


def hh_agenda_pick_day(province_id: int = 1) -> Dict[str, Any]:
    pick = agenda_execute_pick(_trail(province_id))
    score = _norm(float(pick.get("score", 0.65) if isinstance(pick.get("score"), (int, float)) else 0.65))
    if score < 0.2:
        score = 0.65
    q = [
        _q("apply_hh_commit", province_id, score, "hh agenda pick primary"),
        _q("apply_counterplay", province_id, 0.5, "hh agenda pick counter"),
    ]
    return _day(
        "hh_agenda_pick_day",
        "HH agenda pick day",
        "HH agenda pick day · %s · score %.2f" % (pick.get("summary", "pick"), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "pick"],
        {"pick": pick},
    )


def hh_agenda_actions_day(province_id: int = 1) -> Dict[str, Any]:
    acts = pick_agenda_actions(_trail(province_id))
    score = 0.6
    q = [
        _q("apply_hh_commit", province_id, score, "hh agenda actions primary"),
        _q("apply_agent_dispatch", province_id, 0.5, "hh agenda actions agents"),
    ]
    return _day(
        "hh_agenda_actions_day",
        "HH agenda actions day",
        "HH agenda actions day · %s · score %.2f" % (acts.get("summary", "actions"), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "actions"],
        {"agenda": acts},
    )


def hh_order_path_day(province_id: int = 1) -> Dict[str, Any]:
    order = hh_order_commit(trail=_trail(province_id))
    score = _norm(float(order.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "hh order path primary"),
        _q("apply_counterplay", province_id, 0.5, "hh order path counter"),
        _q("apply_agent_dispatch", province_id, 0.45, "hh order path agents"),
    ]
    return _day(
        "hh_order_path_day",
        "HH order path day",
        "HH order path day · %s · score %.2f" % (order.get("summary", "commit"), score),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "order", "path"],
        {"order": order},
    )


def theater_hh_path_day(province_id: int = 1) -> Dict[str, Any]:
    th = theater_hh_auto_commit(trail=_trail(province_id))
    if th.get("empty"):
        th = hh_order_commit(trail=_trail(province_id))
    score = _norm(float(th.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "theater hh path primary"),
        _q("apply_counterplay", province_id, 0.5, "theater hh path counter"),
    ]
    return _day(
        "theater_hh_path_day",
        "Theater HH path day",
        "Theater HH path day · %s · score %.2f" % (th.get("summary", "theater hh"), score),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "theater", "auto"],
        {"commit": th},
    )


def hh_trail_ops_day(province_id: int = 1) -> Dict[str, Any]:
    primary = "sabotage"
    secondary = pick_hh_secondary_action_class(3, 0.55, primary)
    trail = append_hh_agenda_trail(
        [],
        {
            "action_class": primary,
            "province_id": province_id,
            "influence": 0.55,
            "year": 1936,
            "month": 3,
        },
    )
    counter = apply_hh_counterplay(
        0.55, {"action_class": primary, "province_id": province_id, "influence": 0.55}
    )
    n = len(trail) if isinstance(trail, list) else 1
    score = _norm(0.5 + 0.1 * n + float(counter.get("reduction", 0.12) or 0.12))
    q = [
        _q("apply_hh_commit", province_id, score, "hh trail ops primary"),
        _q("apply_counterplay", province_id, 0.6, "hh trail ops counter"),
    ]
    return _day(
        "hh_trail_ops_day",
        "HH trail ops day",
        "HH trail ops day · %s→%s · trail %d · score %.2f" % (primary, secondary, n, score),
        score,
        q,
        "#c084fc",
        "🛡",
        ["hh", "trail", "counterplay"],
        {"trail": trail, "counter": counter, "secondary": secondary},
    )


def agent_mission_ops_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    score = _norm(float(missions.get("best_score", 0.7) or 0.7))
    if score > 1.0:
        score = _norm(score / 100.0)
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent mission ops primary"),
        _q("apply_counterplay", province_id, 0.5, "agent mission ops counter"),
    ]
    return _day(
        "agent_mission_ops_day",
        "Agent mission ops day",
        "Agent mission ops day · %s · score %.2f" % (missions.get("summary", "missions"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "mission", "ops"],
        {"missions": missions},
    )


def agent_campaign_ops_day(province_id: int = 1) -> Dict[str, Any]:
    resp = agent_campaign_response(
        signal={"action_class": "sabotage", "influence": 0.55, "province_id": province_id},
        available_agents=5,
    )
    score = _norm(float(resp.get("score", 0.55)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent campaign ops primary"),
        _q("apply_counterplay", province_id, 0.55, "agent campaign ops counter"),
        _q("apply_hh_commit", province_id, 0.45, "agent campaign ops hh"),
    ]
    return _day(
        "agent_campaign_ops_day",
        "Agent campaign ops day",
        "Agent campaign ops day · %s · score %.2f" % (resp.get("summary", "agents"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "campaign", "ops"],
        {"response": resp},
    )


# C) Combat multi-phase / inspector


def combat_inspect_stack_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    card = build_assault_estimate_card(100.0, 80.0)
    ribbon = weather_aware_phase_ribbon(100.0, 80.0, 0.85)
    score = _norm(float(est.get("overall_attacker_win_chance", 0.53)))
    q = [
        _q("apply_assault", province_id, score, "combat inspect stack primary"),
        _q("apply_supply", province_id, 0.5, "combat inspect stack supply"),
    ]
    return _day(
        "combat_inspect_stack_day",
        "Combat inspect stack day",
        "Combat inspect stack day · win %.2f · card+ribbon · score %.2f"
        % (float(est.get("overall_attacker_win_chance", 0)), score),
        score,
        q,
        "#ef8f6e",
        "◎",
        ["combat", "inspector", "multi_phase"],
        {"estimate": est, "card": card, "ribbon": ribbon},
    )


def phase_ribbon_inspect_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    ribbon = weather_aware_phase_ribbon(100.0, 80.0, 0.85)
    depth = combat_phase_depth()
    score = _norm(
        max(
            float(est.get("overall_attacker_win_chance", 0.5)),
            float(depth.get("score", 0.45)),
        )
    )
    q = [
        _q("apply_assault", province_id, score, "phase ribbon inspect primary"),
        _q("apply_supply", province_id, 0.5, "phase ribbon inspect supply"),
    ]
    return _day(
        "phase_ribbon_inspect_day",
        "Phase ribbon inspect day",
        "Phase ribbon inspect day · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "🎗",
        ["combat", "ribbon", "inspector"],
        {"estimate": est, "ribbon": ribbon, "depth": depth},
    )


def joint_timeline_inspect_day(province_id: int = 1) -> Dict[str, Any]:
    tl = joint_combat_timeline()
    strip = combat_phase_order_strip()
    score = _norm(max(float(tl.get("score", 0.55)), float(strip.get("score", 0.45))))
    q = [
        _q("apply_assault", province_id, score, "joint timeline inspect land"),
        _q("apply_station", province_id, 0.55, "joint timeline inspect naval"),
        _q("apply_supply", province_id, 0.5, "joint timeline inspect supply"),
    ]
    return _day(
        "joint_timeline_inspect_day",
        "Joint timeline inspect day",
        "Joint timeline inspect day · %s · score %.2f" % (tl.get("summary", "timeline"), score),
        score,
        q,
        "#ef8f6e",
        "⏱",
        ["combat", "timeline", "inspector"],
        {"timeline": tl, "strip": strip},
    )


def assault_rank_inspect_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [
            {"id": province_id, "defender": 40},
            {"id": province_id + 1, "defender": 55},
            {"id": province_id + 2, "defender": 70},
        ],
        attacker_power=100.0,
    )
    card = build_assault_estimate_card(100.0, 55.0)
    best = int(ranked.get("best_province_id") or province_id)
    score = 0.65
    best_row = ranked.get("best") or {}
    if isinstance(best_row, dict) and best_row.get("score") is not None:
        score = _norm(float(best_row["score"]))
    q = [
        _q("apply_assault", best, score, "assault rank inspect primary"),
        _q("apply_supply", best, 0.5, "assault rank inspect supply"),
    ]
    return _day(
        "assault_rank_inspect_day",
        "Assault rank inspect day",
        "Assault rank inspect day · best %d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "🃏",
        ["assault", "rank", "inspector"],
        {"ranked": ranked, "card": card},
    )


def combat_campaign_ops_day(province_id: int = 1) -> Dict[str, Any]:
    phase = combat_campaign_phase()
    auto = theater_combat_auto_command()
    score = _norm(
        max(float(phase.get("score", 0.35)), float(auto.get("score", 0.35)))
    )
    q = [
        _q("apply_assault", province_id, score, "combat campaign ops primary"),
        _q("apply_supply", province_id, 0.5, "combat campaign ops supply"),
        _q("apply_station", province_id, 0.45, "combat campaign ops station"),
    ]
    return _day(
        "combat_campaign_ops_day",
        "Combat campaign ops day",
        "Combat campaign ops day · phase %.2f · auto %.2f · score %.2f"
        % (float(phase.get("score", 0)), float(auto.get("score", 0)), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "campaign", "ops"],
        {"phase": phase, "auto": auto},
    )


def fleet_hh_combat_close_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group()
    hh = hh_order_commit(trail=_trail(province_id))
    est = estimate_multi_phase_combat(100.0, 80.0)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * (0.7 if not tg.get("empty") else 0.3)
        + 0.25 * float(hh.get("score", 0.5))
        + 0.25 * float(est.get("overall_attacker_win_chance", 0.5))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, 0.55, "fleet hh combat close station"),
        _q("apply_hh_commit", province_id, float(hh.get("score", 0.6)), "fleet hh combat close hh"),
        _q("apply_assault", province_id, float(est.get("overall_attacker_win_chance", 0.5)), "fleet hh combat close assault"),
        _q("apply_supply", province_id, 0.45, "fleet hh combat close supply"),
    ]
    return _day(
        "fleet_hh_combat_close_day",
        "Fleet HH combat close day",
        "Fleet HH combat close day · fleet · HH · combat · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["fleet", "hh", "combat", "close"],
        {"task_group": tg, "hh": hh, "estimate": est, "gate": gate, "sole": sole, "ok": ok},
    )


FLEET_HH_COMBAT_DAY_IDS: List[str] = [
    "fleet_ai_task_day",
    "fleet_wx_ops_day",
    "basing_fuel_ops_day",
    "naval_phase_ops_day",
    "coastal_fog_ops_day",
    "fleet_station_mut_day",
    "naval_task_mut_day",
    "hh_agenda_pick_day",
    "hh_agenda_actions_day",
    "hh_order_path_day",
    "theater_hh_path_day",
    "hh_trail_ops_day",
    "agent_mission_ops_day",
    "agent_campaign_ops_day",
    "combat_inspect_stack_day",
    "phase_ribbon_inspect_day",
    "joint_timeline_inspect_day",
    "assault_rank_inspect_day",
    "combat_campaign_ops_day",
    "fleet_hh_combat_close_day",
]


DAY_FUNCS = [
    fleet_ai_task_day,
    fleet_wx_ops_day,
    basing_fuel_ops_day,
    naval_phase_ops_day,
    coastal_fog_ops_day,
    fleet_station_mut_day,
    naval_task_mut_day,
    hh_agenda_pick_day,
    hh_agenda_actions_day,
    hh_order_path_day,
    theater_hh_path_day,
    hh_trail_ops_day,
    agent_mission_ops_day,
    agent_campaign_ops_day,
    combat_inspect_stack_day,
    phase_ribbon_inspect_day,
    joint_timeline_inspect_day,
    assault_rank_inspect_day,
    combat_campaign_ops_day,
    fleet_hh_combat_close_day,
]


def fleet_hh_combat_integrity() -> Dict[str, Any]:
    tg = compose_task_group()
    hh = hh_order_commit(trail=_trail(1))
    est = estimate_multi_phase_combat(100.0, 80.0)
    gate = execution_integrity_gate()
    ok = (
        not bool(tg.get("empty", False))
        and not bool(hh.get("empty", False))
        and not bool(est.get("empty", False))
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "fleet_empty": bool(tg.get("empty", False)),
        "hh_score": float(hh.get("score", 0)),
        "combat_win": float(est.get("overall_attacker_win_chance", 0)),
        "gate": gate,
        "summary": "Fleet-HH-combat integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next130_fleet_hh_combat_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name == "coastal_fog_ops_day":
                packages[name] = fn(weather=w)
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = fleet_hh_combat_integrity()
    label = "Close next130 fleet-HH-combat · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next130 fleet-HH-combat[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
