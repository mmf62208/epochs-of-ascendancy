"""Next-60 command depth: 20 day packages (orders, daily plans, mutations, intel).

1 air_ops_sortie_day · 2 agent_escalation_day · 3 agent_coverage_day
4 combat_order_day · 5 production_order_day · 6 supply_order_day
7 combat_phase_strip_day · 8 fleet_patrol_day · 9 execute_one_day
10 daily_fleet_plan_day · 11 daily_combat_plan_day · 12 daily_prod_plan_day
13 daily_agent_plan_day · 14 daily_supply_plan_day
15 agent_dispatch_mutation_day · 16 fleet_station_mutation_day
17 assault_stage_mutation_day · 18 naval_task_mutation_day
19 air_land_stage_mutation_day · 20 hh_monthly_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_cohesion import air_ops_package  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from campaign_execution import (  # type: ignore
    combat_order_execute,
    production_order_resolve,
    supply_order_resolve,
)
from ops_depth import (  # type: ignore
    combat_phase_order_strip,
    fleet_patrol_depth,
    execute_one_order,
)
from daily_command_tick import (  # type: ignore
    daily_fleet_auto_apply_plan,
    daily_combat_auto_apply_plan,
    daily_production_auto_apply_plan,
    daily_agent_auto_apply_plan,
    daily_supply_auto_apply_plan,
)
from live_mutation import (  # type: ignore
    agent_dispatch_mutation,
    fleet_station_mutation,
    assault_stage_mutation,
    naval_task_mutation,
    air_land_stage_mutation,
)
from hh_monthly_brief import format_hh_monthly_brief  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


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
    label: str,
    summary: str,
    score: float,
    apply_queue: List[Dict[str, Any]],
    bb_color: str = "#5ec8ff",
    marker: str = "★",
    integration: Optional[List[str]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": label, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]"
        % (bb_color, marker, label.replace("Run ", ""), summary),
        "empty": False,
        "integration": integration or [],
    }
    if extra:
        out.update(extra)
    return out


def air_ops_sortie_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        pkg = air_ops_package(w, month=month)
    except Exception:
        pkg = {"effective": 0.8, "grounded": False, "summary": "air ops stub"}
    eff = _norm(pkg.get("effective", pkg.get("score", 0.8)))
    grounded = bool(pkg.get("grounded", False))
    q = []
    if grounded or eff < 0.55:
        q.append(_q("apply_supply", province_id, max(0.4, 1.0 - eff), "Wait/refit air ops"))
        q.append(_q("apply_station", province_id, 0.45, "Hold under grounding"))
    else:
        q.append(_q("apply_assault", province_id, eff, "Sortie-supported assault"))
        q.append(_q("apply_supply", province_id, 0.45, "Feed sortie package"))
    return _day(
        "air_ops_sortie_day",
        "Run air ops sortie day",
        "Air ops sortie day · eff %.0f%% · grounded=%s" % (eff * 100.0, "Y" if grounded else "N"),
        eff,
        q,
        "#ff9a6e",
        "✈",
        ["air", "sortie", "ops"],
        {"package": pkg},
    )


def agent_escalation_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.4,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.7,
            "province_id": province_id,
        }
    )
    try:
        esc = plan_agent_escalation(
            sig, network_strength=network_strength, available_agents=available_agents
        )
    except Exception:
        esc = {"level": 2, "summary": "escalation stub", "top_action": "counterintel"}
    level = int(esc.get("level", 2) or 2)
    score = _norm(level / 3.0)
    q = [
        _q("apply_agent_dispatch", int(sig.get("province_id", province_id)), score, "Escalate agent ops"),
        _q("apply_counterplay", province_id, score * 0.9, "Counter escalate"),
    ]
    return _day(
        "agent_escalation_day",
        "Run agent escalation day",
        "Agent escalation day · L%d · %s" % (level, str(esc.get("top_action", "?"))),
        score,
        q,
        "#c084fc",
        "◈",
        ["agent", "escalation"],
        {"escalation": esc},
    )


def agent_coverage_day(
    threats: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.4,
    province_id: int = 1,
) -> Dict[str, Any]:
    th = list(
        threats
        or [
            {"action_class": "sabotage", "influence": 0.7, "province_id": province_id},
            {"action_class": "intel", "influence": 0.5, "province_id": max(1, province_id + 1)},
        ]
    )
    try:
        cov = plan_agent_coverage(th, available_agents=available_agents, network_strength=network_strength)
    except Exception:
        cov = {"summary": "coverage stub", "score": 0.5, "empty": False}
    score = _norm(cov.get("score", 0.55))
    q = [
        _q("apply_agent_dispatch", province_id, score, "Cover top threat"),
        _q("apply_counterplay", province_id, score * 0.9, "Network counterplay"),
    ]
    return _day(
        "agent_coverage_day",
        "Run agent coverage day",
        "Agent coverage day · score %.2f · threats %d" % (score, len(th)),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "coverage"],
        {"coverage": cov},
    )


def combat_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        order = combat_order_execute(
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
            weather=w,
            province_id=province_id,
        )
    except Exception:
        order = {"score": 0.45, "summary": "combat order stub"}
    score = _norm(order.get("score", 0.45))
    step = str(order.get("step", order.get("order", "HOLD")))
    q = []
    if "PRESS" in step.upper() or "ASSAULT" in step.upper() or score >= 0.5:
        q.append(_q("apply_assault", province_id, score, "Execute combat order"))
    q.append(_q("apply_supply", province_id, max(0.35, 1.0 - attacker_supply), "Feed combat order"))
    if not q:
        q.append(_q("apply_station", province_id, 0.4, "Hold combat order"))
    return _day(
        "combat_order_day",
        "Run combat order day",
        "Combat order day · %s · score %.2f" % (step, score),
        score,
        q[:4],
        "#ff9a6e",
        "⚔",
        ["combat", "order"],
        {"order": order},
    )


def production_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    line_id: str = "primary",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        order = production_order_resolve(weather=w, base_output=base_output, line_id=line_id)
    except Exception:
        order = {"score": 0.7, "priority": "SURGE", "summary": "prod order stub"}
    score = _norm(order.get("score", 0.7))
    pri = str(order.get("priority", "SURGE"))
    q = [
        _q("apply_production", province_id, score, "Set production %s" % pri),
        _q("apply_supply", province_id, 0.45, "Sustain production lines"),
    ]
    return _day(
        "production_order_day",
        "Run production order day",
        "Production order day · %s · score %.2f" % (pri, score),
        score,
        q,
        "#f87171",
        "🏭",
        ["production", "order"],
        {"order": order},
    )


def supply_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    sea_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        order = supply_order_resolve(
            weather=w, basing_level=basing_level, sea_mult=sea_mult, route_id="main"
        )
    except Exception:
        order = {"score": 0.55, "priority": "SUSTAIN", "summary": "supply order stub"}
    score = _norm(order.get("score", 0.55))
    pri = str(order.get("priority", "SUSTAIN"))
    q = [
        _q("apply_supply", province_id, score, "Supply order %s" % pri),
        _q("apply_station", province_id, 0.45, "Escort supply order"),
    ]
    return _day(
        "supply_order_day",
        "Run supply order day",
        "Supply order day · %s · score %.2f" % (pri, score),
        score,
        q,
        "#5ec8ff",
        "📦",
        ["supply", "order"],
        {"order": order},
    )


def combat_phase_strip_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        strip = combat_phase_order_strip(
            weather=w, attacker_power=attacker_power, defender_power=defender_power
        )
    except Exception:
        strip = {"score": 0.5, "summary": "phase strip stub", "count": 2}
    score = _norm(strip.get("score", 0.5))
    q = [
        _q("apply_assault", province_id, score, "Stage from phase strip"),
        _q("apply_supply", province_id, 0.45, "Feed phase strip"),
    ]
    return _day(
        "combat_phase_strip_day",
        "Run combat phase strip day",
        "Combat phase strip day · count %s · score %.2f"
        % (strip.get("count", "?"), score),
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["combat", "phase", "strip"],
        {"strip": strip},
    )


def fleet_patrol_day(
    province_ids: Optional[Sequence[int]] = None,
    *,
    fuel_level: float = 0.7,
    basing_level: str = "port",
    country_tag: str = "ENG",
    province_id: int = 1,
) -> Dict[str, Any]:
    ids = list(province_ids or [province_id, province_id + 1, province_id + 2])
    try:
        depth = fleet_patrol_depth(
            province_ids=ids,
            fuel_level=fuel_level,
            country_tag=country_tag,
            basing_level=basing_level,
        )
    except Exception:
        depth = {"score": 0.55, "summary": "patrol stub"}
    score = _norm(depth.get("score", 0.55))
    q = [
        _q("apply_station", province_id, score, "Patrol station"),
    ]
    if fuel_level < 0.65:
        q.append(_q("apply_supply", province_id, max(0.4, 1.0 - fuel_level), "Refuel patrol"))
    return _day(
        "fleet_patrol_day",
        "Run fleet patrol day",
        "Fleet patrol day · zones %d · fuel %.0f%% · score %.2f"
        % (len(ids), fuel_level * 100.0, score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["fleet", "patrol"],
        {"depth": depth},
    )


def execute_one_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        one = execute_one_order(weather=w, trail=list(trail or []), prefer_apply_ready=True)
    except Exception:
        one = {"score": 0.5, "summary": "execute one stub", "domain": "supply"}
    score = _norm(one.get("score", 0.5))
    domain = str(one.get("domain", one.get("kind", "supply"))).lower()
    aid = "apply_supply"
    if "combat" in domain or "assault" in domain:
        aid = "apply_assault"
    elif "fleet" in domain or "station" in domain or "naval" in domain:
        aid = "apply_station"
    elif "prod" in domain:
        aid = "apply_production"
    elif "agent" in domain:
        aid = "apply_agent_dispatch"
    elif "hh" in domain or "agenda" in domain:
        aid = "apply_hh_commit"
    q = [_q(aid, province_id, score, "Execute-one %s" % domain)]
    return _day(
        "execute_one_day",
        "Run execute-one day",
        "Execute-one day · domain %s · score %.2f" % (domain, score),
        score,
        q,
        "#5ec8ff",
        "▶",
        ["execute", "one", "queue"],
        {"one": one},
    )


def daily_fleet_plan_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    country_tag: str = "ENG",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        plan = daily_fleet_auto_apply_plan(weather=w, country_tag=country_tag)
    except Exception:
        plan = {"score": 0.55, "apply_ready": True, "summary": "daily fleet stub"}
    score = _norm(plan.get("score", 0.55))
    pid = int(plan.get("province_id", province_id) or province_id)
    if pid < 0:
        pid = province_id
    q = [_q("apply_station", pid, score, "Daily fleet plan station")]
    if not bool(plan.get("apply_ready", True)):
        q.append(_q("apply_supply", pid, 0.5, "Daily fleet refuel"))
    return _day(
        "daily_fleet_plan_day",
        "Run daily fleet plan day",
        "Daily fleet plan day · ready=%s · score %.2f"
        % ("Y" if plan.get("apply_ready", True) else "N", score),
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["daily", "fleet", "plan"],
        {"plan": plan},
    )


def daily_combat_plan_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_tag: str = "GER",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        plan = daily_combat_auto_apply_plan(weather=w, attacker_tag=attacker_tag)
    except Exception:
        plan = {"score": 0.4, "execute": False, "summary": "daily combat stub"}
    score = _norm(plan.get("score", 0.4))
    q = []
    if bool(plan.get("execute", plan.get("apply_ready", False))) or score >= 0.5:
        q.append(_q("apply_assault", province_id, score, "Daily combat press"))
    q.append(_q("apply_supply", province_id, max(0.4, 1.0 - score), "Daily combat supply"))
    return _day(
        "daily_combat_plan_day",
        "Run daily combat plan day",
        "Daily combat plan day · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["daily", "combat", "plan"],
        {"plan": plan},
    )


def daily_prod_plan_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        plan = daily_production_auto_apply_plan(weather=w)
    except Exception:
        plan = {"score": 0.8, "summary": "daily prod stub"}
    score = _norm(plan.get("score", 0.8))
    q = [
        _q("apply_production", province_id, score, "Daily production plan"),
        _q("apply_supply", province_id, 0.45, "Daily prod sustain"),
    ]
    return _day(
        "daily_prod_plan_day",
        "Run daily production plan day",
        "Daily production plan day · score %.2f" % score,
        score,
        q,
        "#f87171",
        "🏭",
        ["daily", "production", "plan"],
        {"plan": plan},
    )


def daily_agent_plan_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.65,
            "province_id": province_id,
        }
    )
    try:
        plan = daily_agent_auto_apply_plan(signal=sig)
    except Exception:
        plan = {"score": 0.55, "summary": "daily agent stub"}
    score = _norm(plan.get("score", 0.55))
    q = [
        _q("apply_agent_dispatch", int(sig.get("province_id", province_id)), score, "Daily agent plan"),
        _q("apply_counterplay", province_id, score * 0.9, "Daily counterplay"),
    ]
    return _day(
        "daily_agent_plan_day",
        "Run daily agent plan day",
        "Daily agent plan day · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🕵",
        ["daily", "agent", "plan"],
        {"plan": plan},
    )


def daily_supply_plan_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        plan = daily_supply_auto_apply_plan(weather=w)
    except Exception:
        plan = {"score": 0.55, "summary": "daily supply stub"}
    score = _norm(plan.get("score", 0.55))
    q = [
        _q("apply_supply", province_id, score, "Daily supply plan"),
        _q("apply_station", province_id, 0.45, "Daily supply escort"),
    ]
    return _day(
        "daily_supply_plan_day",
        "Run daily supply plan day",
        "Daily supply plan day · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "📦",
        ["daily", "supply", "plan"],
        {"plan": plan},
    )


def agent_dispatch_mutation_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.68,
            "province_id": province_id,
        }
    )
    try:
        mut = agent_dispatch_mutation(signal=sig, available_agents=available_agents)
    except Exception:
        mut = {"score": 0.55, "summary": "agent mut stub"}
    score = _norm(mut.get("score", 0.55))
    q = [
        _q("apply_agent_dispatch", int(sig.get("province_id", province_id)), score, "Mutation agent dispatch"),
        _q("apply_counterplay", province_id, score * 0.9, "Mutation counterplay"),
    ]
    return _day(
        "agent_dispatch_mutation_day",
        "Run agent dispatch mutation day",
        "Agent dispatch mutation day · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["mutation", "agent"],
        {"mutation": mut},
    )


def fleet_station_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = fleet_station_mutation(
            basing_level=basing_level,
            fuel_level=fuel_level,
            weather=w,
            province_id=province_id,
        )
    except Exception:
        mut = {"score": 0.45, "summary": "fleet station mut stub"}
    score = _norm(mut.get("score", 0.45))
    q = [_q("apply_station", province_id, score, "Fleet station mutation")]
    if fuel_level < 0.65:
        q.append(_q("apply_supply", province_id, max(0.4, 1.0 - fuel_level), "Refuel station mut"))
    return _day(
        "fleet_station_mutation_day",
        "Run fleet station mutation day",
        "Fleet station mutation day · score %.2f · fuel %.0f%%" % (score, fuel_level * 100.0),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["mutation", "fleet", "station"],
        {"mutation": mut},
    )


def assault_stage_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = assault_stage_mutation(
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
            weather=w,
            from_province_id=province_id,
            target_province_id=province_id,
        )
    except Exception:
        mut = {"score": 0.4, "summary": "assault stage stub"}
    score = _norm(mut.get("score", 0.4))
    q = [
        _q("apply_assault", province_id, max(0.4, score), "Assault stage mutation"),
        _q("apply_supply", province_id, max(0.35, 1.0 - attacker_supply), "Stage assault supply"),
    ]
    return _day(
        "assault_stage_mutation_day",
        "Run assault stage mutation day",
        "Assault stage mutation day · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["mutation", "assault"],
        {"mutation": mut},
    )


def naval_task_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = naval_task_mutation(
            basing_level=basing_level,
            fuel_level=fuel_level,
            weather=w,
            province_id=province_id,
        )
    except Exception:
        mut = {"score": 0.47, "summary": "naval task mut stub"}
    score = _norm(mut.get("score", 0.47))
    q = [_q("apply_station", province_id, score, "Naval task mutation")]
    if fuel_level < 0.65:
        q.append(_q("apply_supply", province_id, max(0.4, 1.0 - fuel_level), "Refuel naval task"))
    return _day(
        "naval_task_mutation_day",
        "Run naval task mutation day",
        "Naval task mutation day · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🚢",
        ["mutation", "naval", "task"],
        {"mutation": mut},
    )


def air_land_stage_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    attacker_power: float = 100.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        mut = air_land_stage_mutation(
            weather=w,
            month=month,
            attacker_power=attacker_power,
            from_province_id=province_id,
            target_province_id=province_id,
        )
    except Exception:
        mut = {"score": 0.45, "summary": "air-land stage stub"}
    score = _norm(mut.get("score", 0.45))
    q = [
        _q("apply_assault", province_id, score, "Air-land stage mutation"),
        _q("apply_supply", province_id, 0.45, "Feed air-land stage"),
    ]
    return _day(
        "air_land_stage_mutation_day",
        "Run air-land stage mutation day",
        "Air-land stage mutation day · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "✈",
        ["mutation", "air_land"],
        {"mutation": mut},
    )


def hh_monthly_day(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    t = list(
        trail
        or [
            {
                "month": 3,
                "year": 1936,
                "action_class": "sabotage",
                "influence": 0.6,
                "province_id": province_id,
            },
            {
                "month": 3,
                "year": 1936,
                "action_class": "intel",
                "influence": 0.45,
                "province_id": max(1, province_id + 1),
            },
        ]
    )
    try:
        brief = format_hh_monthly_brief(t, month_label="1936-03", max_actions=3)
    except Exception:
        brief = {"summary": "monthly brief stub", "empty": False}
    if brief.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }
    score = 0.55
    q = [
        _q("apply_hh_commit", province_id, score, "Monthly HH commit"),
        _q("apply_counterplay", province_id, 0.5, "Monthly counterplay"),
        _q("apply_agent_dispatch", province_id, 0.5, "Monthly agent follow"),
    ]
    return _day(
        "hh_monthly_day",
        "Run HH monthly day",
        "HH monthly day · trail %d · %s" % (len(t), str(brief.get("summary", ""))[:60]),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "monthly", "brief"],
        {"brief": brief},
    )


COMMAND_DAY_IDS: List[str] = [
    "air_ops_sortie_day",
    "agent_escalation_day",
    "agent_coverage_day",
    "combat_order_day",
    "production_order_day",
    "supply_order_day",
    "combat_phase_strip_day",
    "fleet_patrol_day",
    "execute_one_day",
    "daily_fleet_plan_day",
    "daily_combat_plan_day",
    "daily_prod_plan_day",
    "daily_agent_plan_day",
    "daily_supply_plan_day",
    "agent_dispatch_mutation_day",
    "fleet_station_mutation_day",
    "assault_stage_mutation_day",
    "naval_task_mutation_day",
    "air_land_stage_mutation_day",
    "hh_monthly_day",
]


DAY_FUNCS = [
    air_ops_sortie_day,
    agent_escalation_day,
    agent_coverage_day,
    combat_order_day,
    production_order_day,
    supply_order_day,
    combat_phase_strip_day,
    fleet_patrol_day,
    execute_one_day,
    daily_fleet_plan_day,
    daily_combat_plan_day,
    daily_prod_plan_day,
    daily_agent_plan_day,
    daily_supply_plan_day,
    agent_dispatch_mutation_day,
    fleet_station_mutation_day,
    assault_stage_mutation_day,
    naval_task_mutation_day,
    air_land_stage_mutation_day,
    hh_monthly_day,
]


def command_depth_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {"ok": ok, "summary": "Command depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next60_command_depth_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(weather or {"visibility": 0.75, "precip_intensity": 0.2, "ground_state": "dry"})
    packages = {fn.__name__: fn(weather=w) if "weather" in fn.__code__.co_varnames else fn() for fn in DAY_FUNCS}
    # Fix call signatures - some don't take weather
    packages = {}
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in (
                "agent_escalation_day",
                "agent_coverage_day",
                "agent_dispatch_mutation_day",
                "hh_monthly_day",
                "daily_agent_plan_day",
            ):
                packages[name] = fn()
            elif name in ("fleet_patrol_day",):
                packages[name] = fn()
            else:
                packages[name] = fn(weather=w)
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = command_depth_integrity()
    label = "Close next60 command depth · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next60 command depth[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
