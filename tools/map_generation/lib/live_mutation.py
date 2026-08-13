"""Live sim mutation pilots beyond campaign-execution.

Turns execution orders into mutation *plans* (pure) that GD apply sites
can feed into real SupplyManager / BattleManager / ProductionManager / GameData APIs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import (  # type: ignore
    fleet_order_execute,
    combat_order_execute,
    agent_order_dispatch,
    hh_order_commit,
    map_effect_resolve,
    next_day_feedback,
    production_order_resolve,
    supply_order_resolve,
    naval_order_package,
    air_land_order_package,
    theater_order_board,
    focus_order_path,
    execution_integrity_gate,
)
from integrated_theater_ops import format_campaign_strip  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def _avg(*vals: float) -> float:
    xs = [float(v) for v in vals]
    return float(sum(xs)) / max(1, len(xs))


def mutation_result(
    ok: bool,
    kind: str,
    detail: str = "",
    before: Optional[Mapping[str, Any]] = None,
    after: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Normalize apply result for inspector / tests."""
    status = "applied" if ok else "blocked"
    label = "Mutation %s · %s%s" % (status, kind, (" · " + detail) if detail else "")
    return {
        "ok": bool(ok),
        "kind": str(kind),
        "detail": str(detail),
        "before": dict(before or {}),
        "after": dict(after or {}),
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]⟳ Mutation[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["mutation", kind],
    }


def fleet_station_mutation(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = -1,
    formation_id: str = "",
    country_tag: str = "GER",
) -> Dict[str, Any]:
    """Fleet order → station/move mutation plan."""
    order = fleet_order_execute(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
        province_id=province_id,
    )
    role = str(order.get("role", "PATROL"))
    score = _score(order, "score")
    # Prefer basing province for REFUEL/HOLD; combat provinces for STRIKE
    prefer_basing = role in ("REFUEL", "HOLD", "ESCORT")
    plan = {
        "api": "SupplyManager.move_formation_to_province",
        "formation_id": str(formation_id or ""),
        "province_id": int(province_id),
        "country_tag": str(country_tag or "GER").upper(),
        "role": role,
        "prefer_basing": prefer_basing,
        "order": str(order.get("order", "")),
        "score": score,
        "apply_ready": bool(formation_id) and int(province_id) >= 0,
    }
    label = "Fleet station mutation · %s @#%d · score %.2f" % (role, int(province_id), score)
    return {
        "plan": plan,
        "order": order,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan.get("order", ""), label),
        "bbcode": "[color=#5ec8ff]⚓ Station mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_order", "move_formation"],
    }


def assault_stage_mutation(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    from_province_id: int = -1,
    target_province_id: int = -1,
    formation_id: str = "",
    attacker_tag: str = "GER",
) -> Dict[str, Any]:
    """Combat order → assault stage mutation plan (can_assault / execute path)."""
    order = combat_order_execute(
        targets=targets,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        weather=weather,
        month=month,
        province_id=target_province_id,
    )
    step = str(order.get("step", "hold"))
    score = _score(order, "score")
    # Only PRESS stages a real assault attempt; HOLD/SOFTEN stage prep only
    execute = step == "press"
    plan = {
        "api": "BattleManager.execute_province_assault" if execute else "BattleManager.can_assault_province",
        "attacker_tag": str(attacker_tag or "GER").upper(),
        "from_province_id": int(from_province_id),
        "target_province_id": int(target_province_id),
        "formation_id": str(formation_id or ""),
        "step": step,
        "execute": execute,
        "order": str(order.get("order", "")),
        "score": score,
        "apply_ready": bool(formation_id)
        and int(from_province_id) >= 0
        and int(target_province_id) >= 0,
    }
    label = "Assault stage mutation · %s · exec=%s · score %.2f" % (
        step.upper(),
        "yes" if execute else "prep",
        score,
    )
    return {
        "plan": plan,
        "order": order,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan.get("order", ""), label),
        "bbcode": "[color=#5ec8ff]⚔ Assault mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["combat_order", "assault"],
    }


def agent_dispatch_mutation(
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    """Agent dispatch → mission plan record (mutation plan)."""
    disp = agent_order_dispatch(
        signal=signal,
        available_agents=available_agents,
        network_strength=network_strength,
        loyalty=loyalty,
    )
    sig = dict(signal or {})
    plan = {
        "api": "GameData.record_agent_dispatch_mutation",
        "order": str(disp.get("order", "")),
        "province_id": int(sig.get("province_id", -1)),
        "action_class": str(sig.get("action_class", sig.get("class", "sabotage"))),
        "agents": int(available_agents),
        "score": _score(disp, "score"),
        "apply_ready": True,
    }
    label = "Agent dispatch mutation · score %.2f" % plan["score"]
    return {
        "plan": plan,
        "order": disp,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan["order"], label),
        "bbcode": "[color=#5ec8ff]🕵 Dispatch mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["agent_dispatch", "mutation"],
    }


def hh_commit_mutation(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_commits: int = 3,
) -> Dict[str, Any]:
    """HH commit → trail stamp mutation plan; empty trail → empty."""
    t = list(trail or [])
    if not t:
        return {"empty": True, "plan": {}, "order": "", "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    commit = hh_order_commit(trail=t, max_commits=max_commits)
    if commit.get("empty"):
        return {"empty": True, "plan": {}, "order": "", "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    plan = {
        "api": "GameData.apply_hh_order_commit_mutation",
        "order": str(commit.get("order", "")),
        "score": _score(commit, "score"),
        "trail_len": len(t),
        "apply_ready": True,
    }
    label = "HH commit mutation · score %.2f" % plan["score"]
    return {
        "plan": plan,
        "order": commit,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan["order"], label),
        "bbcode": "[color=#5ec8ff]📜 HH mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["hh_commit", "mutation"],
    }


def production_priority_mutation(
    weather: Optional[Mapping[str, Any]] = None,
    base_output: float = 1.0,
    line_id: str = "primary",
    unit_id: str = "",
) -> Dict[str, Any]:
    """PROD order → priority reinforcement mutation plan."""
    prod = production_order_resolve(weather=weather, base_output=base_output, line_id=line_id)
    priority = str(prod.get("priority", "MONITOR"))
    enable = priority in ("SHIELD", "SURGE")
    plan = {
        "api": "ProductionManager.set_unit_priority_reinforcement",
        "unit_id": str(unit_id or line_id),
        "line_id": str(line_id),
        "enabled": enable,
        "priority": priority,
        "order": str(prod.get("order", "")),
        "score": _score(prod, "score"),
        "apply_ready": bool(unit_id or line_id),
        "sole_mult": True,
    }
    label = "Production priority mutation · %s · enable=%s" % (priority, enable)
    return {
        "plan": plan,
        "order": prod,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan["order"], label),
        "bbcode": "[color=#5ec8ff]🏭 Prod mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["production_order", "priority_reinforcement"],
    }


def supply_route_mutation(
    weather: Optional[Mapping[str, Any]] = None,
    basing_level: str = "port",
    sea_mult: float = 1.0,
    route_id: str = "main",
    province_id: int = -1,
) -> Dict[str, Any]:
    """SUPPLY order → route priority state mutation plan."""
    supply = supply_order_resolve(
        weather=weather, basing_level=basing_level, sea_mult=sea_mult, route_id=route_id
    )
    priority = str(supply.get("priority", "SUSTAIN"))
    plan = {
        "api": "GameData.apply_supply_route_mutation",
        "route_id": str(route_id),
        "province_id": int(province_id),
        "priority": priority,
        "order": str(supply.get("order", "")),
        "score": _score(supply, "score"),
        "apply_ready": True,
        "sole_mult": True,
    }
    label = "Supply route mutation · %s · score %.2f" % (priority, plan["score"])
    return {
        "plan": plan,
        "order": supply,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan["order"], label),
        "bbcode": "[color=#5ec8ff]📦 Supply mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["supply_order", "route_state"],
    }


def map_effect_store_mutation(
    order: str = "",
    province_id: int = -1,
    score: float = 0.5,
) -> Dict[str, Any]:
    """Map effect → store mutation plan (GameData campaign_effects trail)."""
    effect = map_effect_resolve(order=order, province_id=province_id, score=score)
    if effect.get("empty"):
        return {"empty": True, "plan": {}, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    plan = {
        "api": "GameData.store_campaign_map_effect",
        "effect": effect.get("effect", {}),
        "order": str(order),
        "province_id": int(province_id),
        "score": _score(effect, "score"),
        "apply_ready": True,
    }
    label = "Map effect store · @#%d · score %.2f" % (int(province_id), plan["score"])
    return {
        "plan": plan,
        "effect": effect,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, order),
        "bbcode": "[color=#5ec8ff]★ Effect store[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["map_effect", "store"],
    }


def next_day_mutation_feedback(
    before_score: float = 0.5,
    after_score: float = 0.55,
    mutation_kind: str = "station",
    order: str = "",
) -> Dict[str, Any]:
    """Before/after after apply — next-day mutation feedback."""
    fb = next_day_feedback(before_score=before_score, after_score=after_score, order=order)
    label = "Mutation feedback · %s · %s" % (mutation_kind, fb.get("trend", "steady"))
    out = dict(fb)
    out["mutation_kind"] = str(mutation_kind)
    out["summary"] = label
    out["label"] = label
    out["bbcode"] = "[color=#5ec8ff]↻ Mut feedback[/color] [color=#8899aa]%s[/color]" % label
    out["integration"] = ["mutation", "feedback"]
    return out


def naval_task_mutation(
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = -1,
    formation_id: str = "",
    country_tag: str = "ENG",
) -> Dict[str, Any]:
    """Naval order → basing station preference mutation plan."""
    naval = naval_order_package(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
        province_id=province_id,
    )
    station = fleet_station_mutation(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_strength,
        zone_relation=zone_relation,
        weather=weather,
        province_id=province_id,
        formation_id=formation_id,
        country_tag=country_tag,
    )
    score = _avg(_score(naval, "score"), _score(station, "score"))
    plan = dict(station.get("plan") or {})
    plan["api"] = "SupplyManager.move_formation_to_province"
    plan["naval_order"] = str(naval.get("order", ""))
    plan["score"] = score
    label = "Naval task mutation · score %.2f" % score
    return {
        "plan": plan,
        "naval": naval,
        "station": station,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan.get("naval_order", ""), label),
        "bbcode": "[color=#5ec8ff]🚢 Naval mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["naval_order", "station_mutation"],
    }


def air_land_stage_mutation(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    attacker_power: float = 100.0,
    from_province_id: int = -1,
    target_province_id: int = -1,
    formation_id: str = "",
    attacker_tag: str = "GER",
) -> Dict[str, Any]:
    """Air-land order → assault stage + air note mutation plan."""
    air = air_land_order_package(
        weather=weather,
        month=month,
        attacker_power=attacker_power,
        province_id=target_province_id,
    )
    assault = assault_stage_mutation(
        attacker_power=attacker_power,
        weather=weather,
        month=month,
        from_province_id=from_province_id,
        target_province_id=target_province_id,
        formation_id=formation_id,
        attacker_tag=attacker_tag,
    )
    score = _avg(_score(air, "score"), _score(assault, "score"))
    plan = dict(assault.get("plan") or {})
    plan["air_order"] = str(air.get("order", ""))
    plan["score"] = score
    label = "Air-land stage mutation · score %.2f" % score
    return {
        "plan": plan,
        "air": air,
        "assault": assault,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan.get("air_order", ""), label),
        "bbcode": "[color=#5ec8ff]✈ Air-land mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["air_land_order", "assault_stage"],
    }


def theater_mutation_board(
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = -1,
    formation_id: str = "",
    country_tag: str = "GER",
) -> Dict[str, Any]:
    """Ranked mutation plans for a theater province."""
    theater = theater_order_board(
        weather=weather,
        month=month,
        available_strength=available_strength,
        zone_relation=zone_relation,
        basing_level=basing_level,
        fuel_level=fuel_level,
        province_id=province_id,
    )
    muts = [
        fleet_station_mutation(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=weather,
            province_id=province_id,
            formation_id=formation_id,
            country_tag=country_tag,
        ),
        production_priority_mutation(weather=weather, line_id="primary"),
        supply_route_mutation(
            weather=weather, basing_level=basing_level, province_id=province_id
        ),
    ]
    ranked = sorted(muts, key=lambda m: float(m.get("score", 0.0)), reverse=True)
    lines = [str(m.get("summary", "")) for m in ranked]
    score = _avg(*[_score(m, "score") for m in ranked], _score(theater, "score"))
    label = "Theater mutation board · %d · score %.2f" % (len(ranked), score)
    return {
        "mutations": ranked,
        "lines": lines,
        "count": len(ranked),
        "score": score,
        "theater": theater,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "[color=#5ec8ff]🗺 Theater mutations[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["theater_orders", "mutations"],
    }


def focus_mutation_path(
    weather: Optional[Mapping[str, Any]] = None,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Focus order → mutation path plan (record + optional prod priority)."""
    focus = focus_order_path(
        weather=weather, focus_id=focus_id, focus_base=focus_base, trail=trail
    )
    action = str(focus.get("action", "HOLD"))
    plan = {
        "api": "GameData.apply_focus_order_mutation",
        "focus_id": focus_id,
        "action": action,
        "order": str(focus.get("order", "")),
        "score": _score(focus, "score"),
        "apply_ready": True,
    }
    label = "Focus mutation · %s · score %.2f" % (action, plan["score"])
    return {
        "plan": plan,
        "focus": focus,
        "score": plan["score"],
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (plan["order"], label),
        "bbcode": "[color=#5ec8ff]🎯 Focus mutate[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["focus_order", "mutation"],
    }


def mutation_decision_strip(
    mutations: Optional[Sequence[Mapping[str, Any]]] = None,
    feedback: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Inspector strip of applied/planned mutations + feedback."""
    blocks: List[Mapping[str, Any]] = []
    for m in list(mutations or []):
        if m and not m.get("empty"):
            blocks.append(m)
    if feedback and not feedback.get("empty"):
        blocks.append(feedback)
    if not blocks:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    strip = format_campaign_strip(blocks, max_lines=6)
    lines: List[str] = []
    for b in blocks:
        s = str(b.get("summary", b.get("label", b.get("order", "")))).strip()
        if s:
            lines.append(s.split("\n")[0])
    label = "Mutation decision strip · %d" % len(lines)
    bb = "\n".join(
        ["[color=#5ec8ff]── Mutations ──[/color]"]
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
            "integration": ["mutations", "feedback", "decision"],
        }
    )
    return out


def mutation_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    mutation_mult: float = 1.0,
) -> Dict[str, Any]:
    """Sole-mult + execution integrity after mutation mults (applied once)."""
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    exec_gate = execution_integrity_gate(
        sea_mult=sea_mult,
        weather_mult=weather_mult,
        route_risk=route_risk,
        order_mult=mutation_mult,
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    exec_ok = bool(exec_gate.get("ok", False))
    sole_health = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(mutation_mult)))
    stacked = sole_health * max(0.1, min(1.4, float(mutation_mult)))
    mut_ok = True
    if abs(float(mutation_mult) - 1.0) > 0.05:
        mut_ok = abs(stacked - sole_health) > 0.01
    ok = sole_ok and exec_ok and mut_ok
    label = "Mutation integrity %s (sole=%s exec=%s mut=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if exec_ok else "fail",
        "ok" if mut_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "execution": exec_gate,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Mut integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "execution_integrity", "mutation_mult"],
    }


def close_mutation_loop(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    province_id: int = 1,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    formation_id: str = "demo_div",
    country_tag: str = "GER",
) -> Dict[str, Any]:
    """Compose: order → mutation plan → map-effect store → feedback → integrity."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))

    station = fleet_station_mutation(
        basing_level=basing_level,
        fuel_level=fuel_level,
        weather=w,
        province_id=province_id,
        formation_id=formation_id,
        country_tag=country_tag,
    )
    prod = production_priority_mutation(weather=w, line_id="primary", unit_id="infantry")
    hh = hh_commit_mutation(trail=trail)
    effect = map_effect_store_mutation(
        order=str((station.get("plan") or {}).get("order", "")),
        province_id=province_id,
        score=_score(station, "score"),
    )
    before = _score(station, "score")
    station_after = fleet_station_mutation(
        basing_level=basing_level,
        fuel_level=max(0.2, fuel_level - 0.2),
        weather=foul,
        province_id=province_id,
        formation_id=formation_id,
        country_tag=country_tag,
    )
    after = _score(station_after, "score")
    fb = next_day_mutation_feedback(
        before_score=before,
        after_score=after,
        mutation_kind="station",
        order=str((station.get("plan") or {}).get("order", "")),
    )
    applied = [
        mutation_result(
            ok=bool((station.get("plan") or {}).get("apply_ready")),
            kind="station",
            detail=str((station.get("plan") or {}).get("role", "")),
        ),
        mutation_result(
            ok=bool((prod.get("plan") or {}).get("apply_ready")),
            kind="production",
            detail=str((prod.get("plan") or {}).get("priority", "")),
        ),
    ]
    if not hh.get("empty"):
        applied.append(
            mutation_result(ok=True, kind="hh_commit", detail=str((hh.get("plan") or {}).get("order", ""))[:40])
        )
    strip = mutation_decision_strip(mutations=applied + [effect], feedback=fb)
    gate = mutation_integrity_gate(mutation_mult=1.1)
    return {
        "station": station,
        "production": prod,
        "hh": hh,
        "effect": effect,
        "feedback": fb,
        "applied": applied,
        "strip": strip,
        "integrity": gate,
        "summary": "Close-mutation-loop · plans=%d · integrity %s"
        % (int(strip.get("count", 0)), "PASS" if gate.get("ok") else "FAIL"),
        "empty": False,
        "integration": ["order", "mutation", "store", "feedback", "integrity"],
    }
