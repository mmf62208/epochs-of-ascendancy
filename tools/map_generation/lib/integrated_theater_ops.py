"""Integrated multi-system theater ops pilots (beyond theater-expand isolated suites).

Composes fleet + weather, combat + supply + morale, HH + agents, sea + choke + storm,
trade/supply/weather chains, and campaign strips for player-facing boards.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from fleet_task_group import compose_task_group  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from weather_effects import (  # type: ignore
    air_sortie_readiness,
    combat_weather_multiplier,
    naval_spotting_multiplier,
    production_weather_multiplier,
    supply_throughput_weather_multiplier,
)
from weather_ops_polish import (  # type: ignore
    air_grounding_alert,
    infra_weather_wear,
    rank_supply_route_weather_risk,
    weather_pressure_index,
)
from theater_ops_polish import (  # type: ignore
    campaign_day_risk,
    combat_morale_weather,
    convoy_weather_window,
    depot_weather_capacity,
    daylight_combat_mod,
    focus_weather_aware_score,
    production_weather_alert,
    sea_naval_weather_ops,
    choke_weather_synergy,
)
from sea_zone_control import sea_zone_strategic_modifiers  # type: ignore


def fleet_weather_mission_package(
    mission: str = "patrol",
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    escort_need: float = 0.0,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Task-group composition shifted by naval weather (fleet + weather compose)."""
    w = dict(weather or {})
    spot = naval_spotting_multiplier(w)
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    mission_l = str(mission or "patrol").lower()
    escort = float(escort_need)
    if storm > 0.55 or spot < 0.4:
        if mission_l in ("strike", "projection", "raid"):
            mission_l = "patrol"
        escort = max(escort, 30.0)
    tg = compose_task_group(
        available_strength=available_strength,
        mission=mission_l,
        zone_relation=zone_relation,
        escort_need=escort,
    )
    label = "Fleet+wx package · %s · spot ×%.2f · primary %s" % (
        mission_l,
        spot,
        tg.get("primary_role", "?"),
    )
    out = dict(tg)
    out.update(
        {
            "spot_mult": float(spot),
            "storm": storm,
            "mission_effective": mission_l,
            "integration": ["fleet_task_group", "naval_weather"],
            "label": label,
            "summary": label,
            "bbcode": "[color=#5ec8ff]🚢 Fleet+wx[/color] [color=#8899aa]%s[/color]" % label,
            "empty": bool(tg.get("empty", False)),
        }
    )
    return out


def assault_readiness_compose(
    targets: Sequence[Mapping[str, Any]],
    attacker_power: float = 100.0,
    attacker_supply: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    path_weather: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Multi-front assault + supply route wx + morale wx (combat+supply+weather)."""
    w = dict(weather or {})
    morale = combat_morale_weather(w)
    supply_mult = supply_throughput_weather_multiplier(w)
    route = rank_supply_route_weather_risk(path_weather or [w])
    eff_supply = max(0.2, float(attacker_supply) * float(morale["morale_mult"]) * supply_mult)
    enriched = []
    for t in targets or []:
        if not isinstance(t, dict):
            continue
        row = dict(t)
        if "weather_mult" not in row:
            row["weather_mult"] = combat_weather_multiplier(w)
        enriched.append(row)
    ranked = rank_assault_targets(
        enriched, attacker_power=attacker_power, attacker_supply=eff_supply
    )
    if ranked.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "integration": ["multi_front", "supply_wx", "morale_wx"],
        }
    best = ranked["best"]
    label = "Assault readiness · #%d win %.0f%% · supply×%.2f morale×%.2f" % (
        int(best["province_id"]),
        float(best["overall"]) * 100.0,
        supply_mult,
        float(morale["morale_mult"]),
    )
    return {
        "ranked": ranked,
        "best_province_id": ranked["best_province_id"],
        "effective_supply": float(eff_supply),
        "supply_mult": float(supply_mult),
        "morale_mult": float(morale["morale_mult"]),
        "route_risk": route,
        "integration": ["multi_front", "supply_wx", "morale_wx"],
        "label": label,
        "summary": label,
        "plain": label + "\n" + str(ranked.get("plain", "")),
        "bbcode": "[color=#ff9a6e]⚔ Assault ready[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def counter_ops_board(
    signal: Mapping[str, Any],
    network_strength: float = 0.3,
    available_agents: int = 4,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    """HH signal → escalation ladder + coverage plan (agents + HH compose)."""
    sig = dict(signal or {})
    if not sig.get("action_class") and not sig.get("province_id") and not bool(sig.get("active", False)):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "integration": ["hh_signal", "escalation", "coverage"],
        }
    esc = plan_agent_escalation(
        sig,
        network_strength=network_strength,
        available_agents=available_agents,
        loyalty=loyalty,
    )
    cov = plan_agent_coverage(
        [sig],
        available_agents=available_agents,
        network_strength=network_strength,
    )
    if esc.get("empty") and cov.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "integration": ["hh_signal", "escalation", "coverage"],
        }
    label = "Counter-ops · L%d %s · cover %s" % (
        int(esc.get("level", 0)),
        esc.get("top_action", "—"),
        (cov.get("summary", "—")[:40] if not cov.get("empty") else "none"),
    )
    plain_lines = [label]
    if not esc.get("empty"):
        plain_lines.append(str(esc.get("summary", "")))
    if not cov.get("empty"):
        plain_lines.append(str(cov.get("summary", "")))
    return {
        "escalation": esc,
        "coverage": cov,
        "integration": ["hh_signal", "escalation", "coverage"],
        "label": label,
        "summary": label,
        "plain": "\n".join(plain_lines),
        "bbcode": "[color=#c084fc]◎ Counter-ops[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def format_hh_agenda_commitments(
    trail: Sequence[Mapping[str, Any]],
    max_commits: int = 3,
) -> Dict[str, Any]:
    """Top agenda commitments from trail (beyond quarterly rollup). Empty trail → empty."""
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if not entries:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "commits": [],
            "count": 0,
        }
    scored = []
    for i, e in enumerate(entries):
        inf = float(e.get("influence", e.get("strength", 0.5)) or 0.5)
        recency = (i + 1) / max(1, len(entries))
        scored.append(
            {
                "action_class": str(e.get("action_class", "influence")),
                "province_id": int(e.get("province_id", -1) or -1),
                "province_name": str(e.get("province_name", "")),
                "influence": inf,
                "score": inf * 0.7 + recency * 0.3,
            }
        )
    scored.sort(key=lambda x: (-float(x["score"]), str(x["action_class"])))
    commits = scored[: max(1, int(max_commits))]
    lines = ["Agenda commits · %d" % len(commits)]
    for c in commits:
        lines.append(
            "%s @#%s (inf %.0f%%)"
            % (c["action_class"], c["province_id"], float(c["influence"]) * 100.0)
        )
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#c084fc]◈ Agenda commits[/color]"]
        + [
            "[color=#8899aa]· %s @#%s[/color]" % (c["action_class"], c["province_id"])
            for c in commits
        ]
    )
    return {
        "commits": commits,
        "count": len(commits),
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0] + " · " + commits[0]["action_class"],
    }


def choke_sea_weather_package(
    control: Optional[Mapping[str, Any]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    is_choke: bool = True,
    friendly: bool = True,
) -> Dict[str, Any]:
    """Choke + sea-zone strategic mults + weather (naval+map+wx compose)."""
    mods = sea_zone_strategic_modifiers(control or {})
    sea_mult = float(mods.get("supply_multiplier", 1.0))
    sea_nav = sea_naval_weather_ops(sea_mult, weather)
    choke = choke_weather_synergy(
        is_choke=is_choke, controller_friendly=friendly, weather=weather
    )
    if choke.get("empty") and not is_choke:
        label = "Sea×wx only · %s" % sea_nav["summary"]
    else:
        label = "Choke×sea×wx · score %.2f · sea×nav %.2f" % (
            float(choke.get("score", 1.0)),
            float(sea_nav["combined"]),
        )
    return {
        "sea_mods": mods,
        "sea_naval": sea_nav,
        "choke": choke,
        "combined_score": float(choke.get("score", 1.0)) * float(sea_nav["combined"]),
        "integration": ["choke", "sea_zone", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🗺 Choke×sea×wx[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def trade_supply_weather_chain(
    sea_trade_mult: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    path_weather: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Trade delivery health from sea mult + weather supply + route risk."""
    w = dict(weather or {})
    wx = supply_throughput_weather_multiplier(w)
    route = rank_supply_route_weather_risk(path_weather or [w])
    risk = float((route.get("worst") or {}).get("risk", 0.0)) if not route.get("empty") else 0.0
    health = max(0.1, min(1.4, float(sea_trade_mult) * wx * (1.0 - risk * 0.25)))
    label = "Trade chain health ×%.2f (sea %.2f · wx %.2f · risk %.0f%%)" % (
        health,
        float(sea_trade_mult),
        wx,
        risk * 100.0,
    )
    return {
        "health": float(health),
        "sea_trade_mult": float(sea_trade_mult),
        "weather_mult": float(wx),
        "route_risk": risk,
        "integration": ["trade", "supply", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]📦 Trade chain[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def factory_risk_compose(weather: Mapping[str, Any]) -> Dict[str, Any]:
    """Production alert + infra wear + pressure (industry+weather)."""
    w = dict(weather or {})
    alert = production_weather_alert(w, threshold=0.9)
    wear = infra_weather_wear(w)
    pressure = weather_pressure_index(w)
    prod = production_weather_multiplier(w)
    risk = max(
        0.0,
        min(
            1.0,
            (1.0 - prod) * 0.5
            + float(pressure["pressure"]) * 0.35
            + (1.0 - float(wear["wear_factor"])) * 0.3,
        ),
    )
    label = "Factory risk %.0f%% · prod ×%.2f · wear ×%.2f" % (
        risk * 100.0,
        prod,
        float(wear["wear_factor"]),
    )
    return {
        "risk": float(risk),
        "production_mult": float(prod),
        "wear": wear,
        "pressure": pressure,
        "alert": alert,
        "integration": ["production", "infra", "weather"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#f87171]🏭 Factory risk[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "severe": risk >= 0.45,
    }


def theater_readiness_board(
    fleet_package: Optional[Mapping[str, Any]] = None,
    assault: Optional[Mapping[str, Any]] = None,
    day_risk: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Compose fleet+wx package + assault readiness + campaign day risk."""
    parts = []
    for block in (fleet_package, assault, day_risk):
        if not block or block.get("empty"):
            continue
        parts.append(str(block.get("summary", block.get("label", ""))).split("\n")[0])
    if not parts:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "lines": []}
    label = "Theater readiness · %d signals" % len(parts)
    plain = "\n".join([label] + parts)
    bbcode = "\n".join(
        ["[color=#5ec8ff]── Theater readiness ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % p for p in parts]
    )
    return {
        "lines": parts,
        "count": len(parts),
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": label,
        "integration": ["fleet_wx", "assault_ready", "day_risk"],
    }


def convoy_package_compose(
    path_zone_relations: Sequence[str],
    available_fleet_strength: float = 50.0,
    cargo_value: float = 100.0,
    weather: Optional[Mapping[str, Any]] = None,
    forecasts: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Escort plan × convoy weather window (fleet+weather+convoy)."""
    w = dict(weather or {})
    interdict = float(w.get("precip_intensity", 0.0) or 0.0) * 0.2 + 0.1
    escort = plan_convoy_escort(
        path_zone_relations,
        available_fleet_strength,
        cargo_value=cargo_value,
        interdiction_chance=interdict,
    )
    days = list(forecasts or [])
    if not days:
        days = [
            dict(w, day_index=0),
            {
                "visibility": min(1.0, float(w.get("visibility", 1.0)) + 0.2),
                "precip_intensity": max(0.0, float(w.get("precip_intensity", 0.0)) - 0.3),
                "ground_state": w.get("ground_state", "dry"),
                "day_index": 1,
            },
        ]
    window = convoy_weather_window(days)
    label = "Convoy package · escort %s · best day %s" % (
        "yes" if escort.get("recommend_escort") or escort.get("sufficient") else "thin",
        window.get("best_day", "?"),
    )
    return {
        "escort": escort,
        "window": window,
        "integration": ["convoy_escort", "weather_window"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]⛵ Convoy package[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "recommend_wait": int(window.get("best_day", 0) or 0) > 0
        and float(w.get("precip_intensity", 0) or 0) > 0.5,
    }


def war_cabinet_board(
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    weather: Optional[Mapping[str, Any]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Focus wx + agent escalation + HH commits (cabinet compose)."""
    w = dict(weather or {})
    focus = focus_weather_aware_score(focus_base, focus_id, w)
    esc = plan_agent_escalation(signal or {}, network_strength=0.3, available_agents=3)
    commits = format_hh_agenda_commitments(trail or [])
    lines = ["War cabinet"]
    lines.append(str(focus.get("summary", "")))
    if not esc.get("empty"):
        lines.append(str(esc.get("summary", "")))
    if not commits.get("empty"):
        lines.append(str(commits.get("summary", "")))
    plain = "\n".join(ln for ln in lines if ln)
    return {
        "focus": focus,
        "escalation": esc,
        "commits": commits,
        "integration": ["focus_wx", "escalation", "hh_commits"],
        "label": lines[0],
        "summary": plain.split("\n")[0] + " · " + (lines[1] if len(lines) > 1 else ""),
        "plain": plain,
        "bbcode": "\n".join(
            ["[color=#c084fc]── War cabinet ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[1:] if ln]
        ),
        "empty": False,
    }


def supply_chain_health(
    base_depot: float = 100.0,
    sea_mult: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    path_weather: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Depot capacity × sea×wx × route rank."""
    w = dict(weather or {})
    depot = depot_weather_capacity(w, base_depot)
    sea_nav = sea_naval_weather_ops(sea_mult, w)
    route = rank_supply_route_weather_risk(path_weather or [w])
    risk = float((route.get("worst") or {}).get("risk", 0.0)) if not route.get("empty") else 0.0
    health = max(
        0.1,
        min(
            1.5,
            float(depot["weather_mult"]) * float(sea_nav["combined"]) * (1.0 - risk * 0.2),
        ),
    )
    label = "Supply chain ×%.2f (depot wx %.2f · sea×nav %.2f)" % (
        health,
        float(depot["weather_mult"]),
        float(sea_nav["combined"]),
    )
    return {
        "health": float(health),
        "depot": depot,
        "sea_naval": sea_nav,
        "route": route,
        "integration": ["depot", "sea_zone", "weather", "route"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]🔗 Supply chain[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }


def air_ops_package(weather: Mapping[str, Any], month: int = 1) -> Dict[str, Any]:
    """Sortie readiness + grounding + daylight (air+weather+season)."""
    w = dict(weather or {})
    ready = air_sortie_readiness(w)
    ground = air_grounding_alert(w)
    day = daylight_combat_mod(month)
    eff = float(ready.get("effectiveness", 1.0)) * float(day["combat_mult"])
    label = "Air ops · sortie %.0f%% · day×%.2f%s" % (
        float(ready.get("effectiveness", 1.0)) * 100.0,
        float(day["combat_mult"]),
        " GROUNDED" if ready.get("grounded") else "",
    )
    return {
        "readiness": ready,
        "grounding": ground,
        "daylight": day,
        "effective": float(eff),
        "integration": ["air_sortie", "grounding", "daylight"],
        "label": label,
        "summary": label,
        "bbcode": "[color=#5ec8ff]✈ Air package[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "grounded": bool(ready.get("grounded", False)),
    }


def format_campaign_strip(
    blocks: Sequence[Mapping[str, Any]],
    max_lines: int = 6,
) -> Dict[str, Any]:
    """Inspector campaign strip from integrated package summaries."""
    lines: List[str] = []
    for b in blocks or []:
        if not b or b.get("empty"):
            continue
        s = str(b.get("summary", b.get("label", ""))).strip()
        if s:
            lines.append(s.split("\n")[0])
        if len(lines) >= max_lines:
            break
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "lines": []}
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#5ec8ff]── Campaign strip ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
    )
    return {
        "lines": lines,
        "count": len(lines),
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": "Campaign strip · %d" % len(lines),
        "integration": ["multi"],
    }


def cross_system_coherence_delta(
    clear_weather: Mapping[str, Any],
    foul_weather: Mapping[str, Any],
) -> Dict[str, Any]:
    """Gate: foul weather must change multi-system package scores vs clear."""
    clear_fleet = fleet_weather_mission_package(
        "strike", weather=clear_weather, zone_relation="hostile"
    )
    foul_fleet = fleet_weather_mission_package(
        "strike", weather=foul_weather, zone_relation="hostile"
    )
    clear_assault = assault_readiness_compose(
        [{"province_id": 1, "defender_power": 80}],
        weather=clear_weather,
        attacker_power=100,
    )
    foul_assault = assault_readiness_compose(
        [{"province_id": 1, "defender_power": 80}],
        weather=foul_weather,
        attacker_power=100,
    )
    clear_trade = trade_supply_weather_chain(sea_trade_mult=1.1, weather=clear_weather)
    foul_trade = trade_supply_weather_chain(sea_trade_mult=1.1, weather=foul_weather)
    changed = (
        clear_fleet.get("primary_role") != foul_fleet.get("primary_role")
        or clear_fleet.get("mission_effective") != foul_fleet.get("mission_effective")
        or abs(
            float(clear_assault.get("effective_supply", 1))
            - float(foul_assault.get("effective_supply", 1))
        )
        > 0.05
        or abs(float(clear_trade["health"]) - float(foul_trade["health"])) > 0.05
    )
    return {
        "changed": changed,
        "clear_fleet_primary": clear_fleet.get("primary_role"),
        "foul_fleet_primary": foul_fleet.get("primary_role"),
        "clear_supply": float(clear_assault.get("effective_supply", 1)),
        "foul_supply": float(foul_assault.get("effective_supply", 1)),
        "clear_trade_health": float(clear_trade["health"]),
        "foul_trade_health": float(foul_trade["health"]),
        "summary": "cross-system coherence %s" % ("PASS" if changed else "FAIL"),
        "empty": False,
    }
