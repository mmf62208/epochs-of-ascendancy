"""Next-110 incomplete play loops: 20 multi-system day packages.

Focus (post next-100 incomplete loops):
  A) Live mutation / order apply feedback (1–7)
  B) Multi-phase combat surface (8–14)
  C) Fleet + HH player path (15–20)

1 live_mut_board_day · 2 feedback_chain_day · 3 mut_close_stack_day
4 dual_domain_mutate_day · 5 assault_mut_fb_day · 6 agent_mut_log_day
7 supply_mut_fb_day · 8 combat_surface_stack_day · 9 phase_timeline_stack_day
10 assault_rank_card_day · 11 joint_naval_land_day · 12 multi_front_surface_day
13 combat_depth_strip_day · 14 phase_estimate_ribbon_day · 15 fleet_path_stack_day
16 basing_mission_day · 17 hh_path_stack_day · 18 hh_trail_counter_day
19 agent_mission_path_day · 20 incomplete_loop_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from live_mutation import (  # type: ignore
    mutation_decision_strip,
    mutation_integrity_gate,
    close_mutation_loop,
    assault_stage_mutation,
    fleet_station_mutation,
    production_priority_mutation,
    agent_dispatch_mutation,
    supply_route_mutation,
    next_day_mutation_feedback,
)
from daily_command_tick import (  # type: ignore
    apply_result_feedback,
    simulate_day_apply_results,
    append_command_log,
)
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from assault_estimate_card import build_assault_estimate_card  # type: ignore
from weather_forecast import weather_aware_phase_ribbon  # type: ignore
from theater_day_depth import joint_combat_timeline  # type: ignore
from day_ops_depth import estimate_naval_multi_phase  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from ops_depth import combat_phase_order_strip, combat_phase_depth  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore
from integrated_theater_ops import fleet_weather_mission_package  # type: ignore
from gameplay_loops import basing_fleet_fuel_logistics, agenda_execute_pick  # type: ignore
from naval_basing import basing_repair_refuel_rates  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore
from campaign_execution import hh_order_commit  # type: ignore
from map_next_list_helpers import apply_hh_counterplay  # type: ignore
from hh_agenda_trail import append_hh_agenda_trail  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from campaign_cohesion import agent_campaign_response  # type: ignore


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
        "integration": list(integration or ["next110", "incomplete_loops"]),
    }
    if extra:
        for k, v in extra.items():
            if k == "actions":
                continue
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
            "fog": 0.18,
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


# ---------------------------------------------------------------------------
# A) Live mutation / order apply feedback
# ---------------------------------------------------------------------------


def live_mut_board_day(province_id: int = 1) -> Dict[str, Any]:
    strip = mutation_decision_strip()
    gate = mutation_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = 0.75 if ok else 0.4
    if not strip.get("empty"):
        score = min(1.0, score + 0.1)
    q = [
        _q("refresh_queue", province_id, score, "live mut board refresh"),
        _q("apply_station", province_id, 0.55, "live mut board station"),
        _q("apply_production", province_id, 0.5, "live mut board production"),
    ]
    return _day(
        "live_mut_board_day",
        "Live mut board day",
        "Live mut board day · gate %s · strip %s · score %.2f"
        % ("PASS" if ok else "FAIL", strip.get("summary") or "seed", score),
        score,
        q,
        "#5ec8ff",
        "☰",
        ["mutation", "board", "integrity"],
        {"strip": strip, "gate": gate, "ok": ok},
    )


def feedback_chain_day(province_id: int = 1) -> Dict[str, Any]:
    fb = apply_result_feedback(0.42, 0.68, "combat")
    sim = simulate_day_apply_results(
        [
            {
                "action_id": "apply_assault",
                "ok": True,
                "apply_ready": True,
                "label": "assault",
                "province_id": province_id,
                "score": 0.68,
            },
            {
                "action_id": "apply_supply",
                "ok": True,
                "apply_ready": True,
                "label": "supply",
                "province_id": province_id,
                "score": 0.6,
            },
        ]
    )
    log = append_command_log(
        [],
        {"action_id": "apply_assault", "ok": True, "label": "assault", "province_id": province_id},
    )
    score = _norm(0.55 + 0.1 * int(sim.get("ok_count", 0)) + 0.05 * int(log.get("count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "feedback chain refresh"),
        _q("apply_assault", province_id, 0.6, "feedback chain assault"),
        _q("apply_supply", province_id, 0.5, "feedback chain supply"),
    ]
    return _day(
        "feedback_chain_day",
        "Feedback chain day",
        "Feedback chain day · %s · %s · score %.2f"
        % (fb.get("summary", "fb"), sim.get("summary", "sim"), score),
        score,
        q,
        "#7dd3a0",
        "↻",
        ["feedback", "apply", "log"],
        {"feedback": fb, "sim": sim, "log": log},
    )


def mut_close_stack_day(province_id: int = 1) -> Dict[str, Any]:
    loop = close_mutation_loop()
    fb = next_day_mutation_feedback()
    gate = mutation_integrity_gate()
    score = 0.7 if gate.get("ok") else 0.4
    q = [
        _q("apply_station", province_id, score, "mut close station"),
        _q("apply_production", province_id, 0.55, "mut close production"),
        _q("apply_hh_commit", province_id, 0.5, "mut close hh"),
    ]
    return _day(
        "mut_close_stack_day",
        "Mut close stack day",
        "Mut close stack day · %s · %s · score %.2f"
        % (loop.get("summary", "close"), fb.get("summary", "fb"), score),
        score,
        q,
        "#5ec8ff",
        "∞",
        ["mutation", "close", "feedback"],
        {"loop": loop, "feedback": fb, "gate": gate},
    )


def dual_domain_mutate_day(province_id: int = 1) -> Dict[str, Any]:
    fleet = fleet_station_mutation()
    prod = production_priority_mutation()
    score = _norm(
        0.5 * float(fleet.get("score", 0.5)) + 0.5 * float(prod.get("score", 0.5))
    )
    q = [
        _q("apply_station", province_id, float(fleet.get("score", score)), "dual mutate station"),
        _q("apply_production", province_id, float(prod.get("score", score)), "dual mutate production"),
        _q("apply_supply", province_id, 0.5, "dual mutate supply"),
    ]
    return _day(
        "dual_domain_mutate_day",
        "Dual domain mutate day",
        "Dual domain mutate day · fleet %.2f · prod %.2f · score %.2f"
        % (float(fleet.get("score", 0)), float(prod.get("score", 0)), score),
        score,
        q,
        "#e8c547",
        "⇄",
        ["mutation", "fleet", "production"],
        {"fleet": fleet, "production": prod},
    )


def assault_mut_fb_day(province_id: int = 1) -> Dict[str, Any]:
    mut = assault_stage_mutation()
    before = float(mut.get("score", 0.4))
    after = min(1.0, before + 0.15)
    fb = apply_result_feedback(before, after, "assault")
    score = _norm(after)
    q = [
        _q("apply_assault", province_id, score, "assault mut fb primary"),
        _q("apply_supply", province_id, 0.5, "assault mut fb supply"),
    ]
    return _day(
        "assault_mut_fb_day",
        "Assault mut fb day",
        "Assault mut fb day · %s · %s · score %.2f"
        % (mut.get("summary", "mut"), fb.get("summary", "fb"), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["assault", "mutation", "feedback"],
        {"mutation": mut, "feedback": fb},
    )


def agent_mut_log_day(province_id: int = 1) -> Dict[str, Any]:
    mut = agent_dispatch_mutation()
    log = append_command_log(
        [],
        {
            "action_id": "apply_agent_dispatch",
            "ok": True,
            "label": "agent dispatch",
            "province_id": province_id,
            "score": float(mut.get("score", 0.55)),
        },
    )
    score = _norm(float(mut.get("score", 0.55)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent mut log primary"),
        _q("apply_counterplay", province_id, 0.5, "agent mut log counter"),
    ]
    return _day(
        "agent_mut_log_day",
        "Agent mut log day",
        "Agent mut log day · %s · log %s · score %.2f"
        % (mut.get("summary", "mut"), log.get("summary", "log"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "mutation", "log"],
        {"mutation": mut, "log": log},
    )


def supply_mut_fb_day(province_id: int = 1) -> Dict[str, Any]:
    mut = supply_route_mutation()
    fb = next_day_mutation_feedback()
    score = _norm(float(mut.get("score", 0.55)))
    q = [
        _q("apply_supply", province_id, score, "supply mut fb primary"),
        _q("apply_station", province_id, 0.5, "supply mut fb station"),
    ]
    return _day(
        "supply_mut_fb_day",
        "Supply mut fb day",
        "Supply mut fb day · %s · %s · score %.2f"
        % (mut.get("summary", "mut"), fb.get("summary", "fb"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "mutation", "feedback"],
        {"mutation": mut, "feedback": fb},
    )


# ---------------------------------------------------------------------------
# B) Multi-phase combat surface
# ---------------------------------------------------------------------------


def combat_surface_stack_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(attacker_power, defender_power)
    card = build_assault_estimate_card(attacker_power, defender_power)
    ribbon = weather_aware_phase_ribbon(attacker_power, defender_power, 0.85)
    score = _norm(float(est.get("overall_attacker_win_chance", 0.53)))
    q = [
        _q("apply_assault", province_id, score, "combat surface stack primary"),
        _q("apply_supply", province_id, 0.5, "combat surface stack supply"),
    ]
    return _day(
        "combat_surface_stack_day",
        "Combat surface stack day",
        "Combat surface stack day · win %.2f · card · ribbon · score %.2f"
        % (float(est.get("overall_attacker_win_chance", 0)), score),
        score,
        q,
        "#ef8f6e",
        "◎",
        ["combat", "multi_phase", "surface"],
        {"estimate": est, "card": card, "ribbon": ribbon},
    )


def phase_timeline_stack_day(province_id: int = 1) -> Dict[str, Any]:
    ribbon = weather_aware_phase_ribbon(100.0, 80.0, 0.85)
    timeline = joint_combat_timeline()
    score = _norm(float(timeline.get("score", 0.55)))
    q = [
        _q("apply_assault", province_id, score, "phase timeline land"),
        _q("apply_station", province_id, 0.55, "phase timeline naval"),
        _q("apply_supply", province_id, 0.5, "phase timeline supply"),
    ]
    return _day(
        "phase_timeline_stack_day",
        "Phase timeline stack day",
        "Phase timeline stack day · %s · score %.2f"
        % (timeline.get("summary", "timeline"), score),
        score,
        q,
        "#ef8f6e",
        "⏱",
        ["combat", "phase", "timeline"],
        {"ribbon": ribbon, "timeline": timeline},
    )


def assault_rank_card_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [
            {"id": province_id, "defender": 40, "defender_power": 40},
            {"id": province_id + 1, "defender": 55, "defender_power": 55},
            {"id": province_id + 2, "defender": 70, "defender_power": 70},
        ],
        attacker_power=attacker_power,
    )
    best = int(ranked.get("best_province_id") or province_id)
    card = build_assault_estimate_card(attacker_power, 55.0)
    score = 0.65
    best_row = ranked.get("best") or {}
    if isinstance(best_row, dict) and best_row.get("score") is not None:
        score = _norm(float(best_row["score"]))
    q = [
        _q("apply_assault", best, score, "assault rank card primary"),
        _q("apply_supply", best, 0.5, "assault rank card supply"),
    ]
    return _day(
        "assault_rank_card_day",
        "Assault rank card day",
        "Assault rank card day · best %d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "🃏",
        ["assault", "rank", "card"],
        {"ranked": ranked, "card": card},
    )


def joint_naval_land_day(
    province_id: int = 1,
    attacker_power: float = 90.0,
    defender_power: float = 70.0,
) -> Dict[str, Any]:
    land = estimate_multi_phase_combat(attacker_power, defender_power)
    naval = estimate_naval_multi_phase(attacker_power * 0.85, defender_power * 0.8)
    land_s = float(land.get("overall_attacker_win_chance", 0.5))
    naval_s = float(naval.get("overall", naval.get("engage_win_chance", 0.55)))
    score = _norm(0.55 * land_s + 0.45 * naval_s)
    q = [
        _q("apply_assault", province_id, land_s, "joint naval land assault"),
        _q("apply_station", province_id, naval_s, "joint naval land station"),
        _q("apply_supply", province_id, 0.5, "joint naval land supply"),
    ]
    return _day(
        "joint_naval_land_day",
        "Joint naval land day",
        "Joint naval land day · land %.2f · naval %.2f · score %.2f"
        % (land_s, naval_s, score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["combat", "naval", "joint"],
        {"land": land, "naval": naval},
    )


def multi_front_surface_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [
            {"id": province_id, "defender": 45},
            {"id": province_id + 1, "defender": 50},
            {"id": province_id + 2, "defender": 60},
        ],
        attacker_power=attacker_power,
    )
    est = estimate_multi_phase_combat(attacker_power, 55.0)
    ribbon = weather_aware_phase_ribbon(attacker_power, 55.0, 0.88)
    best = int(ranked.get("best_province_id") or province_id)
    score = _norm(float(est.get("overall_attacker_win_chance", 0.55)))
    q = [
        _q("apply_assault", best, score, "multi front surface primary"),
        _q("apply_assault", max(1, best + 1), 0.5, "multi front surface secondary"),
        _q("apply_supply", best, 0.45, "multi front surface supply"),
    ]
    return _day(
        "multi_front_surface_day",
        "Multi front surface day",
        "Multi front surface day · best %d · win %.2f · score %.2f"
        % (best, float(est.get("overall_attacker_win_chance", 0)), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["assault", "multi_front", "surface"],
        {"ranked": ranked, "estimate": est, "ribbon": ribbon},
    )


def combat_depth_strip_day(province_id: int = 1) -> Dict[str, Any]:
    depth = combat_phase_depth()
    strip = combat_phase_order_strip()
    score = _norm(
        max(float(depth.get("score", 0.45)), float(strip.get("score", 0.45)))
    )
    q = [
        _q("apply_assault", province_id, score, "combat depth strip primary"),
        _q("apply_supply", province_id, 0.5, "combat depth strip supply"),
    ]
    return _day(
        "combat_depth_strip_day",
        "Combat depth strip day",
        "Combat depth strip day · depth %.2f · strip %.2f · score %.2f"
        % (float(depth.get("score", 0)), float(strip.get("score", 0)), score),
        score,
        q,
        "#ef8f6e",
        "▬",
        ["combat", "phase", "strip"],
        {"depth": depth, "strip": strip},
    )


def phase_estimate_ribbon_day(
    province_id: int = 1,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    weather_mult: float = 0.85,
) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(attacker_power, defender_power)
    ribbon = weather_aware_phase_ribbon(attacker_power, defender_power, weather_mult)
    score = _norm(float(est.get("overall_attacker_win_chance", 0.53)))
    q = [
        _q("apply_assault", province_id, score, "phase estimate ribbon primary"),
        _q("apply_supply", province_id, 0.5, "phase estimate ribbon supply"),
    ]
    return _day(
        "phase_estimate_ribbon_day",
        "Phase estimate ribbon day",
        "Phase estimate ribbon day · win %.2f · wx×%.2f · score %.2f"
        % (float(est.get("overall_attacker_win_chance", 0)), weather_mult, score),
        score,
        q,
        "#ef8f6e",
        "🎗",
        ["combat", "estimate", "ribbon"],
        {"estimate": est, "ribbon": ribbon},
    )


# ---------------------------------------------------------------------------
# C) Fleet + HH player path
# ---------------------------------------------------------------------------


def fleet_path_stack_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group()
    mission = fleet_weather_mission_package()
    fuel = basing_fleet_fuel_logistics()
    score = _norm(
        0.4
        + 0.2 * (0 if tg.get("empty") else 1)
        + 0.2 * (0 if mission.get("empty") else 1)
        + 0.2 * float(fuel.get("fuel_level", 0.5) or 0.5)
    )
    q = [
        _q("apply_station", province_id, score, "fleet path stack primary"),
        _q("apply_supply", province_id, 0.55, "fleet path stack supply"),
    ]
    return _day(
        "fleet_path_stack_day",
        "Fleet path stack day",
        "Fleet path stack day · TG · mission · fuel · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["fleet", "path", "stack"],
        {"task_group": tg, "mission": mission, "fuel": fuel},
    )


def basing_mission_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    rates = basing_repair_refuel_rates(level="port")
    mission = fleet_weather_mission_package()
    score = _norm(float(fuel.get("logistics_score", fuel.get("fuel_level", 0.5)) or 0.5))
    if score < 0.25:
        score = 0.55  # basing logistics often low; keep package actionable
    q = [
        _q("apply_station", province_id, score, "basing mission primary"),
        _q("apply_supply", province_id, 0.5, "basing mission supply"),
    ]
    return _day(
        "basing_mission_day",
        "Basing mission day",
        "Basing mission day · %s · rates · score %.2f"
        % (fuel.get("summary", "fuel"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["basing", "fleet", "mission"],
        {"fuel": fuel, "rates": rates, "mission": mission},
    )


def hh_path_stack_day(province_id: int = 1) -> Dict[str, Any]:
    trail = _trail(province_id)
    pick = agenda_execute_pick(trail)
    acts = pick_agenda_actions(trail)
    order = hh_order_commit(trail=trail)
    score = _norm(float(order.get("score", 0.7)))
    q = [
        _q("apply_hh_commit", province_id, score, "hh path stack primary"),
        _q("apply_counterplay", province_id, 0.5, "hh path stack counter"),
        _q("apply_agent_dispatch", province_id, 0.45, "hh path stack agents"),
    ]
    return _day(
        "hh_path_stack_day",
        "HH path stack day",
        "HH path stack day · pick · actions · commit %.2f · score %.2f"
        % (float(order.get("score", 0)), score),
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "path"],
        {"pick": pick, "agenda": acts, "order": order},
    )


def hh_trail_counter_day(province_id: int = 1, hand_influence: float = 0.55) -> Dict[str, Any]:
    trail = append_hh_agenda_trail(
        [],
        {
            "action_class": "sabotage",
            "province_id": province_id,
            "influence": hand_influence,
            "year": 1936,
            "month": 3,
        },
    )
    counter = apply_hh_counterplay(
        hand_influence,
        {"action_class": "sabotage", "province_id": province_id, "influence": hand_influence},
    )
    n = len(trail) if isinstance(trail, list) else 1
    red = float(counter.get("reduction", 0.12) or 0.12)
    score = _norm(0.5 + 0.1 * n + red)
    q = [
        _q("apply_hh_commit", province_id, score, "hh trail counter primary"),
        _q("apply_counterplay", province_id, 0.6, "hh trail counter secondary"),
    ]
    return _day(
        "hh_trail_counter_day",
        "HH trail counter day",
        "HH trail counter day · trail %d · %s · score %.2f"
        % (n, counter.get("label", "counter"), score),
        score,
        q,
        "#c084fc",
        "🛡",
        ["hh", "trail", "counterplay"],
        {"trail": trail, "counter": counter},
    )


def agent_mission_path_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    resp = agent_campaign_response(
        signal={"action_class": "sabotage", "influence": 0.55, "province_id": province_id},
        available_agents=5,
    )
    score = _norm(
        max(float(missions.get("best_score", 0.5) or 0.5), float(resp.get("score", 0.5)))
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent mission path primary"),
        _q("apply_counterplay", province_id, 0.5, "agent mission path counter"),
        _q("apply_hh_commit", province_id, 0.45, "agent mission path hh"),
    ]
    return _day(
        "agent_mission_path_day",
        "Agent mission path day",
        "Agent mission path day · %s · %s · score %.2f"
        % (missions.get("summary", "missions"), resp.get("summary", "resp"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "mission", "path"],
        {"missions": missions, "response": resp},
    )


def incomplete_loop_close_day(province_id: int = 1) -> Dict[str, Any]:
    """Close package: mutation integrity + combat surface score + HH commit + fleet TG."""
    gate = mutation_integrity_gate()
    est = estimate_multi_phase_combat(100.0, 80.0)
    hh = hh_order_commit(trail=_trail(province_id))
    tg = compose_task_group()
    fb = apply_result_feedback(0.5, 0.7, "command")
    ok = bool(gate.get("ok", False))
    score = _norm(
        (0.8 if ok else 0.35)
        * 0.4
        + 0.2 * float(est.get("overall_attacker_win_chance", 0.5))
        + 0.2 * float(hh.get("score", 0.5))
        + 0.2 * (0.7 if not tg.get("empty") else 0.3)
    )
    q = [
        _q("apply_assault", province_id, score, "incomplete loop assault"),
        _q("apply_station", province_id, 0.55, "incomplete loop station"),
        _q("apply_hh_commit", province_id, 0.5, "incomplete loop hh"),
        _q("apply_supply", province_id, 0.45, "incomplete loop supply"),
    ]
    return _day(
        "incomplete_loop_close_day",
        "Incomplete loop close day",
        "Incomplete loop close day · mut %s · combat · HH · fleet · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["close", "mutation", "combat", "hh", "fleet"],
        {"gate": gate, "estimate": est, "hh": hh, "task_group": tg, "feedback": fb, "ok": ok},
    )


INCOMPLETE_LOOP_DAY_IDS: List[str] = [
    "live_mut_board_day",
    "feedback_chain_day",
    "mut_close_stack_day",
    "dual_domain_mutate_day",
    "assault_mut_fb_day",
    "agent_mut_log_day",
    "supply_mut_fb_day",
    "combat_surface_stack_day",
    "phase_timeline_stack_day",
    "assault_rank_card_day",
    "joint_naval_land_day",
    "multi_front_surface_day",
    "combat_depth_strip_day",
    "phase_estimate_ribbon_day",
    "fleet_path_stack_day",
    "basing_mission_day",
    "hh_path_stack_day",
    "hh_trail_counter_day",
    "agent_mission_path_day",
    "incomplete_loop_close_day",
]


DAY_FUNCS = [
    live_mut_board_day,
    feedback_chain_day,
    mut_close_stack_day,
    dual_domain_mutate_day,
    assault_mut_fb_day,
    agent_mut_log_day,
    supply_mut_fb_day,
    combat_surface_stack_day,
    phase_timeline_stack_day,
    assault_rank_card_day,
    joint_naval_land_day,
    multi_front_surface_day,
    combat_depth_strip_day,
    phase_estimate_ribbon_day,
    fleet_path_stack_day,
    basing_mission_day,
    hh_path_stack_day,
    hh_trail_counter_day,
    agent_mission_path_day,
    incomplete_loop_close_day,
]


def incomplete_loop_integrity() -> Dict[str, Any]:
    mut = mutation_integrity_gate()
    est = estimate_multi_phase_combat(100.0, 80.0)
    hh = hh_order_commit(trail=_trail(1))
    tg = compose_task_group()
    ok = (
        bool(mut.get("ok", False))
        and not bool(est.get("empty", False))
        and not bool(hh.get("empty", False))
        and not bool(tg.get("empty", False))
    )
    return {
        "ok": ok,
        "mutation": mut,
        "combat_win": float(est.get("overall_attacker_win_chance", 0)),
        "hh_score": float(hh.get("score", 0)),
        "fleet_empty": bool(tg.get("empty", False)),
        "summary": "Incomplete-loop integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next110_incomplete_loops_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    _ = _wx(weather)
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        try:
            packages[fn.__name__] = fn()
        except TypeError:
            packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = incomplete_loop_integrity()
    label = "Close next110 incomplete loops · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next110 incomplete loops[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
