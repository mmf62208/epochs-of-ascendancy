"""Theater commander + player order-surface pilots beyond live-mutation.

Composes live_mutation plans into theater-level auto-command queues and
player-visible order surfaces. Pure only — GD apply sites call real managers.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from live_mutation import (  # type: ignore
    fleet_station_mutation,
    assault_stage_mutation,
    agent_dispatch_mutation,
    hh_commit_mutation,
    production_priority_mutation,
    supply_route_mutation,
    map_effect_store_mutation,
    next_day_mutation_feedback,
    mutation_integrity_gate,
    mutation_result,
    theater_mutation_board,
)
from gameplay_loops import sole_mult_integrity  # type: ignore
from integrated_theater_ops import format_campaign_strip  # type: ignore


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


def theater_fleet_auto_command(
    provinces: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    formation_id: str = "fleet_div",
    country_tag: str = "ENG",
    fuel_level: float = 0.55,
) -> Dict[str, Any]:
    """Rank station mutations across coastal province set — theater fleet auto-command."""
    w = dict(weather or {})
    provs = list(
        provinces
        or [
            {"province_id": 1, "basing_level": "port", "zone_relation": "contested"},
            {"province_id": 2, "basing_level": "major_base", "zone_relation": "friendly"},
            {"province_id": 3, "basing_level": "anchorage", "zone_relation": "hostile"},
        ]
    )
    ranked: List[Dict[str, Any]] = []
    for p in provs:
        pid = int(p.get("province_id", p.get("id", -1)))
        mut = fleet_station_mutation(
            basing_level=str(p.get("basing_level", "port")),
            fuel_level=float(p.get("fuel_level", fuel_level)),
            available_strength=float(p.get("available_strength", 100.0)),
            zone_relation=str(p.get("zone_relation", "contested")),
            weather=w,
            province_id=pid,
            formation_id=str(p.get("formation_id", formation_id)),
            country_tag=str(p.get("country_tag", country_tag)),
        )
        ranked.append(mut)
    ranked.sort(key=lambda m: float(m.get("score", 0.0)), reverse=True)
    top = ranked[0] if ranked else {"empty": True, "score": 0.0}
    score = _score(top, "score") if ranked else 0.0
    label = "Theater fleet auto · %d candidates · top score %.2f" % (len(ranked), score)
    return {
        "ranked": ranked,
        "top": top,
        "count": len(ranked),
        "score": score,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + [str(m.get("summary", "")) for m in ranked[:4]]),
        "bbcode": "[color=#5ec8ff]⚓ Theater fleet[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not ranked,
        "integration": ["fleet_station_mutation", "theater_auto"],
    }


def theater_combat_auto_command(
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    attacker_tag: str = "GER",
    formation_id: str = "inf_div",
) -> Dict[str, Any]:
    """Rank assault stage mutations; PRESS only when step==press — theater combat auto."""
    w = dict(weather or {})
    fr = list(
        fronts
        or [
            {"from_province_id": 1, "target_province_id": 2, "attacker_power": 100.0},
            {"from_province_id": 3, "target_province_id": 4, "attacker_power": 60.0},
            {"from_province_id": 5, "target_province_id": 6, "attacker_power": 80.0},
        ]
    )
    ranked: List[Dict[str, Any]] = []
    for f in fr:
        mut = assault_stage_mutation(
            attacker_power=float(f.get("attacker_power", 100.0)),
            attacker_supply=float(f.get("attacker_supply", 0.85)),
            weather=w,
            month=int(f.get("month", month)),
            from_province_id=int(f.get("from_province_id", -1)),
            target_province_id=int(f.get("target_province_id", -1)),
            formation_id=str(f.get("formation_id", formation_id)),
            attacker_tag=str(f.get("attacker_tag", attacker_tag)),
        )
        ranked.append(mut)
    # Prefer execute-ready PRESS, then by score
    ranked.sort(
        key=lambda m: (
            1 if str((m.get("plan") or {}).get("step", "")) == "press" else 0,
            float(m.get("score", 0.0)),
        ),
        reverse=True,
    )
    top = ranked[0] if ranked else {"empty": True, "score": 0.0}
    score = _score(top, "score") if ranked else 0.0
    press_n = sum(1 for m in ranked if str((m.get("plan") or {}).get("step", "")) == "press")
    label = "Theater combat auto · %d fronts · press=%d · top %.2f" % (
        len(ranked),
        press_n,
        score,
    )
    return {
        "ranked": ranked,
        "top": top,
        "count": len(ranked),
        "press_count": press_n,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + [str(m.get("summary", "")) for m in ranked[:4]]),
        "bbcode": "[color=#5ec8ff]⚔ Theater combat[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not ranked,
        "integration": ["assault_stage_mutation", "theater_auto"],
    }


def theater_agent_auto_dispatch(
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 5,
) -> Dict[str, Any]:
    """Signal → dispatch mutation plan — theater agent auto-dispatch."""
    mut = agent_dispatch_mutation(signal=signal, available_agents=available_agents)
    plan = mut.get("plan") or {}
    score = _score(mut, "score")
    label = "Theater agent auto · score %.2f" % score
    return {
        "mutation": mut,
        "plan": plan,
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (str(plan.get("order", "")), label),
        "bbcode": "[color=#5ec8ff]🕵 Theater agent[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(mut.get("empty")),
        "integration": ["agent_dispatch_mutation", "theater_auto"],
    }


def theater_hh_auto_commit(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_commits: int = 3,
) -> Dict[str, Any]:
    """Trail → HH commit mutation; empty trail → empty."""
    t = list(trail or [])
    if not t:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0, "plan": {}}
    mut = hh_commit_mutation(trail=t, max_commits=max_commits)
    if mut.get("empty"):
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0, "plan": {}}
    score = _score(mut, "score")
    label = "Theater HH auto-commit · score %.2f" % score
    return {
        "mutation": mut,
        "plan": mut.get("plan") or {},
        "score": score,
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (str((mut.get("plan") or {}).get("order", "")), label),
        "bbcode": "[color=#5ec8ff]📜 Theater HH[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["hh_commit_mutation", "theater_auto"],
    }


def theater_production_auto(
    weather: Optional[Mapping[str, Any]] = None,
    lines: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Auto production priority mutations from weather risk."""
    w = dict(weather or {})
    ls = list(lines or [{"line_id": "primary", "unit_id": "infantry"}, {"line_id": "armor", "unit_id": "tank"}])
    ranked: List[Dict[str, Any]] = []
    for ln in ls:
        mut = production_priority_mutation(
            weather=w,
            base_output=float(ln.get("base_output", 1.0)),
            line_id=str(ln.get("line_id", "primary")),
            unit_id=str(ln.get("unit_id", "")),
        )
        ranked.append(mut)
    ranked.sort(key=lambda m: float((m.get("plan") or {}).get("score", m.get("score", 0.0))), reverse=True)
    top = ranked[0] if ranked else {"empty": True}
    score = _score(top, "score") if ranked else 0.0
    label = "Theater production auto · %d lines · top %.2f" % (len(ranked), score)
    return {
        "ranked": ranked,
        "top": top,
        "count": len(ranked),
        "score": score,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + [str(m.get("summary", "")) for m in ranked[:3]]),
        "bbcode": "[color=#5ec8ff]🏭 Theater prod[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not ranked,
        "sole_mult": True,
        "integration": ["production_priority_mutation", "theater_auto"],
    }


def theater_supply_auto(
    weather: Optional[Mapping[str, Any]] = None,
    routes: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Auto supply route mutations from spine health."""
    w = dict(weather or {})
    rs = list(
        routes
        or [
            {"route_id": "main", "province_id": 1, "basing_level": "port"},
            {"route_id": "alt", "province_id": 2, "basing_level": "anchorage"},
        ]
    )
    ranked: List[Dict[str, Any]] = []
    for r in rs:
        mut = supply_route_mutation(
            weather=w,
            basing_level=str(r.get("basing_level", "port")),
            sea_mult=float(r.get("sea_mult", 1.0)),
            route_id=str(r.get("route_id", "main")),
            province_id=int(r.get("province_id", -1)),
        )
        ranked.append(mut)
    ranked.sort(key=lambda m: float(m.get("score", 0.0)))  # worst health first for attention
    top = ranked[0] if ranked else {"empty": True}
    score = _score(top, "score") if ranked else 0.0
    label = "Theater supply auto · %d routes · worst %.2f" % (len(ranked), score)
    return {
        "ranked": ranked,
        "top": top,
        "count": len(ranked),
        "score": score,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + [str(m.get("summary", "")) for m in ranked[:3]]),
        "bbcode": "[color=#5ec8ff]📦 Theater supply[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not ranked,
        "sole_mult": True,
        "integration": ["supply_route_mutation", "theater_auto"],
    }


def theater_daily_brief(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    month: int = 6,
) -> Dict[str, Any]:
    """Compose fleet+combat+prod theater commands for the day."""
    w = dict(weather or {})
    fleet = theater_fleet_auto_command(weather=w)
    combat = theater_combat_auto_command(weather=w, month=month)
    prod = theater_production_auto(weather=w)
    supply = theater_supply_auto(weather=w)
    hh = theater_hh_auto_commit(trail=trail)
    parts = [fleet, combat, prod, supply]
    if not hh.get("empty"):
        parts.append(hh)
    score = _avg(*[_score(p, "score") for p in parts])
    lines = [str(p.get("summary", "")) for p in parts]
    label = "Theater daily brief · %d domains · score %.2f" % (len(parts), score)
    return {
        "fleet": fleet,
        "combat": combat,
        "production": prod,
        "supply": supply,
        "hh": hh,
        "lines": lines,
        "count": len(parts),
        "score": score,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "[color=#5ec8ff]📋 Theater brief[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_auto", "combat_auto", "prod_auto", "supply_auto"],
    }


def order_queue_board(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Ranked queue of pending mutation plans from theater auto-commands."""
    w = dict(weather or {})
    fleet = theater_fleet_auto_command(weather=w)
    combat = theater_combat_auto_command(weather=w)
    prod = theater_production_auto(weather=w)
    supply = theater_supply_auto(weather=w)
    items: List[Dict[str, Any]] = []
    for src, domain in (
        (fleet.get("top"), "fleet"),
        (combat.get("top"), "combat"),
        (prod.get("top"), "production"),
        (supply.get("top"), "supply"),
    ):
        if not src or src.get("empty"):
            continue
        plan = src.get("plan") or {}
        items.append(
            {
                "domain": domain,
                "plan": plan,
                "score": float(src.get("score", plan.get("score", 0.0))),
                "summary": str(src.get("summary", "")),
                "apply_ready": bool(plan.get("apply_ready", False)),
                "api": str(plan.get("api", "")),
                "order": str(plan.get("order", "")),
            }
        )
    hh = theater_hh_auto_commit(trail=trail)
    if not hh.get("empty"):
        plan = hh.get("plan") or {}
        items.append(
            {
                "domain": "hh",
                "plan": plan,
                "score": float(hh.get("score", 0.0)),
                "summary": str(hh.get("summary", "")),
                "apply_ready": bool(plan.get("apply_ready", False)),
                "api": str(plan.get("api", "")),
                "order": str(plan.get("order", "")),
            }
        )
    items.sort(key=lambda x: float(x.get("score", 0.0)), reverse=True)
    label = "Order queue · %d pending" % len(items)
    return {
        "items": items,
        "count": len(items),
        "top": items[0] if items else {},
        "score": float(items[0]["score"]) if items else 0.0,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + ["%s · %s" % (i["domain"], i.get("order", "")[:48]) for i in items[:5]]),
        "bbcode": "[color=#5ec8ff]☰ Order queue[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not items,
        "integration": ["theater_auto", "queue"],
    }


def execute_one_order(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    prefer_apply_ready: bool = True,
) -> Dict[str, Any]:
    """Pick top queue item for apply API — pure execute-one selection."""
    board = order_queue_board(weather=weather, trail=trail)
    items = list(board.get("items") or [])
    if prefer_apply_ready:
        ready = [i for i in items if i.get("apply_ready")]
        pick = ready[0] if ready else (items[0] if items else None)
    else:
        pick = items[0] if items else None
    if not pick:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    label = "Execute-one · %s · %s" % (pick.get("domain"), str(pick.get("api", ""))[:40])
    return {
        "pick": pick,
        "domain": pick.get("domain"),
        "plan": pick.get("plan") or {},
        "api": pick.get("api"),
        "order": pick.get("order"),
        "apply_ready": bool(pick.get("apply_ready")),
        "score": float(pick.get("score", 0.0)),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(pick.get("order", ""))),
        "bbcode": "[color=#5ec8ff]▶ Execute-one[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "queue": board,
        "integration": ["order_queue", "execute_one"],
    }


def apply_best_station_package(
    weather: Optional[Mapping[str, Any]] = None,
    provinces: Optional[Sequence[Mapping[str, Any]]] = None,
    formation_id: str = "fleet_div",
    country_tag: str = "ENG",
) -> Dict[str, Any]:
    """Select top station plan → apply-ready package for MapManager.apply_fleet_station_mutation."""
    cmd = theater_fleet_auto_command(
        provinces=provinces,
        weather=weather,
        formation_id=formation_id,
        country_tag=country_tag,
    )
    top = cmd.get("top") or {}
    plan = top.get("plan") or {}
    label = "Apply-best station · pid=%s · ready=%s" % (
        plan.get("province_id", -1),
        plan.get("apply_ready"),
    )
    return {
        "command": cmd,
        "plan": plan,
        "province_id": int(plan.get("province_id", -1)),
        "formation_id": str(plan.get("formation_id", formation_id)),
        "country_tag": str(plan.get("country_tag", country_tag)),
        "apply_ready": bool(plan.get("apply_ready")),
        "api": "MapManager.apply_fleet_station_mutation",
        "score": _score(top, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]⚓ Apply station[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(cmd.get("empty")),
        "integration": ["fleet_auto", "apply_fleet_station"],
    }


def apply_best_assault_package(
    weather: Optional[Mapping[str, Any]] = None,
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    formation_id: str = "inf_div",
    attacker_tag: str = "GER",
) -> Dict[str, Any]:
    """Select top assault plan → apply-ready package for MapManager.apply_assault_stage_mutation."""
    cmd = theater_combat_auto_command(
        fronts=fronts, weather=weather, formation_id=formation_id, attacker_tag=attacker_tag
    )
    top = cmd.get("top") or {}
    plan = top.get("plan") or {}
    label = "Apply-best assault · %s · exec=%s" % (
        plan.get("step", "?"),
        plan.get("execute"),
    )
    return {
        "command": cmd,
        "plan": plan,
        "from_province_id": int(plan.get("from_province_id", -1)),
        "target_province_id": int(plan.get("target_province_id", -1)),
        "formation_id": str(plan.get("formation_id", formation_id)),
        "attacker_tag": str(plan.get("attacker_tag", attacker_tag)),
        "execute": bool(plan.get("execute")),
        "apply_ready": bool(plan.get("apply_ready")),
        "api": "MapManager.apply_assault_stage_mutation",
        "score": _score(top, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]⚔ Apply assault[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(cmd.get("empty")),
        "integration": ["combat_auto", "apply_assault_stage"],
    }


def player_order_surface_strip(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Inspector strip of top theater commands + apply status — player-visible surface."""
    queue = order_queue_board(weather=weather, trail=trail)
    execute = execute_one_order(weather=weather, trail=trail)
    station = apply_best_station_package(weather=weather)
    assault = apply_best_assault_package(weather=weather)
    blocks = [queue, execute, station, assault]
    lines: List[str] = []
    for b in blocks:
        if b and not b.get("empty"):
            s = str(b.get("summary", "")).strip()
            if s:
                lines.append(s.split("\n")[0])
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    strip = format_campaign_strip(
        [{"summary": ln} for ln in lines],
        max_lines=6,
    )
    label = "Player order surface · %d" % len(lines)
    bb = "\n".join(
        ["[color=#5ec8ff]── Player orders ──[/color]"]
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
            "queue": queue,
            "execute_one": execute,
            "station": station,
            "assault": assault,
            "integration": ["order_queue", "execute_one", "apply_best"],
        }
    )
    return out


def theater_command_strip(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Inspector multi-system theater command surface."""
    brief = theater_daily_brief(weather=weather, trail=trail)
    surface = player_order_surface_strip(weather=weather, trail=trail)
    lines = list(brief.get("lines") or [])[:3]
    if not surface.get("empty"):
        lines.extend(list(surface.get("lines") or [])[:3])
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    label = "Theater command strip · %d" % len(lines)
    bb = "\n".join(
        ["[color=#5ec8ff]── Theater command ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[:6]]
    )
    return {
        "brief": brief,
        "surface": surface,
        "lines": lines[:6],
        "count": len(lines),
        "score": _avg(_score(brief, "score"), _score(surface, "score", default=0.5)),
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines[:6]),
        "bbcode": bb,
        "empty": False,
        "integration": ["daily_brief", "player_order_surface"],
    }


def command_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    theater_mult: float = 1.0,
) -> Dict[str, Any]:
    """Sole-mult + mutation integrity after theater mults (applied once)."""
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    mut = mutation_integrity_gate(
        sea_mult=sea_mult,
        weather_mult=weather_mult,
        route_risk=route_risk,
        mutation_mult=theater_mult,
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    mut_ok = bool(mut.get("ok", False))
    sole_health = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(theater_mult)))
    stacked = sole_health * max(0.1, min(1.4, float(theater_mult)))
    thr_ok = True
    if abs(float(theater_mult) - 1.0) > 0.05:
        thr_ok = abs(stacked - sole_health) > 0.01
    ok = sole_ok and mut_ok and thr_ok
    label = "Command integrity %s (sole=%s mut=%s thr=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if mut_ok else "fail",
        "ok" if thr_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "mutation": mut,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Cmd integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "mutation_integrity", "theater_mult"],
    }


def close_theater_command_loop(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Full loop: daily brief → queue → execute-one → apply packages → integrity."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))

    brief = theater_daily_brief(weather=w, trail=trail)
    queue = order_queue_board(weather=w, trail=trail)
    one = execute_one_order(weather=w, trail=trail)
    station = apply_best_station_package(weather=w)
    assault = apply_best_assault_package(weather=w)
    surface = player_order_surface_strip(weather=w, trail=trail)
    strip = theater_command_strip(weather=w, trail=trail)
    gate = command_integrity_gate(theater_mult=1.1)

    brief_foul = theater_daily_brief(weather=foul, trail=trail)
    score_shift = abs(_score(brief, "score") - _score(brief_foul, "score"))

    return {
        "brief": brief,
        "queue": queue,
        "execute_one": one,
        "station": station,
        "assault": assault,
        "surface": surface,
        "strip": strip,
        "integrity": gate,
        "weather_score_shift": score_shift,
        "summary": "Close-theater-command · queue=%d · integrity %s · Δwx %.3f"
        % (
            int(queue.get("count", 0)),
            "PASS" if gate.get("ok") else "FAIL",
            score_shift,
        ),
        "empty": False,
        "integration": [
            "daily_brief",
            "order_queue",
            "execute_one",
            "apply_best",
            "player_surface",
            "integrity",
        ],
    }
