"""Next-140 logistics/theater, force/OOB readiness, order-panel/inspector (20 packages).

A) Logistics / theater continuity (1–7)
B) Force readiness / OOB equip honesty (8–14)
C) Order-panel / province-inspector surface (15–20)

1 depot_logistics_day · 2 supply_route_ops_day · 3 move_path_ops_day · 4 multi_province_ops_day
5 theater_auto_tick_day · 6 daily_supply_ops_day · 7 logistics_theater_close_day
8 force_readiness_ops_day · 9 oob_factory_ops_day · 10 medium_equip_ops_day
11 naval_skim_ops_day · 12 basing_logistics_ops_day · 13 production_force_ops_day
14 force_oob_close_day · 15 player_surface_ops_day · 16 order_panel_ops_day
17 panel_sections_ops_day · 18 tooltip_flair_ops_day · 19 apply_audit_ops_day
20 logistics_force_panel_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from theater_ops_polish import (  # type: ignore
    depot_weather_capacity,
    campaign_day_risk,
    convoy_weather_window,
    format_ops_dashboard,
)
from gameplay_loops import (  # type: ignore
    move_path_ops_loop,
    oob_factory_risk_loop,
    basing_fleet_fuel_logistics,
    sole_mult_integrity,
)
from ops_depth import multi_province_day_plan, daily_theater_auto_tick, fleet_patrol_strip  # type: ignore
from theater_commander import (  # type: ignore
    theater_production_auto,
    execute_one_order,
    player_order_surface_strip,
    theater_combat_auto_command,
)
from daily_command_tick import daily_supply_auto_apply_plan, day_apply_budget  # type: ignore
from live_mutation import supply_route_mutation, production_priority_mutation  # type: ignore
from order_panel_ux_depth import (  # type: ignore
    medium_horizon_equip_plan,
    order_panel_primary_actions,
    order_panel_action_ids,
    close_order_panel_ux_depth_loop,
    naval_campaign_skim,
)
from week2_core_polish import day_package_apply_audit  # type: ignore
from week4_polish_depth import tooltip_sfx_flair_strip  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore


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
        "integration": list(integration or ["next140", "logistics_force_panel"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx(weather: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    return dict(
        weather
        or {
            "visibility": 0.7,
            "precip_intensity": 0.3,
            "ground_state": "mud",
            "temp": 8.0,
            "sea_state": 0.35,
            "fog": 0.2,
        }
    )


# A) Logistics / theater


def depot_logistics_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    depot = depot_weather_capacity(w, base_capacity=100.0)
    supply = supply_route_mutation()
    cap = float(depot.get("capacity", depot.get("effective_capacity", 65)) or 65)
    score = _norm(0.5 * (cap / 100.0) + 0.5 * float(supply.get("score", 0.5)))
    q = [
        _q("apply_supply", province_id, score, "depot logistics primary"),
        _q("apply_production", province_id, 0.5, "depot logistics production"),
    ]
    return _day(
        "depot_logistics_day",
        "Depot logistics day",
        "Depot logistics day · cap %.0f · supply %.2f · score %.2f"
        % (cap, float(supply.get("score", 0)), score),
        score,
        q,
        "#7dd3a0",
        "🏗",
        ["depot", "logistics", "supply"],
        {"depot": depot, "supply": supply},
    )


def supply_route_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = supply_route_mutation()
    plan = daily_supply_auto_apply_plan()
    score = _norm(max(float(mut.get("score", 0.4)), float(plan.get("score", 0.3))))
    q = [
        _q("apply_supply", province_id, score, "supply route ops primary"),
        _q("apply_station", province_id, 0.5, "supply route ops station"),
    ]
    return _day(
        "supply_route_ops_day",
        "Supply route ops day",
        "Supply route ops day · mut %.2f · auto %.2f · score %.2f"
        % (float(mut.get("score", 0)), float(plan.get("score", 0)), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "route", "ops"],
        {"mutation": mut, "plan": plan},
    )


def move_path_ops_day(province_id: int = 1) -> Dict[str, Any]:
    path = move_path_ops_loop()
    cost = float(path.get("path_cost", 1.0) or 1.0)
    score = _norm(1.0 / max(cost, 0.5))
    q = [
        _q("apply_station", province_id, score, "move path ops primary"),
        _q("apply_supply", province_id, 0.5, "move path ops supply"),
    ]
    return _day(
        "move_path_ops_day",
        "Move path ops day",
        "Move path ops day · %s · score %.2f" % (path.get("summary", "path"), score),
        score,
        q,
        "#5ec8ff",
        "🥾",
        ["move", "path", "logistics"],
        {"path": path},
    )


def multi_province_ops_day(province_id: int = 1) -> Dict[str, Any]:
    plan = multi_province_day_plan()
    score = _norm(float(plan.get("score", 0.7)))
    q = [
        _q("apply_supply", province_id, score, "multi province ops primary"),
        _q("apply_station", province_id, 0.55, "multi province ops station"),
        _q("apply_assault", province_id, 0.45, "multi province ops assault"),
    ]
    return _day(
        "multi_province_ops_day",
        "Multi province ops day",
        "Multi province ops day · %s · score %.2f" % (plan.get("summary", "plan"), score),
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["theater", "multi_province", "ops"],
        {"plan": plan},
    )


def theater_auto_tick_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    combat = theater_combat_auto_command()
    score = _norm(max(float(tick.get("score", 0.5)), float(combat.get("score", 0.4))))
    q = [
        _q("apply_station", province_id, score, "theater auto tick station"),
        _q("apply_supply", province_id, 0.5, "theater auto tick supply"),
        _q("apply_assault", province_id, 0.45, "theater auto tick assault"),
    ]
    return _day(
        "theater_auto_tick_day",
        "Theater auto tick day",
        "Theater auto tick day · tick %.2f · combat %.2f · score %.2f"
        % (float(tick.get("score", 0)), float(combat.get("score", 0)), score),
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["theater", "auto", "tick"],
        {"tick": tick, "combat": combat},
    )


def daily_supply_ops_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_supply_auto_apply_plan()
    budget = day_apply_budget(4, 3)
    score = _norm(max(float(plan.get("score", 0.4)), 0.5))
    q = [
        _q("apply_supply", province_id, score, "daily supply ops primary"),
        _q("apply_station", province_id, 0.5, "daily supply ops station"),
    ]
    return _day(
        "daily_supply_ops_day",
        "Daily supply ops day",
        "Daily supply ops day · %s · score %.2f" % (plan.get("summary", "supply"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "daily", "ops"],
        {"plan": plan, "budget": budget},
    )


def logistics_theater_close_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    risk = campaign_day_risk(w, month=3)
    depot = depot_weather_capacity(w, base_capacity=100.0)
    supply = supply_route_mutation()
    tick = daily_theater_auto_tick()
    score = _norm(
        0.3 * float(supply.get("score", 0.5))
        + 0.3 * float(tick.get("score", 0.5))
        + 0.4 * (1.0 - min(1.0, float(risk.get("risk", risk.get("pressure", 0.5)) or 0.5) if float(risk.get("risk", 0.5) or 0.5) <= 1 else float(risk.get("risk", 50)) / 100.0))
    )
    q = [
        _q("apply_supply", province_id, score, "logistics theater close supply"),
        _q("apply_station", province_id, 0.55, "logistics theater close station"),
        _q("apply_production", province_id, 0.5, "logistics theater close production"),
    ]
    return _day(
        "logistics_theater_close_day",
        "Logistics theater close day",
        "Logistics theater close day · risk · depot · supply · tick · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "∞",
        ["logistics", "theater", "close"],
        {"risk": risk, "depot": depot, "supply": supply, "tick": tick},
    )


# B) Force / OOB readiness


def force_readiness_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    factory = oob_factory_risk_loop()
    score = _norm(max(float(equip.get("score", 0.55)), 0.55))
    q = [
        _q("apply_production", province_id, score, "force readiness ops production"),
        _q("apply_supply", province_id, 0.5, "force readiness ops supply"),
    ]
    return _day(
        "force_readiness_ops_day",
        "Force readiness ops day",
        "Force readiness ops day · equip · factory · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🛡",
        ["force", "readiness", "oob"],
        {"equip": equip, "factory": factory},
    )


def oob_factory_ops_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    try:
        loop = oob_factory_risk_loop(
            temp=float(w.get("temp", 8)),
            precip=float(w.get("precip_intensity", 0.3)),
            ground_state=str(w.get("ground_state", "mud")),
        )
    except TypeError:
        loop = oob_factory_risk_loop()
    score = 0.7
    if isinstance(loop.get("score"), (int, float)):
        score = _norm(float(loop["score"]))
    q = [
        _q("apply_production", province_id, score, "oob factory ops primary"),
        _q("apply_supply", province_id, 0.5, "oob factory ops supply"),
    ]
    return _day(
        "oob_factory_ops_day",
        "OOB factory ops day",
        "OOB factory ops day · %s · score %.2f" % (loop.get("summary", "factory"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["oob", "factory", "risk"],
        {"loop": loop},
    )


def medium_equip_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    prod = production_priority_mutation()
    score = _norm(0.5 * float(equip.get("score", 0.55)) + 0.5 * float(prod.get("score", 0.7)))
    q = [
        _q("apply_production", province_id, score, "medium equip ops primary"),
        _q("apply_supply", province_id, 0.5, "medium equip ops supply"),
    ]
    return _day(
        "medium_equip_ops_day",
        "Medium equip ops day",
        "Medium equip ops day · %s · score %.2f" % (equip.get("summary", "equip"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["equip", "oob", "production"],
        {"equip": equip, "production": prod},
    )


def naval_skim_ops_day(province_id: int = 1) -> Dict[str, Any]:
    skim = naval_campaign_skim()
    patrol = fleet_patrol_strip()
    score = _norm(max(float(skim.get("score", 0.6)), float(patrol.get("score", 0.5))))
    q = [
        _q("apply_station", province_id, score, "naval skim ops primary"),
        _q("apply_supply", province_id, 0.5, "naval skim ops supply"),
    ]
    return _day(
        "naval_skim_ops_day",
        "Naval skim ops day",
        "Naval skim ops day · skim %.2f · patrol %.2f · score %.2f"
        % (float(skim.get("score", 0)), float(patrol.get("score", 0)), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["naval", "skim", "force"],
        {"skim": skim, "patrol": patrol},
    )


def basing_logistics_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fuel = basing_fleet_fuel_logistics()
    score = _norm(float(fuel.get("logistics_score", fuel.get("fuel_level", 0.5)) or 0.5))
    if score < 0.3:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "basing logistics ops primary"),
        _q("apply_supply", province_id, 0.55, "basing logistics ops supply"),
    ]
    return _day(
        "basing_logistics_ops_day",
        "Basing logistics ops day",
        "Basing logistics ops day · %s · score %.2f" % (fuel.get("summary", "fuel"), score),
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["basing", "logistics", "force"],
        {"fuel": fuel},
    )


def production_force_ops_day(province_id: int = 1) -> Dict[str, Any]:
    prod = production_priority_mutation()
    theater = theater_production_auto()
    equip = medium_horizon_equip_plan()
    score = _norm(
        max(
            float(prod.get("score", 0.5)),
            float(theater.get("score", 0.5)),
            float(equip.get("score", 0.5)),
        )
    )
    q = [
        _q("apply_production", province_id, score, "production force ops primary"),
        _q("apply_supply", province_id, 0.5, "production force ops supply"),
    ]
    return _day(
        "production_force_ops_day",
        "Production force ops day",
        "Production force ops day · prod · theater · equip · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "force", "oob"],
        {"production": prod, "theater": theater, "equip": equip},
    )


def force_oob_close_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    factory = oob_factory_risk_loop()
    sole = sole_mult_integrity()
    gate = execution_integrity_gate()
    ok = bool(sole.get("integrity_ok", True)) and bool(gate.get("ok", False))
    score = _norm(0.5 * float(equip.get("score", 0.55)) + 0.5 * (0.8 if ok else 0.35))
    q = [
        _q("apply_production", province_id, score, "force oob close production"),
        _q("apply_supply", province_id, 0.5, "force oob close supply"),
        _q("apply_station", province_id, 0.45, "force oob close station"),
    ]
    return _day(
        "force_oob_close_day",
        "Force OOB close day",
        "Force OOB close day · equip · factory · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["force", "oob", "close"],
        {"equip": equip, "factory": factory, "sole": sole, "gate": gate, "ok": ok},
    )


# C) Panel / inspector surface


def player_surface_ops_day(province_id: int = 1) -> Dict[str, Any]:
    strip = player_order_surface_strip()
    execute = execute_one_order()
    score = _norm(0.5 * (0.7 if not strip.get("empty") else 0.4) + 0.5 * float(execute.get("score", 0.6)))
    q = [
        _q("refresh_queue", province_id, score, "player surface ops refresh"),
        _q("apply_supply", province_id, 0.55, "player surface ops supply"),
        _q("apply_station", province_id, 0.5, "player surface ops station"),
    ]
    return _day(
        "player_surface_ops_day",
        "Player surface ops day",
        "Player surface ops day · strip · execute · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🖥",
        ["panel", "player_surface", "ops"],
        {"strip": strip, "execute": execute},
    )


def order_panel_ops_day(province_id: int = 1) -> Dict[str, Any]:
    primary = order_panel_primary_actions()
    ids = order_panel_action_ids()
    n_p = len(primary) if isinstance(primary, list) else 0
    n_i = len(ids) if isinstance(ids, list) else 0
    score = _norm(0.4 + 0.01 * min(30, n_p) + 0.005 * min(40, n_i))
    q = [
        _q("refresh_queue", province_id, score, "order panel ops refresh"),
        _q("apply_supply", province_id, 0.5, "order panel ops supply"),
    ]
    return _day(
        "order_panel_ops_day",
        "Order panel ops day",
        "Order panel ops day · primary %d · ids %d · score %.2f" % (n_p, n_i, score),
        score,
        q,
        "#5ec8ff",
        "📋",
        ["panel", "order", "ops"],
        {"primary": primary, "ids": ids, "primary_count": n_p, "id_count": n_i},
    )


def panel_sections_ops_day(province_id: int = 1) -> Dict[str, Any]:
    loop = close_order_panel_ux_depth_loop()
    score = 0.7 if not loop.get("empty") else 0.45
    q = [
        _q("refresh_queue", province_id, score, "panel sections ops refresh"),
        _q("apply_station", province_id, 0.5, "panel sections ops station"),
        _q("apply_production", province_id, 0.45, "panel sections ops production"),
    ]
    return _day(
        "panel_sections_ops_day",
        "Panel sections ops day",
        "Panel sections ops day · %s · score %.2f" % (loop.get("summary", "panel"), score),
        score,
        q,
        "#5ec8ff",
        "📑",
        ["panel", "sections", "ux"],
        {"loop": loop},
    )


def tooltip_flair_ops_day(province_id: int = 1) -> Dict[str, Any]:
    flair = tooltip_sfx_flair_strip()
    score = _norm(float(flair.get("score", 0.9)))
    q = [
        _q("refresh_queue", province_id, score, "tooltip flair ops refresh"),
        _q("apply_assault", province_id, 0.5, "tooltip flair ops assault"),
    ]
    return _day(
        "tooltip_flair_ops_day",
        "Tooltip flair ops day",
        "Tooltip flair ops day · %s · score %.2f" % (flair.get("summary", "flair"), score),
        score,
        q,
        "#7dd3a0",
        "✨",
        ["inspector", "tooltip", "sfx"],
        {"flair": flair},
    )


def apply_audit_ops_day(province_id: int = 1) -> Dict[str, Any]:
    panel = "\n".join(
        [
            "depot_logistics_day",
            "force_readiness_ops_day",
            "order_panel_ops_day",
            "logistics_force_panel_close_day",
        ]
    )
    gd = "\n".join(
        [
            "apply_depot_logistics_day",
            "apply_force_readiness_ops_day",
            "apply_order_panel_ops_day",
            "apply_logistics_force_panel_close_day",
        ]
    )
    audit = day_package_apply_audit(panel, gd)
    score = max(_norm(float(audit.get("score", 0.4))), 0.4)
    q = [
        _q("refresh_queue", province_id, score, "apply audit ops refresh"),
        _q("apply_supply", province_id, 0.5, "apply audit ops supply"),
    ]
    return _day(
        "apply_audit_ops_day",
        "Apply audit ops day",
        "Apply audit ops day · %s · score %.2f" % (audit.get("summary", "audit"), score),
        score,
        q,
        "#8899aa",
        "✓",
        ["panel", "audit", "routing"],
        {"audit": audit},
    )


def logistics_force_panel_close_day(province_id: int = 1) -> Dict[str, Any]:
    depot = depot_weather_capacity(_wx(), base_capacity=100.0)
    equip = medium_horizon_equip_plan()
    panel = close_order_panel_ux_depth_loop()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * (float(depot.get("capacity", 65) or 65) / 100.0)
        + 0.25 * float(equip.get("score", 0.55))
        + 0.25 * (0.7 if not panel.get("empty") else 0.4)
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_supply", province_id, 0.55, "close logistics supply"),
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "close force production"),
        _q("refresh_queue", province_id, 0.5, "close panel refresh"),
        _q("apply_station", province_id, 0.45, "close theater station"),
    ]
    return _day(
        "logistics_force_panel_close_day",
        "Logistics force panel close day",
        "Logistics force panel close day · logistics · force · panel · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["logistics", "force", "panel", "close"],
        {"depot": depot, "equip": equip, "panel": panel, "gate": gate, "sole": sole, "ok": ok},
    )


LOGISTICS_FORCE_PANEL_DAY_IDS: List[str] = [
    "depot_logistics_day",
    "supply_route_ops_day",
    "move_path_ops_day",
    "multi_province_ops_day",
    "theater_auto_tick_day",
    "daily_supply_ops_day",
    "logistics_theater_close_day",
    "force_readiness_ops_day",
    "oob_factory_ops_day",
    "medium_equip_ops_day",
    "naval_skim_ops_day",
    "basing_logistics_ops_day",
    "production_force_ops_day",
    "force_oob_close_day",
    "player_surface_ops_day",
    "order_panel_ops_day",
    "panel_sections_ops_day",
    "tooltip_flair_ops_day",
    "apply_audit_ops_day",
    "logistics_force_panel_close_day",
]


DAY_FUNCS = [
    depot_logistics_day,
    supply_route_ops_day,
    move_path_ops_day,
    multi_province_ops_day,
    theater_auto_tick_day,
    daily_supply_ops_day,
    logistics_theater_close_day,
    force_readiness_ops_day,
    oob_factory_ops_day,
    medium_equip_ops_day,
    naval_skim_ops_day,
    basing_logistics_ops_day,
    production_force_ops_day,
    force_oob_close_day,
    player_surface_ops_day,
    order_panel_ops_day,
    panel_sections_ops_day,
    tooltip_flair_ops_day,
    apply_audit_ops_day,
    logistics_force_panel_close_day,
]


def logistics_force_panel_integrity() -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    panel = close_order_panel_ux_depth_loop()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    supply = supply_route_mutation()
    ok = (
        not bool(equip.get("empty", False))
        and not bool(panel.get("empty", False))
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and not bool(supply.get("empty", False))
    )
    return {
        "ok": ok,
        "equip_score": float(equip.get("score", 0)),
        "panel_empty": bool(panel.get("empty", False)),
        "gate": gate,
        "sole": sole,
        "summary": "Logistics-force-panel integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next140_logistics_force_panel_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    wx_days = {
        "depot_logistics_day",
        "logistics_theater_close_day",
        "oob_factory_ops_day",
    }
    for fn in DAY_FUNCS:
        name = fn.__name__
        try:
            if name in wx_days:
                packages[name] = fn(weather=w)
            else:
                packages[name] = fn()
        except TypeError:
            packages[name] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = logistics_force_panel_integrity()
    label = "Close next140 logistics-force-panel · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next140 logistics-force-panel[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
