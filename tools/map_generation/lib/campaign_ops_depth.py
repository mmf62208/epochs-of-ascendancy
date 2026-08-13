"""Campaign ops depth: combat air-naval joint, multi-theater fleet day, agent auto-dispatch.

Composes existing pure pilots for the next product-depth batch beyond product_depth.py.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from product_depth import (  # type: ignore
    multi_phase_combat_ui_product,
    fleet_autonomy_plan,
    agent_ai_board,
    agent_ai_decision_quality,
    weather_mult_from,
)
from campaign_cohesion import air_land_joint_package  # type: ignore
from integrated_theater_ops import air_ops_package  # type: ignore
from naval_fleet_tasking import rank_naval_orders  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


# ---------------------------------------------------------------------------
# Combat air–naval joint
# ---------------------------------------------------------------------------


def combat_air_naval_joint(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    month: int = 6,
    fuel_level: float = 0.7,
    basing_level: str = "port",
    province_id: int = -1,
) -> Dict[str, Any]:
    """Multi-phase land combat + air ops + naval tasking joint package."""
    w = dict(weather or {})
    combat = multi_phase_combat_ui_product(
        attacker_power=attacker_power,
        defender_power=defender_power,
        attacker_supply=attacker_supply,
        weather=w,
        province_id=province_id,
    )
    air_land = air_land_joint_package(
        weather=w,
        month=month,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
    )
    air = air_ops_package(w, month=month)
    basing = {"level": basing_level, "basing_level": basing_level}
    try:
        naval = rank_naval_orders(basing, zone_relation="contested", fuel_level=fuel_level)
    except TypeError:
        try:
            naval = rank_naval_orders(basing_level=basing_level, fuel_level=fuel_level)  # type: ignore
        except Exception:
            naval = {"best_order": "SEARCH_PATROL", "best_score": 50.0, "empty": False}

    land_s = _score(combat, "score", "overall")
    air_s = _score(air, "effective", "score", default=0.5)
    if air_s > 1.5:
        air_s = min(1.0, air_s / 2.0)
    air_s = max(0.0, min(1.0, air_s))
    naval_s = _score(naval, "best_score", "score", default=50.0)
    if naval_s > 2.0:
        naval_s = min(1.0, naval_s / 100.0)
    joint = (land_s * 0.45 + air_s * 0.3 + naval_s * 0.25) * (
        0.75 if air.get("grounded") else 1.0
    )
    apply_ready = bool(combat.get("apply_ready", False)) and not bool(air.get("grounded", False))
    phase_rows = list(combat.get("phase_rows") or [])
    label = "Combat air-naval joint · land %.0f%% · air %.0f%% · naval %s · score %.2f" % (
        land_s * 100.0,
        air_s * 100.0,
        str(naval.get("best_order", "?")),
        joint,
    )
    if province_id >= 0:
        label += " · #%d" % int(province_id)
    return {
        "combat": combat,
        "air_land": air_land,
        "air": air,
        "naval": naval,
        "phase_rows": phase_rows,
        "score": float(joint),
        "apply_ready": apply_ready,
        "grounded": bool(air.get("grounded", False)),
        "actions": [
            {
                "action_id": "apply_assault",
                "label": "Stage joint assault",
                "enabled": apply_ready,
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Support naval tasking",
                "enabled": fuel_level >= 0.25,
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(combat.get("summary", "")),
                str(air.get("summary", "")),
                str(naval.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#ff9a6e]⚔✈🚢 Joint combat[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["multi_phase", "air_ops", "naval_tasking", "apply"],
    }


# ---------------------------------------------------------------------------
# Fleet multi-theater day autonomy
# ---------------------------------------------------------------------------


def fleet_multi_theater_day(
    theaters: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    default_fuel: float = 0.7,
    country_tag: str = "ENG",
    max_applies: int = 3,
) -> Dict[str, Any]:
    """Plan autonomous fleet actions across multiple theater province sets.

    Empty theaters → empty. Low-fuel theaters may be apply_ready=false.
    """
    raw = [dict(t) for t in list(theaters or []) if isinstance(t, dict)]
    if not raw:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "plans": [],
            "apply_queue": [],
        }

    plans: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for t in raw:
        ids = [int(p) for p in list(t.get("province_ids") or t.get("ids") or []) if int(p) >= 0]
        if not ids and t.get("province_id") is not None:
            ids = [int(t["province_id"])]
        if not ids:
            continue
        fuel = float(t.get("fuel_level", default_fuel) or default_fuel)
        basing = str(t.get("basing_level", "port"))
        zone = str(t.get("zone_relation", "contested"))
        plan = fleet_autonomy_plan(
            ids,
            fuel_level=fuel,
            basing_level=basing,
            zone_relation=zone,
            country_tag=country_tag,
        )
        plan["theater_id"] = t.get("theater_id", t.get("id", len(plans)))
        plans.append(plan)
        if plan.get("apply_ready") and not plan.get("empty"):
            apply_queue.append(
                {
                    "province_id": ids[0],
                    "action_id": "fleet_autonomy",
                    "chosen_order": plan.get("chosen_order"),
                    "score": plan.get("score", 0.5),
                }
            )

    apply_queue.sort(key=lambda x: -float(x.get("score", 0.0)))
    apply_queue = apply_queue[: max(0, int(max_applies))]
    if not plans:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "plans": [],
            "apply_queue": [],
        }

    scores = [float(p.get("score", 0.0)) for p in plans if not p.get("empty")]
    mean = sum(scores) / float(len(scores)) if scores else 0.0
    ready_n = sum(1 for p in plans if p.get("apply_ready"))
    label = "Fleet multi-theater day · %d theaters · ready %d · queue %d · score %.2f" % (
        len(plans),
        ready_n,
        len(apply_queue),
        mean,
    )
    return {
        "plans": plans,
        "apply_queue": apply_queue,
        "ready_count": ready_n,
        "theater_count": len(plans),
        "score": mean,
        "actions": [
            {
                "action_id": "fleet_multi_day",
                "label": "Apply multi-theater fleet day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                "T%s %s score %.2f ready=%s"
                % (
                    p.get("theater_id", "?"),
                    p.get("chosen_order", "?"),
                    float(p.get("score", 0.0)),
                    p.get("apply_ready"),
                )
                for p in plans[:6]
            ]
        ),
        "bbcode": "[color=#5ec8ff]🚢 Multi-theater fleet[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_autonomy", "multi_theater", "day_queue"],
    }


# ---------------------------------------------------------------------------
# Agent auto-dispatch day
# ---------------------------------------------------------------------------


def agent_auto_dispatch_day(
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
    max_dispatches: int = 3,
) -> Dict[str, Any]:
    """Day decision: rank signals → dispatch queue. Empty signals → empty."""
    quality = agent_ai_decision_quality(
        signals, available_agents=available_agents, network_strength=network_strength
    )
    if quality.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "dispatch_queue": [],
            "actions": [],
        }

    queue: List[Dict[str, Any]] = []
    for d in list(quality.get("decisions") or []):
        if not isinstance(d, dict):
            continue
        board = agent_ai_board(
            {
                "active": True,
                "action_class": d.get("action_class", "sabotage"),
                "influence": d.get("threat", 0.55),
                "province_id": d.get("province_id", -1),
            },
            available_agents=max(1, available_agents // 2),
            network_strength=network_strength,
        )
        if board.get("empty"):
            continue
        queue.append(
            {
                "province_id": int(d.get("province_id", -1)),
                "action_class": str(d.get("action_class", "")),
                "best_mission": str(d.get("best_mission", board.get("best_mission", ""))),
                "action_id": "apply_agent_dispatch",
                "score": float(d.get("score", board.get("score", 0.5))),
            }
        )
    queue.sort(key=lambda x: -float(x.get("score", 0.0)))
    queue = queue[: max(0, int(max_dispatches))]
    # Secondary counterplay for top threat
    if queue:
        queue.append(
            {
                "province_id": int(queue[0].get("province_id", -1)),
                "action_id": "apply_counterplay",
                "best_mission": "counter_intel",
                "score": float(queue[0].get("score", 0.5)) * 0.9,
            }
        )

    label = "Agent auto-dispatch day · %d dispatches · affinity %.0f%% · score %.2f" % (
        len([q for q in queue if q.get("action_id") == "apply_agent_dispatch"]),
        float(quality.get("affinity", 0.0)) * 100.0,
        float(quality.get("score", 0.0)),
    )
    return {
        "quality": quality,
        "dispatch_queue": queue,
        "score": float(quality.get("score", 0.0)),
        "affinity": float(quality.get("affinity", 0.0)),
        "actions": [
            {
                "action_id": "agent_auto_day",
                "label": "Run agent auto-dispatch day",
                "enabled": len(queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                "#%s %s → %s"
                % (
                    q.get("province_id", "?"),
                    q.get("action_id", ""),
                    q.get("best_mission", ""),
                )
                for q in queue[:6]
            ]
        ),
        "bbcode": "[color=#c084fc]🕵 Agent day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(queue) == 0,
        "integration": ["agent_quality", "dispatch_queue", "counterplay"],
    }


def campaign_ops_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Campaign ops integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
        "sole": sole,
    }


def close_campaign_ops_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {"precip_intensity": 0.9, "visibility": 0.2, "ground_state": "mud"}
    w = dict(weather or clear)
    j_clear = combat_air_naval_joint(weather=clear)
    j_foul = combat_air_naval_joint(weather=foul)
    fleet = fleet_multi_theater_day(
        [
            {"theater_id": "A", "province_ids": [1, 2], "fuel_level": 0.75},
            {"theater_id": "B", "province_ids": [10, 11], "fuel_level": 0.2},
        ]
    )
    agent = agent_auto_dispatch_day(
        [
            {
                "active": True,
                "action_class": "sabotage",
                "influence": 0.7,
                "province_id": 1,
            },
            {
                "active": True,
                "action_class": "economic_pressure",
                "influence": 0.55,
                "province_id": 2,
            },
        ]
    )
    agent_empty = agent_auto_dispatch_day([])
    gate = campaign_ops_integrity()
    wx_shift = abs(float(j_clear["score"]) - float(j_foul["score"]))
    label = "Close campaign ops · Δwx %.3f · fleet_queue %d · agent_empty %s · %s" % (
        wx_shift,
        len(fleet.get("apply_queue") or []),
        agent_empty.get("empty"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "joint_clear": j_clear,
        "joint_foul": j_foul,
        "fleet_day": fleet,
        "agent_day": agent,
        "agent_empty": agent_empty,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
