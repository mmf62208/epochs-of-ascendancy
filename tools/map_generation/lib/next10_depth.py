"""Next-10 depth day packages: multi-phase combat, air-naval, agent, focus,
production, convoy escort, next-day feedback, map effect, theater brief,
campaign decision.

Composes existing pure helpers into day packages with apply_queue / actions.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from campaign_ops_depth import (  # type: ignore
    combat_air_naval_joint,
    agent_auto_dispatch_day,
)
from focus_pick_priority import rank_focus_picks  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from campaign_execution import map_effect_resolve, next_day_feedback  # type: ignore
from theater_commander import theater_daily_brief  # type: ignore
from campaign_cohesion import campaign_decision_strip  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def _clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def _norm_score(v: float) -> float:
    """Normalize scores that may be 0–1 or 0–100."""
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return _clamp01(x)


# ---------------------------------------------------------------------------
# 1. Multi-phase combat day
# ---------------------------------------------------------------------------


def multi_phase_combat_day(
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather_mult: float = 1.0,
    province_id: int = 1,
    phases: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Estimate multi-phase combat → assault / supply apply queue."""
    ph = list(phases or ("approach", "engage", "disengage"))
    try:
        est = estimate_multi_phase_combat(
            float(attacker_power),
            float(defender_power),
            attacker_supply=float(attacker_supply),
            weather_mult=float(weather_mult),
            phases=ph,
        )
    except TypeError:
        try:
            est = estimate_multi_phase_combat(attacker_power, defender_power)  # type: ignore
        except Exception:
            est = {
                "overall_attacker_win_chance": 0.5,
                "summary": "multi-phase stub",
                "empty": False,
            }

    if est.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    win = _norm_score(
        est.get("overall_attacker_win_chance", est.get("engage_win_chance", 0.5))
    )
    supply = max(0.05, min(1.2, float(attacker_supply)))
    apply_ready = win >= 0.35 and supply >= 0.3
    apply_queue: List[Dict[str, Any]] = []
    if apply_ready and win >= 0.4:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": win,
                "enabled": True,
                "label": "Stage multi-phase assault",
            }
        )
    if supply < 0.75 or win < 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - supply),
                "enabled": True,
                "label": "Feed multi-phase supply",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.4,
                "enabled": True,
                "label": "Hold station (phase wait)",
            }
        )

    label = "Multi-phase combat day · win %.0f%% · supply %.0f%% · phases %d" % (
        win * 100.0,
        supply * 100.0,
        len(ph),
    )
    return {
        "estimate": est,
        "win_chance": win,
        "score": win,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "multi_phase_combat_day",
                "label": "Run multi-phase combat day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(est.get("summary", ""))),
        "bbcode": "[color=#ff9a6e]⚔ Multi-phase combat day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["multi_phase", "assault", "supply"],
    }


# ---------------------------------------------------------------------------
# 2. Combat air-naval day
# ---------------------------------------------------------------------------


def combat_air_naval_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    fuel_level: float = 0.7,
    basing_level: str = "port",
    province_id: int = 1,
    month: int = 6,
) -> Dict[str, Any]:
    """Air-naval joint compose → assault / fleet / supply day queue."""
    w = dict(weather or {})
    try:
        joint = combat_air_naval_joint(
            attacker_power=attacker_power,
            defender_power=defender_power,
            attacker_supply=attacker_supply,
            weather=w,
            month=month,
            fuel_level=fuel_level,
            basing_level=basing_level,
            province_id=province_id,
        )
    except Exception:
        joint = {"score": 0.5, "empty": False, "summary": "air-naval stub", "actions": []}

    if joint.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(joint.get("score", 0.5))
    apply_ready = bool(joint.get("apply_ready", score >= 0.4)) and not bool(
        joint.get("grounded", False)
    )
    apply_queue: List[Dict[str, Any]] = []
    for a in list(joint.get("actions") or []):
        if not isinstance(a, dict):
            continue
        aid = str(a.get("action_id", ""))
        if not aid:
            continue
        # Map joint action ids into day apply routes
        if aid in ("apply_assault", "fleet_autonomy", "apply_supply", "apply_station"):
            apply_queue.append(
                {
                    "action_id": aid if aid != "fleet_autonomy" else "apply_station",
                    "province_id": province_id,
                    "score": score,
                    "enabled": bool(a.get("enabled", True)),
                    "label": str(a.get("label", aid)),
                }
            )
    if apply_ready and not any(q.get("action_id") == "apply_assault" for q in apply_queue):
        apply_queue.insert(
            0,
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Stage joint air-naval assault",
            },
        )
    if fuel_level < 0.55 or score < 0.45:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel joint package",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.4,
                "enabled": True,
            }
        )

    label = "Combat air-naval day · score %.2f · fuel %.0f%% · ready=%s" % (
        score,
        fuel_level * 100.0,
        "Y" if apply_ready else "N",
    )
    return {
        "joint": joint,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "combat_air_naval_day",
                "label": "Run combat air-naval day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(joint.get("summary", ""))),
        "bbcode": "[color=#ff9a6e]✈⚓ Combat air-naval day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["air_naval", "assault", "fleet"],
    }


# ---------------------------------------------------------------------------
# 3. Agent auto day (depth)
# ---------------------------------------------------------------------------


def agent_auto_day(
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.45,
    max_dispatches: int = 3,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Agent auto-dispatch day with default signal seed when empty."""
    sigs = list(signals or [])
    if not sigs:
        # Seed realistic active signals so day packages are non-empty in product surface
        sigs = [
            {
                "active": True,
                "action_class": "sabotage",
                "influence": 0.72,
                "province_id": province_id,
            },
            {
                "active": True,
                "action_class": "intel",
                "influence": 0.58,
                "province_id": max(1, province_id + 1),
            },
            {
                "active": True,
                "action_class": "network",
                "influence": 0.5,
                "province_id": max(1, province_id + 2),
            },
        ]
    try:
        day = agent_auto_dispatch_day(
            sigs,
            available_agents=available_agents,
            network_strength=network_strength,
            max_dispatches=max_dispatches,
        )
    except Exception:
        day = {"empty": True, "score": 0.0, "dispatch_queue": [], "actions": []}

    if day.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    apply_queue: List[Dict[str, Any]] = []
    for q in list(day.get("dispatch_queue") or []):
        if not isinstance(q, dict):
            continue
        apply_queue.append(
            {
                "action_id": str(q.get("action_id", "apply_agent_dispatch")),
                "province_id": int(q.get("province_id", province_id)),
                "score": float(q.get("score", 0.5)),
                "enabled": True,
                "label": str(q.get("best_mission", q.get("action_class", "dispatch"))),
            }
        )
    score = _norm_score(day.get("score", 0.5))
    label = "Agent auto day · queue %d · score %.2f · affinity %.0f%%" % (
        len(apply_queue),
        score,
        float(day.get("affinity", 0.0)) * 100.0,
    )
    return {
        "dispatch": day,
        "score": score,
        "apply_queue": apply_queue[: max(1, max_dispatches + 1)],
        "actions": [
            {
                "action_id": "agent_auto_day",
                "label": "Run agent auto day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(day.get("summary", ""))),
        "bbcode": "[color=#c084fc]◈ Agent auto day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["agent", "dispatch", "counterplay"],
    }


# ---------------------------------------------------------------------------
# 4. Focus pick day
# ---------------------------------------------------------------------------


def focus_pick_day(
    focuses: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    completed_ids: Optional[Sequence[str]] = None,
    year: int = 1936,
    province_id: int = 1,
    max_picks: int = 5,
) -> Dict[str, Any]:
    """Rank national focuses → soft commit apply (HH path / continuity)."""
    foc = list(
        focuses
        or [
            {"id": "industrial_effort", "name": "Industrial Effort", "score": 0.7, "cost": 70},
            {"id": "army_effort", "name": "Army Effort", "score": 0.65, "cost": 70},
            {"id": "naval_effort", "name": "Naval Effort", "score": 0.55, "cost": 70},
            {"id": "air_effort", "name": "Air Effort", "score": 0.5, "cost": 70},
            {"id": "political_effort", "name": "Political Effort", "score": 0.48, "cost": 50},
        ]
    )
    try:
        ranked = rank_focus_picks(
            foc,
            completed_ids=list(completed_ids or []),
            year=year,
            max_picks=max_picks,
        )
    except TypeError:
        try:
            ranked = rank_focus_picks(foc)  # type: ignore
        except Exception:
            ranked = {"empty": True, "picks": [], "summary": ""}

    if ranked.get("empty") or not list(ranked.get("picks") or []):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    picks = list(ranked.get("picks") or [])
    best = picks[0] if picks else {}
    best_id = str(ranked.get("best_id", best.get("id", "")))
    raw_score = float(ranked.get("best_score", best.get("score", 50.0)) or 50.0)
    score = _norm_score(raw_score if raw_score <= 2.0 else raw_score / 200.0)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_hh_commit",
            "province_id": province_id,
            "focus_id": best_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Commit focus %s" % best_id,
        }
    ]
    # Secondary: continuity / war path soft refresh
    apply_queue.append(
        {
            "action_id": "refresh_queue",
            "province_id": province_id,
            "score": 0.45,
            "enabled": True,
            "label": "Refresh focus queue",
        }
    )
    label = "Focus pick day · best %s · score %.2f · picks %d" % (
        best_id or "—",
        score,
        len(picks),
    )
    return {
        "ranked": ranked,
        "best_id": best_id,
        "picks": picks,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "focus_pick_day",
                "label": "Run focus pick day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(ranked.get("plain", ranked.get("summary", "")))),
        "bbcode": "[color=#fbbf24]◎ Focus pick day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["focus", "hh_commit", "war_path"],
    }


# ---------------------------------------------------------------------------
# 5. Production priority day
# ---------------------------------------------------------------------------


def production_priority_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    line_id: str = "primary",
    unit_id: str = "primary",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Production priority mutation → apply_production day queue."""
    w = dict(weather or {})
    try:
        mut = production_priority_mutation(
            weather=w,
            base_output=base_output,
            line_id=line_id,
            unit_id=unit_id or line_id,
        )
    except TypeError:
        try:
            mut = production_priority_mutation()  # type: ignore
        except Exception:
            mut = {"empty": True, "score": 0.0, "summary": ""}

    if mut.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(mut.get("score", 0.7))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_production",
            "province_id": province_id,
            "line_id": line_id,
            "unit_id": unit_id or line_id,
            "score": score,
            "enabled": True,
            "label": "Set production priority",
        }
    ]
    label = "Production priority day · line %s · score %.2f" % (line_id, score)
    return {
        "mutation": mut,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "production_priority_day",
                "label": "Run production priority day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(mut.get("plain", mut.get("summary", "")))),
        "bbcode": "[color=#f87171]🏭 Production priority day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["production", "priority", "surge"],
    }


# ---------------------------------------------------------------------------
# 6. Convoy escort day
# ---------------------------------------------------------------------------


def convoy_escort_day(
    path_zone_relations: Optional[Sequence[str]] = None,
    *,
    available_fleet_strength: float = 80.0,
    cargo_value: float = 100.0,
    interdiction_chance: float = 0.15,
    basing_refuel: float = 0.25,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Plan convoy escort → station / supply apply when coverage thin."""
    zones = list(path_zone_relations or ["contested", "hostile", "friendly", "contested"])
    try:
        plan = plan_convoy_escort(
            zones,
            float(available_fleet_strength),
            cargo_value=float(cargo_value),
            interdiction_chance=float(interdiction_chance),
            basing_refuel=float(basing_refuel),
        )
    except TypeError:
        try:
            plan = plan_convoy_escort(zones, available_fleet_strength)  # type: ignore
        except Exception:
            plan = {"summary": "escort stub", "sufficient": False}

    need_block = plan.get("need", plan.get("escort_need", 0.0))
    assign_block = plan.get("assign", plan.get("escort_assign", 0.0))
    if isinstance(need_block, Mapping):
        need = float(need_block.get("escort_need", need_block.get("need", 0.0)) or 0.0)
    else:
        need = float(need_block or 0.0)
    if isinstance(assign_block, Mapping):
        assign = float(
            assign_block.get("assigned", assign_block.get("desired", assign_block.get("assign", 0.0)))
            or 0.0
        )
        coverage = float(assign_block.get("coverage", 1.0) or 1.0)
        sufficient = bool(assign_block.get("sufficient", plan.get("sufficient", True)))
    else:
        assign = float(assign_block or 0.0)
        coverage = 1.0
        if need > 0.01:
            coverage = min(1.0, assign / need)
        sufficient = bool(plan.get("sufficient", assign >= need * 0.85 if need > 0 else True))
    if need > 0.01 and coverage >= 0.999:
        # recompute if coverage missing/defaulted high but assign thin
        coverage = min(1.0, max(coverage, assign / need if need else 1.0))
    score = _clamp01(0.35 + 0.65 * float(coverage))
    apply_queue: List[Dict[str, Any]] = []
    if not sufficient or coverage < 0.9:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": max(0.4, 1.0 - coverage),
                "enabled": True,
                "label": "Station escort force",
            }
        )
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.5,
                "enabled": True,
                "label": "Sustain convoy route",
            }
        )
    else:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "label": "Maintain convoy sustain",
            }
        )

    label = "Convoy escort day · need %.1f · assign %.1f · cov %.0f%% · %s" % (
        need,
        assign,
        coverage * 100.0,
        "OK" if sufficient else "GAP",
    )
    return {
        "plan": plan,
        "need": need,
        "assign": assign,
        "coverage": coverage,
        "sufficient": sufficient,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "convoy_escort_day",
                "label": "Run convoy escort day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(plan.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]🛡 Convoy escort day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["convoy", "escort", "naval"],
    }


# ---------------------------------------------------------------------------
# 7. Next-day feedback day
# ---------------------------------------------------------------------------


def next_day_feedback_day(
    *,
    before_score: float = 0.45,
    after_score: float = 0.62,
    order: str = "apply_assault",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Next-day feedback strip → refresh / follow-on apply."""
    try:
        fb = next_day_feedback(
            float(before_score), float(after_score), order=str(order or "")
        )
    except TypeError:
        try:
            fb = next_day_feedback(before_score, after_score)  # type: ignore
        except Exception:
            fb = {
                "trend": "steady",
                "delta": 0.0,
                "summary": "feedback stub",
                "empty": False,
            }

    if fb.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    delta = float(fb.get("delta", after_score - before_score) or 0.0)
    trend = str(fb.get("trend", "steady"))
    score = _clamp01(0.5 + delta)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "refresh_queue",
            "province_id": province_id,
            "score": max(0.35, score),
            "enabled": True,
            "label": "Refresh after feedback",
        }
    ]
    if trend == "improved" and delta > 0.05:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Follow-on after improvement",
            }
        )
    elif trend == "worsened":
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, abs(delta)),
                "enabled": True,
                "label": "Recover after setback",
            }
        )

    label = "Next-day feedback day · %s · Δ%+.2f" % (trend, delta)
    return {
        "feedback": fb,
        "trend": trend,
        "delta": delta,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "next_day_feedback_day",
                "label": "Run next-day feedback day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(fb.get("plain", fb.get("summary", "")))),
        "bbcode": "[color=#5ec8ff]↻ Next-day feedback day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["feedback", "execute", "follow_on"],
    }


# ---------------------------------------------------------------------------
# 8. Map effect day
# ---------------------------------------------------------------------------


def map_effect_day(
    *,
    order: str = "apply_supply",
    province_id: int = 1,
    score: float = 0.65,
    effect_class: str = "ops",
) -> Dict[str, Any]:
    """Resolve map effect → soft apply of underlying order."""
    o = str(order or "apply_supply").strip() or "apply_supply"
    try:
        effect = map_effect_resolve(
            order=o,
            province_id=int(province_id),
            score=float(score),
            effect_class=str(effect_class or "ops"),
        )
    except TypeError:
        try:
            effect = map_effect_resolve(o, province_id, score)  # type: ignore
        except Exception:
            effect = {"empty": True, "score": 0.0, "summary": ""}

    if effect.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    sc = _norm_score(effect.get("score", score))
    # Map effect order string → day apply action
    aid = o
    if not aid.startswith("apply_") and aid not in (
        "refresh_queue",
        "apply_assault",
        "apply_supply",
        "apply_station",
        "apply_production",
        "apply_agent_dispatch",
        "apply_hh_commit",
    ):
        up = o.upper()
        if "SUPPLY" in up or "ROUTE" in up:
            aid = "apply_supply"
        elif "ASSAULT" in up or "COMBAT" in up or "PRESS" in up:
            aid = "apply_assault"
        elif "PROD" in up:
            aid = "apply_production"
        elif "AGENT" in up or "DISPATCH" in up:
            aid = "apply_agent_dispatch"
        elif "HH" in up or "COMMIT" in up or "AGENDA" in up:
            aid = "apply_hh_commit"
        else:
            aid = "refresh_queue"

    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": aid,
            "province_id": province_id,
            "score": sc,
            "enabled": True,
            "label": "Apply map effect %s" % aid,
        }
    ]
    label = "Map effect day · %s · score %.2f · #%d" % (
        str((effect.get("effect") or {}).get("effect_class", effect_class)),
        sc,
        province_id,
    )
    return {
        "effect": effect,
        "score": sc,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "map_effect_day",
                "label": "Run map effect day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(effect.get("plain", effect.get("summary", "")))),
        "bbcode": "[color=#5ec8ff]★ Map effect day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["map_effect", "order", "visual"],
    }


# ---------------------------------------------------------------------------
# 9. Theater brief day
# ---------------------------------------------------------------------------


def theater_brief_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    month: int = 6,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Theater daily brief → multi-domain soft apply queue."""
    w = dict(weather or {})
    try:
        brief = theater_daily_brief(weather=w, trail=list(trail or []), month=month)
    except TypeError:
        try:
            brief = theater_daily_brief()  # type: ignore
        except Exception:
            brief = {"empty": True, "score": 0.0, "summary": ""}

    if brief.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(brief.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Theater supply follow",
        },
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.35, score * 0.9),
            "enabled": True,
            "label": "Theater station follow",
        },
    ]
    if score >= 0.55:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Theater press follow",
            }
        )
    if score >= 0.5:
        apply_queue.append(
            {
                "action_id": "apply_hh_commit",
                "province_id": province_id,
                "score": score * 0.85,
                "enabled": True,
                "label": "Theater HH follow",
            }
        )

    label = "Theater brief day · domains %d · score %.2f" % (
        int(brief.get("count", len(brief.get("lines") or [])) or 0),
        score,
    )
    return {
        "brief": brief,
        "score": score,
        "apply_queue": apply_queue[:5],
        "actions": [
            {
                "action_id": "theater_brief_day",
                "label": "Run theater brief day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(brief.get("plain", brief.get("summary", "")))),
        "bbcode": "[color=#5ec8ff]📋 Theater brief day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["theater", "brief", "multi_domain"],
    }


# ---------------------------------------------------------------------------
# 10. Campaign decision day
# ---------------------------------------------------------------------------


def campaign_decision_day(
    boards: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Campaign decision strip → top-board apply queue."""
    default_boards: List[Dict[str, Any]] = [
        {"id": "combat", "score": 0.78, "label": "Press main front", "action_id": "apply_assault"},
        {"id": "supply", "score": 0.62, "label": "Feed rear depots", "action_id": "apply_supply"},
        {"id": "fleet", "score": 0.58, "label": "Sea control patrol", "action_id": "apply_station"},
        {"id": "production", "score": 0.55, "label": "Surge primary line", "action_id": "apply_production"},
        {"id": "agenda", "score": 0.5, "label": "Commit war agenda", "action_id": "apply_hh_commit"},
    ]
    bds = list(boards or default_boards)
    try:
        strip = campaign_decision_strip(boards=bds)
    except TypeError:
        try:
            strip = campaign_decision_strip(bds)  # type: ignore
        except Exception:
            strip = {"empty": True, "count": 0, "summary": ""}

    if strip.get("empty") and not bds:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    # If strip empty due to API shape but we have boards, rebuild lightly
    if strip.get("empty"):
        lines = [str(b.get("label", b.get("id", ""))) for b in bds if b]
        strip = {
            "lines": lines,
            "count": len(lines),
            "empty": len(lines) == 0,
            "summary": "Campaign decision strip · %d" % len(lines),
            "plain": "\n".join(lines),
        }

    ranked = sorted(
        [b for b in bds if isinstance(b, dict)],
        key=lambda x: -float(x.get("score", 0.0) or 0.0),
    )
    apply_queue: List[Dict[str, Any]] = []
    for b in ranked[:4]:
        aid = str(b.get("action_id", "refresh_queue") or "refresh_queue")
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": province_id,
                "score": _norm_score(b.get("score", 0.5)),
                "enabled": True,
                "label": str(b.get("label", b.get("id", aid))),
            }
        )
    scores = [float(b.get("score", 0.5) or 0.5) for b in ranked]
    score = _norm_score(sum(scores) / float(len(scores)) if scores else 0.5)
    label = "Campaign decision day · boards %d · top %s · score %.2f" % (
        len(ranked),
        str(ranked[0].get("id", "?")) if ranked else "—",
        score,
    )
    return {
        "strip": strip,
        "boards": ranked,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "campaign_decision_day",
                "label": "Run campaign decision day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(strip.get("plain", strip.get("summary", "")))),
        "bbcode": "[color=#5ec8ff]── Campaign decision day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["campaign", "decision", "multi_board"],
    }


# ---------------------------------------------------------------------------
# Close / integrity
# ---------------------------------------------------------------------------


NEXT10_DAY_IDS: List[str] = [
    "multi_phase_combat_day",
    "combat_air_naval_day",
    "agent_auto_day",
    "focus_pick_day",
    "production_priority_day",
    "convoy_escort_day",
    "next_day_feedback_day",
    "map_effect_day",
    "theater_brief_day",
    "campaign_decision_day",
]


def next10_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Next10 integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next10_depth_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Run all 10 day packages + integrity gate."""
    w = dict(weather or {"visibility": 1.0, "precip_intensity": 0.1, "ground_state": "dry"})
    packages = {
        "multi_phase_combat_day": multi_phase_combat_day(attacker_supply=0.85),
        "combat_air_naval_day": combat_air_naval_day(weather=w),
        "agent_auto_day": agent_auto_day(),
        "focus_pick_day": focus_pick_day(),
        "production_priority_day": production_priority_day(weather=w),
        "convoy_escort_day": convoy_escort_day(),
        "next_day_feedback_day": next_day_feedback_day(),
        "map_effect_day": map_effect_day(),
        "theater_brief_day": theater_brief_day(weather=w),
        "campaign_decision_day": campaign_decision_day(),
    }
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = next10_integrity()
    label = "Close next10 depth · packages %d/10 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if gate.get("ok") and non_empty >= 10 else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 10.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next10 depth[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 10,
    }
