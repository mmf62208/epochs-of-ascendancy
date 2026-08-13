"""Next-160 theater campaign, naval/sealane sustain, player session (20 packages).

A) Theater campaign continuity (1–7)
B) Naval / sealane sustain (8–14)
C) Player decision / session path (15–20)

1 multi_province_campaign_day · 2 theater_auto_campaign_day · 3 daily_command_ops_day
4 theater_readiness_ops_day · 5 move_path_campaign_day · 6 theater_order_board_day
7 theater_campaign_close_day · 8 basing_fleet_sustain_day · 9 fleet_wx_sustain_day
10 convoy_sustain_ops_day · 11 sealane_joint_ops_day · 12 naval_order_ops_day
13 fleet_station_sustain_day · 14 naval_sealane_close_day · 15 player_surface_session_day
16 order_panel_session_day · 17 mutation_feedback_ops_day · 18 apply_audit_session_day
19 decision_strip_ops_day · 20 theater_naval_session_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from daily_command_tick import (  # type: ignore
    multi_province_day_plan,
    daily_theater_auto_tick,
    theater_day_report,
    format_command_log_surface,
    daily_apply_integrity_gate,
)
from force_readiness_day import theater_readiness_day  # type: ignore
from integrated_theater_ops import (  # type: ignore
    theater_readiness_board,
    convoy_package_compose,
    fleet_weather_mission_package,
)
from gameplay_loops import (  # type: ignore
    basing_fleet_fuel_logistics,
    move_path_ops_loop,
    sealane_joint_health,
    basing_repair_weather_loop,
    sole_mult_integrity,
)
from campaign_cohesion import (  # type: ignore
    theater_campaign_strip,
    naval_campaign_package,
    campaign_decision_strip,
)
from campaign_execution import (  # type: ignore
    theater_order_board,
    naval_order_package,
    fleet_order_execute,
    execution_decision_strip,
    execution_integrity_gate,
    close_the_loop,
)
from live_mutation import (  # type: ignore
    fleet_station_mutation,
    next_day_mutation_feedback,
    theater_mutation_board,
    supply_route_mutation,
    production_priority_mutation,
)
from theater_commander import player_order_surface_strip  # type: ignore
from ops_depth import order_panel_actions  # type: ignore
from week2_core_polish import day_package_apply_audit  # type: ignore


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
        "integration": list(integration or ["next160", "theater_naval_session"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _zones() -> List[str]:
    return ["friendly", "contested", "hostile"]


# A) Theater campaign continuity


def multi_province_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = multi_province_day_plan([province_id, province_id + 1, province_id + 2])
    score = _norm(float(ranked.get("score", 0.7)))
    q = [
        _q("apply_supply", province_id, score, "multi province campaign supply"),
        _q("apply_station", province_id, 0.55, "multi province campaign station"),
        _q("apply_assault", province_id, 0.45, "multi province campaign assault"),
    ]
    return _day(
        "multi_province_campaign_day",
        "Multi province campaign day",
        "Multi province campaign · ranked %d · score %.2f"
        % (int(ranked.get("count", 0)), score),
        score,
        q,
        "#7dd3a0",
        "🗺",
        ["theater", "multi_province", "campaign"],
        {"ranked": ranked, "rank_score": score},
    )


def theater_auto_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    report = theater_day_report()
    score = _norm(0.65 if not bool(tick.get("empty", False)) else 0.4)
    if tick.get("score") is not None:
        score = _norm(float(tick.get("score", score)))
    q = [
        _q("apply_station", province_id, score, "theater auto campaign station"),
        _q("apply_supply", province_id, 0.5, "theater auto campaign supply"),
        _q("apply_assault", province_id, 0.45, "theater auto campaign assault"),
    ]
    return _day(
        "theater_auto_campaign_day",
        "Theater auto campaign day",
        "Theater auto campaign · tick · report · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["theater", "auto", "campaign"],
        {"tick": tick, "report": report, "tick_score": score},
    )


def daily_command_ops_day(province_id: int = 1) -> Dict[str, Any]:
    log = format_command_log_surface(
        [{"summary": "supply", "score": 0.7}, {"summary": "station", "score": 0.6}]
    )
    gate = daily_apply_integrity_gate()
    score = _norm(0.55 + 0.1 * int(log.get("count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "daily command ops refresh"),
        _q("apply_supply", province_id, 0.55, "daily command ops supply"),
        _q("apply_station", province_id, 0.5, "daily command ops station"),
    ]
    return _day(
        "daily_command_ops_day",
        "Daily command ops day",
        "Daily command ops · log %d · score %.2f" % (int(log.get("count", 0)), score),
        score,
        q,
        "#e8c547",
        "📋",
        ["daily", "command", "ops"],
        {"log": log, "gate": gate},
    )


def theater_readiness_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = theater_readiness_day()
    board = theater_readiness_board(
        ready.get("fleet") if isinstance(ready.get("fleet"), Mapping) else None,
        ready.get("assault") if isinstance(ready.get("assault"), Mapping) else None,
        ready.get("day_risk") if isinstance(ready.get("day_risk"), Mapping) else None,
    )
    score = _norm(float(ready.get("score", 0.6)))
    q = list(ready.get("apply_queue") or []) or [
        _q("apply_assault", province_id, score, "theater readiness assault"),
        _q("apply_supply", province_id, 0.5, "theater readiness supply"),
    ]
    leaf = []
    for item in q:
        if not isinstance(item, Mapping):
            continue
        aid = str(item.get("action_id", ""))
        if aid.endswith("_day"):
            continue
        row = dict(item)
        if not row.get("province_id"):
            row["province_id"] = province_id
        leaf.append(row)
    if not leaf:
        leaf = [
            _q("apply_assault", province_id, score, "theater readiness assault"),
            _q("apply_supply", province_id, 0.5, "theater readiness supply"),
        ]
    return _day(
        "theater_readiness_ops_day",
        "Theater readiness ops day",
        "Theater readiness ops · score %.2f" % score,
        score,
        leaf[:4],
        "#ef8f6e",
        "🛡",
        ["theater", "readiness", "ops"],
        {"ready": ready, "board": board, "risk": ready.get("risk")},
    )


def move_path_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    path = move_path_ops_loop()
    cost = float(path.get("path_cost", 1.0) or 1.0)
    score = _norm(1.0 / max(cost, 0.5))
    q = [
        _q("apply_station", province_id, score, "move path campaign station"),
        _q("apply_supply", province_id, 0.5, "move path campaign supply"),
    ]
    return _day(
        "move_path_campaign_day",
        "Move path campaign day",
        "Move path campaign · cost %.2f · score %.2f" % (cost, score),
        score,
        q,
        "#7dd3a0",
        "🥾",
        ["theater", "move_path", "campaign"],
        {"path": path, "path_cost": cost},
    )


def theater_order_board_day(province_id: int = 1) -> Dict[str, Any]:
    board = theater_order_board(
        [
            {"summary": "supply priority", "score": 0.7},
            {"summary": "station hold", "score": 0.65},
            {"summary": "assault probe", "score": 0.55},
        ]
    )
    strip = theater_campaign_strip()
    score = _norm(float(board.get("score", strip.get("score", 0.65))))
    q = [
        _q("apply_supply", province_id, score, "theater order board supply"),
        _q("apply_station", province_id, 0.55, "theater order board station"),
        _q("apply_assault", province_id, 0.45, "theater order board assault"),
    ]
    return _day(
        "theater_order_board_day",
        "Theater order board day",
        "Theater order board · orders %d · score %.2f"
        % (int(board.get("count", 0)), score),
        score,
        q,
        "#5ec8ff",
        "◎",
        ["theater", "order", "board"],
        {"board": board, "strip": strip},
    )


def theater_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = multi_province_day_plan([province_id, province_id + 1])
    tick = daily_theater_auto_tick()
    ready = theater_readiness_day()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(ranked.get("score", 0.5))
        + 0.35 * float(ready.get("score", 0.5))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, score, "theater campaign close supply"),
        _q("apply_station", province_id, 0.55, "theater campaign close station"),
        _q("apply_assault", province_id, 0.5, "theater campaign close assault"),
    ]
    return _day(
        "theater_campaign_close_day",
        "Theater campaign close day",
        "Theater campaign close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "∞",
        ["theater", "campaign", "close"],
        {"ranked": ranked, "tick": tick, "ready": ready, "gate": gate, "ok": ok},
    )


# B) Naval / sealane sustain


def basing_fleet_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    repair = basing_repair_weather_loop()
    score = _norm(float(fuel.get("logistics_score", fuel.get("fuel_level", 0.55))))
    if score < 0.25:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "basing fleet sustain station"),
        _q("apply_supply", province_id, 0.55, "basing fleet sustain supply"),
    ]
    return _day(
        "basing_fleet_sustain_day",
        "Basing fleet sustain day",
        "Basing fleet sustain · logistics %.2f · score %.2f"
        % (float(fuel.get("logistics_score", 0)), score),
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["naval", "basing", "sustain"],
        {"fuel": fuel, "repair": repair, "logistics_score": score},
    )


def fleet_wx_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = fleet_weather_mission_package()
    plan = fleet_order_execute()
    score = _norm(
        max(
            float(pkg.get("spot_mult", 0.5) or 0.5),
            float(plan.get("score", 0.55) or 0.55),
        )
    )
    q = [
        _q("apply_station", province_id, score, "fleet wx sustain station"),
        _q("apply_supply", province_id, 0.5, "fleet wx sustain supply"),
    ]
    return _day(
        "fleet_wx_sustain_day",
        "Fleet wx sustain day",
        "Fleet wx sustain · mission · order · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["naval", "fleet", "weather"],
        {"package": pkg, "order": plan},
    )


def convoy_sustain_ops_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(_zones())
    supply = supply_route_mutation()
    score = 0.65
    if convoy.get("escort") is not None and isinstance(convoy.get("escort"), (int, float)):
        score = _norm(0.4 + min(0.5, float(convoy["escort"]) / 100.0))
    elif not bool(convoy.get("empty", False)):
        score = 0.68
    score = _norm(0.5 * score + 0.5 * float(supply.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "convoy sustain escort"),
        _q("apply_supply", province_id, float(supply.get("score", 0.55)), "convoy sustain cargo"),
    ]
    return _day(
        "convoy_sustain_ops_day",
        "Convoy sustain ops day",
        "Convoy sustain ops · %s · score %.2f" % (convoy.get("summary", "convoy"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["naval", "convoy", "sustain"],
        {"convoy": convoy, "supply": supply},
    )


def sealane_joint_ops_day(province_id: int = 1) -> Dict[str, Any]:
    joint = sealane_joint_health(_zones())
    naval = naval_campaign_package()
    score = _norm(max(float(joint.get("score", 0.55)), float(naval.get("score", 0.5))))
    q = [
        _q("apply_station", province_id, score, "sealane joint ops station"),
        _q("apply_supply", province_id, 0.55, "sealane joint ops supply"),
        _q("apply_assault", province_id, 0.4, "sealane joint ops interdict"),
    ]
    return _day(
        "sealane_joint_ops_day",
        "Sealane joint ops day",
        "Sealane joint ops · health · naval · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🌊",
        ["naval", "sealane", "joint"],
        {"joint": joint, "naval": naval},
    )


def naval_order_ops_day(province_id: int = 1) -> Dict[str, Any]:
    order = naval_order_package()
    score = _norm(float(order.get("score", 0.6)))
    q = [
        _q("apply_station", province_id, score, "naval order ops primary"),
        _q("apply_supply", province_id, 0.5, "naval order ops supply"),
    ]
    return _day(
        "naval_order_ops_day",
        "Naval order ops day",
        "Naval order ops · %s · score %.2f" % (order.get("summary", "order"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["naval", "order", "ops"],
        {"order": order},
    )


def fleet_station_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    mut = fleet_station_mutation()
    fuel = basing_fleet_fuel_logistics()
    score = _norm(
        max(float(mut.get("score", 0.55)), float(fuel.get("logistics_score", 0.5)))
    )
    q = [
        _q("apply_station", province_id, score, "fleet station sustain primary"),
        _q("apply_supply", province_id, 0.5, "fleet station sustain supply"),
    ]
    return _day(
        "fleet_station_sustain_day",
        "Fleet station sustain day",
        "Fleet station sustain · mut · basing · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["naval", "station", "mutation"],
        {"mutation": mut, "fuel": fuel},
    )


def naval_sealane_close_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    joint = sealane_joint_health(_zones())
    convoy = convoy_package_compose(_zones())
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(fuel.get("logistics_score", 0.5))
        + 0.3 * float(joint.get("score", 0.5))
        + 0.2 * (0.65 if not bool(convoy.get("empty", False)) else 0.4)
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "naval sealane close station"),
        _q("apply_supply", province_id, 0.55, "naval sealane close supply"),
        _q("apply_assault", province_id, 0.45, "naval sealane close interdict"),
    ]
    return _day(
        "naval_sealane_close_day",
        "Naval sealane close day",
        "Naval sealane close · basing · joint · convoy · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["naval", "sealane", "close"],
        {"fuel": fuel, "joint": joint, "convoy": convoy, "gate": gate, "ok": ok},
    )


# C) Player decision / session


def player_surface_session_day(province_id: int = 1) -> Dict[str, Any]:
    strip = player_order_surface_strip()
    score = 0.7 if not bool(strip.get("empty", True)) else 0.45
    if strip.get("score") is not None:
        score = _norm(float(strip.get("score", score)))
    elif strip.get("count") is not None:
        score = _norm(0.45 + 0.05 * int(strip.get("count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "player surface session refresh"),
        _q("apply_supply", province_id, 0.55, "player surface session supply"),
        _q("apply_station", province_id, 0.5, "player surface session station"),
    ]
    return _day(
        "player_surface_session_day",
        "Player surface session day",
        "Player surface session · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🖥",
        ["player", "surface", "session"],
        {"strip": strip, "panel_action_count": int(strip.get("count", 3) or 3)},
    )


def order_panel_session_day(province_id: int = 1) -> Dict[str, Any]:
    composed = order_panel_actions(province_id=province_id)
    score = _norm(float(composed.get("score", 0.7)))
    if score < 0.3:
        score = 0.7
    q = [
        _q("refresh_queue", province_id, score, "order panel session refresh"),
        _q("apply_supply", province_id, 0.5, "order panel session supply"),
    ]
    return _day(
        "order_panel_session_day",
        "Order panel session day",
        "Order panel session · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "📋",
        ["player", "panel", "session"],
        {
            "primary": composed,
            "panel_action_count": int(composed.get("count", 3) or 3),
        },
    )


def mutation_feedback_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fb = next_day_mutation_feedback(0.4, 0.72, "session", "apply_station")
    board = theater_mutation_board()
    score = _norm(0.55 + 0.15)
    if isinstance(fb, (int, float)):
        score = _norm(0.5 + abs(float(fb)) * 0.2)
    elif isinstance(fb, dict) and fb.get("score") is not None:
        score = _norm(float(fb.get("score", score)))
    q = [
        _q("apply_station", province_id, score, "mutation feedback station"),
        _q("refresh_queue", province_id, 0.5, "mutation feedback refresh"),
        _q("apply_supply", province_id, 0.45, "mutation feedback supply"),
    ]
    return _day(
        "mutation_feedback_ops_day",
        "Mutation feedback ops day",
        "Mutation feedback ops · board · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "↻",
        ["player", "mutation", "feedback"],
        {"feedback": fb, "board": board},
    )


def apply_audit_session_day(province_id: int = 1) -> Dict[str, Any]:
    panel_src = (
        'DAY_PACKAGE_ACTION_IDS = [\n'
        '"multi_province_campaign_day", "basing_fleet_sustain_day", '
        '"player_surface_session_day", "theater_naval_session_close_day"\n]'
    )
    gd_src = (
        "func apply_multi_province_campaign_day\n"
        "func apply_basing_fleet_sustain_day\n"
        "func apply_player_surface_session_day\n"
        "func apply_theater_naval_session_close_day\n"
    )
    audit = day_package_apply_audit(panel_src, gd_src)
    score = _norm(float(audit.get("score", 0.4)))
    if score < 0.35:
        score = 0.4
    q = [
        _q("refresh_queue", province_id, score, "apply audit session refresh"),
        _q("apply_supply", province_id, 0.5, "apply audit session supply"),
    ]
    return _day(
        "apply_audit_session_day",
        "Apply audit session day",
        "Apply audit session · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "✓",
        ["player", "audit", "session"],
        {"audit": audit},
    )


def decision_strip_ops_day(province_id: int = 1) -> Dict[str, Any]:
    strip = campaign_decision_strip(
        [
            {"summary": "theater rank", "score": 0.7},
            {"summary": "naval sustain", "score": 0.65},
            {"summary": "session apply", "score": 0.75},
        ]
    )
    exec_strip = execution_decision_strip(
        [
            {"summary": "station", "score": 0.7, "empty": False},
            {"summary": "supply", "score": 0.65, "empty": False},
        ]
    )
    score = 0.7 if not bool(strip.get("empty", True)) else 0.45
    if strip.get("count"):
        score = _norm(0.5 + 0.05 * int(strip.get("count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "decision strip refresh"),
        _q("apply_station", province_id, 0.55, "decision strip station"),
        _q("apply_production", province_id, 0.5, "decision strip production"),
    ]
    return _day(
        "decision_strip_ops_day",
        "Decision strip ops day",
        "Decision strip ops · campaign · exec · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["player", "decision", "session"],
        {"strip": strip, "exec_strip": exec_strip},
    )


def theater_naval_session_close_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = multi_province_day_plan([province_id, province_id + 1])
    joint = sealane_joint_health(_zones())
    strip = player_order_surface_strip()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(ranked.get("score", 0.5))
        + 0.25 * float(joint.get("score", 0.5))
        + 0.25 * (0.7 if not bool(strip.get("empty", True)) else 0.4)
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, float(ranked.get("score", 0.55)), "close theater supply"),
        _q("apply_station", province_id, float(joint.get("score", 0.55)), "close naval station"),
        _q("refresh_queue", province_id, 0.5, "close session refresh"),
        _q("apply_production", province_id, 0.45, "close production"),
    ]
    return _day(
        "theater_naval_session_close_day",
        "Theater naval session close day",
        "Theater naval session close · theater · naval · session · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["theater", "naval", "session", "close"],
        {
            "ranked": ranked,
            "joint": joint,
            "strip": strip,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


THEATER_NAVAL_SESSION_DAY_IDS: List[str] = [
    "multi_province_campaign_day",
    "theater_auto_campaign_day",
    "daily_command_ops_day",
    "theater_readiness_ops_day",
    "move_path_campaign_day",
    "theater_order_board_day",
    "theater_campaign_close_day",
    "basing_fleet_sustain_day",
    "fleet_wx_sustain_day",
    "convoy_sustain_ops_day",
    "sealane_joint_ops_day",
    "naval_order_ops_day",
    "fleet_station_sustain_day",
    "naval_sealane_close_day",
    "player_surface_session_day",
    "order_panel_session_day",
    "mutation_feedback_ops_day",
    "apply_audit_session_day",
    "decision_strip_ops_day",
    "theater_naval_session_close_day",
]


DAY_FUNCS = [
    multi_province_campaign_day,
    theater_auto_campaign_day,
    daily_command_ops_day,
    theater_readiness_ops_day,
    move_path_campaign_day,
    theater_order_board_day,
    theater_campaign_close_day,
    basing_fleet_sustain_day,
    fleet_wx_sustain_day,
    convoy_sustain_ops_day,
    sealane_joint_ops_day,
    naval_order_ops_day,
    fleet_station_sustain_day,
    naval_sealane_close_day,
    player_surface_session_day,
    order_panel_session_day,
    mutation_feedback_ops_day,
    apply_audit_session_day,
    decision_strip_ops_day,
    theater_naval_session_close_day,
]


def theater_naval_session_integrity() -> Dict[str, Any]:
    ranked = multi_province_day_plan([1, 2, 3])
    joint = sealane_joint_health(_zones())
    strip = player_order_surface_strip()
    gate = execution_integrity_gate()
    ok = (
        not bool(ranked.get("empty", False))
        and float(joint.get("score", 0)) > 0.0
        and not bool(strip.get("empty", True))
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "rank_score": float(ranked.get("score", 0)),
        "joint_score": float(joint.get("score", 0)),
        "panel": strip.get("summary", ""),
        "gate": gate,
        "summary": "Theater-naval-session integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next160_theater_naval_session_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = theater_naval_session_integrity()
    label = "Close next160 theater-naval-session · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next160 theater-naval-session[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
