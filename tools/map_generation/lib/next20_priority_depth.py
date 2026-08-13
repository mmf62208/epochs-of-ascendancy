"""Next-20 priority depth: turn open P1–P9 pilots + basing/follow-on into day packages.

1 order_panel_ux_day · 2 multi_phase_combat_ui_day · 3 fleet_ai_ops_day
4 hh_agenda_package_day · 5 agent_campaign_depth_day · 6 industry_economy_day
7 save_slot_browser_day · 8 basing_logistics_day · 9 assault_follow_on_day
10 joint_ops_loop_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from priority_systems import (  # type: ignore
    order_panel_ux_model,
    multi_phase_combat_ui,
    fleet_ai_ops_package,
    hh_agenda_screen_package,
    agent_campaign_depth,
    industry_economy_depth,
    save_slot_browser_package,
)
from gameplay_loops import (  # type: ignore
    basing_fleet_fuel_logistics,
    assault_follow_on_loop,
    joint_ops_loop_strip,
    sole_mult_integrity,
)


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
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return _clamp01(x)


def _actions_to_queue(
    actions: Sequence[Mapping[str, Any]],
    province_id: int,
    default_score: float = 0.5,
) -> List[Dict[str, Any]]:
    queue: List[Dict[str, Any]] = []
    for a in list(actions or []):
        if not isinstance(a, dict):
            continue
        aid = str(a.get("action_id", "")).strip()
        if not aid:
            continue
        # Skip nested day packages in apply_queue
        if aid.endswith("_day") and not aid.startswith("save_slot") and not aid.startswith("load_slot"):
            continue
        queue.append(
            {
                "action_id": aid,
                "province_id": int(a.get("province_id", province_id)),
                "score": float(a.get("score", default_score) or default_score),
                "enabled": bool(a.get("enabled", True)),
                "label": str(a.get("label", aid)),
            }
        )
    return queue


# ---------------------------------------------------------------------------
# 1. Order panel UX day
# ---------------------------------------------------------------------------


def order_panel_ux_day(
    province_ids: Optional[Sequence[int]] = None,
    *,
    selected_province_id: int = 1,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    last_result: Optional[Mapping[str, Any]] = None,
    province_names: Optional[Mapping[int, str]] = None,
) -> Dict[str, Any]:
    ids = list(province_ids or [1, 2, 3])
    try:
        model = order_panel_ux_model(
            province_ids=ids,
            selected_province_id=selected_province_id,
            weather=weather,
            trail=trail,
            last_result=last_result,
            province_names=province_names,
        )
    except Exception:
        model = {"empty": True, "score": 0.0, "actions": []}

    if model.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    pid = int(model.get("selected_province_id", selected_province_id) or selected_province_id)
    score = _norm_score(model.get("score", 0.7))
    apply_queue = _actions_to_queue(model.get("actions") or [], pid, score)
    # Always include soft refresh for panel surface
    if not any(q.get("action_id") == "refresh_queue" for q in apply_queue):
        apply_queue.append(
            {
                "action_id": "refresh_queue",
                "province_id": pid,
                "score": 0.4,
                "enabled": True,
                "label": "Refresh order panel",
            }
        )
    apply_queue = apply_queue[:8]
    label = "Order panel UX day · provinces %d · selected #%d · q %d" % (
        len(ids),
        pid,
        len(apply_queue),
    )
    return {
        "model": model,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "order_panel_ux_day",
                "label": "Run order panel UX day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(model.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]📋 Order panel UX day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["order_panel", "ux", "province_bind"],
    }


# ---------------------------------------------------------------------------
# 2. Multi-phase combat UI day
# ---------------------------------------------------------------------------


def multi_phase_combat_ui_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        ui = multi_phase_combat_ui(
            attacker_power=attacker_power,
            defender_power=defender_power,
            attacker_supply=attacker_supply,
            weather=w,
        )
    except Exception:
        ui = {"empty": True, "score": 0.0, "actions": []}

    if ui.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(ui.get("score", 0.5))
    apply_queue = _actions_to_queue(ui.get("actions") or [], province_id, score)
    if score < 0.45 or attacker_supply < 0.7:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.35, 1.0 - float(attacker_supply)),
                "enabled": True,
                "label": "Feed phase assault",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
            }
        )
    label = "Multi-phase combat UI day · score %.2f · atk %.0f/dfd %.0f" % (
        score,
        attacker_power,
        defender_power,
    )
    return {
        "ui": ui,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "multi_phase_combat_ui_day",
                "label": "Run multi-phase combat UI day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(ui.get("plain", ui.get("summary", "")))[:200]),
        "bbcode": "[color=#ff9a6e]⚔ Multi-phase combat UI day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["combat_ui", "ribbon", "card", "assault"],
    }


# ---------------------------------------------------------------------------
# 3. Fleet AI ops day
# ---------------------------------------------------------------------------


def fleet_ai_ops_day(
    province_ids: Optional[Sequence[int]] = None,
    *,
    fuel_level: float = 0.7,
    available_strength: float = 100.0,
    basing_level: str = "port",
    path_zone_relations: Optional[Sequence[str]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    ids = list(province_ids or [1, 2, 3])
    try:
        pkg = fleet_ai_ops_package(
            province_ids=ids,
            fuel_level=fuel_level,
            available_strength=available_strength,
            path_zone_relations=path_zone_relations,
            basing_level=basing_level,
        )
    except Exception:
        pkg = {"empty": True, "score": 0.0, "actions": []}

    if pkg.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(pkg.get("score", 0.55))
    apply_queue = _actions_to_queue(pkg.get("actions") or [], province_id, score)
    if fuel_level < 0.55:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel fleet AI ops",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
            }
        )
    label = "Fleet AI ops day · posture %s · score %.2f · fuel %.0f%%" % (
        str(pkg.get("best_posture", "?")),
        score,
        fuel_level * 100.0,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "fleet_ai_ops_day",
                "label": "Run fleet AI ops day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("plain", pkg.get("summary", "")))[:200]),
        "bbcode": "[color=#5ec8ff]🚢 Fleet AI ops day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet_ai", "patrol", "tasking", "escort"],
    }


# ---------------------------------------------------------------------------
# 4. HH agenda package day
# ---------------------------------------------------------------------------


def hh_agenda_package_day(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    seed_if_empty: bool = True,
) -> Dict[str, Any]:
    t = list(trail or [])
    if not t and seed_if_empty:
        t = [
            {
                "month": 3,
                "year": 1936,
                "action_class": "sabotage",
                "influence": 0.62,
                "province_id": province_id,
            },
            {
                "month": 4,
                "year": 1936,
                "action_class": "infiltration",
                "influence": 0.48,
                "province_id": max(1, province_id + 1),
            },
        ]
    try:
        pkg = hh_agenda_screen_package(trail=t)
    except Exception:
        pkg = {"empty": True, "score": 0.0, "actions": []}

    if pkg.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(pkg.get("score", 0.5))
    apply_queue = _actions_to_queue(pkg.get("actions") or [], province_id, score)
    apply_queue.append(
        {
            "action_id": "apply_counterplay",
            "province_id": province_id,
            "score": max(0.4, score * 0.9),
            "enabled": True,
            "label": "Counter agenda signal",
        }
    )
    label = "HH agenda package day · trail %d · score %.2f" % (
        int(pkg.get("trail_len", len(t)) or len(t)),
        score,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "hh_agenda_package_day",
                "label": "Run HH agenda package day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("plain", pkg.get("summary", "")))[:200]),
        "bbcode": "[color=#c084fc]📜 HH agenda package day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["hh_agenda", "screen", "commit", "counterplay"],
    }


# ---------------------------------------------------------------------------
# 5. Agent campaign depth day
# ---------------------------------------------------------------------------


def agent_campaign_depth_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "class": "sabotage",
            "action_class": "sabotage",
            "influence": 0.65,
            "province_id": province_id,
        }
    )
    try:
        depth = agent_campaign_depth(signal=sig, available_agents=available_agents)
    except Exception:
        depth = {"empty": True, "score": 0.0, "actions": []}

    if depth.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(depth.get("score", 0.5))
    apply_queue = _actions_to_queue(depth.get("actions") or [], province_id, score)
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_agent_dispatch",
                "province_id": province_id,
                "score": score,
                "enabled": True,
            }
        )
    label = "Agent campaign depth day · score %.2f · agents %d" % (score, available_agents)
    return {
        "depth": depth,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "agent_campaign_depth_day",
                "label": "Run agent campaign depth day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(depth.get("plain", depth.get("summary", "")))[:200]),
        "bbcode": "[color=#c084fc]🕵 Agent campaign depth day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["agent", "missions", "coverage", "escalation"],
    }


# ---------------------------------------------------------------------------
# 6. Industry economy day
# ---------------------------------------------------------------------------


def industry_economy_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    sea_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        econ = industry_economy_depth(
            weather=w, base_output=base_output, sea_mult=sea_mult
        )
    except Exception:
        econ = {"empty": True, "score": 0.0, "actions": []}

    if econ.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(econ.get("score", 0.7))
    risk = float(econ.get("risk", 0.0) or 0.0)
    apply_queue = _actions_to_queue(econ.get("actions") or [], province_id, score)
    if risk >= 0.35 and not any(q.get("action_id") == "apply_supply" for q in apply_queue):
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, risk),
                "enabled": True,
                "label": "Shield industry supply",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_production",
                "province_id": province_id,
                "score": score,
                "enabled": True,
            }
        )
    label = "Industry economy day · score %.2f · risk %.0f%%" % (score, risk * 100.0)
    return {
        "economy": econ,
        "score": score,
        "risk": risk,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "industry_economy_day",
                "label": "Run industry economy day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(econ.get("plain", econ.get("summary", "")))),
        "bbcode": "[color=#f87171]🏭 Industry economy day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["industry", "economy", "oob", "supply"],
    }


# ---------------------------------------------------------------------------
# 7. Save slot browser day
# ---------------------------------------------------------------------------


def save_slot_browser_day(
    occupied_slots: Optional[Sequence[Mapping[str, Any]]] = None,
    fixed_slots: Optional[Sequence[str]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    occ = list(
        occupied_slots
        or [
            {
                "slot": "quicksave",
                "occupied": True,
                "metadata": {"scenario_id": "world_full", "year": 1936},
            }
        ]
    )
    try:
        pkg = save_slot_browser_package(
            occupied_slots=occ, fixed_slots=list(fixed_slots or [])
        )
    except Exception:
        pkg = {"empty": True, "score": 0.0, "actions": [], "rows": []}

    if pkg.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(pkg.get("score", 0.6))
    # Prefer save_slot:quicksave as soft apply (safe)
    apply_queue: List[Dict[str, Any]] = []
    for a in list(pkg.get("actions") or []):
        if not isinstance(a, dict):
            continue
        aid = str(a.get("action_id", ""))
        if not aid.startswith("save_slot:"):
            continue
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": province_id,
                "score": score,
                "enabled": bool(a.get("enabled", True)),
                "label": str(a.get("label", aid)),
            }
        )
        if len(apply_queue) >= 2:
            break
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "save_slot:quicksave",
                "province_id": province_id,
                "score": 0.5,
                "enabled": True,
                "label": "Quicksave",
            }
        )
    label = "Save slot browser day · slots %d · occupied %d" % (
        int(pkg.get("count", 0) or 0),
        int(pkg.get("occupied_count", 0) or 0),
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "save_slot_browser_day",
                "label": "Run save slot browser day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("plain", pkg.get("summary", "")))[:200]),
        "bbcode": "[color=#5ec8ff]💾 Save slot browser day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["save_load", "slots", "browser"],
    }


# ---------------------------------------------------------------------------
# 8. Basing logistics day
# ---------------------------------------------------------------------------


def basing_logistics_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    mission: str = "patrol",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        log = basing_fleet_fuel_logistics(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=w,
            mission=mission,
        )
    except Exception:
        log = {"empty": True, "summary": "", "logistics_score": 0.0}

    if log.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(
        log.get("logistics_score", log.get("score", log.get("mission_effective", 0.55)))
    )
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Station at basing tier",
        }
    ]
    if fuel_level < 0.7:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel at base",
            }
        )
    label = "Basing logistics day · %s · fuel %.0f%% · score %.2f" % (
        basing_level,
        fuel_level * 100.0,
        score,
    )
    return {
        "logistics": log,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "basing_logistics_day",
                "label": "Run basing logistics day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(log.get("summary", log.get("label", "")))),
        "bbcode": "[color=#5ec8ff]⚓ Basing logistics day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["basing", "fuel", "fleet", "logistics"],
    }


# ---------------------------------------------------------------------------
# 9. Assault follow-on day
# ---------------------------------------------------------------------------


def assault_follow_on_day(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
) -> Dict[str, Any]:
    tgts = list(
        targets
        or [
            {
                "id": province_id,
                "province_id": province_id,
                "power": 40.0,
                "defender_power": 40.0,
            },
            {
                "id": max(1, province_id + 1),
                "province_id": max(1, province_id + 1),
                "power": 30.0,
                "defender_power": 35.0,
            },
        ]
    )
    w = dict(weather or {})
    try:
        follow = assault_follow_on_loop(
            tgts,
            attacker_power=attacker_power,
            attacker_supply=attacker_supply,
            weather=w,
        )
    except Exception:
        follow = {"empty": True, "score": 0.0, "summary": ""}

    if follow.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    overall = float(follow.get("overall", follow.get("score", 0.5)) or 0.5)
    score = _norm_score(overall if overall <= 2.0 else overall / 100.0)
    next_step = str(follow.get("next_step", follow.get("advice", "hold")) or "hold")
    best_pid = int(follow.get("best_province_id", province_id) or province_id)
    apply_queue: List[Dict[str, Any]] = []
    if next_step in ("press", "soften", "assault") or score >= 0.45:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": best_pid,
                "score": score,
                "enabled": True,
                "label": "Follow-on %s" % next_step,
            }
        )
    if next_step in ("hold", "supply") or attacker_supply < 0.7 or score < 0.5:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": best_pid,
                "score": max(0.35, 1.0 - float(attacker_supply)),
                "enabled": True,
                "label": "Sustain follow-on",
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": best_pid,
                "score": 0.4,
                "enabled": True,
            }
        )
    label = "Assault follow-on day · %s · win %.0f%% · #%d" % (
        next_step,
        score * 100.0,
        best_pid,
    )
    return {
        "follow": follow,
        "next_step": next_step,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "assault_follow_on_day",
                "label": "Run assault follow-on day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(follow.get("plain", follow.get("summary", "")))),
        "bbcode": "[color=#ff9a6e]⚔ Assault follow-on day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["assault", "follow_on", "readiness"],
    }


# ---------------------------------------------------------------------------
# 10. Joint ops loop day
# ---------------------------------------------------------------------------


def joint_ops_loop_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.6,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    basing = basing_logistics_day(
        weather=w,
        basing_level=basing_level,
        fuel_level=fuel_level,
        province_id=province_id,
    )
    follow = assault_follow_on_day(
        weather=w,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        province_id=province_id,
    )
    try:
        strip = joint_ops_loop_strip(
            basing_logistics=basing.get("logistics") or basing,
            follow_on=follow.get("follow") or follow,
            execute_pick={"summary": "Execute joint pick", "empty": False},
        )
    except Exception:
        strip = {
            "summary": "Joint ops loop · 2",
            "count": 2,
            "empty": False,
            "plain": "",
        }

    score = (
        _norm_score(basing.get("score", 0.5)) + _norm_score(follow.get("score", 0.5))
    ) / 2.0
    apply_queue: List[Dict[str, Any]] = []
    for block in (basing, follow):
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))
    # dedupe
    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:6]
    label = "Joint ops loop day · basing %.2f · follow %.2f · q %d" % (
        float(basing.get("score", 0.0)),
        float(follow.get("score", 0.0)),
        len(apply_queue),
    )
    return {
        "basing": basing,
        "follow": follow,
        "strip": strip,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "joint_ops_loop_day",
                "label": "Run joint ops loop day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(strip.get("summary", "")),
                str(basing.get("summary", "")),
                str(follow.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]◎ Joint ops loop day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["joint_ops", "basing", "follow_on"],
    }


# ---------------------------------------------------------------------------
# Close / integrity
# ---------------------------------------------------------------------------


PRIORITY_DAY_IDS: List[str] = [
    "order_panel_ux_day",
    "multi_phase_combat_ui_day",
    "fleet_ai_ops_day",
    "hh_agenda_package_day",
    "agent_campaign_depth_day",
    "industry_economy_day",
    "save_slot_browser_day",
    "basing_logistics_day",
    "assault_follow_on_day",
    "joint_ops_loop_day",
]


def priority_depth_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Priority depth integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next20_priority_depth_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {"visibility": 1.0, "precip_intensity": 0.1, "ground_state": "dry"}
    )
    packages = {
        "order_panel_ux_day": order_panel_ux_day(weather=w),
        "multi_phase_combat_ui_day": multi_phase_combat_ui_day(weather=w),
        "fleet_ai_ops_day": fleet_ai_ops_day(),
        "hh_agenda_package_day": hh_agenda_package_day(),
        "agent_campaign_depth_day": agent_campaign_depth_day(),
        "industry_economy_day": industry_economy_day(weather=w),
        "save_slot_browser_day": save_slot_browser_day(),
        "basing_logistics_day": basing_logistics_day(weather=w),
        "assault_follow_on_day": assault_follow_on_day(weather=w),
        "joint_ops_loop_day": joint_ops_loop_day(weather=w),
    }
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = priority_depth_integrity()
    label = "Close next20 priority depth · packages %d/10 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next20 priority depth[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 10,
    }
