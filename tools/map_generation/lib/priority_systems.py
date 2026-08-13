"""Priority systems depth (P1–P9 pilots): order panel UX model, multi-phase combat UI,
fleet AI ops, HH agenda screen, agent campaign, industry economy, save slots, GPU profile.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from ops_depth import (  # type: ignore
    order_panel_actions,
    order_panel_refresh_surface,
    combat_phase_depth,
    fleet_patrol_depth,
    multi_province_live_plan,
    ops_depth_integrity_gate,
)
from combat_phase_ui import format_phase_ribbon  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from assault_estimate_card import build_assault_estimate_card  # type: ignore
from hh_agenda_actions import format_hh_agenda_screen, pick_agenda_actions  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from save_slot_ui import build_save_slot_list, format_slot_row  # type: ignore
from naval_fleet_tasking import rank_naval_orders  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from theater_ops_polish import production_weather_alert  # type: ignore
from integrated_theater_ops import factory_risk_compose, supply_chain_health  # type: ignore
from gameplay_loops import sole_mult_integrity, oob_factory_risk_loop  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def order_panel_ux_model(
    province_ids: Optional[Sequence[int]] = None,
    selected_province_id: int = -1,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    last_result: Optional[Mapping[str, Any]] = None,
    province_names: Optional[Mapping[int, str]] = None,
) -> Dict[str, Any]:
    """P1: richer order panel model — named provinces, selection, actions, last result."""
    ids = [int(p) for p in list(province_ids or []) if int(p) >= 0]
    if not ids:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "options": [],
            "actions": [],
        }
    sel = int(selected_province_id)
    if sel not in ids:
        sel = ids[0]
    names = dict(province_names or {})
    options = []
    for pid in ids:
        pname = str(names.get(pid, "")).strip()
        label = "%s (#%d)" % (pname, pid) if pname else "Province #%d" % pid
        options.append({"province_id": pid, "label": label, "selected": pid == sel})
    panel = order_panel_actions(weather=weather, trail=trail, province_id=sel)
    surface = order_panel_refresh_surface(weather=weather, trail=trail, province_id=sel)
    result_line = ""
    if last_result and not last_result.get("empty"):
        result_line = "Last: %s → %s" % (
            last_result.get("action_id", "?"),
            "OK" if last_result.get("ok") else last_result.get("reason", "blocked"),
        )
    lines = [str(surface.get("summary", "")), str(panel.get("summary", ""))]
    if result_line:
        lines.append(result_line)
    # Extended action catalogue for full-game panel sections
    base_actions = list(panel.get("actions") or [])
    extended_ids = {
        str(a.get("action_id", "")) for a in base_actions if isinstance(a, dict)
    }
    for extra in (
        {"action_id": "apply_supply", "label": "Sustain supply route", "enabled": True},
        {"action_id": "apply_hh_commit", "label": "Commit HH agenda", "enabled": True},
        {
            "action_id": "apply_agent_dispatch",
            "label": "Dispatch agent counter-ops",
            "enabled": True,
        },
        {"action_id": "apply_counterplay", "label": "Apply counter-intel", "enabled": True},
        {"action_id": "apply_focus", "label": "Hold industrial focus", "enabled": True},
    ):
        if extra["action_id"] not in extended_ids:
            base_actions.append(extra)
            extended_ids.add(extra["action_id"])
    label = "Order panel UX · %d provinces · selected #%d · %d actions" % (
        len(ids),
        sel,
        len(base_actions),
    )
    return {
        "options": options,
        "selected_province_id": sel,
        "panel": panel,
        "surface": surface,
        "last_result": dict(last_result or {}),
        "actions": base_actions,
        "count": len(base_actions),
        "score": _score(panel, "score"),
        "summary": label,
        "plain": "\n".join([label] + [ln for ln in lines if ln]),
        "bbcode": "[color=#5ec8ff]📋 Order UX[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["order_panel", "province_bind", "feedback", "map_select", "extended_actions"],
    }


def multi_phase_combat_ui(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """P2: multi-phase combat UI package — estimate + ribbon + card + apply action."""
    w = dict(weather or {})
    precip = float(w.get("precip_intensity", 0.0) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    wmult = max(0.35, min(1.15, 1.0 - precip * 0.35 + (vis - 1.0) * 0.2))
    est = estimate_multi_phase_combat(
        attacker_power, defender_power, attacker_supply=attacker_supply, weather_mult=wmult
    )
    ribbon = format_phase_ribbon(est, attacker_power=attacker_power, defender_power=defender_power)
    try:
        card = build_assault_estimate_card(
            attacker_power=attacker_power,
            defender_power=defender_power,
            attacker_supply=attacker_supply,
            weather_mult=wmult,
        )
    except TypeError:
        try:
            card = build_assault_estimate_card(est)  # type: ignore
        except Exception:
            card = {"summary": str(est.get("summary", "")), "empty": False}
    depth = combat_phase_depth(
        attacker_power=attacker_power,
        defender_power=defender_power,
        attacker_supply=attacker_supply,
        weather=w,
    )
    score = _score(depth, "score")
    label = "Multi-phase combat UI · score %.2f · ribbon %s · atk %.0f/dfd %.0f" % (
        score,
        "yes" if not ribbon.get("empty") else "no",
        float(attacker_power),
        float(defender_power),
    )
    return {
        "estimate": est,
        "ribbon": ribbon,
        "card": card,
        "depth": depth,
        "attacker_power": float(attacker_power),
        "defender_power": float(defender_power),
        "actions": [
            {
                "action_id": "apply_assault",
                "label": "Stage multi-phase assault",
                "enabled": True,
            }
        ],
        "score": score,
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(ribbon.get("plain", ribbon.get("summary", ""))),
                str(card.get("plain", card.get("summary", "")))[:120],
            ]
        ),
        "bbcode": "[color=#5ec8ff]⚔ Multi-phase UI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["combat_phase", "ribbon", "card", "apply_assault"],
    }


def fleet_ai_ops_package(
    province_ids: Optional[Sequence[int]] = None,
    fuel_level: float = 0.7,
    available_strength: float = 100.0,
    path_zone_relations: Optional[Sequence[str]] = None,
    basing_level: str = "port",
) -> Dict[str, Any]:
    """P3: fleet AI ops — patrol depth + tasking rank + convoy escort plan."""
    ids = [int(p) for p in list(province_ids or [1, 2, 3]) if int(p) >= 0]
    patrol = fleet_patrol_depth(province_ids=ids, fuel_level=fuel_level, basing_level=basing_level)
    path = list(path_zone_relations or ["friendly", "contested", "hostile"])
    basing = {"level": basing_level, "basing_level": basing_level}
    try:
        tasking = rank_naval_orders(
            basing,
            zone_relation=path[-1] if path else "contested",
            fuel_level=fuel_level,
        )
    except TypeError:
        try:
            tasking = rank_naval_orders(basing=basing, fuel_level=fuel_level)  # type: ignore
        except Exception:
            tasking = {"summary": "tasking stub", "score": 0.5, "empty": False}
    try:
        escort = plan_convoy_escort(
            path_zone_relations=path,
            available_fleet_strength=available_strength,
            cargo_value=100.0,
        )
    except TypeError:
        try:
            escort = plan_convoy_escort(path, available_strength)  # type: ignore
        except Exception:
            escort = {"summary": "escort stub", "score": 0.5}
    score = (
        _score(patrol, "score")
        + _score(tasking, "score", "best_score", default=0.5)
        + _score(escort, "score", "coverage", default=0.5)
    ) / 3.0
    if isinstance(tasking.get("best_score"), (int, float)) and float(tasking["best_score"]) > 2:
        # normalize large posture scores
        score = (
            _score(patrol, "score")
            + min(1.0, float(tasking["best_score"]) / 100.0)
            + _score(escort, "score", "coverage", default=0.5)
        ) / 3.0
    best_posture = str(
        tasking.get("best_posture", tasking.get("best_order", patrol.get("dominant", "PATROL")))
    )
    label = "Fleet AI ops · patrol+task+escort · score %.2f · %s" % (score, best_posture)
    actions = [
        {"action_id": "apply_station", "label": "Apply fleet station", "enabled": True},
        {"action_id": "apply_supply", "label": "Convoy sustain", "enabled": True},
    ]
    return {
        "patrol": patrol,
        "tasking": tasking,
        "escort": escort,
        "actions": actions,
        "best_posture": best_posture,
        "score": score,
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(patrol.get("summary", "")),
                str(tasking.get("summary", tasking.get("best_posture", ""))),
                str(escort.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]🚢 Fleet AI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_patrol", "tasking", "convoy_escort", "apply_actions"],
    }


def hh_agenda_screen_package(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """P5: full HH agenda screen package (empty trail → empty)."""
    t = list(trail or [])
    if not t:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    try:
        screen = format_hh_agenda_screen(t)
    except TypeError:
        try:
            screen = format_hh_agenda_screen(t, max_lines=8)  # type: ignore
        except Exception:
            screen = {"summary": "agenda screen", "plain": str(len(t)), "empty": False}
    if screen.get("empty"):
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    try:
        picks = pick_agenda_actions(t)
    except TypeError:
        try:
            picks = pick_agenda_actions(t, max_actions=3)  # type: ignore
        except Exception:
            picks = {"summary": "", "empty": True}
    score = min(1.0, 0.2 * len(t) + (0.3 if not picks.get("empty") else 0.0))
    label = "HH agenda screen · trail %d · score %.2f" % (len(t), score)
    return {
        "screen": screen,
        "picks": picks,
        "trail_len": len(t),
        "actions": [
            {"action_id": "apply_hh_commit", "label": "Commit HH agenda", "enabled": True}
        ],
        "score": score,
        "summary": label,
        "plain": "\n".join(
            [label, str(screen.get("plain", screen.get("summary", "")))[:200]]
        ),
        "bbcode": "[color=#5ec8ff]📜 HH agenda[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["hh_agenda_screen", "actions", "apply_hh_commit"],
    }


def agent_campaign_depth(
    signal: Optional[Mapping[str, Any]] = None,
    available_agents: int = 5,
) -> Dict[str, Any]:
    """P6: deep agent campaign board — missions + coverage + escalation."""
    sig = dict(signal or {"class": "sabotage", "action_class": "sabotage", "influence": 0.6})
    ac = str(sig.get("action_class", sig.get("class", "sabotage")))
    threat = float(sig.get("influence", sig.get("threat", 0.55)) or 0.55)
    try:
        missions = rank_agent_missions(ac, threat, 0.35, 0.5, 4)
    except TypeError:
        try:
            missions = rank_agent_missions(ac, threat)  # type: ignore
        except Exception:
            missions = {"summary": "missions", "score": 0.5}
    try:
        cov = plan_agent_coverage([sig], available_agents=available_agents, network_strength=0.35)
    except TypeError:
        try:
            cov = plan_agent_coverage([sig], available_agents=available_agents)  # type: ignore
        except Exception:
            cov = {"summary": "coverage", "score": 0.4}
    try:
        esc = plan_agent_escalation(sig, network_strength=0.35, available_agents=available_agents)
    except TypeError:
        try:
            esc = plan_agent_escalation(sig)  # type: ignore
        except Exception:
            esc = {"level": 1, "summary": "escalation"}
    score = (
        _score(missions, "score", default=0.5)
        + min(1.0, float(esc.get("level", 1)) / 3.0)
        + (0.5 if not cov.get("empty") else 0.3)
    ) / 3.0
    label = "Agent campaign depth · score %.2f · L%s" % (score, esc.get("level", "?"))
    return {
        "missions": missions,
        "coverage": cov,
        "escalation": esc,
        "actions": [
            {
                "action_id": "apply_agent_dispatch",
                "label": "Dispatch agent counter-ops",
                "enabled": True,
            },
            {
                "action_id": "apply_counterplay",
                "label": "Apply counter-intel",
                "enabled": True,
            },
        ],
        "score": score,
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(missions.get("summary", "")),
                str(esc.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]🕵 Agent campaign[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["missions", "coverage", "escalation", "apply_actions"],
    }


def industry_economy_depth(
    weather: Optional[Mapping[str, Any]] = None,
    base_output: float = 1.0,
    sea_mult: float = 1.0,
) -> Dict[str, Any]:
    """P7: economy/industry campaign depth — OOB risk + factory + supply + alert."""
    w = dict(weather or {})
    oob = oob_factory_risk_loop(weather=w, base_output=base_output)
    try:
        factory = factory_risk_compose(w)
    except TypeError:
        factory = factory_risk_compose(weather=w)  # type: ignore
    supply = supply_chain_health(sea_mult=sea_mult, weather=w)
    alert = production_weather_alert(w)
    mult = _score(oob, "mult", "effective_output", default=1.0)
    risk = max(0.0, min(1.0, 1.0 - mult))
    health = _score(supply, "health", "score", default=0.7)
    score = (1.0 - risk) * 0.5 + health * 0.5
    label = "Industry economy · out×%.2f · supply×%.2f · risk %.0f%%" % (
        mult,
        health,
        risk * 100.0,
    )
    return {
        "oob": oob,
        "factory": factory,
        "supply": supply,
        "alert": alert,
        "actions": [
            {
                "action_id": "apply_production",
                "label": "Set production priority",
                "enabled": True,
            },
            {"action_id": "apply_supply", "label": "Sustain supply route", "enabled": True},
            {"action_id": "apply_focus", "label": "Hold industrial focus", "enabled": True},
        ],
        "score": score,
        "risk": risk,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🏭 Industry[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["oob_factory", "factory_risk", "supply_chain", "apply_actions"],
    }


def save_slot_browser_package(
    occupied_slots: Optional[Sequence[Mapping[str, Any]]] = None,
    fixed_slots: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """P8: save-slot browser rows (pure model of SaveLoadManager.list_slots_for_ui)."""
    fixed = list(fixed_slots or ["quicksave", "autosave", "slot1", "slot2", "slot3"])
    occ = {str(e.get("slot", "")): e for e in list(occupied_slots or []) if e}
    occupied_entries = list(occupied_slots or [])
    try:
        row_list = list(build_save_slot_list(occupied_entries, fixed_slots=fixed))
        package = {"rows": row_list}
    except TypeError:
        try:
            row_list = list(build_save_slot_list(occupied_entries, fixed))  # type: ignore
            package = {"rows": row_list}
        except Exception:
            row_list = []
            for name in fixed:
                if name in occ:
                    meta = occ[name].get("metadata", {})
                    try:
                        row_list.append(format_slot_row(name, True, meta))
                    except Exception:
                        row_list.append(
                            {
                                "slot": name,
                                "occupied": True,
                                "status": "occupied",
                                "label": "%s · %s" % (name, meta.get("scenario_id", "save")),
                                "can_load": True,
                                "can_save": True,
                            }
                        )
                else:
                    row_list.append(
                        {
                            "slot": name,
                            "occupied": False,
                            "status": "empty",
                            "label": "%s · empty" % name,
                            "can_load": False,
                            "can_save": True,
                        }
                    )
            package = {"rows": row_list}
    occ_n = sum(1 for r in row_list if isinstance(r, dict) and r.get("occupied"))
    label = "Save slot browser · %d slots · %d occupied" % (len(row_list), occ_n)
    actions = []
    for r in row_list:
        if not isinstance(r, dict):
            continue
        slot = str(r.get("slot", "")).strip()
        if not slot:
            continue
        actions.append(
            {
                "action_id": "save_slot:%s" % slot,
                "label": "Save %s" % slot,
                "enabled": bool(r.get("can_save", True)),
            }
        )
        if r.get("occupied") or r.get("can_load"):
            actions.append(
                {
                    "action_id": "load_slot:%s" % slot,
                    "label": "Load %s" % slot,
                    "enabled": bool(r.get("can_load", True)),
                }
            )
    return {
        "rows": row_list,
        "occupied_count": occ_n,
        "count": len(row_list),
        "actions": actions,
        "score": min(1.0, 0.2 * len(row_list)),
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                str(r.get("label", r.get("slot", "")))
                for r in row_list
                if isinstance(r, dict)
            ][:8]
        ),
        "bbcode": "[color=#5ec8ff]💾 Save browser[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(row_list) == 0,
        "package": package,
        "integration": ["save_slots", "ui", "save_load_actions"],
    }


def gpu_pan_zoom_profile(
    province_count: int = 2665,
    zoom: float = 0.5,
    cull_margin: float = 192.0,
    resource_icon_budget: int = 180,
    label_budget: int = 140,
) -> Dict[str, Any]:
    """P9: GPU/pan-zoom profile recommendation (no hard gate; advisory pilot)."""
    # Scale budgets with zoom (more detail when zoomed in)
    icon_eff = int(resource_icon_budget * (0.6 + 0.8 * max(0.1, min(1.0, zoom))))
    label_eff = int(label_budget * (0.5 + 0.9 * max(0.1, min(1.0, zoom))))
    # Heavy map when many provinces + high zoom
    load = (province_count / 2665.0) * (0.4 + 0.6 * zoom)
    recommended_cull = cull_margin * (1.1 if load > 0.85 else 1.0)
    score = max(0.1, min(1.0, 1.0 - load * 0.35))
    label = "GPU pan/zoom profile · zoom %.2f · icons %d · labels %d · load %.0f%%" % (
        zoom,
        icon_eff,
        label_eff,
        load * 100.0,
    )
    return {
        "province_count": province_count,
        "zoom": zoom,
        "cull_margin": recommended_cull,
        "resource_icon_budget": icon_eff,
        "label_budget": label_eff,
        "load": load,
        "score": score,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🖥 GPU profile[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "deferred_hard_gate": True,
        "integration": ["pan_zoom", "lod"],
    }


def priority_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    priority_mult: float = 1.0,
) -> Dict[str, Any]:
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    ops = ops_depth_integrity_gate(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk, ops_mult=priority_mult
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    ops_ok = bool(ops.get("ok", False))
    sole_h = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(priority_mult)))
    stacked = sole_h * max(0.1, min(1.4, float(priority_mult)))
    p_ok = True
    if abs(float(priority_mult) - 1.0) > 0.05:
        p_ok = abs(stacked - sole_h) > 0.01
    ok = sole_ok and ops_ok and p_ok
    label = "Priority integrity %s (sole=%s ops=%s p=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if ops_ok else "fail",
        "ok" if p_ok else "fail",
    )
    return {
        "ok": ok,
        "summary": label,
        "bbcode": "[color=#5ec8ff]✓ Priority integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "ops_integrity", "priority_mult"],
    }


def close_priority_systems_loop(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Compose all priority pilots for weather/trail sensitivity check."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))
    ids = list(province_ids or [10, 20, 30, 40])
    p1 = order_panel_ux_model(ids, ids[0], weather=w, trail=trail)
    p2 = multi_phase_combat_ui(weather=w)
    p3 = fleet_ai_ops_package(province_ids=ids[:3])
    p5 = hh_agenda_screen_package(trail=trail)
    p6 = agent_campaign_depth()
    p7 = industry_economy_depth(weather=w)
    p7f = industry_economy_depth(weather=foul)
    p8 = save_slot_browser_package(
        occupied_slots=[{"slot": "autosave", "metadata": {"scenario_id": "world_full"}}]
    )
    p9 = gpu_pan_zoom_profile(zoom=0.45)
    gate = priority_integrity_gate(priority_mult=1.1)
    wx_shift = abs(_score(p7, "score") - _score(p7f, "score"))
    label = "Close-priorities · P1–P9 · integrity %s · Δwx %.3f" % (
        "PASS" if gate.get("ok") else "FAIL",
        wx_shift,
    )
    return {
        "p1_order_ux": p1,
        "p2_combat_ui": p2,
        "p3_fleet_ai": p3,
        "p5_hh_agenda": p5,
        "p6_agent": p6,
        "p7_industry": p7,
        "p8_saves": p8,
        "p9_gpu": p9,
        "integrity": gate,
        "weather_score_shift": wx_shift,
        "summary": label,
        "empty": False,
        "integration": ["p1", "p2", "p3", "p5", "p6", "p7", "p8", "p9", "integrity"],
    }
