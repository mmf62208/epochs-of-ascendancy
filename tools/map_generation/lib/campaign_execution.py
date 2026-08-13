"""Campaign execution pilots beyond campaign-cohesion.

Turns campaign boards into executable orders, map effects, next-day feedback,
and integrity gates — player-facing close-the-loop surfaces.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_cohesion import (  # type: ignore
    fleet_campaign_plan,
    combat_campaign_phase,
    agent_campaign_response,
    hh_campaign_board,
    theater_campaign_strip,
    production_campaign_risk,
    supply_campaign_spine,
    focus_war_path_board,
    force_posture_board,
    naval_campaign_package,
    air_land_joint_package,
    campaign_decision_strip,
    cohesion_integrity_gate,
)
from gameplay_loops import sole_mult_integrity  # type: ignore
from integrated_theater_ops import format_campaign_strip  # type: ignore


def _avg(*vals: float) -> float:
    xs = [float(v) for v in vals]
    return float(sum(xs)) / max(1, len(xs))


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def fleet_order_execute(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Fleet campaign → DEPLOY order string."""
    plan = fleet_campaign_plan(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
    )
    score = _score(plan, "score")
    role = "PATROL"
    if score >= 0.55 and fuel_level >= 0.45:
        role = "STRIKE" if zone_relation in ("hostile", "contested") else "ESCORT"
    elif score < 0.35 or fuel_level < 0.35:
        role = "REFUEL" if basing_level in ("port", "major_base", "anchorage") else "HOLD"
    order = "DEPLOY FLEET %s L%s strength=%.0f @#%d" % (
        role,
        basing_level.upper(),
        available_strength,
        int(province_id),
    )
    label = "Fleet order · %s · score %.2f" % (role, score)
    return {
        "order": order,
        "role": role,
        "score": score,
        "plan": plan,
        "province_id": int(province_id),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]⚓ Fleet order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["fleet_campaign", "execute"],
    }


def combat_order_execute(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Combat campaign phase → PRESS/HOLD/SOFTEN order."""
    phase = combat_campaign_phase(
        targets=targets,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=weather,
        month=month,
    )
    score = _score(phase, "score")
    fo = phase.get("follow_on") or {}
    step = str(fo.get("next_step", "")).lower()
    if not step or step == "none":
        if score >= 0.55:
            step = "press"
        elif score >= 0.35:
            step = "hold"
        else:
            step = "soften"
    order = "COMBAT %s power=%.0f supply=%.0f%% @#%d" % (
        step.upper(),
        attacker_power,
        attacker_supply * 100.0,
        int(province_id),
    )
    label = "Combat order · %s · score %.2f" % (step.upper(), score)
    return {
        "order": order,
        "step": step,
        "score": score,
        "phase": phase,
        "province_id": int(province_id),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]⚔ Combat order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["combat_campaign", "execute"],
    }


def agent_order_dispatch(
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    """Agent campaign response → mission dispatch order."""
    resp = agent_campaign_response(
        signal=signal,
        available_agents=available_agents,
        network_strength=network_strength,
        loyalty=loyalty,
    )
    order_block = resp.get("order") or {}
    order = str(order_block.get("order", "")).strip()
    if not order:
        top = str(order_block.get("top_action", "monitor")).upper()
        pid = int((signal or {}).get("province_id", -1))
        order = "DISPATCH %s agents=%d @#%d" % (top, available_agents, pid)
    score = _score(resp, "score")
    label = "Agent dispatch · score %.2f" % score
    return {
        "order": order,
        "score": score,
        "response": resp,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]🕵 Agent dispatch[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["agent_campaign", "dispatch"],
    }


def hh_order_commit(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_commits: int = 3,
) -> Dict[str, Any]:
    """HH campaign board → commit NEXT action; empty trail → empty."""
    t = list(trail or [])
    if not t:
        return {"empty": True, "order": "", "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    board = hh_campaign_board(trail=t, max_commits=max_commits)
    if board.get("empty"):
        return {"empty": True, "order": "", "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    pick = board.get("pick") or {}
    next_line = str(pick.get("pick", pick.get("summary", ""))).strip()
    if not next_line:
        plain = str(board.get("plain", "")).strip()
        next_line = plain.split("\n")[0] if plain else "HOLD AGENDA"
    if not next_line.upper().startswith("NEXT") and not next_line.upper().startswith("COMMIT"):
        order = "COMMIT %s" % next_line
    else:
        order = next_line if next_line.upper().startswith("COMMIT") else "COMMIT %s" % next_line
    score = _score(board, "score", default=0.5)
    label = "HH order commit · score %.2f" % score
    return {
        "order": order,
        "score": score,
        "board": board,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]📜 HH commit[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["hh_campaign", "commit"],
    }


def map_effect_resolve(
    order: str = "",
    province_id: int = -1,
    score: float = 0.5,
    effect_class: str = "ops",
) -> Dict[str, Any]:
    """Order → province map-effect summary."""
    o = str(order or "").strip()
    if not o:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    strength = max(0.15, min(1.0, float(score)))
    cls = str(effect_class or "ops").lower()
    if "FLEET" in o.upper() or "DEPLOY" in o.upper():
        cls = "naval"
        marker = "⚓"
    elif "COMBAT" in o.upper() or "PRESS" in o.upper() or "SOFTEN" in o.upper():
        cls = "combat"
        marker = "⚔"
    elif "DISPATCH" in o.upper() or "AGENT" in o.upper() or "NETWORK" in o.upper():
        cls = "intel"
        marker = "◈"
    elif "COMMIT" in o.upper() or "AGENDA" in o.upper():
        cls = "agenda"
        marker = "📜"
    elif "PROD" in o.upper() or "LINE" in o.upper():
        cls = "industry"
        marker = "🏭"
    elif "SUPPLY" in o.upper() or "ROUTE" in o.upper():
        cls = "supply"
        marker = "📦"
    else:
        marker = "★"
    effect = {
        "province_id": int(province_id),
        "effect_class": cls,
        "marker": marker,
        "strength": strength,
        "order": o,
        "active": True,
        "tint_key": "ops_%s" % cls,
    }
    label = "Map effect · %s %s ×%.0f%% @#%d" % (marker, cls, strength * 100.0, int(province_id))
    return {
        "effect": effect,
        "score": strength,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, o),
        "bbcode": "[color=#5ec8ff]%s Map effect[/color] [color=#8899aa]%s[/color]" % (marker, label),
        "empty": False,
        "integration": ["order", "map_effect"],
    }


def next_day_feedback(
    before_score: float = 0.5,
    after_score: float = 0.55,
    order: str = "",
) -> Dict[str, Any]:
    """Before/after score delta after execute — next-day feedback."""
    b = float(before_score)
    a = float(after_score)
    delta = a - b
    trend = "improved" if delta > 0.02 else ("worsened" if delta < -0.02 else "steady")
    label = "Next-day feedback · %s · Δ%+.2f (%.2f→%.2f)" % (trend, delta, b, a)
    o = str(order or "").strip()
    plain_lines = [label]
    if o:
        plain_lines.append("after: %s" % o.split("\n")[0])
    return {
        "before": b,
        "after": a,
        "delta": delta,
        "trend": trend,
        "order": o,
        "summary": label,
        "label": label,
        "plain": "\n".join(plain_lines),
        "bbcode": "[color=#5ec8ff]↻ Next-day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["execute", "feedback"],
    }


def production_order_resolve(
    weather: Optional[Mapping[str, Any]] = None,
    base_output: float = 1.0,
    line_id: str = "primary",
) -> Dict[str, Any]:
    """Production campaign risk → line priority order."""
    risk = production_campaign_risk(weather=weather, base_output=base_output)
    r = _score(risk, "risk", "score", default=0.0)
    if r >= 0.35:
        priority = "SHIELD"
        order = "PROD LINE %s PRIORITY SHIELD risk=%.0f%%" % (line_id, r * 100.0)
    elif r >= 0.15:
        priority = "MONITOR"
        order = "PROD LINE %s PRIORITY MONITOR risk=%.0f%%" % (line_id, r * 100.0)
    else:
        priority = "SURGE"
        order = "PROD LINE %s PRIORITY SURGE risk=%.0f%%" % (line_id, r * 100.0)
    label = "Production order · %s · risk %.2f" % (priority, r)
    return {
        "order": order,
        "priority": priority,
        "risk": r,
        "score": 1.0 - r,
        "campaign": risk,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]🏭 Prod order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "sole_mult": True,
        "integration": ["production_campaign", "order"],
    }


def supply_order_resolve(
    weather: Optional[Mapping[str, Any]] = None,
    basing_level: str = "port",
    sea_mult: float = 1.0,
    route_id: str = "main",
) -> Dict[str, Any]:
    """Supply campaign spine → route priority order."""
    spine = supply_campaign_spine(
        weather=weather, basing_level=basing_level, sea_mult=sea_mult
    )
    score = _score(spine, "score")
    if score < 0.35:
        priority = "REROUTE"
    elif score < 0.55:
        priority = "ESCORT"
    else:
        priority = "SUSTAIN"
    order = "SUPPLY ROUTE %s PRIORITY %s health=%.0f%%" % (route_id, priority, score * 100.0)
    label = "Supply order · %s · score %.2f" % (priority, score)
    return {
        "order": order,
        "priority": priority,
        "score": score,
        "spine": spine,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]📦 Supply order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "sole_mult": True,
        "integration": ["supply_campaign", "order"],
    }


def naval_order_package(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Naval campaign → task order package."""
    pkg = naval_campaign_package(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
    )
    fleet = fleet_order_execute(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
        province_id=province_id,
    )
    score = _avg(_score(pkg, "score"), _score(fleet, "score"))
    order = "NAVAL TASK %s · %s" % (fleet.get("role", "PATROL"), fleet.get("order", ""))
    label = "Naval order package · score %.2f" % score
    return {
        "order": order,
        "score": score,
        "package": pkg,
        "fleet_order": fleet,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]🚢 Naval order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["naval_campaign", "fleet_order"],
    }


def air_land_order_package(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    attacker_power: float = 100.0,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Air-land joint → sortie/assault order."""
    joint = air_land_joint_package(
        weather=weather, month=month, attacker_power=attacker_power
    )
    combat = combat_order_execute(
        attacker_power=attacker_power, weather=weather, month=month, province_id=province_id
    )
    score = _avg(_score(joint, "score"), _score(combat, "score"))
    air_ok = _score(joint, "score") >= 0.4
    air_part = "SORTIE READY" if air_ok else "GROUND AIR"
    order = "AIR-LAND %s · %s" % (air_part, combat.get("step", "hold").upper())
    label = "Air-land order · score %.2f" % score
    return {
        "order": order,
        "score": score,
        "joint": joint,
        "combat_order": combat,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]✈ Air-land order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["air_land_joint", "combat_order"],
    }


def theater_order_board(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Theater campaign strip → ranked orders."""
    strip = theater_campaign_strip(
        weather=weather,
        month=month,
        available_strength=available_strength,
        zone_relation=zone_relation,
        basing_level=basing_level,
        fuel_level=fuel_level,
    )
    orders: List[Dict[str, Any]] = [
        fleet_order_execute(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=weather,
            province_id=province_id,
        ),
        combat_order_execute(
            attacker_power=available_strength,
            weather=weather,
            month=month,
            province_id=province_id,
        ),
        supply_order_resolve(weather=weather, basing_level=basing_level),
    ]
    ranked = sorted(orders, key=lambda o: float(o.get("score", 0.0)), reverse=True)
    lines = [str(o.get("order", "")) for o in ranked if o.get("order")]
    score = _avg(*[_score(o, "score") for o in ranked], _score(strip, "score"))
    label = "Theater order board · %d orders · score %.2f" % (len(lines), score)
    return {
        "orders": ranked,
        "lines": lines,
        "count": len(lines),
        "score": score,
        "strip": strip,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "[color=#5ec8ff]🗺 Theater orders[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["theater_campaign", "fleet_order", "combat_order", "supply_order"],
    }


def focus_order_path(
    weather: Optional[Mapping[str, Any]] = None,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Focus war path → next focus action order."""
    board = focus_war_path_board(
        weather=weather, focus_id=focus_id, focus_base=focus_base, trail=trail
    )
    score = _score(board, "score")
    if score >= 0.55:
        action = "PUSH"
    elif score >= 0.35:
        action = "HOLD"
    else:
        action = "REDIRECT"
    order = "FOCUS %s %s score=%.0f%%" % (action, focus_id, score * 100.0)
    label = "Focus order · %s · %.2f" % (action, score)
    return {
        "order": order,
        "action": action,
        "score": score,
        "board": board,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (order, label),
        "bbcode": "[color=#5ec8ff]🎯 Focus order[/color] [color=#8899aa]%s[/color]" % order,
        "empty": False,
        "integration": ["focus_war_path", "order"],
    }


def execution_decision_strip(
    orders: Optional[Sequence[Mapping[str, Any]]] = None,
    feedback: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Inspector strip of executed orders + feedback."""
    blocks: List[Mapping[str, Any]] = []
    for o in list(orders or []):
        if o and not o.get("empty"):
            blocks.append(o)
    if feedback and not feedback.get("empty"):
        blocks.append(feedback)
    if not blocks:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    strip = format_campaign_strip(blocks, max_lines=6)
    lines: List[str] = []
    for b in blocks:
        s = str(b.get("order", b.get("summary", b.get("label", "")))).strip()
        if s:
            lines.append(s.split("\n")[0])
    label = "Execution decision strip · %d" % len(lines)
    bb = "\n".join(
        ["[color=#5ec8ff]── Execution ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[:6]]
    )
    out = dict(strip) if isinstance(strip, dict) else {}
    out.update(
        {
            "count": len(lines),
            "lines": lines[:6],
            "plain": "\n".join(lines[:6]),
            "bbcode": bb,
            "summary": label,
            "label": label,
            "empty": False,
            "integration": ["orders", "feedback", "decision"],
        }
    )
    return out


def execution_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    order_mult: float = 1.0,
) -> Dict[str, Any]:
    """Sole-mult + cohesion hold after order mults — execution integrity."""
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    coh = cohesion_integrity_gate(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    coh_ok = bool(coh.get("ok", False))
    # Order mult applied once (sole) — stacking order_mult twice must diverge when non-1
    sole_health = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(order_mult)))
    stacked = sole_health * max(0.1, min(1.4, float(order_mult)))  # anti-pattern double order mult
    order_ok = True
    if abs(float(order_mult) - 1.0) > 0.05:
        order_ok = abs(stacked - sole_health) > 0.01
    ok = sole_ok and coh_ok and order_ok
    label = "Execution integrity %s (sole=%s coh=%s order=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if coh_ok else "fail",
        "ok" if order_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "cohesion": coh,
        "sole_after_order": sole_health,
        "stacked_order": stacked,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Exec integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "cohesion", "order_mult"],
    }


def close_the_loop(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    province_id: int = 1,
    basing_level: str = "port",
    fuel_level: float = 0.55,
) -> Dict[str, Any]:
    """Compose: decide → order → map effect → next-day feedback (2+ cross-system)."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))

    fleet = fleet_order_execute(
        basing_level=basing_level, fuel_level=fuel_level, weather=w, province_id=province_id
    )
    combat = combat_order_execute(weather=w, province_id=province_id)
    hh = hh_order_commit(trail=trail)
    before = _avg(_score(fleet, "score"), _score(combat, "score"))
    # After: re-score under fouler weather (execution cost)
    fleet_after = fleet_order_execute(
        basing_level=basing_level, fuel_level=fuel_level, weather=foul, province_id=province_id
    )
    after = _avg(_score(fleet_after, "score"), _score(combat, "score") * 0.95)
    effect = map_effect_resolve(
        order=str(fleet.get("order", "")),
        province_id=province_id,
        score=_score(fleet, "score"),
    )
    fb = next_day_feedback(before_score=before, after_score=after, order=str(fleet.get("order", "")))
    strip = execution_decision_strip(
        orders=[fleet, combat] + ([hh] if not hh.get("empty") else []),
        feedback=fb,
    )
    gate = execution_integrity_gate()
    return {
        "fleet_order": fleet,
        "combat_order": combat,
        "hh_order": hh,
        "map_effect": effect,
        "feedback": fb,
        "strip": strip,
        "integrity": gate,
        "summary": "Close-the-loop · orders=%d · integrity %s"
        % (int(strip.get("count", 0)), "PASS" if gate.get("ok") else "FAIL"),
        "empty": False,
        "integration": ["order", "map_effect", "feedback", "integrity"],
    }
