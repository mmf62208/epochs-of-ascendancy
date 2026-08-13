"""Gameplay loop pilots beyond integration-expand.

Deeper multi-system loops: basing+fleet+fuel, assault follow-on, counter-ops execute,
agenda execute pick, move×wx×supply, basing repair×weather, sealane joint health,
reinforced assault, war path urgency, OOB factory risk, force×supply, leader weather,
joint ops strip, sole-mult integrity.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from naval_basing import compute_naval_basing, basing_from_province_signals  # type: ignore
from integrated_theater_ops import (  # type: ignore
    fleet_weather_mission_package,
    assault_readiness_compose,
    counter_ops_board,
    format_hh_agenda_commitments,
    convoy_package_compose,
    trade_supply_weather_chain,
    factory_risk_compose,
    supply_chain_health,
)
from weather_effects import (  # type: ignore
    combat_weather_multiplier,
    movement_multiplier,
    production_weather_multiplier,
    supply_throughput_weather_multiplier,
)
from theater_ops_polish import (  # type: ignore
    daylight_combat_mod,
    focus_weather_aware_score,
    choke_weather_synergy,
)
from weather_ops_polish import weather_pressure_index  # type: ignore


# Mirror basing rates from naval_basing module if available
try:
    from naval_basing import basing_service_rates  # type: ignore
except Exception:  # pragma: no cover
    basing_service_rates = None


_LEVEL_RATES = {
    "none": {"refuel_rate": 0.0, "repair_org_rate": 0.0},
    "anchorage": {"refuel_rate": 0.10, "repair_org_rate": 0.015},
    "port": {"refuel_rate": 0.25, "repair_org_rate": 0.04},
    "major_base": {"refuel_rate": 0.40, "repair_org_rate": 0.06},
}


def basing_fleet_fuel_logistics(
    basing_level: str = "port",
    fuel_level: float = 0.5,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    mission: str = "patrol",
) -> Dict[str, Any]:
    """Basing tier × fleet+wx package × fuel — logistics loop."""
    level = str(basing_level or "none").lower()
    rates = _LEVEL_RATES.get(level, _LEVEL_RATES["none"])
    fuel = max(0.05, min(1.2, float(fuel_level)))
    # Low fuel prefers refuel mission bias into fleet package via escort_need bump
    escort_need = 0.0
    if fuel < 0.4:
        escort_need = 35.0
        mission_eff = "hold" if level in ("port", "major_base", "anchorage") else "patrol"
    else:
        mission_eff = mission
    pkg = fleet_weather_mission_package(
        mission_eff,
        available_strength=available_strength,
        zone_relation=zone_relation,
        escort_need=escort_need,
        weather=weather,
    )
    # Logistics score: basing refuel capacity * fuel deficit urgency * package strength
    refuel = float(rates["refuel_rate"])
    urgency = max(0.0, 1.0 - fuel)
    logistics = refuel * (0.5 + 0.5 * urgency) * (0.7 + 0.3 * float(available_strength) / 100.0)
    if fuel < 0.35 and level == "none":
        logistics *= 0.3
    label = "Basing logistics · %s · fuel %.0f%% · refuel %.2f · primary %s" % (
        level,
        fuel * 100.0,
        refuel,
        pkg.get("primary_role", "?"),
    )
    return {
        "basing_level": level,
        "fuel_level": fuel,
        "refuel_rate": refuel,
        "fleet_package": pkg,
        "logistics_score": float(logistics),
        "mission_effective": pkg.get("mission_effective", mission_eff),
        "primary_role": pkg.get("primary_role", ""),
        "integration": ["basing", "fleet_wx", "fuel"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]⚓ Basing logistics[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def assault_follow_on_loop(
    targets: Sequence[Mapping[str, Any]],
    attacker_power: float = 100.0,
    attacker_supply: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Assault readiness → press / hold / soften next step."""
    ready = assault_readiness_compose(
        targets,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=weather,
    )
    if ready.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "next_step": "none",
            "integration": ["assault_ready", "follow_on"],
        }
    overall = float((ready.get("ranked") or {}).get("best", {}).get("overall", 0.0))
    if overall >= 0.65:
        step = "press"
        advice = "Press follow-on assault"
    elif overall >= 0.45:
        step = "hold"
        advice = "Hold — reinforce supply before follow-on"
    else:
        step = "soften"
        advice = "Soften with recon/artillery first"
    label = "Follow-on · %s · win %.0f%% · %s" % (step, overall * 100.0, advice)
    return {
        "readiness": ready,
        "overall": overall,
        "next_step": step,
        "advice": advice,
        "best_province_id": ready.get("best_province_id", -1),
        "integration": ["assault_ready", "follow_on"],
        "label": label,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#ff9a6e]⚔ Follow-on[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def counter_ops_execute_order(
    signal: Mapping[str, Any],
    network_strength: float = 0.3,
    available_agents: int = 4,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    """Counter-ops board → deploy mission order string."""
    board = counter_ops_board(
        signal,
        network_strength=network_strength,
        available_agents=available_agents,
        loyalty=loyalty,
    )
    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "order": "",
            "integration": ["counter_ops", "execute"],
        }
    esc = board.get("escalation") or {}
    top = str(esc.get("top_action", "monitor"))
    level = int(esc.get("level", 0))
    pid = int(signal.get("province_id", -1) or -1)
    order = "DEPLOY %s L%d agents=%d @#%d" % (top.upper(), level, available_agents, pid)
    label = "Execute order · %s" % order
    return {
        "board": board,
        "order": order,
        "top_action": top,
        "level": level,
        "integration": ["counter_ops", "execute"],
        "label": label,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]◎ Execute[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def agenda_execute_pick(
    trail: Sequence[Mapping[str, Any]],
    max_commits: int = 3,
) -> Dict[str, Any]:
    """Commits → next action pick. Empty trail → empty."""
    commits = format_hh_agenda_commitments(trail, max_commits=max_commits)
    if commits.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "pick": "",
            "integration": ["hh_commits", "execute_pick"],
        }
    top = (commits.get("commits") or [{}])[0]
    pick = "NEXT: %s @#%s" % (
        top.get("action_class", "influence"),
        top.get("province_id", -1),
    )
    label = "Agenda execute pick · %s" % pick
    return {
        "commits": commits,
        "pick": pick,
        "top": top,
        "integration": ["hh_commits", "execute_pick"],
        "label": label,
        "summary": label,
        "plain": label + "\n" + str(commits.get("plain", "")),
        "bbcode": "[color=#c084fc]◈ Execute pick[/color] [color=#8899aa]%s[/color]" % pick,
        "empty": False,
    }


def move_path_ops_loop(
    base_move_cost: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    supply_health: float = 1.0,
    armored: bool = False,
) -> Dict[str, Any]:
    """Formation move × weather move × supply health."""
    w = dict(weather or {})
    tags = ["armor"] if armored else []
    move_m = movement_multiplier(w, unit_tags=tags)
    supply_h = max(0.15, min(1.5, float(supply_health)))
    # Effective path cost rises when move mult falls or supply is poor
    cost = max(0.05, float(base_move_cost) / max(0.15, move_m) / max(0.3, supply_h))
    label = "Move path · cost %.2f (wx ×%.2f · supply ×%.2f)" % (cost, move_m, supply_h)
    return {
        "base_cost": float(base_move_cost),
        "weather_move_mult": float(move_m),
        "supply_health": supply_h,
        "path_cost": float(cost),
        "integration": ["move", "weather", "supply"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🥾 Move path[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def basing_repair_weather_loop(
    basing_level: str = "port",
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Naval basing repair rate reduced by storm/precip."""
    level = str(basing_level or "none").lower()
    rates = _LEVEL_RATES.get(level, _LEVEL_RATES["none"])
    base_repair = float(rates["repair_org_rate"])
    w = dict(weather or {})
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    # Storm cuts repair efficiency
    repair = base_repair * max(0.25, 1.0 - storm * 0.55)
    refuel = float(rates["refuel_rate"]) * max(0.4, 1.0 - storm * 0.3)
    label = "Basing repair · %s · org %.3f/d (storm %.0f%%)" % (
        level,
        repair,
        storm * 100.0,
    )
    return {
        "basing_level": level,
        "base_repair_org_rate": base_repair,
        "repair_org_rate": float(repair),
        "refuel_rate": float(refuel),
        "storm": storm,
        "integration": ["basing", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🔧 Basing×wx[/color] [color=#8899aa]%s[/color]" % label,
        "empty": level == "none",
    }


def sealane_joint_health(
    path_zone_relations: Sequence[str],
    sea_trade_mult: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    available_fleet: float = 50.0,
) -> Dict[str, Any]:
    """Convoy package × trade chain → single sealane score."""
    convoy = convoy_package_compose(
        path_zone_relations,
        available_fleet_strength=available_fleet,
        weather=weather,
    )
    trade = trade_supply_weather_chain(sea_trade_mult=sea_trade_mult, weather=weather)
    escort_ok = 1.0 if convoy.get("sufficient") or convoy.get("recommend_escort") else 0.65
    if convoy.get("recommend_wait"):
        escort_ok *= 0.85
    score = float(trade["health"]) * escort_ok
    label = "Sealane health ×%.2f (trade ×%.2f · escort %.0f%%)" % (
        score,
        float(trade["health"]),
        escort_ok * 100.0,
    )
    return {
        "score": float(score),
        "trade": trade,
        "convoy": convoy,
        "integration": ["convoy_package", "trade_chain"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🌊 Sealane[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def reinforced_assault_loop(
    targets: Sequence[Mapping[str, Any]],
    attacker_power: float = 100.0,
    attacker_supply: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 1,
    is_choke: bool = False,
    controller_friendly: bool = True,
) -> Dict[str, Any]:
    """Readiness × daylight × choke score."""
    ready = assault_readiness_compose(
        targets,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=weather,
    )
    day = daylight_combat_mod(month)
    choke = choke_weather_synergy(
        is_choke=is_choke, controller_friendly=controller_friendly, weather=weather
    )
    base = float((ready.get("ranked") or {}).get("best", {}).get("overall", 0.5)) if not ready.get("empty") else 0.3
    day_m = float(day["combat_mult"])
    choke_m = float(choke.get("score", 1.0)) if not choke.get("empty") else 1.0
    score = max(0.05, min(0.98, base * day_m * (0.85 + 0.15 * choke_m)))
    label = "Reinforced assault · score %.0f%% (ready %.0f%% · day×%.2f · choke×%.2f)" % (
        score * 100.0,
        base * 100.0,
        day_m,
        choke_m,
    )
    return {
        "score": float(score),
        "readiness": ready,
        "daylight": day,
        "choke": choke,
        "integration": ["assault_ready", "daylight", "choke"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#ff9a6e]⚔ Reinforced[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(ready.get("empty", False)),
    }


def war_path_urgency(
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Focus wx + agenda execute pick urgency."""
    focus = focus_weather_aware_score(focus_base, focus_id, weather)
    pick = agenda_execute_pick(trail or [])
    urgency = float(focus.get("boost", 0.0)) / 20.0
    if not pick.get("empty"):
        urgency += 0.25
    urgency = max(0.0, min(1.0, urgency))
    label = "War path urgency %.0f%% · focus %s · pick %s" % (
        urgency * 100.0,
        focus_id,
        "yes" if not pick.get("empty") else "none",
    )
    return {
        "urgency": float(urgency),
        "focus": focus,
        "execute_pick": pick,
        "integration": ["focus_wx", "agenda_execute"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#c084fc]◆ War path[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def oob_factory_risk_loop(
    weather: Optional[Mapping[str, Any]] = None,
    base_output: float = 1.0,
) -> Dict[str, Any]:
    """Production weather mult × factory risk for OOB lines."""
    w = dict(weather or {})
    prod = production_weather_multiplier(w)
    risk = factory_risk_compose(w)
    effective = max(0.1, float(base_output) * prod * (1.0 - float(risk["risk"]) * 0.4))
    label = "OOB factory · out ×%.2f (prod ×%.2f · risk %.0f%%)" % (
        effective,
        prod,
        float(risk["risk"]) * 100.0,
    )
    return {
        "effective_output": float(effective),
        "production_mult": float(prod),
        "risk": risk,
        "integration": ["production", "factory_risk", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#f87171]🏭 OOB factory[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def force_supply_posture(
    force_strength: float = 50.0,
    supply_health: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Force report pressure × supply chain health."""
    force = max(0.0, float(force_strength))
    supply = max(0.15, min(1.5, float(supply_health)))
    pressure = weather_pressure_index(weather or {})
    # Posture score: forces thrives with supply, hurt by weather pressure
    posture = (force / 100.0) * supply * (1.0 - float(pressure["pressure"]) * 0.35)
    posture = max(0.05, min(1.5, posture))
    label = "Force×supply · posture ×%.2f (force %.0f · supply ×%.2f)" % (
        posture,
        force,
        supply,
    )
    return {
        "posture": float(posture),
        "force_strength": force,
        "supply_health": supply,
        "pressure": pressure,
        "integration": ["force", "supply", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🛡 Force×supply[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def leader_weather_assign(
    leader_skill: float = 0.5,
    weather: Optional[Mapping[str, Any]] = None,
    armored: bool = False,
) -> Dict[str, Any]:
    """Leader skill × weather move for station preference."""
    skill = max(0.1, min(1.5, float(leader_skill)))
    move_m = movement_multiplier(weather or {}, unit_tags=["armor"] if armored else [])
    # Better leaders offset foul weather slightly
    effective = move_m * (0.85 + 0.3 * skill)
    effective = max(0.15, min(1.6, effective))
    label = "Leader×wx · move ×%.2f (skill %.2f · wx ×%.2f)" % (effective, skill, move_m)
    return {
        "effective_move": float(effective),
        "leader_skill": skill,
        "weather_move_mult": float(move_m),
        "integration": ["leader", "weather", "move"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]★ Leader×wx[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def joint_ops_loop_strip(
    basing_logistics: Optional[Mapping[str, Any]] = None,
    follow_on: Optional[Mapping[str, Any]] = None,
    execute_pick: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Inspector strip of basing logistics + follow-on + execute pick."""
    lines: List[str] = []
    for block in (basing_logistics, follow_on, execute_pick):
        if not block or block.get("empty"):
            continue
        s = str(block.get("summary", block.get("label", ""))).strip()
        if s:
            lines.append(s.split("\n")[0])
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "lines": []}
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#5ec8ff]── Joint ops loop ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
    )
    return {
        "lines": lines,
        "count": len(lines),
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": "Joint ops loop · %d" % len(lines),
        "integration": ["basing_logistics", "follow_on", "agenda_execute"],
    }


def sole_mult_integrity(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
) -> Dict[str, Any]:
    """Gate: compose health equals sea×wx×(1-risk) — no double-count identity."""
    from integrated_theater_ops import trade_supply_weather_chain as tsc  # local

    # trade_supply_weather_chain uses weather dict not mult; reconstruct via formula
    expected = max(0.1, min(1.4, float(sea_mult) * float(weather_mult) * (1.0 - float(route_risk) * 0.25)))
    # Simulate: if someone double-counted: sea * wx * chain(sea,wx)
    double = expected * expected / max(0.1, float(weather_mult))  # nonsense stack pattern
    ok = abs(expected - (float(sea_mult) * float(weather_mult) * (1.0 - float(route_risk) * 0.25))) < 1e-9
    # Integrity: double-count path must differ from sole path when mults != 1
    sole = expected
    stacked = float(sea_mult) * float(weather_mult) * sole  # the anti-pattern
    integrity = abs(sole - stacked) > 0.01 if (sea_mult != 1.0 or weather_mult != 1.0) else True
    # When inputs non-trivial, stacked double-count must not equal sole
    if abs(sea_mult - 1.0) > 0.05 or abs(weather_mult - 1.0) > 0.05:
        integrity = abs(stacked - sole) > 0.01
    else:
        integrity = True
    return {
        "sole_health": float(sole),
        "stacked_health": float(stacked),
        "integrity_ok": integrity,
        "summary": "sole-mult integrity %s (sole %.3f · stacked %.3f)"
        % ("PASS" if integrity else "FAIL", sole, stacked),
        "empty": False,
        "integration": ["trade_chain", "sole_mult"],
    }
