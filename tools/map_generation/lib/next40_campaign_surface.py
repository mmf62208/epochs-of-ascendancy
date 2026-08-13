"""Next-40 campaign surface day packages.

1 sealane_health_day · 2 convoy_package_day · 3 theater_campaign_day
4 production_risk_day · 5 leader_campaign_day · 6 basing_repair_day
7 focus_order_day · 8 naval_order_day · 9 air_land_order_day
10 theater_order_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_cohesion import (  # type: ignore
    sealane_joint_health,
    theater_campaign_strip,
    production_campaign_risk,
    leader_campaign_assign,
)
from gameplay_loops import (  # type: ignore
    convoy_package_compose,
    basing_repair_weather_loop,
    sole_mult_integrity,
)
from campaign_execution import (  # type: ignore
    focus_order_path,
    naval_order_package,
    air_land_order_package,
    theater_order_board,
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


# ---------------------------------------------------------------------------
# 1. Sealane health day
# ---------------------------------------------------------------------------


def sealane_health_day(
    path_zone_relations: Optional[Sequence[str]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    sea_trade_mult: float = 1.0,
    available_fleet: float = 60.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    zones = list(path_zone_relations or ["contested", "hostile", "friendly", "contested"])
    w = dict(weather or {})
    try:
        health = sealane_joint_health(
            zones,
            sea_trade_mult=sea_trade_mult,
            weather=w,
            available_fleet=available_fleet,
        )
    except TypeError:
        try:
            health = sealane_joint_health(zones, sea_trade_mult, w, available_fleet)  # type: ignore
        except Exception:
            health = {"empty": True, "score": 0.0, "summary": ""}

    if health.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(health.get("score", health.get("health", 0.55)))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, 1.0 - score),
            "enabled": True,
            "label": "Sustain sealane",
        },
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.4, 1.0 - score),
            "enabled": True,
            "label": "Escort sealane",
        },
    ]
    label = "Sealane health day · score %.2f · fleet %.0f" % (score, available_fleet)
    return {
        "health": health,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "sealane_health_day",
                "label": "Run sealane health day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(health.get("summary", health.get("label", "")))),
        "bbcode": "[color=#5ec8ff]🌊 Sealane health day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["sealane", "trade", "escort"],
    }


# ---------------------------------------------------------------------------
# 2. Convoy package day
# ---------------------------------------------------------------------------


def convoy_package_day(
    path_zone_relations: Optional[Sequence[str]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    available_fleet_strength: float = 70.0,
    cargo_value: float = 100.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    zones = list(path_zone_relations or ["contested", "hostile", "friendly"])
    w = dict(weather or {})
    try:
        pkg = convoy_package_compose(
            zones,
            available_fleet_strength=available_fleet_strength,
            cargo_value=cargo_value,
            weather=w,
        )
    except TypeError:
        try:
            pkg = convoy_package_compose(zones, available_fleet_strength)  # type: ignore
        except Exception:
            pkg = {"empty": True, "summary": ""}

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

    recommend_wait = bool(pkg.get("recommend_wait", False))
    score = 0.55 if not recommend_wait else 0.4
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": 0.55 if not recommend_wait else 0.65,
            "enabled": True,
            "label": "Assign convoy escort",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": 0.5,
            "enabled": True,
            "label": "Sustain convoy cargo",
        },
    ]
    label = "Convoy package day · wait=%s · fleet %.0f" % (
        "Y" if recommend_wait else "N",
        available_fleet_strength,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "convoy_package_day",
                "label": "Run convoy package day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", pkg.get("label", "")))),
        "bbcode": "[color=#5ec8ff]🛡 Convoy package day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["convoy", "escort", "weather_window"],
    }


# ---------------------------------------------------------------------------
# 3. Theater campaign day
# ---------------------------------------------------------------------------


def theater_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    basing_level: str = "port",
    fuel_level: float = 0.6,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        strip = theater_campaign_strip(
            weather=w,
            month=month,
            available_strength=available_strength,
            zone_relation=zone_relation,
            basing_level=basing_level,
            fuel_level=fuel_level,
        )
    except Exception:
        strip = {"empty": True, "score": 0.0, "summary": ""}

    if strip.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(strip.get("score", 0.6))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Theater fleet station",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, 1.0 - fuel_level),
            "enabled": True,
            "label": "Theater convoy feed",
        },
    ]
    if score >= 0.55:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Theater joint press",
            }
        )
    label = "Theater campaign day · score %.2f · fuel %.0f%%" % (score, fuel_level * 100.0)
    return {
        "strip": strip,
        "score": score,
        "apply_queue": apply_queue[:5],
        "actions": [
            {
                "action_id": "theater_campaign_day",
                "label": "Run theater campaign day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(strip.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]🎯 Theater campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["theater", "readiness", "convoy", "joint"],
    }


# ---------------------------------------------------------------------------
# 4. Production risk day
# ---------------------------------------------------------------------------


def production_risk_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    base_output: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {"precip_intensity": 0.25, "temp": 8.0, "ground_state": "dry"})
    try:
        risk = production_campaign_risk(weather=w, base_output=base_output)
    except Exception:
        risk = {"empty": True, "score": 0.0, "summary": ""}

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

    r = _clamp01(float(risk.get("risk", risk.get("score", 0.0)) or 0.0))
    score = _clamp01(1.0 - r)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_production",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Set production under risk",
        }
    ]
    if r >= 0.2:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, r),
                "enabled": True,
                "label": "Shield factories",
            }
        )
    else:
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "label": "Hold industrial focus",
            }
        )
    label = "Production risk day · risk %.0f%% · score %.2f" % (r * 100.0, score)
    return {
        "risk_board": risk,
        "risk": r,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "production_risk_day",
                "label": "Run production risk day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(risk.get("summary", ""))),
        "bbcode": "[color=#f87171]🏭 Production risk day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["production", "risk", "oob"],
    }


# ---------------------------------------------------------------------------
# 5. Leader campaign day
# ---------------------------------------------------------------------------


def leader_campaign_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    leader_skill: float = 0.65,
    armored: bool = False,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        assign = leader_campaign_assign(
            leader_skill=leader_skill, weather=w, armored=armored
        )
    except Exception:
        assign = {"empty": True, "score": 0.0, "summary": ""}

    if assign.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(assign.get("score", leader_skill))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Station leader formation",
        }
    ]
    if score >= 0.55:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Leader-led press",
            }
        )
    else:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "label": "Support leader ops",
            }
        )
    label = "Leader campaign day · skill×wx %.2f · armored=%s" % (
        score,
        "Y" if armored else "N",
    )
    return {
        "assign": assign,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "leader_campaign_day",
                "label": "Run leader campaign day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(assign.get("summary", ""))),
        "bbcode": "[color=#fbbf24]★ Leader campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["leader", "assign", "weather"],
    }


# ---------------------------------------------------------------------------
# 6. Basing repair day
# ---------------------------------------------------------------------------


def basing_repair_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    basing_level: str = "port",
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {"precip_intensity": 0.4, "visibility": 0.7})
    try:
        repair = basing_repair_weather_loop(basing_level=basing_level, weather=w)
    except Exception:
        repair = {"empty": True, "summary": ""}

    if repair.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    rate = float(repair.get("repair_org_rate", repair.get("base_repair_org_rate", 0.03)) or 0.03)
    score = _clamp01(0.35 + rate * 8.0)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Dock for basing repair",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": 0.5,
            "enabled": True,
            "label": "Refuel at base",
        },
    ]
    label = "Basing repair day · %s · org %.3f/d · score %.2f" % (
        basing_level,
        rate,
        score,
    )
    return {
        "repair": repair,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "basing_repair_day",
                "label": "Run basing repair day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(repair.get("summary", repair.get("label", "")))),
        "bbcode": "[color=#5ec8ff]🔧 Basing repair day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["basing", "repair", "weather"],
    }


# ---------------------------------------------------------------------------
# 7. Focus order day
# ---------------------------------------------------------------------------


def focus_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        path = focus_order_path(
            weather=w,
            focus_id=focus_id,
            focus_base=focus_base,
            trail=list(trail or []),
        )
    except Exception:
        path = {"empty": True, "score": 0.0, "summary": ""}

    if path.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(path.get("score", 0.5))
    action = str(path.get("action", path.get("order", "HOLD")))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_focus",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Focus %s · %s" % (focus_id, action),
        },
        {
            "action_id": "apply_hh_commit",
            "province_id": province_id,
            "score": max(0.35, score * 0.9),
            "enabled": True,
            "label": "Align agenda with focus",
        },
    ]
    label = "Focus order day · %s · %s · score %.2f" % (focus_id, action, score)
    return {
        "path": path,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "focus_order_day",
                "label": "Run focus order day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(path.get("summary", ""))),
        "bbcode": "[color=#fbbf24]◎ Focus order day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["focus", "order", "war_path"],
    }


# ---------------------------------------------------------------------------
# 8. Naval order day
# ---------------------------------------------------------------------------


def naval_order_day(
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
        pkg = naval_order_package(
            basing_level=basing_level,
            fuel_level=fuel_level,
            available_strength=available_strength,
            zone_relation=zone_relation,
            weather=w,
            province_id=province_id,
        )
    except Exception:
        pkg = {"empty": True, "score": 0.0, "summary": ""}

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
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Execute naval order",
        }
    ]
    if fuel_level < 0.65:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel naval package",
            }
        )
    label = "Naval order day · score %.2f · fuel %.0f%% · %s" % (
        score,
        fuel_level * 100.0,
        basing_level,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "naval_order_day",
                "label": "Run naval order day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]⚓ Naval order day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["naval", "order", "fleet", "basing"],
    }


# ---------------------------------------------------------------------------
# 9. Air-land order day
# ---------------------------------------------------------------------------


def air_land_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    attacker_power: float = 100.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        pkg = air_land_order_package(
            weather=w,
            month=month,
            attacker_power=attacker_power,
            province_id=province_id,
        )
    except Exception:
        pkg = {"empty": True, "score": 0.0, "summary": ""}

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
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_assault",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Stage air-land order",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.35, 1.0 - score),
            "enabled": True,
            "label": "Feed air-land package",
        },
    ]
    label = "Air-land order day · score %.2f · power %.0f" % (score, attacker_power)
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "air_land_order_day",
                "label": "Run air-land order day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", ""))),
        "bbcode": "[color=#ff9a6e]✈ Air-land order day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["air_land", "order", "assault"],
    }


# ---------------------------------------------------------------------------
# 10. Theater order day
# ---------------------------------------------------------------------------


def theater_order_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    available_strength: float = 100.0,
    zone_relation: str = "contested",
    basing_level: str = "port",
    fuel_level: float = 0.55,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        board = theater_order_board(
            weather=w,
            month=month,
            available_strength=available_strength,
            zone_relation=zone_relation,
            basing_level=basing_level,
            fuel_level=fuel_level,
            province_id=province_id,
        )
    except Exception:
        board = {"empty": True, "score": 0.0, "orders": [], "summary": ""}

    if board.get("empty") and not list(board.get("orders") or []):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(board.get("score", 0.5))
    apply_queue: List[Dict[str, Any]] = []
    for o in list(board.get("orders") or [])[:4]:
        if not isinstance(o, dict):
            continue
        aid = str(o.get("action_id", o.get("order", "apply_supply")))
        if not aid.startswith("apply_") and aid != "refresh_queue":
            kind = str(o.get("kind", o.get("domain", ""))).lower()
            if "fleet" in kind or "naval" in kind:
                aid = "apply_station"
            elif "combat" in kind or "assault" in kind or "air" in kind:
                aid = "apply_assault"
            elif "prod" in kind:
                aid = "apply_production"
            else:
                aid = "apply_supply"
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": int(o.get("province_id", province_id)),
                "score": float(o.get("score", score)),
                "enabled": True,
                "label": str(o.get("label", o.get("summary", aid)))[:60],
            }
        )
    if not apply_queue:
        apply_queue = [
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Theater fleet order",
            },
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score * 0.95,
                "enabled": True,
                "label": "Theater combat order",
            },
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.5,
                "enabled": True,
                "label": "Theater supply order",
            },
        ]
    label = "Theater order day · orders %d · score %.2f" % (len(apply_queue), score)
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue[:5],
        "actions": [
            {
                "action_id": "theater_order_day",
                "label": "Run theater order day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("summary", board.get("plain", "")))),
        "bbcode": "[color=#5ec8ff]📋 Theater order day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["theater", "orders", "fleet", "combat", "supply"],
    }


# ---------------------------------------------------------------------------
# Close
# ---------------------------------------------------------------------------


CAMPAIGN_SURFACE_DAY_IDS: List[str] = [
    "sealane_health_day",
    "convoy_package_day",
    "theater_campaign_day",
    "production_risk_day",
    "leader_campaign_day",
    "basing_repair_day",
    "focus_order_day",
    "naval_order_day",
    "air_land_order_day",
    "theater_order_day",
]


def campaign_surface_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Campaign surface integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next40_campaign_surface_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {
            "visibility": 0.8,
            "precip_intensity": 0.2,
            "ground_state": "dry",
            "temp": 12.0,
        }
    )
    packages = {
        "sealane_health_day": sealane_health_day(weather=w),
        "convoy_package_day": convoy_package_day(weather=w),
        "theater_campaign_day": theater_campaign_day(weather=w),
        "production_risk_day": production_risk_day(weather=w),
        "leader_campaign_day": leader_campaign_day(weather=w),
        "basing_repair_day": basing_repair_day(weather=w),
        "focus_order_day": focus_order_day(weather=w),
        "naval_order_day": naval_order_day(weather=w),
        "air_land_order_day": air_land_order_day(weather=w),
        "theater_order_day": theater_order_day(weather=w),
    }
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = campaign_surface_integrity()
    label = "Close next40 campaign surface · packages %d/10 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next40 campaign surface[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 10,
    }
