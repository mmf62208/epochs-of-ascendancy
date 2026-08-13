"""Next-30 theater surface depth: war cabinet, supply campaign, force×supply,
counter-ops, multi-province live, order queue, agent AI board, fleet order,
fleet theater posture, campaign day risk.

Composes existing pure boards into day packages with apply_queue / actions.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_cohesion import (  # type: ignore
    war_cabinet_board,
    supply_campaign_spine,
    campaign_day_risk,
)
from gameplay_loops import (  # type: ignore
    force_supply_posture,
    counter_ops_board,
    sole_mult_integrity,
)
from ops_depth import multi_province_live_plan, order_queue_board  # type: ignore
from product_depth import agent_ai_board  # type: ignore
from campaign_execution import fleet_order_execute  # type: ignore
from fleet_theater_posture import plan_fleet_theater_posture  # type: ignore


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
        aid = str(a.get("action_id", a.get("order", ""))).strip()
        if not aid:
            continue
        if aid.endswith("_day") and not aid.startswith("save_slot"):
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
# 1. War cabinet day
# ---------------------------------------------------------------------------


def war_cabinet_day(
    weather: Optional[Mapping[str, Any]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.55,
            "province_id": province_id,
        }
    )
    tr = list(
        trail
        or [
            {
                "month": 3,
                "action_class": "sabotage",
                "influence": 0.55,
                "province_id": province_id,
            }
        ]
    )
    try:
        board = war_cabinet_board(
            focus_id=focus_id,
            focus_base=focus_base,
            weather=w,
            signal=sig,
            trail=tr,
        )
    except Exception:
        board = {"empty": True, "summary": ""}

    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(board.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_hh_commit",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Cabinet HH commit",
        },
        {
            "action_id": "apply_focus",
            "province_id": province_id,
            "score": max(0.4, score * 0.9),
            "enabled": True,
            "label": "Hold focus %s" % focus_id,
        },
        {
            "action_id": "apply_counterplay",
            "province_id": province_id,
            "score": 0.45,
            "enabled": True,
            "label": "Cabinet counter-intel",
        },
    ]
    label = "War cabinet day · focus %s · score %.2f" % (focus_id, score)
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "war_cabinet_day",
                "label": "Run war cabinet day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("plain", board.get("summary", "")))[:200]),
        "bbcode": "[color=#fbbf24]── War cabinet day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["war_cabinet", "focus", "hh", "counterplay"],
    }


# ---------------------------------------------------------------------------
# 2. Supply campaign day
# ---------------------------------------------------------------------------


def supply_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    path_zone_relations: Optional[Sequence[str]] = None,
    *,
    basing_level: str = "port",
    sea_mult: float = 1.0,
    available_fleet: float = 80.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        spine = supply_campaign_spine(
            weather=w,
            basing_level=basing_level,
            sea_mult=sea_mult,
            path_zone_relations=list(
                path_zone_relations or ["contested", "hostile", "friendly"]
            ),
            available_fleet=available_fleet,
        )
    except Exception:
        spine = {"empty": True, "score": 0.0, "summary": ""}

    if spine.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(spine.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Sustain supply spine",
        },
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.35, 1.0 - score),
            "enabled": True,
            "label": "Escort supply spine",
        },
    ]
    label = "Supply campaign day · score %.2f · basing %s" % (score, basing_level)
    return {
        "spine": spine,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "supply_campaign_day",
                "label": "Run supply campaign day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(spine.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]📦 Supply campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["supply", "campaign", "escort", "sealane"],
    }


# ---------------------------------------------------------------------------
# 3. Force supply day
# ---------------------------------------------------------------------------


def force_supply_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    force_strength: float = 80.0,
    supply_health: float = 0.65,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        posture = force_supply_posture(
            force_strength=force_strength,
            supply_health=supply_health,
            weather=w,
        )
    except Exception:
        posture = {"empty": True, "summary": ""}

    if posture.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    mult = _score(posture, "posture", "score", "mult", default=0.6)
    score = _norm_score(mult if mult <= 2.0 else mult / 2.0)
    apply_queue: List[Dict[str, Any]] = []
    if supply_health < 0.75 or score < 0.55:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - supply_health),
                "enabled": True,
                "label": "Restore force supply",
            }
        )
    apply_queue.append(
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.35, score),
            "enabled": True,
            "label": "Hold force posture",
        }
    )
    if score >= 0.55 and supply_health >= 0.55:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Press with supplied force",
            }
        )
    label = "Force supply day · posture ×%.2f · force %.0f · supply %.0f%%" % (
        score,
        force_strength,
        supply_health * 100.0,
    )
    return {
        "posture": posture,
        "score": score,
        "apply_queue": apply_queue[:5],
        "actions": [
            {
                "action_id": "force_supply_day",
                "label": "Run force supply day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(posture.get("summary", posture.get("label", "")))),
        "bbcode": "[color=#ff9a6e]⚔ Force supply day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["force", "supply", "posture"],
    }


# ---------------------------------------------------------------------------
# 4. Counter-ops day
# ---------------------------------------------------------------------------


def counter_ops_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    network_strength: float = 0.35,
    available_agents: int = 5,
    loyalty: float = 0.5,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.7,
            "province_id": province_id,
        }
    )
    try:
        board = counter_ops_board(
            sig,
            network_strength=network_strength,
            available_agents=available_agents,
            loyalty=loyalty,
        )
    except TypeError:
        try:
            board = counter_ops_board(sig)  # type: ignore
        except Exception:
            board = {"empty": True, "summary": ""}

    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(board.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_counterplay",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Apply counter-ops",
        },
        {
            "action_id": "apply_agent_dispatch",
            "province_id": int(sig.get("province_id", province_id)),
            "score": max(0.4, score * 0.95),
            "enabled": True,
            "label": "Dispatch counter agents",
        },
    ]
    label = "Counter-ops day · score %.2f · agents %d" % (score, available_agents)
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "counter_ops_day",
                "label": "Run counter-ops day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("summary", board.get("label", "")))),
        "bbcode": "[color=#c084fc]◈ Counter-ops day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["counter_ops", "agent", "hh"],
    }


# ---------------------------------------------------------------------------
# 5. Multi-province live day
# ---------------------------------------------------------------------------


def multi_province_live_day(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    max_provinces: int = 4,
    country_tag: str = "GER",
    province_id: int = 1,
) -> Dict[str, Any]:
    ids = list(province_ids or [province_id, province_id + 1, province_id + 2, province_id + 3])
    w = dict(weather or {})
    try:
        plan = multi_province_live_plan(
            province_ids=ids,
            weather=w,
            trail=list(trail or []),
            max_provinces=max_provinces,
            country_tag=country_tag,
        )
    except Exception:
        plan = {"empty": True, "score": 0.0, "summary": ""}

    if plan.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(plan.get("score", 0.7))
    apply_queue: List[Dict[str, Any]] = []
    for item in list(plan.get("items", plan.get("top", plan.get("provinces", []))) or [])[:4]:
        if not isinstance(item, dict):
            continue
        pid = int(item.get("province_id", item.get("id", province_id)))
        aid = str(item.get("action_id", item.get("best_action", "apply_supply")))
        if not aid.startswith("apply_") and aid != "refresh_queue":
            aid = "apply_supply"
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": pid,
                "score": float(item.get("score", score)),
                "enabled": True,
                "label": str(item.get("label", "Live #%d" % pid)),
            }
        )
    if not apply_queue:
        for pid in ids[: max(1, max_provinces)]:
            apply_queue.append(
                {
                    "action_id": "apply_supply",
                    "province_id": int(pid),
                    "score": score,
                    "enabled": True,
                    "label": "Live supply #%d" % int(pid),
                }
            )
    label = "Multi-province live day · %s · top %d · score %.2f" % (
        country_tag,
        len(apply_queue),
        score,
    )
    return {
        "plan": plan,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "multi_province_live_day",
                "label": "Run multi-province live day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(plan.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]◎ Multi-province live day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["multi_province", "live", "theater"],
    }


# ---------------------------------------------------------------------------
# 6. Order queue day
# ---------------------------------------------------------------------------


def order_queue_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        board = order_queue_board(weather=w, trail=list(trail or []))
    except Exception:
        board = {"empty": True, "score": 0.0, "items": [], "summary": ""}

    if board.get("empty") and not list(board.get("items") or []):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(board.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = []
    for item in list(board.get("items") or [])[:5]:
        if not isinstance(item, dict):
            continue
        aid = str(item.get("action_id", item.get("order", "apply_supply")))
        # Map domain auto plans to leaf applies
        if not aid.startswith("apply_") and aid not in ("refresh_queue",):
            dom = str(item.get("domain", item.get("kind", ""))).lower()
            if "combat" in dom or "assault" in aid:
                aid = "apply_assault"
            elif "fleet" in dom or "station" in aid or "patrol" in aid:
                aid = "apply_station"
            elif "prod" in dom:
                aid = "apply_production"
            elif "hh" in dom or "agenda" in aid:
                aid = "apply_hh_commit"
            elif "agent" in dom:
                aid = "apply_agent_dispatch"
            else:
                aid = "apply_supply"
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": int(item.get("province_id", province_id)),
                "score": float(item.get("score", score)),
                "enabled": True,
                "label": str(item.get("label", item.get("summary", aid)))[:60],
            }
        )
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "refresh_queue",
                "province_id": province_id,
                "score": 0.4,
                "enabled": True,
            }
        )
    label = "Order queue day · pending %d · score %.2f" % (len(apply_queue), score)
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue[:6],
        "actions": [
            {
                "action_id": "order_queue_day",
                "label": "Run order queue day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("summary", board.get("label", "")))),
        "bbcode": "[color=#5ec8ff]📋 Order queue day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["order_queue", "theater_auto", "execute"],
    }


# ---------------------------------------------------------------------------
# 7. Agent AI board day
# ---------------------------------------------------------------------------


def agent_ai_board_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.4,
    province_id: int = 1,
) -> Dict[str, Any]:
    sig = dict(
        signal
        or {
            "active": True,
            "action_class": "sabotage",
            "influence": 0.68,
            "province_id": province_id,
        }
    )
    try:
        board = agent_ai_board(
            sig, available_agents=available_agents, network_strength=network_strength
        )
    except Exception:
        board = {"empty": True, "score": 0.0, "summary": ""}

    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(board.get("score", 0.6))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_agent_dispatch",
            "province_id": int(sig.get("province_id", province_id)),
            "score": score,
            "enabled": True,
            "label": "Dispatch %s" % str(board.get("best_mission", "agent")),
        },
        {
            "action_id": "apply_counterplay",
            "province_id": province_id,
            "score": score * 0.9,
            "enabled": True,
            "label": "Board counterplay",
        },
    ]
    label = "Agent AI board day · %s · score %.2f" % (
        str(board.get("best_mission", board.get("mission", "?"))),
        score,
    )
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "agent_ai_board_day",
                "label": "Run agent AI board day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("summary", ""))),
        "bbcode": "[color=#c084fc]🕵 Agent AI board day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["agent_ai", "board", "dispatch"],
    }


# ---------------------------------------------------------------------------
# 8. Fleet order day
# ---------------------------------------------------------------------------


def fleet_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    fuel_level: float = 0.55,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        order = fleet_order_execute(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=w,
            province_id=province_id,
        )
    except Exception:
        order = {"empty": True, "score": 0.0, "summary": ""}

    if order.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(order.get("score", 0.5))
    chosen = str(order.get("chosen_order", order.get("best_order", "PATROL")))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Execute fleet %s" % chosen,
        }
    ]
    if fuel_level < 0.65:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel for fleet order",
            }
        )
    label = "Fleet order day · %s · score %.2f · fuel %.0f%%" % (
        chosen,
        score,
        fuel_level * 100.0,
    )
    return {
        "order": order,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "fleet_order_day",
                "label": "Run fleet order day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(order.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]⚓ Fleet order day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet", "order", "execute"],
    }


# ---------------------------------------------------------------------------
# 9. Fleet theater posture day
# ---------------------------------------------------------------------------


def fleet_theater_posture_day(
    province_inputs: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    default_fuel: float = 0.7,
    province_id: int = 1,
) -> Dict[str, Any]:
    inputs = list(
        province_inputs
        or [
            {
                "province_id": province_id,
                "basing_level": "port",
                "fuel_level": default_fuel,
                "zone_relation": "contested",
            },
            {
                "province_id": max(1, province_id + 1),
                "basing_level": "anchorage",
                "fuel_level": max(0.3, default_fuel - 0.15),
                "zone_relation": "hostile",
            },
            {
                "province_id": max(1, province_id + 2),
                "basing_level": "port",
                "fuel_level": default_fuel,
                "zone_relation": "friendly",
            },
        ]
    )
    try:
        plan = plan_fleet_theater_posture(inputs, default_fuel=default_fuel)
    except Exception:
        plan = {"empty": True, "summary": "", "count": 0}

    if plan.get("empty") and int(plan.get("count", 0) or 0) == 0:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    dominant = str(plan.get("dominant_posture", "PATROL"))
    score = _clamp01(0.45 + 0.1 * min(5, int(plan.get("count", 1) or 1)))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Theater posture %s" % dominant,
        }
    ]
    if int(plan.get("refuel_count", 0) or 0) > 0 or default_fuel < 0.6:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.5,
                "enabled": True,
                "label": "Theater refuel",
            }
        )
    label = "Fleet theater posture day · %s · ports %s · score %.2f" % (
        dominant,
        plan.get("count", "?"),
        score,
    )
    return {
        "plan": plan,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "fleet_theater_posture_day",
                "label": "Run fleet theater posture day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(plan.get("summary", plan.get("plain", "")))),
        "bbcode": "[color=#5ec8ff]🚢 Fleet theater posture day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet", "theater", "posture"],
    }


# ---------------------------------------------------------------------------
# 10. Campaign risk day
# ---------------------------------------------------------------------------


def campaign_risk_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {"visibility": 0.7, "precip_intensity": 0.35, "ground_state": "mud", "temp": 8.0}
    )
    try:
        risk = campaign_day_risk(w, month=month)
    except Exception:
        risk = {"empty": True, "summary": "", "risk": 0.5}

    if risk.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    r = _clamp01(float(risk.get("risk", risk.get("score", 0.4)) or 0.4))
    # Higher risk → lower campaign score; feed supply / hold
    score = _clamp01(1.0 - r)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, r),
            "enabled": True,
            "label": "Mitigate campaign risk",
        }
    ]
    if r < 0.4:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Press low-risk window",
            }
        )
    else:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "label": "Hold under risk",
            }
        )
    label = "Campaign risk day · risk %.0f%% · score %.2f · month %d" % (
        r * 100.0,
        score,
        month,
    )
    return {
        "risk_board": risk,
        "risk": r,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "campaign_risk_day",
                "label": "Run campaign risk day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(risk.get("summary", risk.get("label", "")))),
        "bbcode": "[color=#f87171]⚠ Campaign risk day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["campaign", "risk", "weather"],
    }


# ---------------------------------------------------------------------------
# Close / integrity
# ---------------------------------------------------------------------------


THEATER_SURFACE_DAY_IDS: List[str] = [
    "war_cabinet_day",
    "supply_campaign_day",
    "force_supply_day",
    "counter_ops_day",
    "multi_province_live_day",
    "order_queue_day",
    "agent_ai_board_day",
    "fleet_order_day",
    "fleet_theater_posture_day",
    "campaign_risk_day",
]


def theater_surface_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Theater surface integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next30_theater_surface_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {
            "visibility": 0.75,
            "precip_intensity": 0.25,
            "ground_state": "dry",
            "temp": 12.0,
        }
    )
    packages = {
        "war_cabinet_day": war_cabinet_day(weather=w),
        "supply_campaign_day": supply_campaign_day(weather=w),
        "force_supply_day": force_supply_day(weather=w),
        "counter_ops_day": counter_ops_day(),
        "multi_province_live_day": multi_province_live_day(weather=w),
        "order_queue_day": order_queue_day(weather=w),
        "agent_ai_board_day": agent_ai_board_day(),
        "fleet_order_day": fleet_order_day(weather=w),
        "fleet_theater_posture_day": fleet_theater_posture_day(),
        "campaign_risk_day": campaign_risk_day(weather=w),
    }
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = theater_surface_integrity()
    label = "Close next30 theater surface · packages %d/10 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next30 theater surface[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 10,
    }
