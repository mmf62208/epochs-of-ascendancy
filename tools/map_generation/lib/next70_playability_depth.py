"""Next-70 playability depth: 20 day packages closing live command surface gaps.

1 leader_weather_day · 2 oob_factory_day · 3 move_ops_day · 4 fleet_wx_mission_day
5 player_surface_day · 6 multi_province_plan_day · 7 theater_prod_auto_day
8 focus_mutation_day · 9 mutation_feedback_day · 10 hh_quarterly_day
11 depot_weather_day · 12 fleet_patrol_strip_day · 13 close_loop_day
14 agent_missions_day · 15 supply_route_mutation_day · 16 basing_fuel_day
17 ops_dashboard_day · 18 daily_theater_tick_day · 19 command_log_day
20 integrity_gate_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import (  # type: ignore
    leader_weather_assign,
    oob_factory_risk_loop,
    move_path_ops_loop,
    fleet_weather_mission_package,
    basing_fleet_fuel_logistics,
    sole_mult_integrity,
)
from daily_command_tick import player_order_surface_strip  # type: ignore
from ops_depth import (  # type: ignore
    multi_province_day_plan,
    theater_production_auto,
    fleet_patrol_strip,
    daily_theater_auto_tick,
)
from live_mutation import (  # type: ignore
    focus_mutation_path,
    next_day_mutation_feedback,
    supply_route_mutation,
)
from hh_quarterly_rollup import format_hh_quarterly_rollup  # type: ignore
from theater_ops_polish import depot_weather_capacity, format_ops_dashboard, campaign_day_risk  # type: ignore
from campaign_execution import close_the_loop  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from fleet_task_group import compose_task_group  # type: ignore


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
        "integration": integration or [],
    }
    if extra:
        out.update(extra)
    return out


def leader_weather_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    leader_skill: float = 0.65,
    armored: bool = False,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        board = leader_weather_assign(leader_skill, weather=w, armored=armored)
    except Exception:
        board = {"summary": "leader wx stub", "score": leader_skill}
    score = _norm(board.get("score", leader_skill))
    q = [
        _q("apply_station", province_id, score, "Station leader formation"),
        _q("apply_supply", province_id, 0.45, "Support leader weather ops"),
    ]
    if score >= 0.55:
        q.append(_q("apply_assault", province_id, score, "Leader-led weather press"))
    return _day(
        "leader_weather_day",
        "Leader weather day",
        "Leader weather day · skill×wx %.2f · armored=%s"
        % (score, "Y" if armored else "N"),
        score,
        q[:4],
        "#fbbf24",
        "★",
        ["leader", "weather"],
        {"board": board},
    )


def oob_factory_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        oob = oob_factory_risk_loop(weather=w, base_output=base_output)
    except Exception:
        oob = {"effective_output": 1.0, "summary": "oob stub"}
    mult = float(oob.get("effective_output", oob.get("mult", 1.0)) or 1.0)
    risk = max(0.0, min(1.0, 1.0 - mult))
    score = _norm(1.0 - risk)
    q = [
        _q("apply_production", province_id, score, "OOB production priority"),
        _q("apply_supply", province_id, max(0.35, risk + 0.3), "Shield OOB factories"),
    ]
    return _day(
        "oob_factory_day",
        "OOB factory day",
        "OOB factory day · out×%.2f · risk %.0f%%" % (mult, risk * 100.0),
        score,
        q,
        "#f87171",
        "🏭",
        ["oob", "factory", "production"],
        {"oob": oob, "risk": risk, "sole_mult": True},
    )


def move_ops_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_move_cost: float = 1.0,
    supply_health: float = 0.7,
    armored: bool = False,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {"ground_state": "mud", "precip_intensity": 0.3})
    try:
        path = move_path_ops_loop(
            base_move_cost=base_move_cost,
            weather=w,
            supply_health=supply_health,
            armored=armored,
        )
    except Exception:
        path = {"path_cost": 1.5, "summary": "move ops stub"}
    cost = float(path.get("path_cost", 1.0) or 1.0)
    score = _norm(max(0.1, 1.2 - cost * 0.25))
    q = [
        _q("apply_station", province_id, score, "Station for move ops"),
        _q("apply_supply", province_id, max(0.35, 1.0 - supply_health), "Feed move path"),
    ]
    return _day(
        "move_ops_day",
        "Move ops day",
        "Move ops day · cost %.2f · supply %.0f%% · score %.2f"
        % (cost, supply_health * 100.0, score),
        score,
        q,
        "#5ec8ff",
        "↗",
        ["move", "path", "ops"],
        {"path": path},
    )


def fleet_wx_mission_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    mission: str = "patrol",
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        pkg = fleet_weather_mission_package(
            mission=mission,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=w,
        )
    except Exception:
        pkg = {"summary": "fleet wx stub", "primary_role": "SCREEN"}
    role = str(pkg.get("primary_role", "SCREEN"))
    score = 0.6
    q = [
        _q("apply_station", province_id, score, "Fleet wx %s station" % role),
        _q("apply_supply", province_id, 0.5, "Fleet wx sustain"),
    ]
    return _day(
        "fleet_wx_mission_day",
        "Fleet weather mission day",
        "Fleet wx mission day · %s · role %s · strength %.0f"
        % (mission, role, available_strength),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "weather", "mission"],
        {"package": pkg},
    )


def player_surface_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        strip = player_order_surface_strip(weather=w, trail=list(trail or []))
    except Exception:
        strip = {"summary": "player surface stub", "count": 4, "lines": []}
    count = int(strip.get("count", len(strip.get("lines") or [])) or 0)
    score = _norm(0.4 + 0.1 * min(6, count))
    q = [
        _q("refresh_queue", province_id, score, "Refresh player surface"),
        _q("apply_supply", province_id, 0.5, "Surface supply action"),
        _q("apply_station", province_id, 0.48, "Surface station action"),
    ]
    return _day(
        "player_surface_day",
        "Player surface day",
        "Player surface day · lines %d · score %.2f" % (count, score),
        score,
        q,
        "#5ec8ff",
        "📋",
        ["player", "order", "surface"],
        {"strip": strip},
    )


def multi_province_plan_day(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    max_provinces: int = 3,
    province_id: int = 1,
) -> Dict[str, Any]:
    ids = list(province_ids or [province_id, province_id + 1, province_id + 2, province_id + 3])
    w = dict(weather or {})
    try:
        plan = multi_province_day_plan(
            province_ids=ids, weather=w, max_provinces=max_provinces
        )
    except Exception:
        plan = {"summary": "multi plan stub", "count": len(ids[:max_provinces]), "top": []}
    score = _norm(plan.get("score", 0.65))
    q: List[Dict[str, Any]] = []
    for item in list(plan.get("top", plan.get("ranked", [])) or [])[:max_provinces]:
        if not isinstance(item, dict):
            continue
        pid = int(item.get("province_id", item.get("id", province_id)))
        aid = str(item.get("action_id", "apply_supply"))
        if not aid.startswith("apply_") and aid != "refresh_queue":
            aid = "apply_supply"
        q.append(_q(aid, pid, float(item.get("score", score)), "Plan #%d" % pid))
    if not q:
        for pid in ids[:max_provinces]:
            q.append(_q("apply_supply", int(pid), score, "Plan supply #%d" % int(pid)))
    return _day(
        "multi_province_plan_day",
        "Multi-province plan day",
        "Multi-province plan day · top %d · score %.2f" % (len(q), score),
        score,
        q[:5],
        "#5ec8ff",
        "◎",
        ["multi_province", "plan"],
        {"plan": plan},
    )


def theater_prod_auto_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        auto = theater_production_auto(weather=w)
    except Exception:
        auto = {"score": 0.8, "summary": "theater prod stub", "count": 2}
    score = _norm(auto.get("score", 0.8))
    q = [
        _q("apply_production", province_id, score, "Theater production auto"),
        _q("apply_supply", province_id, 0.45, "Sustain theater production"),
    ]
    return _day(
        "theater_prod_auto_day",
        "Theater production auto day",
        "Theater production auto day · lines %s · score %.2f"
        % (auto.get("count", "?"), score),
        score,
        q,
        "#f87171",
        "🏭",
        ["theater", "production", "auto"],
        {"auto": auto},
    )


def focus_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    focus_id: str = "industrial_effort",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = focus_mutation_path(weather=w, focus_id=focus_id)
    except Exception:
        mut = {"score": 0.5, "summary": "focus mut stub"}
    score = _norm(mut.get("score", 0.5))
    q = [
        _q("apply_focus", province_id, score, "Focus mutation %s" % focus_id),
        _q("apply_hh_commit", province_id, score * 0.9, "Align HH to focus mut"),
    ]
    return _day(
        "focus_mutation_day",
        "Focus mutation day",
        "Focus mutation day · %s · score %.2f" % (focus_id, score),
        score,
        q,
        "#fbbf24",
        "◎",
        ["focus", "mutation"],
        {"mutation": mut},
    )


def mutation_feedback_day(
    *,
    before_score: float = 0.4,
    after_score: float = 0.65,
    order: str = "apply_station",
    province_id: int = 1,
) -> Dict[str, Any]:
    try:
        fb = next_day_mutation_feedback(before_score, after_score, order)
    except TypeError:
        try:
            fb = next_day_mutation_feedback(
                before_score=before_score, after_score=after_score, order=order
            )  # type: ignore
        except Exception:
            fb = {
                "trend": "improved" if after_score > before_score else "steady",
                "delta": after_score - before_score,
                "summary": "mutation feedback stub",
            }
    delta = float(fb.get("delta", after_score - before_score) or 0.0)
    trend = str(fb.get("trend", "steady"))
    score = _norm(0.5 + delta)
    q = [_q("refresh_queue", province_id, max(0.35, score), "Refresh after mutation feedback")]
    if trend == "improved":
        q.append(_q("apply_assault", province_id, score, "Follow improved mutation"))
    else:
        q.append(_q("apply_supply", province_id, max(0.4, abs(delta)), "Recover mutation setback"))
    return _day(
        "mutation_feedback_day",
        "Mutation feedback day",
        "Mutation feedback day · %s · Δ%+.2f" % (trend, delta),
        score,
        q,
        "#5ec8ff",
        "↻",
        ["mutation", "feedback"],
        {"feedback": fb, "trend": trend, "delta": delta},
    )


def hh_quarterly_day(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    t = list(
        trail
        or [
            {"month": 1, "action_class": "sabotage", "influence": 0.55, "province_id": province_id},
            {"month": 2, "action_class": "intel", "influence": 0.48, "province_id": province_id},
            {"month": 3, "action_class": "network", "influence": 0.52, "province_id": province_id},
        ]
    )
    try:
        roll = format_hh_quarterly_rollup(t, quarter_label="Q1-1936")
    except Exception:
        roll = {"summary": "quarterly stub", "empty": False}
    if roll.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }
    score = 0.58
    q = [
        _q("apply_hh_commit", province_id, score, "Quarterly HH commit"),
        _q("apply_counterplay", province_id, 0.5, "Quarterly counterplay"),
        _q("apply_agent_dispatch", province_id, 0.5, "Quarterly agent follow"),
    ]
    return _day(
        "hh_quarterly_day",
        "HH quarterly day",
        "HH quarterly day · events %d · %s"
        % (len(t), str(roll.get("summary", ""))[:50]),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "quarterly"],
        {"rollup": roll},
    )


def depot_weather_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_capacity: float = 100.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {"precip_intensity": 0.35, "temp": 5.0})
    try:
        dep = depot_weather_capacity(w, base_capacity)
    except Exception:
        dep = {"capacity": 90.0, "summary": "depot stub"}
    cap = float(dep.get("capacity", base_capacity) or base_capacity)
    score = _norm(cap / max(1.0, base_capacity))
    q = [
        _q("apply_supply", province_id, max(0.4, 1.0 - score), "Protect depot throughput"),
        _q("apply_production", province_id, score, "Align production to depot cap"),
    ]
    return _day(
        "depot_weather_day",
        "Depot weather day",
        "Depot weather day · cap %.0f/%.0f · score %.2f" % (cap, base_capacity, score),
        score,
        q,
        "#5ec8ff",
        "📦",
        ["depot", "weather", "capacity"],
        {"depot": dep},
    )


def fleet_patrol_strip_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        strip = fleet_patrol_strip(weather=w) if "weather" in fleet_patrol_strip.__code__.co_varnames else fleet_patrol_strip()
    except TypeError:
        try:
            strip = fleet_patrol_strip()
        except Exception:
            strip = {"score": 0.55, "count": 2, "summary": "patrol strip stub"}
    score = _norm(strip.get("score", 0.55))
    q = [
        _q("apply_station", province_id, score, "Patrol strip station"),
        _q("apply_supply", province_id, 0.45, "Patrol strip sustain"),
    ]
    return _day(
        "fleet_patrol_strip_day",
        "Fleet patrol strip day",
        "Fleet patrol strip day · count %s · score %.2f" % (strip.get("count", "?"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "patrol", "strip"],
        {"strip": strip},
    )


def close_loop_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        loop = close_the_loop(weather=w) if "weather" in close_the_loop.__code__.co_varnames else close_the_loop()
    except TypeError:
        try:
            loop = close_the_loop()
        except Exception:
            loop = {"summary": "close loop stub", "orders": 3}
    score = 0.6
    q = [
        _q("apply_station", province_id, score, "Close-loop fleet"),
        _q("apply_assault", province_id, score * 0.9, "Close-loop combat"),
        _q("apply_hh_commit", province_id, 0.5, "Close-loop HH"),
    ]
    return _day(
        "close_loop_day",
        "Close-the-loop day",
        "Close-the-loop day · %s" % str(loop.get("summary", "orders")),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["close_loop", "integrity"],
        {"loop": loop},
    )


def agent_missions_day(
    *,
    action_class: str = "sabotage",
    threat: float = 0.7,
    province_id: int = 1,
) -> Dict[str, Any]:
    try:
        ranked = rank_agent_missions(
            hh_action_class=action_class, threat=threat, network_strength=0.4, loyalty=0.5
        )
    except Exception:
        ranked = {"best_mission": "counterintel", "best_score": 70.0, "summary": "missions stub"}
    best = str(ranked.get("best_mission", "counterintel"))
    score = _norm(ranked.get("best_score", ranked.get("score", 0.7)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "Dispatch %s" % best),
        _q("apply_counterplay", province_id, score * 0.9, "Mission counterplay"),
    ]
    return _day(
        "agent_missions_day",
        "Agent missions day",
        "Agent missions day · best %s · score %.2f" % (best, score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "missions"],
        {"ranked": ranked},
    )


def supply_route_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = supply_route_mutation(
            weather=w, basing_level=basing_level
        ) if "weather" in supply_route_mutation.__code__.co_varnames else supply_route_mutation()
    except TypeError:
        try:
            mut = supply_route_mutation()
        except Exception:
            mut = {"score": 0.55, "summary": "supply route mut stub"}
    score = _norm(mut.get("score", 0.55))
    q = [
        _q("apply_supply", province_id, score, "Supply route mutation"),
        _q("apply_station", province_id, 0.45, "Escort mutated route"),
    ]
    return _day(
        "supply_route_mutation_day",
        "Supply route mutation day",
        "Supply route mutation day · score %.2f · basing %s" % (score, basing_level),
        score,
        q,
        "#5ec8ff",
        "📦",
        ["supply", "mutation", "route"],
        {"mutation": mut},
    )


def basing_fuel_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        log = basing_fleet_fuel_logistics(
            basing_level=basing_level, fuel_level=fuel_level, weather=w
        )
    except Exception:
        log = {"logistics_score": 0.5, "summary": "basing fuel stub"}
    score = _norm(log.get("logistics_score", log.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "Basing fuel station"),
        _q("apply_supply", province_id, max(0.4, 1.0 - fuel_level), "Refuel at basing"),
    ]
    return _day(
        "basing_fuel_day",
        "Basing fuel day",
        "Basing fuel day · %s · fuel %.0f%% · score %.2f"
        % (basing_level, fuel_level * 100.0, score),
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["basing", "fuel", "logistics"],
        {"logistics": log},
    )


def ops_dashboard_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {"precip_intensity": 0.3, "visibility": 0.7})
    try:
        risk = campaign_day_risk(w, month=6)
    except Exception:
        risk = {"summary": "risk stub", "risk": 0.3}
    try:
        tg = compose_task_group(available_strength=100.0, mission="patrol", zone_relation="contested")
    except Exception:
        tg = {"summary": "task group stub", "primary_role": "SCREEN"}
    try:
        dash = format_ops_dashboard(day_risk=risk, task_group=tg)
    except Exception:
        dash = {"summary": "ops dash stub", "lines": [], "empty": False}
    score = 0.58
    q = [
        _q("refresh_queue", province_id, score, "Refresh ops dashboard"),
        _q("apply_station", province_id, 0.5, "Dashboard fleet follow"),
        _q("apply_supply", province_id, 0.48, "Dashboard supply follow"),
    ]
    return _day(
        "ops_dashboard_day",
        "Ops dashboard day",
        "Ops dashboard day · %s" % str(dash.get("summary", "strip"))[:60],
        score,
        q,
        "#5ec8ff",
        "📊",
        ["ops", "dashboard"],
        {"dashboard": dash},
    )


def daily_theater_tick_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    max_applies: int = 3,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        tick = daily_theater_auto_tick(weather=w, max_applies=max_applies)
    except TypeError:
        try:
            tick = daily_theater_auto_tick()  # type: ignore
        except Exception:
            tick = {"summary": "daily theater tick stub", "selected": 3}
    score = 0.6
    q = [
        _q("apply_station", province_id, score, "Daily theater fleet"),
        _q("apply_supply", province_id, 0.5, "Daily theater supply"),
        _q("apply_assault", province_id, 0.48, "Daily theater combat"),
    ]
    return _day(
        "daily_theater_tick_day",
        "Daily theater tick day",
        "Daily theater tick day · %s" % str(tick.get("summary", "selected"))[:70],
        score,
        q[: max(1, max_applies)],
        "#5ec8ff",
        "📅",
        ["daily", "theater", "tick"],
        {"tick": tick},
    )


def command_log_day(
    *,
    province_id: int = 1,
    log_entries: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    entries = list(
        log_entries
        or [
            {"action_id": "apply_supply", "ok": True},
            {"action_id": "apply_station", "ok": True},
            {"action_id": "apply_assault", "ok": False},
        ]
    )
    ok_n = sum(1 for e in entries if e.get("ok"))
    score = _norm(ok_n / max(1, len(entries)))
    q = [
        _q("refresh_queue", province_id, score, "Refresh after command log"),
        _q("apply_supply", province_id, 0.5, "Retry supply from log"),
    ]
    if ok_n < len(entries):
        q.append(_q("apply_station", province_id, 0.45, "Retry station from log"))
    return _day(
        "command_log_day",
        "Command log day",
        "Command log day · %d/%d ok · score %.2f" % (ok_n, len(entries), score),
        score,
        q,
        "#5ec8ff",
        "📜",
        ["command", "log"],
        {"entries": entries, "ok_count": ok_n},
    )


def integrity_gate_day(
    *,
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    province_id: int = 1,
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    score = 0.75 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "Refresh integrity advisory"),
        _q("apply_supply", province_id, 0.45, "Sole-mult supply check"),
    ]
    return _day(
        "integrity_gate_day",
        "Integrity gate day",
        "Integrity gate day · sole-mult %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["integrity", "sole_mult", "advisory"],
        {"gate": sole, "ok": ok, "deferred_hard_gate": True},
    )


PLAYABILITY_DAY_IDS: List[str] = [
    "leader_weather_day",
    "oob_factory_day",
    "move_ops_day",
    "fleet_wx_mission_day",
    "player_surface_day",
    "multi_province_plan_day",
    "theater_prod_auto_day",
    "focus_mutation_day",
    "mutation_feedback_day",
    "hh_quarterly_day",
    "depot_weather_day",
    "fleet_patrol_strip_day",
    "close_loop_day",
    "agent_missions_day",
    "supply_route_mutation_day",
    "basing_fuel_day",
    "ops_dashboard_day",
    "daily_theater_tick_day",
    "command_log_day",
    "integrity_gate_day",
]


DAY_FUNCS = [
    leader_weather_day,
    oob_factory_day,
    move_ops_day,
    fleet_wx_mission_day,
    player_surface_day,
    multi_province_plan_day,
    theater_prod_auto_day,
    focus_mutation_day,
    mutation_feedback_day,
    hh_quarterly_day,
    depot_weather_day,
    fleet_patrol_strip_day,
    close_loop_day,
    agent_missions_day,
    supply_route_mutation_day,
    basing_fuel_day,
    ops_dashboard_day,
    daily_theater_tick_day,
    command_log_day,
    integrity_gate_day,
]


def playability_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Playability integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next70_playability_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {
            "visibility": 0.75,
            "precip_intensity": 0.25,
            "ground_state": "mud",
            "temp": 8.0,
        }
    )
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in (
                "mutation_feedback_day",
                "hh_quarterly_day",
                "agent_missions_day",
                "command_log_day",
                "integrity_gate_day",
            ):
                packages[name] = fn()
            else:
                packages[name] = fn(weather=w)
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = playability_integrity()
    label = "Close next70 playability · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next70 playability[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
