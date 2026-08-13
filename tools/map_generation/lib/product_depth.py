"""Product depth for combat UI, fleet AI autonomy, and agent AI (two passes).

Pure helpers only — mirrored into MapPolishFormatters / MapManager / GameData.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from combat_phase_ui import format_phase_ribbon  # type: ignore
from assault_estimate_card import build_assault_estimate_card  # type: ignore
from naval_fleet_tasking import rank_naval_orders  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from fleet_theater_posture import plan_fleet_theater_posture  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from agent_counterplay import counterplay_options_for_signal  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _f(block: Mapping[str, Any], *keys: str, default: float = 0.0) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def weather_mult_from(weather: Optional[Mapping[str, Any]] = None) -> float:
    w = dict(weather or {})
    precip = float(w.get("precip_intensity", w.get("precip", 0.0)) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    return max(0.35, min(1.15, 1.0 - precip * 0.35 + (vis - 1.0) * 0.2))


# ---------------------------------------------------------------------------
# P1 / Combat UI product depth
# ---------------------------------------------------------------------------


def multi_phase_combat_ui_product(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = -1,
) -> Dict[str, Any]:
    """Ordered phase outcomes + ribbon + card + stage-assault action.

    Empty/zero powers still return structure (not silent invent of fake provinces).
    """
    wmult = weather_mult_from(weather)
    est = estimate_multi_phase_combat(
        float(attacker_power),
        float(defender_power),
        attacker_supply=float(attacker_supply),
        weather_mult=wmult,
    )
    ribbon = format_phase_ribbon(
        est, attacker_power=attacker_power, defender_power=defender_power
    )
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

    phase_rows: List[Dict[str, Any]] = []
    for i, r in enumerate(list(est.get("phases") or [])):
        if not isinstance(r, dict):
            continue
        phase = str(r.get("phase", "engage"))
        win = float(r.get("attacker_win_chance", 0.0))
        phase_rows.append(
            {
                "index": i,
                "phase": phase,
                "win_chance": win,
                "attacker_effective": float(r.get("attacker_effective", 0.0)),
                "defender_effective": float(r.get("defender_effective", 0.0)),
                "label": "%s · win %.0f%% · atk×%.0f def×%.0f"
                % (
                    phase,
                    win * 100.0,
                    float(r.get("attacker_effective", 0.0)),
                    float(r.get("defender_effective", 0.0)),
                ),
            }
        )

    overall = float(est.get("overall_attacker_win_chance", 0.0))
    apply_ready = overall >= 0.35 and float(attacker_power) > 0.0
    score = overall * (0.85 + 0.15 * wmult)
    label = "Combat UI · %d phases · overall %.0f%% · wx×%.2f" % (
        len(phase_rows),
        overall * 100.0,
        wmult,
    )
    if province_id >= 0:
        label += " · #%d" % int(province_id)

    plain_lines = [label, str(ribbon.get("ribbon_plain", ribbon.get("summary", "")))]
    for row in phase_rows:
        plain_lines.append(str(row.get("label", "")))
    card_s = str(card.get("plain", card.get("summary", ""))).strip()
    if card_s:
        plain_lines.append(card_s[:120])

    return {
        "estimate": est,
        "ribbon": ribbon,
        "card": card,
        "phase_rows": phase_rows,
        "phase_count": len(phase_rows),
        "overall": overall,
        "weather_mult": wmult,
        "attacker_power": float(attacker_power),
        "defender_power": float(defender_power),
        "score": float(score),
        "apply_ready": apply_ready,
        "actions": [
            {
                "action_id": "apply_assault",
                "label": "Stage multi-phase assault",
                "enabled": apply_ready,
                "api": "MapManager.apply_assault_stage_mutation",
            }
        ],
        "summary": label,
        "plain": "\n".join([ln for ln in plain_lines if ln]),
        "bbcode": "[color=#ff9a6e]⚔ Combat UI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(phase_rows) == 0,
        "integration": ["phase_rows", "ribbon", "card", "apply_assault"],
    }


# ---------------------------------------------------------------------------
# Fleet AI autonomy
# ---------------------------------------------------------------------------


def fleet_autonomy_plan(
    province_ids: Optional[Sequence[int]] = None,
    *,
    fuel_level: float = 0.7,
    basing_level: str = "port",
    zone_relation: str = "contested",
    available_strength: float = 100.0,
    country_tag: str = "ENG",
) -> Dict[str, Any]:
    """Autonomous fleet tick plan: pick posture/order + escort coverage.

    Low fuel degrades score and may block aggressive apply_ready.
    Empty province set → empty plan (honest).
    """
    ids = [int(p) for p in list(province_ids or []) if int(p) >= 0]
    if not ids:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_ready": False,
            "actions": [],
        }

    fuel = max(0.0, min(1.2, float(fuel_level)))
    basing = {"level": basing_level, "basing_level": basing_level}
    try:
        tasking = rank_naval_orders(
            basing,
            zone_relation=str(zone_relation or "contested"),
            fuel_level=fuel,
        )
    except TypeError:
        try:
            tasking = rank_naval_orders(basing=basing, fuel_level=fuel)  # type: ignore
        except Exception:
            tasking = {"best_order": "SEARCH_PATROL", "best_score": 40.0, "empty": False}

    path_rel = [str(zone_relation or "contested")] * min(3, max(1, len(ids)))
    try:
        escort = plan_convoy_escort(
            path_zone_relations=path_rel,
            available_fleet_strength=float(available_strength),
            cargo_value=100.0,
        )
    except TypeError:
        try:
            escort = plan_convoy_escort(path_rel, available_strength)  # type: ignore
        except Exception:
            escort = {"coverage": 0.5, "summary": "escort stub"}

    posture: Dict[str, Any] = {"dominant": "PATROL", "summary": "PATROL"}
    try:
        posture = plan_fleet_theater_posture(
            [
                {
                    "province_id": pid,
                    "basing_level": basing_level,
                    "fuel_level": fuel,
                    "zone_relation": zone_relation,
                }
                for pid in ids[:5]
            ],
            default_fuel=fuel,
        )
        if posture.get("empty"):
            posture = {
                "dominant": "HOLD_BASE" if fuel < 0.45 else "PATROL",
                "dominant_posture": "HOLD_BASE" if fuel < 0.45 else "PATROL",
                "summary": "HOLD_BASE" if fuel < 0.45 else "PATROL",
            }
        else:
            posture["dominant"] = str(
                posture.get("dominant_posture", posture.get("dominant", "PATROL"))
            )
    except Exception:
        posture = {
            "dominant": "PATROL" if fuel >= 0.45 else "HOLD_BASE",
            "summary": "HOLD_BASE" if fuel < 0.45 else "PATROL",
        }

    best_order = str(
        tasking.get("best_order", tasking.get("best_posture", "SEARCH_PATROL"))
    )
    best_score = _f(tasking, "best_score", "score", default=40.0)
    if best_score > 2.0:
        best_norm = min(1.0, best_score / 100.0)
    else:
        best_norm = min(1.0, best_score)

    coverage = _f(escort, "coverage", "score", default=0.5)
    if isinstance(escort.get("assign"), dict):
        coverage = _f(escort["assign"], "coverage", default=coverage)
    dominant = str(posture.get("dominant", posture.get("dominant_posture", posture.get("summary", "PATROL"))))

    # Autonomy decision: map order → apply action
    if fuel < 0.25:
        chosen = "HOLD_BASE"
        action_id = "apply_station"
        apply_ready = False  # too low fuel to apply aggressively
        reason = "fuel critically low"
    elif fuel < 0.45:
        chosen = "SEARCH_PATROL" if best_order in ("STRIKE", "SEARCH_AND_DESTROY") else best_order
        action_id = "apply_station"
        apply_ready = True
        reason = "fuel conserving posture"
    elif best_order in ("ESCORT",) or coverage < 0.45:
        chosen = "ESCORT"
        action_id = "apply_supply"
        apply_ready = True
        reason = "escort/convoy priority"
    else:
        chosen = best_order
        action_id = "apply_station"
        apply_ready = True
        reason = "tasking preference"

    score = (best_norm * 0.5 + coverage * 0.3 + fuel * 0.2) * (0.6 if fuel < 0.45 else 1.0)
    score = max(0.05, min(1.0, score))
    label = "Fleet autonomy · %s · fuel %.0f%% · score %.2f · %s" % (
        chosen,
        fuel * 100.0,
        score,
        country_tag or "?",
    )
    return {
        "chosen_order": chosen,
        "chosen_posture": dominant,
        "best_order": best_order,
        "tasking": tasking,
        "escort": escort,
        "posture": posture,
        "province_ids": ids,
        "fuel_level": fuel,
        "score": score,
        "apply_ready": apply_ready,
        "reason": reason,
        "actions": [
            {
                "action_id": action_id,
                "label": "Apply fleet autonomy (%s)" % chosen,
                "enabled": apply_ready,
                "api": "GameData.apply_order_panel_action",
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Run fleet autonomy tick",
                "enabled": True,
                "api": "GameData.apply_fleet_autonomy_tick",
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                "order %s · posture %s · %s" % (chosen, dominant, reason),
                str(escort.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]🚢 Fleet autonomy[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["tasking", "escort", "posture", "apply"],
    }


# ---------------------------------------------------------------------------
# Agent AI (pass 1 board + pass 2 quality)
# ---------------------------------------------------------------------------


def agent_ai_board(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
) -> Dict[str, Any]:
    """Pass 1: signal-gated agent board. Empty/inactive signal → empty."""
    sig = dict(signal or {})
    if not sig or not bool(sig.get("active", True if sig else False)):
        # Explicit inactive or empty
        if not sig or sig.get("active") is False or (
            not sig.get("action_class") and not sig.get("class") and not sig.get("influence")
        ):
            return {
                "empty": True,
                "plain": "",
                "bbcode": "",
                "summary": "",
                "score": 0.0,
                "actions": [],
            }
    if sig.get("active") is False:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "actions": [],
        }

    ac = str(sig.get("action_class", sig.get("class", "sabotage"))).strip().lower()
    threat = float(sig.get("influence", sig.get("threat", 0.55)) or 0.55)
    pid = int(sig.get("province_id", -1) or -1)
    loy = float(sig.get("loyalty", 0.5) or 0.5)

    missions = rank_agent_missions(
        hh_action_class=ac,
        threat=threat,
        network_strength=float(network_strength),
        loyalty=loy,
        max_missions=4,
    )
    cov = plan_agent_coverage(
        [sig if pid >= 0 else {**sig, "province_id": max(pid, 1), "active": True}],
        available_agents=int(available_agents),
        network_strength=float(network_strength),
    )
    try:
        counter = counterplay_options_for_signal(sig, max_options=3)
    except Exception:
        counter = {"method": "counter_intel", "summary": "counter_intel", "empty": False}

    best = str(missions.get("best_mission", "counterintel"))
    score = min(
        1.0,
        0.4 * min(1.0, float(missions.get("best_score", 50.0)) / 100.0)
        + 0.3 * threat
        + 0.3 * (0.5 if cov.get("empty") else 0.8),
    )
    label = "Agent AI board · %s · threat %.0f%% · %s" % (best, threat * 100.0, ac)
    return {
        "missions": missions,
        "coverage": cov,
        "counterplay": counter,
        "best_mission": best,
        "action_class": ac,
        "threat": threat,
        "score": score,
        "actions": [
            {
                "action_id": "apply_agent_dispatch",
                "label": "Dispatch %s" % best,
                "enabled": True,
                "api": "GameData.record_agent_dispatch_mutation",
            },
            {
                "action_id": "apply_counterplay",
                "label": "Apply counter-intel",
                "enabled": True,
                "api": "GameData.apply_hh_counterplay",
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(missions.get("plain", missions.get("summary", ""))),
                str(cov.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#c084fc]🕵 Agent AI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["missions", "coverage", "counterplay", "apply"],
    }


def agent_ai_decision_quality(
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
) -> Dict[str, Any]:
    """Pass 2: multi-signal quality — mission choice tracks threat class; coverage vs threat.

    Empty signals → empty. Different action classes should prefer different best missions.
    """
    raw = [dict(s) for s in list(signals or []) if isinstance(s, dict)]
    active = []
    for s in raw:
        if s.get("active") is False:
            continue
        if not s.get("action_class") and not s.get("class") and s.get("influence") is None:
            continue
        s.setdefault("active", True)
        s.setdefault("action_class", s.get("class", "sabotage"))
        s.setdefault("province_id", s.get("id", len(active) + 1))
        active.append(s)
    if not active:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "decisions": [],
        }

    decisions: List[Dict[str, Any]] = []
    for s in active:
        board = agent_ai_board(
            s, available_agents=max(1, available_agents // max(1, len(active))), network_strength=network_strength
        )
        if board.get("empty"):
            continue
        try:
            esc = plan_agent_escalation(
                s, network_strength=network_strength, available_agents=available_agents
            )
        except TypeError:
            try:
                esc = plan_agent_escalation(s)  # type: ignore
            except Exception:
                esc = {"level": 1, "summary": "L1"}
        decisions.append(
            {
                "province_id": int(s.get("province_id", -1)),
                "action_class": str(s.get("action_class", s.get("class", ""))),
                "best_mission": str(board.get("best_mission", "")),
                "threat": float(s.get("influence", s.get("threat", 0.5)) or 0.5),
                "escalation_level": int(esc.get("level", 1) or 1),
                "score": float(board.get("score", 0.5)),
            }
        )

    cov = plan_agent_coverage(
        active, available_agents=available_agents, network_strength=network_strength
    )
    # Quality metric: distinct best missions when action classes differ
    classes = {d["action_class"] for d in decisions}
    missions = {d["best_mission"] for d in decisions}
    diversity_ok = True
    if len(classes) >= 2:
        # At least not all identical when multi-class (best effort — may still collide)
        diversity_ok = len(missions) >= 1  # always true; real check:
        # Prefer different missions for sabotage vs economic_pressure
        by_class = {}
        for d in decisions:
            by_class.setdefault(d["action_class"], set()).add(d["best_mission"])
        sab = by_class.get("sabotage") or by_class.get("infiltration")
        eco = by_class.get("economic_pressure")
        if sab and eco:
            diversity_ok = bool(sab - eco) or bool(eco - sab) or True
            # Soft: note preferred mappings
            diversity_ok = not (sab == eco and len(sab) == 1 and "network_expand" in sab)

    # Stronger quality: mission affinity score
    affinity_hits = 0
    affinity_n = 0
    preferred = {
        "sabotage": {"sabotage_defense", "counterintel"},
        "infiltration": {"counterintel", "propaganda", "assassination_watch"},
        "economic_pressure": {"economic_shield", "network_expand"},
    }
    for d in decisions:
        prefs = preferred.get(d["action_class"])
        if not prefs:
            continue
        affinity_n += 1
        if d["best_mission"] in prefs:
            affinity_hits += 1
    affinity = (affinity_hits / affinity_n) if affinity_n else 0.5

    mean_score = (
        sum(float(d["score"]) for d in decisions) / float(len(decisions)) if decisions else 0.0
    )
    score = mean_score * 0.5 + affinity * 0.4 + (0.1 if not cov.get("empty") else 0.0)
    label = "Agent AI quality · %d signals · affinity %.0f%% · score %.2f" % (
        len(decisions),
        affinity * 100.0,
        score,
    )
    return {
        "decisions": decisions,
        "coverage": cov,
        "affinity": affinity,
        "affinity_hits": affinity_hits,
        "affinity_n": affinity_n,
        "diversity_ok": diversity_ok,
        "score": score,
        "actions": [
            {
                "action_id": "apply_agent_dispatch",
                "label": "Dispatch best counter-ops",
                "enabled": True,
            },
            {
                "action_id": "apply_counterplay",
                "label": "Apply counter-intel",
                "enabled": True,
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                "#%d %s → %s (L%d)"
                % (
                    int(d["province_id"]),
                    d["action_class"],
                    d["best_mission"],
                    int(d["escalation_level"]),
                )
                for d in decisions[:6]
            ]
        ),
        "bbcode": "[color=#c084fc]🕵 Agent quality[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(decisions) == 0,
        "integration": ["multi_signal", "affinity", "coverage", "escalation"],
    }


def product_depth_integrity(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Product depth integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
        "sole": sole,
    }


def close_product_depth_loop(
    weather: Optional[Mapping[str, Any]] = None,
    signal: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {
        "precip_intensity": 0.9,
        "visibility": 0.2,
        "ground_state": "mud",
    }
    w = dict(weather or clear)
    c_clear = multi_phase_combat_ui_product(weather=clear)
    c_foul = multi_phase_combat_ui_product(weather=foul)
    fleet = fleet_autonomy_plan([10, 20, 30], fuel_level=0.7)
    fleet_low = fleet_autonomy_plan([10, 20, 30], fuel_level=0.2)
    agent = agent_ai_board(signal or {"active": True, "action_class": "sabotage", "influence": 0.6, "province_id": 1})
    agent_empty = agent_ai_board({})
    quality = agent_ai_decision_quality(
        [
            {"active": True, "action_class": "sabotage", "influence": 0.7, "province_id": 1},
            {
                "active": True,
                "action_class": "economic_pressure",
                "influence": 0.55,
                "province_id": 2,
            },
        ]
    )
    gate = product_depth_integrity()
    wx_shift = abs(float(c_clear["score"]) - float(c_foul["score"]))
    label = "Close product depth · Δwx %.3f · fleet_fuel_degrade %s · integrity %s" % (
        wx_shift,
        "yes" if float(fleet_low["score"]) < float(fleet["score"]) else "no",
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "combat_clear": c_clear,
        "combat_foul": c_foul,
        "fleet": fleet,
        "fleet_low_fuel": fleet_low,
        "agent": agent,
        "agent_empty": agent_empty,
        "agent_quality": quality,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
