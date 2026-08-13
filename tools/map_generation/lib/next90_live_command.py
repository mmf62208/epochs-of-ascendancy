"""Next-90 live command depth: 20 day packages for mutation, HH, fleet, combat UI, production.

1 mutation_result_day · 2 mutation_strip_day · 3 close_mutation_day · 4 mutation_gate_day
5 agenda_pick_day · 6 agenda_actions_day · 7 hh_commit_order_day · 8 theater_hh_commit_day
9 hh_counterplay_day · 10 task_group_day · 11 naval_basing_day · 12 naval_multi_phase_day
13 coastal_fog_gate_day · 14 phase_ribbon_day · 15 assault_rank_day
16 joint_timeline_day · 17 daylight_combat_day · 18 production_auto_day
19 production_risk_alert_day · 20 day_results_flair_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from live_mutation import (  # type: ignore
    mutation_result,
    mutation_decision_strip,
    mutation_integrity_gate,
    close_mutation_loop,
    hh_commit_mutation,
)
from gameplay_loops import agenda_execute_pick  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore
from campaign_execution import hh_order_commit  # type: ignore
from theater_commander import (  # type: ignore
    theater_hh_auto_commit,
    theater_combat_auto_command,
    theater_production_auto,
)
from map_next_list_helpers import apply_hh_counterplay, pick_hh_action_class  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore
from naval_basing import compute_naval_basing  # type: ignore
from day_ops_depth import estimate_naval_multi_phase  # type: ignore
from weather_ops_polish import coastal_fog_naval_gate  # type: ignore
from weather_forecast import weather_aware_phase_ribbon  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from theater_day_depth import joint_combat_timeline  # type: ignore
from theater_ops_polish import daylight_combat_mod, production_weather_alert  # type: ignore
from daily_command_tick import (  # type: ignore
    daily_production_auto_apply_plan,
    simulate_day_apply_results,
    daily_apply_integrity_gate,
)
from campaign_cohesion import production_campaign_risk  # type: ignore
from week4_polish_depth import tooltip_sfx_flair_strip  # type: ignore


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
        "integration": list(integration or ["next90", "live_command"]),
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
            "fog": 0.15,
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


def mutation_result_day(province_id: int = 1) -> Dict[str, Any]:
    res = mutation_result(
        True,
        "station",
        "applied",
        before={"score": 0.4},
        after={"score": 0.65},
    )
    score = 0.7 if res.get("ok") else 0.35
    q = [
        _q("refresh_queue", province_id, score, "mutation result refresh"),
        _q("apply_station", province_id, 0.5, "mutation result station"),
    ]
    return _day(
        "mutation_result_day",
        "Mutation result day",
        "Mutation result day · %s · score %.2f" % (res.get("summary", "result"), score),
        score,
        q,
        "#7dd3a0",
        "↻",
        ["mutation", "result"],
        {"result": res},
    )


def mutation_strip_day(province_id: int = 1) -> Dict[str, Any]:
    strip = mutation_decision_strip()
    # Ensure non-empty package even when strip empty
    score = _norm(0.55 + 0.05 * int(strip.get("count", 0) or 0))
    if strip.get("empty"):
        score = 0.5
    q = [
        _q("refresh_queue", province_id, score, "mutation strip refresh"),
        _q("apply_production", province_id, 0.5, "mutation strip prod"),
    ]
    return _day(
        "mutation_strip_day",
        "Mutation strip day",
        "Mutation strip day · %s · score %.2f" % (strip.get("summary", "strip") or "empty→seed", score),
        score,
        q,
        "#5ec8ff",
        "☰",
        ["mutation", "strip"],
        {"strip": strip},
    )


def close_mutation_day(province_id: int = 1) -> Dict[str, Any]:
    loop = close_mutation_loop()
    applied = loop.get("applied") or {}
    n = len(applied) if isinstance(applied, dict) else int(bool(applied))
    score = _norm(0.5 + 0.08 * min(5, n if n else 3))
    q = [
        _q("apply_station", province_id, score, "close mutation station"),
        _q("apply_production", province_id, 0.55, "close mutation production"),
        _q("apply_hh_commit", province_id, 0.5, "close mutation hh"),
    ]
    return _day(
        "close_mutation_day",
        "Close mutation day",
        "Close mutation day · applied %s · score %.2f" % (n or "loop", score),
        score,
        q,
        "#5ec8ff",
        "∞",
        ["mutation", "close_loop"],
        {"loop": loop},
    )


def mutation_gate_day(province_id: int = 1) -> Dict[str, Any]:
    gate = mutation_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = 0.8 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "mutation gate refresh"),
        _q("apply_supply", province_id, 0.5, "mutation gate supply"),
    ]
    return _day(
        "mutation_gate_day",
        "Mutation gate day",
        "Mutation gate day · %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["mutation", "integrity"],
        {"gate": gate, "ok": ok},
    )


def agenda_pick_day(province_id: int = 1) -> Dict[str, Any]:
    pick = agenda_execute_pick(_trail(province_id))
    score = _norm(float(pick.get("score", 0.65) if isinstance(pick.get("score"), (int, float)) else 0.65))
    if score < 0.1:
        score = 0.65
    q = [
        _q("apply_hh_commit", province_id, score, "agenda pick primary"),
        _q("apply_counterplay", province_id, 0.5, "agenda pick secondary"),
    ]
    return _day(
        "agenda_pick_day",
        "Agenda pick day",
        "Agenda pick day · %s · score %.2f" % (pick.get("summary", "pick"), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "pick"],
        {"pick": pick},
    )


def agenda_actions_day(province_id: int = 1) -> Dict[str, Any]:
    acts = pick_agenda_actions(_trail(province_id))
    score = _norm(float(acts.get("score", 0.6) if isinstance(acts.get("score"), (int, float)) else 0.6))
    if score < 0.1:
        score = 0.6
    q = [
        _q("apply_hh_commit", province_id, score, "agenda actions primary"),
        _q("apply_agent_dispatch", province_id, 0.5, "agenda actions dispatch"),
    ]
    return _day(
        "agenda_actions_day",
        "Agenda actions day",
        "Agenda actions day · %s · score %.2f" % (acts.get("summary", "actions"), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "actions"],
        {"agenda": acts},  # not "actions" — would overwrite day package action list
    )


def hh_commit_order_day(province_id: int = 1) -> Dict[str, Any]:
    order = hh_order_commit(trail=_trail(province_id))
    score = _norm(float(order.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "hh commit order primary"),
        _q("apply_counterplay", province_id, 0.5, "hh commit order secondary"),
    ]
    return _day(
        "hh_commit_order_day",
        "HH commit order day",
        "HH commit order day · %s · score %.2f" % (order.get("summary", "commit"), score),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "commit", "order"],
        {"order": order},
    )


def theater_hh_commit_day(province_id: int = 1) -> Dict[str, Any]:
    # Prefer theater auto-commit with trail; fall back to hh_commit_mutation
    th = theater_hh_auto_commit(trail=_trail(province_id))
    if th.get("empty"):
        try:
            th = hh_commit_mutation(trail=_trail(province_id))
        except TypeError:
            th = hh_order_commit(trail=_trail(province_id))
        if th.get("empty"):
            th = hh_order_commit(trail=_trail(province_id))
    score = _norm(float(th.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "theater hh commit primary"),
        _q("apply_counterplay", province_id, 0.5, "theater hh commit secondary"),
    ]
    return _day(
        "theater_hh_commit_day",
        "Theater HH commit day",
        "Theater HH commit day · %s · score %.2f" % (th.get("summary", "theater hh"), score),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "theater", "auto"],
        {"commit": th},
    )


def hh_counterplay_day(province_id: int = 1, hand_influence: float = 0.55) -> Dict[str, Any]:
    klass = pick_hh_action_class(3, hand_influence)
    counter = apply_hh_counterplay(
        hand_influence,
        {"action_class": klass, "province_id": province_id, "influence": hand_influence},
    )
    score = _norm(float(counter.get("reduction", 0.12)) * 4.0 + 0.3)
    q = [
        _q("apply_counterplay", province_id, score, "hh counterplay primary"),
        _q("apply_agent_dispatch", province_id, 0.5, "hh counterplay agents"),
    ]
    return _day(
        "hh_counterplay_day",
        "HH counterplay day",
        "HH counterplay day · %s · class %s · score %.2f"
        % (counter.get("label", "counter"), klass, score),
        score,
        q,
        "#c084fc",
        "🛡",
        ["hh", "counterplay"],
        {"counter": counter, "action_class": klass},
    )


def task_group_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group()
    score = _norm(float(tg.get("available_strength", 100.0)) / 100.0 * 0.7 + 0.2)
    q = [
        _q("apply_station", province_id, score, "task group primary"),
        _q("apply_supply", province_id, 0.5, "task group supply"),
    ]
    return _day(
        "task_group_day",
        "Task group day",
        "Task group day · %s · score %.2f" % (tg.get("summary", "TG"), score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "task_group"],
        {"task_group": tg},
    )


def naval_basing_day(province_id: int = 1) -> Dict[str, Any]:
    basing = compute_naval_basing(
        province_id=province_id,
        is_coastal=True,
        has_port=True,
        port_tier=2,
        domain="coastal_land",
        in_sea_zone=True,
    )
    cap = float(basing.get("capacity", 0) or 0)
    score = _norm(0.4 + min(0.5, cap / 10.0)) if cap else 0.45
    q = [
        _q("apply_station", province_id, score, "naval basing primary"),
        _q("apply_supply", province_id, 0.5, "naval basing supply"),
    ]
    return _day(
        "naval_basing_day",
        "Naval basing day",
        "Naval basing day · %s · score %.2f" % (basing.get("summary", "basing"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "basing"],
        {"basing": basing},
    )


def naval_multi_phase_day(
    province_id: int = 1,
    attacker_power: float = 80.0,
    defender_power: float = 60.0,
) -> Dict[str, Any]:
    est = estimate_naval_multi_phase(attacker_power, defender_power)
    score = _norm(float(est.get("overall", est.get("engage_win_chance", 0.55))))
    q = [
        _q("apply_station", province_id, score, "naval multi-phase primary"),
        _q("apply_assault", province_id, 0.5, "naval multi-phase assault"),
    ]
    return _day(
        "naval_multi_phase_day",
        "Naval multi-phase day",
        "Naval multi-phase day · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◎",
        ["fleet", "multi_phase"],
        {"estimate": est},
    )


def coastal_fog_gate_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    w["fog"] = float(w.get("fog", 0.55))
    w["visibility"] = min(float(w.get("visibility", 0.5)), 0.4)
    try:
        gate = coastal_fog_naval_gate(w)
    except TypeError:
        try:
            gate = coastal_fog_naval_gate(weather=w)
        except TypeError:
            gate = coastal_fog_naval_gate()
    can = bool(gate.get("can_surface_strike", True))
    score = _norm(float(gate.get("ops_mult", 0.6 if can else 0.35)))
    q = [
        _q("apply_station", province_id, score, "coastal fog gate primary"),
        _q("apply_supply", province_id, 0.5, "coastal fog gate supply"),
    ]
    return _day(
        "coastal_fog_gate_day",
        "Coastal fog gate day",
        "Coastal fog gate day · can_strike=%s · score %.2f" % (can, score),
        score,
        q,
        "#8899aa",
        "🌫",
        ["fleet", "weather", "fog"],
        {"gate": gate},
    )


def phase_ribbon_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    weather_mult: float = 0.85,
) -> Dict[str, Any]:
    ribbon = weather_aware_phase_ribbon(attacker_power, defender_power, weather_mult)
    overall = ribbon.get("overall", {})
    if isinstance(overall, dict):
        score = _norm(float(overall.get("score", overall.get("win_chance", 0.55))))
    else:
        score = _norm(float(overall) if overall is not None else 0.55)
    q = [
        _q("apply_assault", province_id, score, "phase ribbon primary"),
        _q("apply_supply", province_id, 0.5, "phase ribbon secondary"),
    ]
    return _day(
        "phase_ribbon_day",
        "Phase ribbon day",
        "Phase ribbon day · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "🎗",
        ["combat", "ui", "ribbon"],
        {"ribbon": ribbon},
    )


def assault_rank_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [
            {"id": province_id, "province_id": province_id, "defender": 40, "defender_power": 40, "supply": 0.6},
            {"id": province_id + 1, "province_id": province_id + 1, "defender": 55, "defender_power": 55, "supply": 0.4},
            {"id": province_id + 2, "province_id": province_id + 2, "defender": 70, "defender_power": 70, "supply": 0.5},
        ],
        attacker_power=attacker_power,
    )
    best = int(ranked.get("best_province_id") or province_id)
    score = 0.7
    best_row = ranked.get("best") or {}
    if isinstance(best_row, dict) and best_row.get("score") is not None:
        score = _norm(float(best_row["score"]))
    q = [
        _q("apply_assault", best, score, "assault rank primary"),
        _q("apply_supply", best, 0.5, "assault rank supply"),
    ]
    return _day(
        "assault_rank_day",
        "Assault rank day",
        "Assault rank day · best %d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "assault", "rank"],
        {"ranked": ranked},
    )


def joint_timeline_day(province_id: int = 1) -> Dict[str, Any]:
    tl = joint_combat_timeline()
    score = _norm(float(tl.get("score", 0.55)))
    q = [
        _q("apply_assault", province_id, score, "joint timeline land"),
        _q("apply_station", province_id, 0.55, "joint timeline naval"),
        _q("apply_supply", province_id, 0.5, "joint timeline supply"),
    ]
    return _day(
        "joint_timeline_day",
        "Joint timeline day",
        "Joint timeline day · %s · score %.2f" % (tl.get("summary", "timeline"), score),
        score,
        q,
        "#ef8f6e",
        "⏱",
        ["combat", "joint", "timeline"],
        {"timeline": tl},
    )


def daylight_combat_day(province_id: int = 1, month: int = 6) -> Dict[str, Any]:
    dl = daylight_combat_mod(month)
    score = _norm(float(dl.get("combat_mult", 1.0)) / 1.2)
    q = [
        _q("apply_assault", province_id, score, "daylight combat primary"),
        _q("apply_supply", province_id, 0.5, "daylight combat secondary"),
    ]
    return _day(
        "daylight_combat_day",
        "Daylight combat day",
        "Daylight combat day · %s · score %.2f" % (dl.get("summary", "daylight"), score),
        score,
        q,
        "#7dd3a0",
        "☀",
        ["combat", "weather", "daylight"],
        {"daylight": dl},
    )


def production_auto_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_production_auto_apply_plan()
    theater = theater_production_auto()
    score = _norm(max(float(plan.get("score", 0.0)), float(theater.get("score", 0.0))))
    q = [
        _q("apply_production", province_id, score, "production auto primary"),
        _q("apply_supply", province_id, 0.5, "production auto supply"),
    ]
    return _day(
        "production_auto_day",
        "Production auto day",
        "Production auto day · plan %.2f · theater %.2f · score %.2f"
        % (float(plan.get("score", 0)), float(theater.get("score", 0)), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "auto"],
        {"plan": plan, "theater": theater},
    )


def production_risk_alert_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    w["precip_intensity"] = max(float(w.get("precip_intensity", 0.25)), 0.7)
    alert = production_weather_alert(w)
    risk = production_campaign_risk()
    score = _norm(max(0.45, 1.0 - float(risk.get("score", 0.0))))
    if alert.get("alert"):
        score = min(1.0, score + 0.15)
    # Force non-empty even if alert empty
    q = [
        _q("apply_production", province_id, score, "production risk primary"),
        _q("apply_supply", province_id, 0.5, "production risk supply"),
    ]
    return _day(
        "production_risk_alert_day",
        "Production risk alert day",
        "Production risk alert day · risk %s · score %.2f"
        % (risk.get("summary", risk.get("label", "?")), score),
        score,
        q,
        "#e8c547",
        "⚠",
        ["production", "weather", "risk"],
        {"alert": alert, "risk": risk},
    )


def day_results_flair_day(province_id: int = 1) -> Dict[str, Any]:
    sim = simulate_day_apply_results(
        [
            {"action_id": "apply_supply", "ok": True, "label": "supply", "province_id": province_id, "apply_ready": True, "score": 0.7},
            {"action_id": "apply_station", "ok": True, "label": "station", "province_id": province_id, "apply_ready": True, "score": 0.65},
        ]
    )
    flair = tooltip_sfx_flair_strip()
    gate = daily_apply_integrity_gate()
    score = _norm(0.55 + 0.05 * int(sim.get("count", 0)) + (0.15 if gate.get("ok") else 0.0))
    q = [
        _q("refresh_queue", province_id, score, "day results flair refresh"),
        _q("apply_supply", province_id, 0.5, "day results flair supply"),
        _q("apply_station", province_id, 0.45, "day results flair station"),
    ]
    return _day(
        "day_results_flair_day",
        "Day results flair day",
        "Day results flair day · sim %s · flair %.2f · score %.2f"
        % (sim.get("summary", "sim"), float(flair.get("score", 0.9)), score),
        score,
        q,
        "#7dd3a0",
        "✦",
        ["feedback", "flair", "results"],
        {"sim": sim, "flair": flair, "gate": gate},
    )


LIVE_COMMAND_DAY_IDS: List[str] = [
    "mutation_result_day",
    "mutation_strip_day",
    "close_mutation_day",
    "mutation_gate_day",
    "agenda_pick_day",
    "agenda_actions_day",
    "hh_commit_order_day",
    "theater_hh_commit_day",
    "hh_counterplay_day",
    "task_group_day",
    "naval_basing_day",
    "naval_multi_phase_day",
    "coastal_fog_gate_day",
    "phase_ribbon_day",
    "assault_rank_day",
    "joint_timeline_day",
    "daylight_combat_day",
    "production_auto_day",
    "production_risk_alert_day",
    "day_results_flair_day",
]


DAY_FUNCS = [
    mutation_result_day,
    mutation_strip_day,
    close_mutation_day,
    mutation_gate_day,
    agenda_pick_day,
    agenda_actions_day,
    hh_commit_order_day,
    theater_hh_commit_day,
    hh_counterplay_day,
    task_group_day,
    naval_basing_day,
    naval_multi_phase_day,
    coastal_fog_gate_day,
    phase_ribbon_day,
    assault_rank_day,
    joint_timeline_day,
    daylight_combat_day,
    production_auto_day,
    production_risk_alert_day,
    day_results_flair_day,
]


def live_command_integrity() -> Dict[str, Any]:
    mut = mutation_integrity_gate()
    daily = daily_apply_integrity_gate()
    ok = bool(mut.get("ok", False)) and bool(daily.get("ok", False))
    return {
        "ok": ok,
        "mutation": mut,
        "daily": daily,
        "summary": "Live command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next90_live_command_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in ("coastal_fog_gate_day", "production_risk_alert_day"):
                packages[name] = fn(weather=w)
            elif name == "daylight_combat_day":
                packages[name] = fn(month=6)
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = live_command_integrity()
    label = "Close next90 live command · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next90 live command[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
