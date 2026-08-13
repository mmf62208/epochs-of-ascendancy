"""Campaign cohesion pilots beyond gameplay-loops.

Composes multi-system loops into player-facing campaign boards:
fleet campaign plan, combat campaign phase, agent campaign response,
HH campaign board, theater/production/supply spines, focus/force/leader
boards, naval/air-land packages, campaign decision strip, cohesion integrity.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import (  # type: ignore
    basing_fleet_fuel_logistics,
    assault_follow_on_loop,
    counter_ops_execute_order,
    agenda_execute_pick,
    basing_repair_weather_loop,
    sealane_joint_health,
    reinforced_assault_loop,
    war_path_urgency,
    oob_factory_risk_loop,
    force_supply_posture,
    leader_weather_assign,
    joint_ops_loop_strip,
    sole_mult_integrity,
)
from integrated_theater_ops import (  # type: ignore
    fleet_weather_mission_package,
    assault_readiness_compose,
    theater_readiness_board,
    convoy_package_compose,
    war_cabinet_board,
    supply_chain_health,
    air_ops_package,
    format_campaign_strip,
    cross_system_coherence_delta,
    campaign_day_risk,
)
from theater_ops_polish import (  # type: ignore
    production_weather_alert,
    daylight_combat_mod,
    focus_weather_aware_score,
)
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from hh_quarterly_rollup import format_hh_quarterly_rollup  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore


def _avg(*vals: float) -> float:
    xs = [float(v) for v in vals]
    return float(sum(xs)) / max(1, len(xs))


def _score_of(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def fleet_campaign_plan(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    path_zone_relations: Optional[Sequence[str]] = None,
    sea_trade_mult: float = 1.0,
) -> Dict[str, Any]:
    """Basing logistics × theater readiness × sealane joint — fleet campaign plan."""
    w = dict(weather or {})
    path = list(path_zone_relations or [zone_relation, "friendly"])
    basing = basing_fleet_fuel_logistics(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=w,
    )
    fleet_pkg = fleet_weather_mission_package(
        mission="patrol",
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=w,
    )
    assault = assault_readiness_compose(
        targets=[{"id": 1, "power": 40.0, "supply": 0.8}],
        attacker_power=available_strength,
        weather=w,
    )
    day = campaign_day_risk(w, month=month)
    theater = theater_readiness_board(fleet_package=fleet_pkg, assault=assault, day_risk=day)
    sealane = sealane_joint_health(
        path_zone_relations=path,
        sea_trade_mult=sea_trade_mult,
        weather=w,
        available_fleet=available_strength,
    )
    score = _avg(
        _score_of(basing, "logistics_score", "score", "health"),
        _score_of(theater, "readiness", "score", "board_score"),
        _score_of(sealane, "joint_health", "health", "score"),
    )
    label = "Fleet campaign · basing+theater+sealane · score %.2f" % score
    return {
        "score": score,
        "basing": basing,
        "theater": theater,
        "sealane": sealane,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]⚓ Fleet campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["basing_logistics", "theater_readiness", "sealane_joint"],
    }


def combat_campaign_phase(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    is_choke: bool = False,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Follow-on × reinforced × war path — combat campaign phase."""
    w = dict(weather or {})
    tgts = list(targets or [{"id": 1, "power": 40.0, "supply": 0.7}])
    fo = assault_follow_on_loop(
        targets=tgts,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=w,
    )
    reinf = reinforced_assault_loop(
        targets=tgts,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=w,
        month=month,
        is_choke=is_choke,
    )
    war = war_path_urgency(
        focus_id="industrial_effort",
        focus_base=50.0,
        weather=w,
        trail=list(trail or []),
    )
    score = _avg(
        _score_of(fo, "score", "readiness", "follow_on_score"),
        _score_of(reinf, "score", "readiness", "reinforced_score"),
        _score_of(war, "urgency", "score"),
    )
    label = "Combat campaign · follow-on+reinf+war · score %.2f" % score
    return {
        "score": score,
        "follow_on": fo,
        "reinforced": reinf,
        "war_path": war,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]⚔ Combat campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["follow_on", "reinforced", "war_path"],
    }


def agent_campaign_response(
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    """Execute order × coverage × escalation — agent campaign response."""
    sig = dict(signal or {"class": "sabotage", "action_class": "sabotage", "influence": 0.6})
    order = counter_ops_execute_order(
        signal=sig,
        network_strength=network_strength,
        available_agents=available_agents,
        loyalty=loyalty,
    )
    threats = [sig]
    cov = plan_agent_coverage(
        threats,
        available_agents=available_agents,
        network_strength=network_strength,
    )
    esc = plan_agent_escalation(
        sig,
        network_strength=network_strength,
        available_agents=available_agents,
        loyalty=loyalty,
    )
    order_score = 0.7 if not order.get("empty") and str(order.get("order", "")).strip() else 0.2
    cov_score = min(1.0, float(cov.get("covered", 0) or 0) / max(1.0, float(available_agents)))
    if cov.get("empty") and not cov.get("assignments"):
        cov_score = 0.35  # partial board still counts as campaign response
    esc_score = min(1.0, float(esc.get("level", 0) or 0) / 3.0)
    score = min(1.0, _avg(order_score, cov_score, esc_score))
    label = "Agent campaign · order+coverage+escalation · score %.2f" % score
    return {
        "score": score,
        "order": order,
        "coverage": cov,
        "escalation": esc,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🕵 Agent campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["counter_ops_execute", "coverage", "escalation"],
    }


def hh_campaign_board(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_commits: int = 3,
    weather: Optional[Mapping[str, Any]] = None,
    signal: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Agenda execute × quarterly × war cabinet — HH campaign board."""
    t = list(trail or [])
    # Empty trail → empty board (no spam; matches agenda execute pick contract)
    if not t:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    pick = agenda_execute_pick(trail=t, max_commits=max_commits)
    q = format_hh_quarterly_rollup(t)
    cab = war_cabinet_board(
        focus_id="industrial_effort",
        focus_base=50.0,
        weather=weather,
        signal=signal,
        trail=t,
    )
    empty = bool(pick.get("empty")) and bool(q.get("empty", not t)) and bool(cab.get("empty", False))
    if empty:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    lines: List[str] = []
    for block in (pick, q, cab):
        if not block or block.get("empty"):
            continue
        s = str(block.get("summary", block.get("plain", block.get("label", "")))).strip()
        if s:
            lines.append(s.split("\n")[0])
    score = min(1.0, 0.2 * len(lines) + (0.25 if not pick.get("empty") else 0.0))
    label = "HH campaign board · %d parts" % max(1, len(lines))
    return {
        "score": score,
        "pick": pick,
        "quarterly": q,
        "cabinet": cab,
        "lines": lines,
        "summary": label,
        "label": label,
        "plain": "\n".join(lines),
        "bbcode": "[color=#5ec8ff]📜 HH campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["agenda_execute", "quarterly", "war_cabinet"],
    }


def theater_campaign_strip(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    path_zone_relations: Optional[Sequence[str]] = None,
    basing_level: str = "port",
    fuel_level: float = 0.6,
) -> Dict[str, Any]:
    """Theater readiness × convoy package × joint ops — theater campaign strip."""
    w = dict(weather or {})
    path = list(path_zone_relations or [zone_relation, "hostile"])
    fleet_pkg = fleet_weather_mission_package(
        available_strength=available_strength, zone_relation=zone_relation, weather=w
    )
    assault = assault_readiness_compose(
        targets=[{"id": 1, "power": 35.0}], attacker_power=available_strength, weather=w
    )
    day = campaign_day_risk(w, month=month)
    theater = theater_readiness_board(fleet_package=fleet_pkg, assault=assault, day_risk=day)
    convoy = convoy_package_compose(
        path_zone_relations=path,
        available_fleet_strength=available_strength,
        weather=w,
    )
    basing = basing_fleet_fuel_logistics(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=w,
    )
    fo = assault_follow_on_loop(
        targets=[{"id": 1, "power": 35.0}],
        attacker_power=available_strength,
        weather=w,
    )
    pick = agenda_execute_pick(trail=[{"class": "sabotage", "month": month, "influence": 0.5}])
    joint = joint_ops_loop_strip(basing_logistics=basing, follow_on=fo, execute_pick=pick)
    score = _avg(
        _score_of(theater, "readiness", "score", "board_score"),
        _score_of(convoy, "score", "package_score", "health"),
        min(1.0, float(joint.get("count", 1)) / 3.0),
    )
    label = "Theater campaign · readiness+convoy+joint · score %.2f" % score
    return {
        "score": score,
        "theater": theater,
        "convoy": convoy,
        "joint": joint,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🗺 Theater campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["theater_readiness", "convoy_package", "joint_ops"],
    }


def production_campaign_risk(
    weather: Optional[Mapping[str, Any]] = None,
    base_output: float = 1.0,
) -> Dict[str, Any]:
    """OOB factory risk × production weather alert — production campaign risk."""
    w = dict(weather or {})
    oob = oob_factory_risk_loop(weather=w, base_output=base_output)
    alert = production_weather_alert(w)
    mult = _score_of(oob, "mult", "effective_output", "output_mult", default=1.0)
    risk = max(0.0, min(1.0, 1.0 - mult))
    if not alert.get("empty", True):
        risk = min(1.0, risk + 0.12)
    label = "Production campaign risk · %.2f · oob mult %.2f" % (risk, mult)
    return {
        "score": risk,
        "risk": risk,
        "oob": oob,
        "alert": alert,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🏭 Production risk[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["oob_factory_risk", "production_weather"],
        "sole_mult": True,
    }


def supply_campaign_spine(
    weather: Optional[Mapping[str, Any]] = None,
    basing_level: str = "port",
    sea_mult: float = 1.0,
    path_zone_relations: Optional[Sequence[str]] = None,
    available_fleet: float = 80.0,
    base_depot: float = 100.0,
) -> Dict[str, Any]:
    """Supply chain × basing repair × sealane — supply campaign spine."""
    w = dict(weather or {})
    path = list(path_zone_relations or ["friendly", "contested"])
    chain = supply_chain_health(base_depot=base_depot, sea_mult=sea_mult, weather=w)
    repair = basing_repair_weather_loop(basing_level=basing_level, weather=w)
    sealane = sealane_joint_health(
        path_zone_relations=path,
        sea_trade_mult=sea_mult,
        weather=w,
        available_fleet=available_fleet,
    )
    score = _avg(
        _score_of(chain, "health", "score", "chain_health"),
        _score_of(repair, "repair_rate", "repair_org_rate", "score", default=0.4),
        _score_of(sealane, "joint_health", "health", "score"),
    )
    label = "Supply campaign spine · chain+repair+sealane · score %.2f" % score
    return {
        "score": score,
        "chain": chain,
        "repair": repair,
        "sealane": sealane,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]📦 Supply spine[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["supply_chain", "basing_repair", "sealane_joint"],
        "sole_mult": True,
    }


def focus_war_path_board(
    weather: Optional[Mapping[str, Any]] = None,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Focus wx pick × war path urgency × agenda execute — focus war path board."""
    w = dict(weather or {})
    t = list(trail or [{"class": "economic_pressure", "influence": 0.4}])
    focus = focus_weather_aware_score(focus_base, focus_id=focus_id, weather=w)
    pick = agenda_execute_pick(trail=t)
    war = war_path_urgency(focus_id=focus_id, focus_base=focus_base, weather=w, trail=t)
    focus_norm = _score_of(focus, "score", "adjusted", default=focus_base) / max(1.0, float(focus_base) * 1.5)
    focus_norm = max(0.0, min(1.0, focus_norm))
    score = _avg(
        focus_norm,
        _score_of(war, "urgency", default=0.25),
        0.55 if not pick.get("empty") else 0.2,
    )
    label = "Focus war path · score %.2f" % score
    return {
        "score": score,
        "focus": focus,
        "war_path": war,
        "pick": pick,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🎯 Focus war path[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["focus_wx", "war_path", "agenda_execute"],
    }


def force_posture_board(
    force_strength: float = 50.0,
    supply_health: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Force×supply × multi-front readiness — force posture board."""
    w = dict(weather or {})
    posture = force_supply_posture(
        force_strength=force_strength,
        supply_health=supply_health,
        weather=w,
    )
    targets = list(
        fronts
        or [
            {"id": 1, "power": force_strength * 0.4},
            {"id": 2, "power": force_strength * 0.3},
        ]
    )
    ranked = rank_assault_targets(
        targets, attacker_power=force_strength, attacker_supply=supply_health
    )
    n = int(ranked.get("count", len(ranked.get("ranked", targets))) or len(targets))
    score = _avg(
        _score_of(posture, "score", "posture", "pressure", default=0.5),
        min(1.0, float(n) / 3.0),
    )
    label = "Force posture board · score %.2f" % score
    return {
        "score": score,
        "posture": posture,
        "fronts": ranked,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🛡 Force posture[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["force_supply", "multi_front"],
    }


def leader_campaign_assign(
    leader_skill: float = 0.6,
    weather: Optional[Mapping[str, Any]] = None,
    armored: bool = False,
) -> Dict[str, Any]:
    """Leader weather × skill for station — leader campaign assign."""
    w = dict(weather or {})
    assign = leader_weather_assign(leader_skill=leader_skill, weather=w, armored=armored)
    score = _score_of(assign, "score", "effective_skill", default=leader_skill)
    label = "Leader campaign assign · skill×wx %.2f" % score
    return {
        "score": score,
        "assign": assign,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]★ Leader campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["leader", "weather", "station"],
    }


def naval_campaign_package(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    path_zone_relations: Optional[Sequence[str]] = None,
    escort_need: float = 25.0,
) -> Dict[str, Any]:
    """Fleet+wx × basing logistics × convoy — naval campaign package."""
    w = dict(weather or {})
    path = list(path_zone_relations or [zone_relation, "hostile"])
    fleet_wx = fleet_weather_mission_package(
        mission="patrol",
        available_strength=available_strength,
        zone_relation=zone_relation,
        escort_need=escort_need,
        weather=w,
    )
    basing = basing_fleet_fuel_logistics(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=w,
    )
    convoy = convoy_package_compose(
        path_zone_relations=path,
        available_fleet_strength=available_strength,
        weather=w,
    )
    score = _avg(
        _score_of(fleet_wx, "spot_mult", "score", default=0.7),
        _score_of(basing, "logistics_score", "score", "health"),
        _score_of(convoy, "score", "package_score", "health"),
    )
    label = "Naval campaign package · fleet+basing+convoy · score %.2f" % score
    return {
        "score": score,
        "fleet_wx": fleet_wx,
        "basing": basing,
        "convoy": convoy,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]🚢 Naval campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_wx", "basing_logistics", "convoy_package"],
    }


def air_land_joint_package(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
) -> Dict[str, Any]:
    """Air ops × assault readiness × daylight — air-land joint package."""
    w = dict(weather or {})
    air = air_ops_package(w, month=month)
    assault = assault_readiness_compose(
        targets=list(targets or [{"id": 1, "power": 40.0}]),
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=w,
    )
    day = daylight_combat_mod(month)
    score = _avg(
        _score_of(air, "score", "sortie_ready", "readiness", default=0.5),
        _score_of(assault, "readiness", "score"),
        _score_of(day, "mult", "score", default=1.0),
    )
    label = "Air-land joint · air+assault+daylight · score %.2f" % score
    return {
        "score": score,
        "air": air,
        "assault": assault,
        "daylight": day,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✈ Air-land joint[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["air_ops", "assault_readiness", "daylight"],
    }


def campaign_decision_strip(
    boards: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Inspector strip of 3+ campaign boards — campaign decision strip."""
    blocks = [b for b in list(boards or []) if b and not b.get("empty")]
    strip = format_campaign_strip(blocks, max_lines=6)
    if not blocks:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    summaries: List[str] = []
    for b in blocks:
        s = str(b.get("summary", b.get("label", ""))).strip()
        if s:
            summaries.append(s.split("\n")[0])
    label = "Campaign decision strip · %d" % len(summaries)
    bb = "\n".join(
        ["[color=#5ec8ff]── Campaign decision ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in summaries[:6]]
    )
    out = dict(strip) if isinstance(strip, dict) else {}
    out.update(
        {
            "count": len(summaries),
            "lines": summaries[:6],
            "plain": "\n".join(summaries[:6]),
            "bbcode": bb,
            "summary": label,
            "label": label,
            "empty": False,
            "integration": ["fleet_campaign", "combat_campaign", "hh_campaign"],
        }
    )
    return out


def cohesion_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    clear_weather: Optional[Mapping[str, Any]] = None,
    foul_weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Sole-mult + coherence delta both pass — cohesion integrity gate."""
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    clear = dict(clear_weather or {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"})
    foul = dict(
        foul_weather
        or {
            "precip_intensity": 0.9,
            "visibility": 0.25,
            "ground_state": "mud",
            "wind": 0.8,
            "temperature_c": -5.0,
        }
    )
    coh = cross_system_coherence_delta(clear_weather=clear, foul_weather=foul)
    sole_ok = bool(sole.get("integrity_ok", False))
    # shipped coherence uses `changed` + summary PASS when foul shifts multi-system scores
    coh_ok = bool(coh.get("changed", coh.get("coherent", False)))
    if not coh_ok:
        delta = float(coh.get("delta", coh.get("score_delta", 0.0)) or 0.0)
        coh_ok = abs(delta) > 0.01
    if "PASS" in str(coh.get("summary", "")).upper():
        coh_ok = True
    ok = sole_ok and coh_ok
    label = "Cohesion integrity %s (sole=%s coh=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if coh_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "coherence": coh,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Cohesion[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "cross_system_coherence"],
    }
