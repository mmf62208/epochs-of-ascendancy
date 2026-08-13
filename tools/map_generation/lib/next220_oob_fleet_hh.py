"""Next-220 medium-horizon OOB/equip · fleet multi-theater/redeploy · HH agenda (20 packages).

A) Medium-horizon OOB / equip honesty (1–7)
B) Fleet multi-theater / redeploy (8–14)
C) HH agenda depth (15–20)

1 equip_horizon_depth_day · 2 stockpile_line_ops_day · 3 oob_line_continuity_day
4 factory_oob_depth_day · 5 medium_horizon_plan_day · 6 equip_stockpile_joint_day
7 equip_oob_close_day · 8 fleet_multi_theater_ops_day · 9 fleet_redeploy_ops_day
10 task_group_posture_ops_day · 11 fleet_posture_ops_day · 12 redeploy_route_ops_day
13 fleet_theater_joint_day · 14 fleet_redeploy_close_day · 15 hh_monthly_ops_day
16 hh_quarterly_ops_day · 17 agenda_pulse_ops_day · 18 trail_counterplay_ops_day
19 hh_agenda_depth_joint_day · 20 oob_fleet_hh_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from gameplay_loops import oob_factory_risk_loop, sole_mult_integrity  # type: ignore
from campaign_ops_depth import fleet_multi_theater_day  # type: ignore
from fleet_campaign_day import fleet_redeploy_day  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore
from fleet_redeploy_route import plan_fleet_redeploy_routes  # type: ignore
from next60_command_depth import hh_monthly_day  # type: ignore
from next70_playability_depth import hh_quarterly_day  # type: ignore
from campaign_cohesion import hh_campaign_board  # type: ignore
from campaign_execution import hh_order_commit, execution_integrity_gate, close_the_loop  # type: ignore
from map_next_list_helpers import apply_hh_counterplay  # type: ignore
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
        "integration": list(integration or ["next220", "oob_fleet_hh"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _trail(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"action_class": "sabotage", "influence": 0.6, "province_id": province_id, "month": 3},
        {"action_class": "intel", "influence": 0.45, "province_id": province_id + 1, "month": 3},
        {"action_class": "network", "influence": 0.5, "province_id": province_id, "month": 2},
    ]


def _theaters(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {
            "theater_id": "home",
            "province_ids": [province_id, province_id + 1],
            "fuel_level": 0.7,
            "basing_level": "port",
            "zone_relation": "friendly",
        },
        {
            "theater_id": "forward",
            "province_ids": [province_id + 2],
            "fuel_level": 0.55,
            "basing_level": "anchorage",
            "zone_relation": "contested",
        },
    ]


# A) Medium-horizon OOB / equip


def equip_horizon_depth_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan(days_horizon=60, factories=14, tank_line_progress=0.2)
    score = _norm(float(equip.get("score", 0.55)))
    q = [
        _q("apply_production", province_id, score, "equip horizon depth primary"),
        _q("apply_supply", province_id, 0.5, "equip horizon depth supply"),
    ]
    return _day(
        "equip_horizon_depth_day",
        "Equip horizon depth day",
        "Equip horizon depth · %s · score %.2f" % (equip.get("summary", "horizon"), score),
        score,
        q,
        "#e8c547",
        "🛡",
        ["oob", "equip", "horizon"],
        {"equip": equip, "equip_score": score, "horizon_days": int(equip.get("days_horizon", 60))},
    )


def stockpile_line_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation()
    equip = medium_horizon_equip_plan(tank_stock=0.0, tank_line_progress=0.12)
    score = _norm(
        0.55 * float(mut.get("score", 0.5)) + 0.45 * float(equip.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "stockpile line primary"),
        _q("apply_supply", province_id, 0.55, "stockpile line supply"),
    ]
    return _day(
        "stockpile_line_ops_day",
        "Stockpile line ops day",
        "Stockpile line · priority · equip · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "📦",
        ["oob", "stockpile", "line"],
        {"mutation": mut, "equip": equip, "equip_score": score},
    )


def oob_line_continuity_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    loop = oob_factory_risk_loop()
    score = _norm(
        0.5 * float(equip.get("score", 0.55))
        + 0.5 * float(loop.get("effective_output", loop.get("score", 0.7)))
    )
    q = [
        _q("apply_production", province_id, score, "oob line continuity production"),
        _q("apply_supply", province_id, 0.55, "oob line continuity supply"),
        _q("apply_station", province_id, 0.45, "oob line continuity station"),
    ]
    return _day(
        "oob_line_continuity_day",
        "OOB line continuity day",
        "OOB line continuity · equip · factory · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "∞",
        ["oob", "line", "continuity"],
        {"equip": equip, "loop": loop, "equip_score": score},
    )


def factory_oob_depth_day(province_id: int = 1) -> Dict[str, Any]:
    loop = oob_factory_risk_loop()
    mut = production_priority_mutation()
    score = _norm(
        0.55 * float(loop.get("effective_output", 0.7))
        + 0.45 * float(mut.get("score", 0.5))
    )
    q = [
        _q("apply_production", province_id, score, "factory oob depth primary"),
        _q("apply_supply", province_id, 0.5, "factory oob depth supply"),
    ]
    return _day(
        "factory_oob_depth_day",
        "Factory OOB depth day",
        "Factory OOB depth · risk · priority · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏭",
        ["oob", "factory", "depth"],
        {"loop": loop, "mutation": mut},
    )


def medium_horizon_plan_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan(days_horizon=90, factories=16, tank_line_progress=0.25)
    score = _norm(float(equip.get("score", 0.55)))
    q = [
        _q("apply_production", province_id, score, "medium horizon plan primary"),
        _q("apply_supply", province_id, 0.5, "medium horizon plan supply"),
        _q("apply_focus", province_id, 0.45, "medium horizon plan focus"),
    ]
    return _day(
        "medium_horizon_plan_day",
        "Medium horizon plan day",
        "Medium horizon plan · %dd · score %.2f"
        % (int(equip.get("days_horizon", 90)), score),
        score,
        q,
        "#e8c547",
        "📅",
        ["oob", "equip", "plan"],
        {
            "equip": equip,
            "equip_score": score,
            "horizon_days": int(equip.get("days_horizon", 90)),
            "will_complete_tank": bool(equip.get("will_complete_tank", False)),
        },
    )


def equip_stockpile_joint_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    mut = production_priority_mutation()
    loop = oob_factory_risk_loop()
    score = _norm(
        0.4 * float(equip.get("score", 0.5))
        + 0.3 * float(mut.get("score", 0.5))
        + 0.3 * float(loop.get("effective_output", 0.6))
    )
    q = [
        _q("apply_production", province_id, score, "equip stockpile joint production"),
        _q("apply_supply", province_id, 0.55, "equip stockpile joint supply"),
        _q("apply_station", province_id, 0.45, "equip stockpile joint station"),
    ]
    return _day(
        "equip_stockpile_joint_day",
        "Equip stockpile joint day",
        "Equip stockpile joint · horizon · line · factory · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "◈",
        ["oob", "equip", "joint"],
        {"equip": equip, "mutation": mut, "loop": loop, "equip_score": score},
    )


def equip_oob_close_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    loop = oob_factory_risk_loop()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(equip.get("score", 0.5))
        + 0.35 * float(loop.get("effective_output", 0.6))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, score, "equip oob close production"),
        _q("apply_supply", province_id, 0.55, "equip oob close supply"),
        _q("apply_station", province_id, 0.45, "equip oob close station"),
    ]
    return _day(
        "equip_oob_close_day",
        "Equip OOB close day",
        "Equip OOB close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["oob", "equip", "close"],
        {"equip": equip, "loop": loop, "gate": gate, "ok": ok, "equip_score": score},
    )


# B) Fleet multi-theater / redeploy


def fleet_multi_theater_ops_day(province_id: int = 1) -> Dict[str, Any]:
    multi = fleet_multi_theater_day(_theaters(province_id), country_tag="ENG")
    score = _norm(float(multi.get("score", 0.6)) if not multi.get("empty") else 0.4)
    if score < 0.2:
        score = 0.6
    q = [
        _q("apply_station", province_id, score, "fleet multi theater station"),
        _q("apply_supply", province_id, 0.55, "fleet multi theater supply"),
        _q("apply_assault", province_id, 0.4, "fleet multi theater assault"),
    ]
    return _day(
        "fleet_multi_theater_ops_day",
        "Fleet multi theater ops day",
        "Fleet multi-theater · %s · score %.2f" % (multi.get("summary", "multi"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "multi_theater", "ops"],
        {"multi": multi, "fleet_score": score},
    )


def fleet_redeploy_ops_day(province_id: int = 1) -> Dict[str, Any]:
    redeploy = fleet_redeploy_day(province_id=province_id, fuel_level=0.65)
    score = _norm(float(redeploy.get("score", 0.55)))
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "fleet redeploy station"),
        _q("apply_supply", province_id, 0.5, "fleet redeploy supply"),
    ]
    return _day(
        "fleet_redeploy_ops_day",
        "Fleet redeploy ops day",
        "Fleet redeploy · %s · score %.2f" % (redeploy.get("summary", "redeploy"), score),
        score,
        q,
        "#5ec8ff",
        "↗",
        ["fleet", "redeploy", "ops"],
        {"redeploy": redeploy, "fleet_score": score},
    )


def task_group_posture_ops_day(province_id: int = 1) -> Dict[str, Any]:
    tg = compose_task_group(
        available_strength=100.0, mission="patrol", zone_relation="contested", escort_need=10.0
    )
    # Task group has no score; derive from allocation completeness.
    score = 0.62 if not bool(tg.get("empty", False)) else 0.35
    score = _norm(score)
    q = [
        _q("apply_station", province_id, score, "task group posture station"),
        _q("apply_supply", province_id, 0.5, "task group posture supply"),
    ]
    return _day(
        "task_group_posture_ops_day",
        "Task group posture ops day",
        "Task group posture · %s · score %.2f" % (tg.get("summary", "tg"), score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["fleet", "task_group", "posture"],
        {"task_group": tg, "fleet_score": score},
    )


def fleet_posture_ops_day(province_id: int = 1) -> Dict[str, Any]:
    multi = fleet_multi_theater_day(_theaters(province_id))
    redeploy = fleet_redeploy_day(province_id=province_id)
    score = _norm(
        0.5 * float(multi.get("score", 0.55) if not multi.get("empty") else 0.4)
        + 0.5 * float(redeploy.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "fleet posture station"),
        _q("apply_supply", province_id, 0.55, "fleet posture supply"),
        _q("apply_assault", province_id, 0.4, "fleet posture assault"),
    ]
    return _day(
        "fleet_posture_ops_day",
        "Fleet posture ops day",
        "Fleet posture · multi · redeploy · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◆",
        ["fleet", "posture", "ops"],
        {"multi": multi, "redeploy": redeploy, "fleet_score": score},
    )


def redeploy_route_ops_day(province_id: int = 1) -> Dict[str, Any]:
    cands = [
        {
            "province_id": province_id,
            "basing_level": "port",
            "fuel_level": 0.7,
            "path_hostile_segments": 0,
            "path_length": 2,
            "zone_relation": "friendly",
            "origin_basing": "anchorage",
        },
        {
            "province_id": province_id + 1,
            "basing_level": "major_base",
            "fuel_level": 0.6,
            "path_hostile_segments": 1,
            "path_length": 3,
            "zone_relation": "contested",
            "origin_basing": "anchorage",
        },
    ]
    try:
        routes = plan_fleet_redeploy_routes(cands, fuel_level=0.7, origin_basing="anchorage")
    except TypeError:
        routes = plan_fleet_redeploy_routes(cands)  # type: ignore
    raw = float(routes.get("best_score", routes.get("score", 55.0)) or 55.0)
    score = _norm(raw if raw <= 2.0 else raw / 100.0)
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "redeploy route station"),
        _q("apply_supply", province_id, 0.5, "redeploy route supply"),
    ]
    return _day(
        "redeploy_route_ops_day",
        "Redeploy route ops day",
        "Redeploy route · %s · score %.2f" % (routes.get("summary", "routes"), score),
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["fleet", "redeploy", "route"],
        {"routes": routes, "fleet_score": score},
    )


def fleet_theater_joint_day(province_id: int = 1) -> Dict[str, Any]:
    multi = fleet_multi_theater_day(_theaters(province_id))
    redeploy = fleet_redeploy_day(province_id=province_id)
    tg = compose_task_group(
        available_strength=90.0, mission="strike", zone_relation="hostile", escort_need=20.0
    )
    tg_score = 0.62 if not bool(tg.get("empty", False)) else 0.35
    score = _norm(
        0.4 * float(multi.get("score", 0.55) if not multi.get("empty") else 0.4)
        + 0.3 * float(redeploy.get("score", 0.55))
        + 0.3 * tg_score
    )
    q = [
        _q("apply_station", province_id, score, "fleet theater joint station"),
        _q("apply_supply", province_id, 0.55, "fleet theater joint supply"),
        _q("apply_assault", province_id, 0.4, "fleet theater joint assault"),
    ]
    return _day(
        "fleet_theater_joint_day",
        "Fleet theater joint day",
        "Fleet theater joint · multi · redeploy · tg · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◈",
        ["fleet", "theater", "joint"],
        {"multi": multi, "redeploy": redeploy, "task_group": tg, "fleet_score": score},
    )


def fleet_redeploy_close_day(province_id: int = 1) -> Dict[str, Any]:
    multi = fleet_multi_theater_day(_theaters(province_id))
    redeploy = fleet_redeploy_day(province_id=province_id)
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(multi.get("score", 0.55) if not multi.get("empty") else 0.4)
        + 0.35 * float(redeploy.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "fleet redeploy close station"),
        _q("apply_supply", province_id, 0.55, "fleet redeploy close supply"),
        _q("apply_assault", province_id, 0.4, "fleet redeploy close assault"),
    ]
    return _day(
        "fleet_redeploy_close_day",
        "Fleet redeploy close day",
        "Fleet redeploy close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["fleet", "redeploy", "close"],
        {"multi": multi, "redeploy": redeploy, "gate": gate, "ok": ok, "fleet_score": score},
    )


# C) HH agenda depth


def hh_monthly_ops_day(province_id: int = 1) -> Dict[str, Any]:
    monthly = hh_monthly_day(trail=_trail(province_id), province_id=province_id)
    score = _norm(float(monthly.get("score", 0.55)))
    if monthly.get("empty"):
        score = 0.45
    q = [
        _q("apply_hh_commit", province_id, score, "hh monthly ops commit"),
        _q("apply_counterplay", province_id, 0.5, "hh monthly ops counter"),
    ]
    return _day(
        "hh_monthly_ops_day",
        "HH monthly ops day",
        "HH monthly · %s · score %.2f" % (monthly.get("summary", "monthly"), score),
        score,
        q,
        "#c084fc",
        "📅",
        ["hh", "monthly", "ops"],
        {"monthly": monthly, "hh_score": score},
    )


def hh_quarterly_ops_day(province_id: int = 1) -> Dict[str, Any]:
    quarterly = hh_quarterly_day(trail=_trail(province_id), province_id=province_id)
    score = _norm(float(quarterly.get("score", 0.58)))
    if quarterly.get("empty"):
        score = 0.45
    q = [
        _q("apply_hh_commit", province_id, score, "hh quarterly ops commit"),
        _q("apply_counterplay", province_id, 0.5, "hh quarterly ops counter"),
        _q("apply_agent_dispatch", province_id, 0.45, "hh quarterly ops agents"),
    ]
    return _day(
        "hh_quarterly_ops_day",
        "HH quarterly ops day",
        "HH quarterly · %s · score %.2f" % (quarterly.get("summary", "quarterly"), score),
        score,
        q,
        "#c084fc",
        "📊",
        ["hh", "quarterly", "ops"],
        {"quarterly": quarterly, "hh_score": score},
    )


def agenda_pulse_ops_day(province_id: int = 1) -> Dict[str, Any]:
    board = hh_campaign_board(_trail(province_id))
    commit = hh_order_commit(_trail(province_id))
    score = _norm(
        0.5 * (0.65 if not bool(board.get("empty", True)) else 0.35)
        + 0.5 * float(commit.get("score", 0.55) if not commit.get("empty") else 0.4)
    )
    q = [
        _q("apply_hh_commit", province_id, score, "agenda pulse commit"),
        _q("apply_agent_dispatch", province_id, 0.55, "agenda pulse agents"),
    ]
    return _day(
        "agenda_pulse_ops_day",
        "Agenda pulse ops day",
        "Agenda pulse · board · commit · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["hh", "agenda", "pulse"],
        {"board": board, "commit": commit, "hh_score": score},
    )


def trail_counterplay_ops_day(province_id: int = 1) -> Dict[str, Any]:
    counter = apply_hh_counterplay(0.55, {"action_class": "sabotage", "influence": 0.55, "province_id": province_id})
    board = hh_campaign_board(_trail(province_id))
    score = _norm(
        0.55
        + float(counter.get("reduction", 0.12) or 0.12) * 0.5
        + 0.1 * (0.2 if not bool(board.get("empty", True)) else 0.0)
    )
    q = [
        _q("apply_counterplay", province_id, score, "trail counterplay primary"),
        _q("apply_hh_commit", province_id, 0.5, "trail counterplay commit"),
        _q("apply_agent_dispatch", province_id, 0.45, "trail counterplay agents"),
    ]
    return _day(
        "trail_counterplay_ops_day",
        "Trail counterplay ops day",
        "Trail counterplay · reduction · board · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🛡",
        ["hh", "trail", "counterplay"],
        {"counter": counter, "board": board, "hh_score": score},
    )


def hh_agenda_depth_joint_day(province_id: int = 1) -> Dict[str, Any]:
    monthly = hh_monthly_day(trail=_trail(province_id), province_id=province_id)
    quarterly = hh_quarterly_day(trail=_trail(province_id), province_id=province_id)
    board = hh_campaign_board(_trail(province_id))
    score = _norm(
        0.35 * float(monthly.get("score", 0.55))
        + 0.35 * float(quarterly.get("score", 0.58))
        + 0.3 * (0.65 if not bool(board.get("empty", True)) else 0.35)
    )
    q = [
        _q("apply_hh_commit", province_id, score, "hh agenda depth joint commit"),
        _q("apply_counterplay", province_id, 0.55, "hh agenda depth joint counter"),
        _q("apply_agent_dispatch", province_id, 0.5, "hh agenda depth joint agents"),
    ]
    return _day(
        "hh_agenda_depth_joint_day",
        "HH agenda depth joint day",
        "HH agenda depth joint · monthly · quarterly · board · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "agenda", "joint"],
        {"monthly": monthly, "quarterly": quarterly, "board": board, "hh_score": score},
    )


def oob_fleet_hh_close_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    multi = fleet_multi_theater_day(_theaters(province_id))
    board = hh_campaign_board(_trail(province_id))
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(equip.get("score", 0.5))
        + 0.25 * float(multi.get("score", 0.55) if not multi.get("empty") else 0.4)
        + 0.25 * (0.65 if not bool(board.get("empty", True)) else 0.35)
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "close equip production"),
        _q("apply_station", province_id, float(multi.get("score", 0.55) if not multi.get("empty") else 0.5), "close fleet station"),
        _q("apply_hh_commit", province_id, 0.55, "close hh commit"),
        _q("apply_counterplay", province_id, 0.45, "close counterplay"),
    ]
    return _day(
        "oob_fleet_hh_close_day",
        "OOB fleet HH close day",
        "OOB fleet HH close · equip · fleet · agenda · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["oob", "fleet", "hh", "close"],
        {
            "equip": equip,
            "multi": multi,
            "board": board,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


OOB_FLEET_HH_DAY_IDS: List[str] = [
    "equip_horizon_depth_day",
    "stockpile_line_ops_day",
    "oob_line_continuity_day",
    "factory_oob_depth_day",
    "medium_horizon_plan_day",
    "equip_stockpile_joint_day",
    "equip_oob_close_day",
    "fleet_multi_theater_ops_day",
    "fleet_redeploy_ops_day",
    "task_group_posture_ops_day",
    "fleet_posture_ops_day",
    "redeploy_route_ops_day",
    "fleet_theater_joint_day",
    "fleet_redeploy_close_day",
    "hh_monthly_ops_day",
    "hh_quarterly_ops_day",
    "agenda_pulse_ops_day",
    "trail_counterplay_ops_day",
    "hh_agenda_depth_joint_day",
    "oob_fleet_hh_close_day",
]


DAY_FUNCS = [
    equip_horizon_depth_day,
    stockpile_line_ops_day,
    oob_line_continuity_day,
    factory_oob_depth_day,
    medium_horizon_plan_day,
    equip_stockpile_joint_day,
    equip_oob_close_day,
    fleet_multi_theater_ops_day,
    fleet_redeploy_ops_day,
    task_group_posture_ops_day,
    fleet_posture_ops_day,
    redeploy_route_ops_day,
    fleet_theater_joint_day,
    fleet_redeploy_close_day,
    hh_monthly_ops_day,
    hh_quarterly_ops_day,
    agenda_pulse_ops_day,
    trail_counterplay_ops_day,
    hh_agenda_depth_joint_day,
    oob_fleet_hh_close_day,
]


def oob_fleet_hh_integrity() -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    multi = fleet_multi_theater_day(_theaters(1))
    board = hh_campaign_board(_trail(1))
    gate = execution_integrity_gate()
    ok = (
        not bool(equip.get("empty", False))
        and float(equip.get("score", 0)) > 0.0
        and not bool(multi.get("empty", True))
        and bool(board is not None)
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "equip_score": float(equip.get("score", 0)),
        "fleet_score": float(multi.get("score", 0) if not multi.get("empty") else 0),
        "hh_board": str(board.get("summary", board.get("plain", "")))[:80],
        "gate": gate,
        "summary": "OOB-fleet-HH integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next220_oob_fleet_hh_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = oob_fleet_hh_integrity()
    label = "Close next220 oob-fleet-hh · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next220 oob-fleet-hh[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
