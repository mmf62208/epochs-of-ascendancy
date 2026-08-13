"""Next-120 industry/save/live-apply loops: 20 multi-system day packages.

Post next-110 gaps:
  A) Live order/mutation apply path (1–7)
  B) Industry/production campaign surface (8–14)
  C) Save/load + campaign continuity (15–20)

1 prod_mut_apply_day · 2 supply_mut_apply_day · 3 execute_prod_live_day
4 day_budget_apply_day · 5 apply_audit_live_day · 6 live_apply_results_day
7 mutation_gate_apply_day · 8 daily_prod_auto_live_day · 9 theater_prod_live_day
10 prod_campaign_risk_day · 11 prod_wx_stack_day · 12 factory_risk_live_day
13 depot_prod_stack_day · 14 industry_close_loop_day · 15 save_slot_surface_day
16 save_browser_live_day · 17 campaign_continuity_day · 18 ops_dash_continuity_day
19 execution_gate_cont_day · 20 industry_save_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from live_mutation import (  # type: ignore
    production_priority_mutation,
    supply_route_mutation,
    next_day_mutation_feedback,
    mutation_integrity_gate,
    fleet_station_mutation,
)
from daily_command_tick import (  # type: ignore
    daily_production_auto_apply_plan,
    apply_result_feedback,
    simulate_day_apply_results,
    day_apply_budget,
)
from campaign_cohesion import production_campaign_risk  # type: ignore
from theater_ops_polish import (  # type: ignore
    production_weather_alert,
    depot_weather_capacity,
    campaign_day_risk,
    format_ops_dashboard,
)
from weather_effects import production_weather_multiplier  # type: ignore
from theater_commander import theater_production_auto, execute_one_order  # type: ignore
from week2_core_polish import day_package_apply_audit  # type: ignore
from save_slot_ui import build_save_slot_list  # type: ignore
from campaign_execution import close_the_loop, execution_integrity_gate  # type: ignore
from gameplay_loops import oob_factory_risk_loop, sole_mult_integrity  # type: ignore


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
        "integration": list(integration or ["next120", "industry_save"]),
    }
    if extra:
        for k, v in extra.items():
            if k == "actions":
                continue
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


# ---------------------------------------------------------------------------
# A) Live order/mutation apply path
# ---------------------------------------------------------------------------


def prod_mut_apply_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation()
    before = 0.45
    after = float(mut.get("score", 1.0))
    fb = next_day_mutation_feedback(before, after, "production", "apply_production")
    score = _norm(after)
    q = [
        _q("apply_production", province_id, score, "prod mut apply primary"),
        _q("apply_supply", province_id, 0.5, "prod mut apply supply"),
    ]
    return _day(
        "prod_mut_apply_day",
        "Prod mut apply day",
        "Prod mut apply day · %s · score %.2f" % (mut.get("summary", "prod"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "mutation", "apply"],
        {"mutation": mut, "feedback": fb},
    )


def supply_mut_apply_day(province_id: int = 1) -> Dict[str, Any]:
    mut = supply_route_mutation()
    fb = apply_result_feedback(0.4, float(mut.get("score", 0.55)), "supply")
    score = _norm(float(mut.get("score", 0.55)))
    q = [
        _q("apply_supply", province_id, score, "supply mut apply primary"),
        _q("apply_station", province_id, 0.5, "supply mut apply station"),
    ]
    return _day(
        "supply_mut_apply_day",
        "Supply mut apply day",
        "Supply mut apply day · %s · score %.2f" % (mut.get("summary", "supply"), score),
        score,
        q,
        "#7dd3a0",
        "📦",
        ["supply", "mutation", "apply"],
        {"mutation": mut, "feedback": fb},
    )


def execute_prod_live_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    order = execute_one_order(weather=_wx(weather))
    score = _norm(float(order.get("score", 0.7)))
    domain = str(order.get("domain", "production"))
    primary = {
        "combat": "apply_assault",
        "fleet": "apply_station",
        "agent": "apply_agent_dispatch",
        "hh": "apply_hh_commit",
        "production": "apply_production",
    }.get(domain, "apply_production")
    q = [
        _q(primary, province_id, score, "execute prod live primary"),
        _q("apply_supply", province_id, 0.5, "execute prod live secondary"),
    ]
    return _day(
        "execute_prod_live_day",
        "Execute prod live day",
        "Execute prod live day · %s · score %.2f" % (order.get("summary", domain), score),
        score,
        q,
        "#e8c547",
        "▶",
        ["execute", "production", "live"],
        {"order": order},
    )


def day_budget_apply_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    bud = day_apply_budget(5, 3, _wx(weather))
    score = _norm(float(bud.get("score", 0.6)))
    if score < 0.1:
        score = 0.6  # keep actionable when pending capped
    allowed = int(bud.get("allowed", 3) or 3)
    q = [
        _q("refresh_queue", province_id, score, "day budget apply gate"),
        _q("apply_production", province_id, 0.55, "day budget apply production"),
        _q("apply_supply", province_id, 0.5, "day budget apply supply"),
    ]
    return _day(
        "day_budget_apply_day",
        "Day budget apply day",
        "Day budget apply day · allow %d · score %.2f" % (allowed, score),
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["budget", "apply", "cap"],
        {"budget": bud},
    )


def apply_audit_live_day(province_id: int = 1) -> Dict[str, Any]:
    panel = "\n".join(
        [
            "prod_mut_apply_day",
            "daily_prod_auto_live_day",
            "save_slot_surface_day",
            "industry_save_close_day",
            "execute_prod_live_day",
        ]
    )
    gd = "\n".join(
        [
            "apply_prod_mut_apply_day",
            "apply_daily_prod_auto_live_day",
            "apply_save_slot_surface_day",
            "apply_industry_save_close_day",
            "apply_execute_prod_live_day",
        ]
    )
    audit = day_package_apply_audit(panel, gd)
    score = _norm(float(audit.get("score", 0.5)))
    q = [
        _q("refresh_queue", province_id, max(score, 0.4), "apply audit live refresh"),
        _q("apply_supply", province_id, 0.5, "apply audit live supply"),
    ]
    return _day(
        "apply_audit_live_day",
        "Apply audit live day",
        "Apply audit live day · %s · score %.2f" % (audit.get("summary", "audit"), score),
        max(score, 0.35),
        q,
        "#8899aa",
        "✓",
        ["audit", "routing", "apply"],
        {"audit": audit},
    )


def live_apply_results_day(province_id: int = 1) -> Dict[str, Any]:
    sim = simulate_day_apply_results(
        [
            {
                "action_id": "apply_production",
                "ok": True,
                "apply_ready": True,
                "label": "production",
                "province_id": province_id,
                "score": 0.8,
            },
            {
                "action_id": "apply_supply",
                "ok": True,
                "apply_ready": True,
                "label": "supply",
                "province_id": province_id,
                "score": 0.6,
            },
            {
                "action_id": "save_slot:quicksave",
                "ok": True,
                "apply_ready": True,
                "label": "quicksave",
                "province_id": province_id,
                "score": 0.7,
            },
        ]
    )
    fb = apply_result_feedback(0.5, 0.75, "production")
    ok_count = int(sim.get("ok_count", 0) or 0)
    score = _norm(0.5 + 0.1 * ok_count)
    q = [
        _q("refresh_queue", province_id, score, "live apply results refresh"),
        _q("apply_production", province_id, 0.6, "live apply results production"),
        _q("save_slot:quicksave", province_id, 0.55, "live apply results save"),
    ]
    return _day(
        "live_apply_results_day",
        "Live apply results day",
        "Live apply results day · %s · score %.2f" % (sim.get("summary", "sim"), score),
        score,
        q,
        "#7dd3a0",
        "↻",
        ["apply", "results", "feedback"],
        {"sim": sim, "feedback": fb},
    )


def mutation_gate_apply_day(province_id: int = 1) -> Dict[str, Any]:
    gate = mutation_integrity_gate()
    prod = production_priority_mutation()
    fleet = fleet_station_mutation()
    ok = bool(gate.get("ok", False))
    score = _norm(
        (0.75 if ok else 0.35) * 0.5
        + 0.25 * float(prod.get("score", 0.5))
        + 0.25 * float(fleet.get("score", 0.5))
    )
    q = [
        _q("apply_production", province_id, float(prod.get("score", score)), "mutation gate apply prod"),
        _q("apply_station", province_id, float(fleet.get("score", score)), "mutation gate apply station"),
        _q("apply_supply", province_id, 0.5, "mutation gate apply supply"),
    ]
    return _day(
        "mutation_gate_apply_day",
        "Mutation gate apply day",
        "Mutation gate apply day · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["mutation", "gate", "apply"],
        {"gate": gate, "production": prod, "fleet": fleet, "ok": ok},
    )


# ---------------------------------------------------------------------------
# B) Industry / production campaign surface
# ---------------------------------------------------------------------------


def daily_prod_auto_live_day(province_id: int = 1) -> Dict[str, Any]:
    plan = daily_production_auto_apply_plan()
    score = _norm(float(plan.get("score", 1.0)))
    q = [
        _q("apply_production", province_id, score, "daily prod auto primary"),
        _q("apply_supply", province_id, 0.5, "daily prod auto supply"),
    ]
    return _day(
        "daily_prod_auto_live_day",
        "Daily prod auto live day",
        "Daily prod auto live day · %s · score %.2f" % (plan.get("summary", "auto"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "auto", "daily"],
        {"plan": plan},
    )


def theater_prod_live_day(province_id: int = 1) -> Dict[str, Any]:
    theater = theater_production_auto()
    score = _norm(float(theater.get("score", 1.0)))
    q = [
        _q("apply_production", province_id, score, "theater prod live primary"),
        _q("apply_supply", province_id, 0.5, "theater prod live supply"),
    ]
    return _day(
        "theater_prod_live_day",
        "Theater prod live day",
        "Theater prod live day · %s · score %.2f" % (theater.get("summary", "theater"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "theater", "auto"],
        {"theater": theater},
    )


def prod_campaign_risk_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    risk = production_campaign_risk(weather=_wx(weather))
    raw = float(risk.get("score", risk.get("risk", 0.0)) or 0.0)
    # lower risk → higher actionable production score
    score = _norm(1.0 - (raw if raw <= 1.0 else raw / 100.0))
    if score < 0.35:
        score = 0.55
    q = [
        _q("apply_production", province_id, score, "prod campaign risk primary"),
        _q("apply_supply", province_id, 0.5, "prod campaign risk supply"),
    ]
    return _day(
        "prod_campaign_risk_day",
        "Prod campaign risk day",
        "Prod campaign risk day · %s · score %.2f" % (risk.get("summary", "risk"), score),
        score,
        q,
        "#e8c547",
        "⚠",
        ["production", "campaign", "risk"],
        {"risk": risk},
    )


def prod_wx_stack_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    mult = float(production_weather_multiplier(w))
    alert = production_weather_alert(w)
    mut = production_priority_mutation()
    score = _norm(max(mult, float(mut.get("score", 0.5)) * 0.5 + mult * 0.5))
    q = [
        _q("apply_production", province_id, score, "prod wx stack primary"),
        _q("apply_supply", province_id, 0.5, "prod wx stack supply"),
    ]
    return _day(
        "prod_wx_stack_day",
        "Prod wx stack day",
        "Prod wx stack day · mult ×%.2f · mut %.2f · score %.2f"
        % (mult, float(mut.get("score", 0)), score),
        score,
        q,
        "#e8c547",
        "🌦",
        ["production", "weather", "mutation"],
        {"mult": mult, "alert": alert, "mutation": mut},
    )


def factory_risk_live_day(
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
    elif "out" in str(loop.get("summary", "")):
        score = 0.75
    q = [
        _q("apply_production", province_id, score, "factory risk live primary"),
        _q("apply_supply", province_id, 0.5, "factory risk live supply"),
    ]
    return _day(
        "factory_risk_live_day",
        "Factory risk live day",
        "Factory risk live day · %s · score %.2f" % (loop.get("summary", "factory"), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["factory", "risk", "production"],
        {"loop": loop},
    )


def depot_prod_stack_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    depot = depot_weather_capacity(w, base_capacity=100.0)
    prod = daily_production_auto_apply_plan()
    cap = float(depot.get("capacity", depot.get("effective_capacity", 65)) or 65)
    score = _norm(0.5 * (cap / 100.0) + 0.5 * float(prod.get("score", 0.8)))
    q = [
        _q("apply_supply", province_id, _norm(cap / 100.0), "depot prod stack supply"),
        _q("apply_production", province_id, float(prod.get("score", 0.8)), "depot prod stack production"),
    ]
    return _day(
        "depot_prod_stack_day",
        "Depot prod stack day",
        "Depot prod stack day · cap %.0f · prod %.2f · score %.2f"
        % (cap, float(prod.get("score", 0)), score),
        score,
        q,
        "#e8c547",
        "🏗",
        ["depot", "production", "stack"],
        {"depot": depot, "plan": prod},
    )


def industry_close_loop_day(province_id: int = 1) -> Dict[str, Any]:
    loop = close_the_loop()
    sole = sole_mult_integrity()
    prod = production_priority_mutation()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", sole.get("ok", True)))
    score = _norm(0.6 if ok else 0.35)
    score = _norm(0.5 * score + 0.5 * float(prod.get("score", 0.5)))
    q = [
        _q("apply_production", province_id, float(prod.get("score", score)), "industry close production"),
        _q("apply_station", province_id, 0.55, "industry close station"),
        _q("apply_supply", province_id, 0.5, "industry close supply"),
    ]
    return _day(
        "industry_close_loop_day",
        "Industry close loop day",
        "Industry close loop day · %s · gate %s · score %.2f"
        % (loop.get("summary", "close"), "PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "∞",
        ["industry", "close_loop", "integrity"],
        {"loop": loop, "sole": sole, "production": prod, "gate": gate, "ok": ok},
    )


# ---------------------------------------------------------------------------
# C) Save / campaign continuity
# ---------------------------------------------------------------------------


def save_slot_surface_day(province_id: int = 1) -> Dict[str, Any]:
    slots = build_save_slot_list(
        [
            {"slot": "quicksave", "mtime": 1, "label": "Quicksave"},
            {"slot": "slot_1", "mtime": 2, "label": "Campaign 1"},
            {"slot": "autosave", "mtime": 3, "label": "Autosave"},
        ]
    )
    n = len(slots) if isinstance(slots, list) else 0
    score = _norm(0.4 + 0.08 * min(6, n))
    q = [
        _q("save_slot:quicksave", province_id, score, "save slot surface quicksave"),
        _q("refresh_queue", province_id, 0.5, "save slot surface refresh"),
    ]
    return _day(
        "save_slot_surface_day",
        "Save slot surface day",
        "Save slot surface day · slots %d · score %.2f" % (n, score),
        score,
        q,
        "#8899aa",
        "💾",
        ["save", "slots", "surface"],
        {"slots": slots, "count": n},
    )


def save_browser_live_day(province_id: int = 1) -> Dict[str, Any]:
    slots = build_save_slot_list(
        [
            {"slot": "quicksave", "mtime": 10, "label": "Quicksave"},
            {"slot": "slot_1", "mtime": 20, "label": "Ironman"},
            {"slot": "slot_2", "mtime": 15, "label": "Backup"},
        ]
    )
    n = len(slots) if isinstance(slots, list) else 0
    occupied = 0
    if isinstance(slots, list):
        for s in slots:
            if isinstance(s, dict) and s.get("occupied", s.get("status") == "occupied"):
                occupied += 1
    score = _norm(0.45 + 0.08 * min(5, n) + 0.05 * min(3, occupied))
    q = [
        _q("save_slot:quicksave", province_id, score, "save browser live quicksave"),
        _q("apply_supply", province_id, 0.45, "save browser live supply"),
    ]
    return _day(
        "save_browser_live_day",
        "Save browser live day",
        "Save browser live day · slots %d · occupied %d · score %.2f" % (n, occupied, score),
        score,
        q,
        "#8899aa",
        "📂",
        ["save", "browser", "continuity"],
        {"slots": slots, "count": n, "occupied": occupied},
    )


def campaign_continuity_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    risk = campaign_day_risk(w, month=3)
    loop = close_the_loop()
    slots = build_save_slot_list([{"slot": "quicksave", "mtime": 1, "label": "Q"}])
    pressure = float(risk.get("risk", risk.get("pressure", 0.5)) or 0.5)
    if pressure > 2:
        pressure = pressure / 100.0
    score = _norm(1.0 - pressure * 0.5)
    q = [
        _q("save_slot:quicksave", province_id, score, "campaign continuity save"),
        _q("apply_station", province_id, 0.55, "campaign continuity station"),
        _q("apply_supply", province_id, 0.5, "campaign continuity supply"),
    ]
    return _day(
        "campaign_continuity_day",
        "Campaign continuity day",
        "Campaign continuity day · %s · save · score %.2f"
        % (risk.get("summary", "risk"), score),
        score,
        q,
        "#5ec8ff",
        "📜",
        ["campaign", "continuity", "save"],
        {"risk": risk, "loop": loop, "slots": slots},
    )


def ops_dash_continuity_day(
    province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    risk = campaign_day_risk(w, month=6)
    dash = format_ops_dashboard(day_risk=risk)
    score = 0.6 if not dash.get("empty") else 0.55
    if risk.get("summary"):
        score = 0.65
    q = [
        _q("refresh_queue", province_id, score, "ops dash continuity refresh"),
        _q("apply_station", province_id, 0.5, "ops dash continuity station"),
        _q("apply_production", province_id, 0.5, "ops dash continuity production"),
    ]
    return _day(
        "ops_dash_continuity_day",
        "Ops dash continuity day",
        "Ops dash continuity day · %s · score %.2f" % (risk.get("summary", "ops"), score),
        score,
        q,
        "#5ec8ff",
        "📋",
        ["ops", "dashboard", "continuity"],
        {"risk": risk, "dashboard": dash},
    )


def execution_gate_cont_day(province_id: int = 1) -> Dict[str, Any]:
    gate = execution_integrity_gate()
    mut = mutation_integrity_gate()
    ok = bool(gate.get("ok", False)) and bool(mut.get("ok", False))
    score = 0.8 if ok else 0.35
    q = [
        _q("refresh_queue", province_id, score, "execution gate cont refresh"),
        _q("apply_production", province_id, 0.55, "execution gate cont production"),
        _q("save_slot:quicksave", province_id, 0.5, "execution gate cont save"),
    ]
    return _day(
        "execution_gate_cont_day",
        "Execution gate cont day",
        "Execution gate cont day · exec %s · mut %s · score %.2f"
        % (
            "PASS" if gate.get("ok") else "FAIL",
            "PASS" if mut.get("ok") else "FAIL",
            score,
        ),
        score,
        q,
        "#5ec8ff",
        "🛡",
        ["execution", "integrity", "continuity"],
        {"gate": gate, "mutation_gate": mut, "ok": ok},
    )


def industry_save_close_day(province_id: int = 1) -> Dict[str, Any]:
    """Close package: production mut + save slots + execution gate + sole mult."""
    prod = production_priority_mutation()
    plan = daily_production_auto_apply_plan()
    slots = build_save_slot_list(
        [{"slot": "quicksave", "mtime": 1, "label": "Q"}, {"slot": "slot_1", "mtime": 2, "label": "S1"}]
    )
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    n = len(slots) if isinstance(slots, list) else 0
    score = _norm(
        0.3 * float(prod.get("score", 0.5))
        + 0.3 * float(plan.get("score", 0.5))
        + 0.2 * (0.8 if ok else 0.3)
        + 0.2 * min(1.0, 0.3 + 0.1 * n)
    )
    q = [
        _q("apply_production", province_id, float(prod.get("score", score)), "industry save close prod"),
        _q("save_slot:quicksave", province_id, 0.6, "industry save close quicksave"),
        _q("apply_supply", province_id, 0.5, "industry save close supply"),
        _q("apply_station", province_id, 0.45, "industry save close station"),
    ]
    return _day(
        "industry_save_close_day",
        "Industry save close day",
        "Industry save close day · prod · save %d · gate %s · score %.2f"
        % (n, "PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["industry", "save", "close", "integrity"],
        {
            "production": prod,
            "plan": plan,
            "slots": slots,
            "gate": gate,
            "sole": sole,
            "ok": ok,
        },
    )


INDUSTRY_SAVE_DAY_IDS: List[str] = [
    "prod_mut_apply_day",
    "supply_mut_apply_day",
    "execute_prod_live_day",
    "day_budget_apply_day",
    "apply_audit_live_day",
    "live_apply_results_day",
    "mutation_gate_apply_day",
    "daily_prod_auto_live_day",
    "theater_prod_live_day",
    "prod_campaign_risk_day",
    "prod_wx_stack_day",
    "factory_risk_live_day",
    "depot_prod_stack_day",
    "industry_close_loop_day",
    "save_slot_surface_day",
    "save_browser_live_day",
    "campaign_continuity_day",
    "ops_dash_continuity_day",
    "execution_gate_cont_day",
    "industry_save_close_day",
]


DAY_FUNCS = [
    prod_mut_apply_day,
    supply_mut_apply_day,
    execute_prod_live_day,
    day_budget_apply_day,
    apply_audit_live_day,
    live_apply_results_day,
    mutation_gate_apply_day,
    daily_prod_auto_live_day,
    theater_prod_live_day,
    prod_campaign_risk_day,
    prod_wx_stack_day,
    factory_risk_live_day,
    depot_prod_stack_day,
    industry_close_loop_day,
    save_slot_surface_day,
    save_browser_live_day,
    campaign_continuity_day,
    ops_dash_continuity_day,
    execution_gate_cont_day,
    industry_save_close_day,
]


def industry_save_integrity() -> Dict[str, Any]:
    gate = execution_integrity_gate()
    mut = mutation_integrity_gate()
    sole = sole_mult_integrity()
    prod = production_priority_mutation()
    slots = build_save_slot_list([{"slot": "quicksave", "mtime": 1, "label": "Q"}])
    ok = (
        bool(gate.get("ok", False))
        and bool(mut.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and not bool(prod.get("empty", False))
        and isinstance(slots, list)
        and len(slots) >= 1
    )
    return {
        "ok": ok,
        "execution": gate,
        "mutation": mut,
        "sole": sole,
        "production_score": float(prod.get("score", 0)),
        "slot_count": len(slots) if isinstance(slots, list) else 0,
        "summary": "Industry-save integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next120_industry_save_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = _wx(weather)
    packages: Dict[str, Any] = {}
    wx_days = {
        "execute_prod_live_day",
        "day_budget_apply_day",
        "prod_campaign_risk_day",
        "prod_wx_stack_day",
        "factory_risk_live_day",
        "depot_prod_stack_day",
        "campaign_continuity_day",
        "ops_dash_continuity_day",
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
    gate = industry_save_integrity()
    label = "Close next120 industry-save · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next120 industry-save[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
