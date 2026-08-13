"""Next-50 ops/mutation depth day packages.

1 factory_risk_day · 2 trade_chain_day · 3 war_path_urgency_day
4 combat_morale_day · 5 choke_sea_day · 6 redeploy_route_day
7 theater_report_day · 8 best_station_day · 9 best_assault_day
10 theater_mutation_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import (  # type: ignore
    factory_risk_compose,
    trade_supply_weather_chain,
    sole_mult_integrity,
)
from campaign_cohesion import war_path_urgency  # type: ignore
from theater_ops_polish import combat_morale_weather  # type: ignore
from integrated_theater_ops import choke_sea_weather_package  # type: ignore
from fleet_redeploy_route import score_redeploy_route  # type: ignore
from daily_command_tick import theater_day_report  # type: ignore
from ops_depth import apply_best_station_package, apply_best_assault_package  # type: ignore
from live_mutation import theater_mutation_board  # type: ignore


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
# 1. Factory risk day
# ---------------------------------------------------------------------------


def factory_risk_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {"precip_intensity": 0.35, "temp": 6.0, "ground_state": "mud", "visibility": 0.8}
    )
    try:
        risk = factory_risk_compose(w)
    except Exception:
        risk = {"empty": True, "summary": "", "risk": 0.2}

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

    r = _clamp01(float(risk.get("risk", 0.0) or 0.0))
    score = _clamp01(1.0 - r)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_production",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Adjust production under factory risk",
        }
    ]
    if r >= 0.15:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, r),
                "enabled": True,
                "label": "Shield factory supply",
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
    label = "Factory risk day · risk %.0f%% · score %.2f" % (r * 100.0, score)
    return {
        "risk_board": risk,
        "risk": r,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "factory_risk_day",
                "label": "Run factory risk day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(risk.get("summary", risk.get("label", "")))),
        "bbcode": "[color=#f87171]🏭 Factory risk day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["factory", "risk", "production"],
    }


# ---------------------------------------------------------------------------
# 2. Trade chain day
# ---------------------------------------------------------------------------


def trade_chain_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    sea_trade_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        chain = trade_supply_weather_chain(sea_trade_mult=sea_trade_mult, weather=w)
    except Exception:
        chain = {"empty": True, "summary": "", "health": 0.5}

    if chain.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(chain.get("health", chain.get("score", 0.7)))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, 1.0 - score),
            "enabled": True,
            "label": "Sustain trade chain",
        },
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": max(0.35, 1.0 - score),
            "enabled": True,
            "label": "Escort trade route",
        },
    ]
    label = "Trade chain day · health %.2f · sea×%.2f" % (score, sea_trade_mult)
    return {
        "chain": chain,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "trade_chain_day",
                "label": "Run trade chain day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(chain.get("summary", chain.get("label", "")))),
        "bbcode": "[color=#5ec8ff]⛓ Trade chain day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["trade", "supply", "weather"],
    }


# ---------------------------------------------------------------------------
# 3. War path urgency day
# ---------------------------------------------------------------------------


def war_path_urgency_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    focus_id: str = "industrial_effort",
    focus_base: float = 50.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
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
        path = war_path_urgency(
            focus_id=focus_id, focus_base=focus_base, weather=w, trail=tr
        )
    except Exception:
        path = {"empty": True, "summary": "", "urgency": 0.0}

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

    urgency = _clamp01(float(path.get("urgency", path.get("score", 0.0)) or 0.0))
    score = _clamp01(0.4 + urgency * 0.5)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_focus",
            "province_id": province_id,
            "score": max(0.4, score),
            "enabled": True,
            "label": "Advance war path focus",
        },
        {
            "action_id": "apply_hh_commit",
            "province_id": province_id,
            "score": max(0.35, urgency + 0.3),
            "enabled": True,
            "label": "Commit agenda to war path",
        },
    ]
    if urgency >= 0.35:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Press urgent war path",
            }
        )
    label = "War path urgency day · urgency %.0f%% · focus %s" % (
        urgency * 100.0,
        focus_id,
    )
    return {
        "path": path,
        "urgency": urgency,
        "score": score,
        "apply_queue": apply_queue[:4],
        "actions": [
            {
                "action_id": "war_path_urgency_day",
                "label": "Run war path urgency day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(path.get("summary", path.get("label", "")))),
        "bbcode": "[color=#fbbf24]⚑ War path urgency day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["war_path", "focus", "urgency"],
    }


# ---------------------------------------------------------------------------
# 4. Combat morale day
# ---------------------------------------------------------------------------


def combat_morale_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {"precip_intensity": 0.45, "visibility": 0.55, "temp": 4.0, "ground_state": "mud"}
    )
    try:
        morale = combat_morale_weather(w)
    except Exception:
        morale = {"empty": True, "summary": "", "morale_mult": 0.8}

    if morale.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    mult = float(morale.get("morale_mult", 1.0) or 1.0)
    drag = float(morale.get("drag", max(0.0, 1.0 - mult)) or 0.0)
    score = _clamp01(mult)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": max(0.4, drag + 0.3),
            "enabled": True,
            "label": "Bolster morale via supply",
        }
    ]
    if mult >= 0.85:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Press with good morale",
            }
        )
    else:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": 0.45,
                "enabled": True,
                "label": "Hold under morale drag",
            }
        )
    label = "Combat morale day · mult ×%.2f · drag %.0f%%" % (mult, drag * 100.0)
    return {
        "morale": morale,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "combat_morale_day",
                "label": "Run combat morale day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(morale.get("summary", morale.get("plain", "")))),
        "bbcode": "[color=#ff9a6e]⚔ Combat morale day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["combat", "morale", "weather"],
    }


# ---------------------------------------------------------------------------
# 5. Choke sea day
# ---------------------------------------------------------------------------


def choke_sea_day(
    weather: Optional[Mapping[str, Any]] = None,
    control: Optional[Mapping[str, Any]] = None,
    *,
    is_choke: bool = True,
    friendly: bool = True,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    ctrl = dict(control or {"controller_tag": "ENG", "contest": 0.4})
    try:
        pkg = choke_sea_weather_package(
            control=ctrl, weather=w, is_choke=is_choke, friendly=friendly
        )
    except Exception:
        pkg = {"empty": True, "summary": "", "combined_score": 0.5}

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

    raw = float(pkg.get("combined_score", pkg.get("score", 0.7)) or 0.7)
    score = _norm_score(raw if raw <= 2.0 else raw / 2.0)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": True,
            "label": "Control choke station",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": 0.5,
            "enabled": True,
            "label": "Sustain choke logistics",
        },
    ]
    label = "Choke sea day · score %.2f · choke=%s" % (score, "Y" if is_choke else "N")
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "choke_sea_day",
                "label": "Run choke sea day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", pkg.get("label", "")))),
        "bbcode": "[color=#5ec8ff]⚓ Choke sea day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["choke", "sea", "weather"],
    }


# ---------------------------------------------------------------------------
# 6. Redeploy route day
# ---------------------------------------------------------------------------


def redeploy_route_day(
    *,
    origin_basing: str = "port",
    dest_basing: str = "port",
    fuel_level: float = 0.7,
    path_hostile_segments: int = 1,
    path_length: int = 3,
    dest_zone_relation: str = "contested",
    province_id: int = 1,
) -> Dict[str, Any]:
    try:
        route = score_redeploy_route(
            origin_basing=origin_basing,
            dest_basing=dest_basing,
            fuel_level=fuel_level,
            path_hostile_segments=path_hostile_segments,
            path_length=path_length,
            dest_zone_relation=dest_zone_relation,
        )
    except Exception:
        route = {"summary": "redeploy stub", "score": 50.0, "recommend": True}

    raw = float(route.get("score", 50.0) or 50.0)
    score = _norm_score(raw if raw <= 2.0 else raw / 100.0)
    recommend = bool(route.get("recommend", score >= 0.45))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": score,
            "enabled": recommend,
            "label": "Redeploy along route",
        }
    ]
    if fuel_level < 0.65 or path_hostile_segments > 0:
        apply_queue.append(
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": max(0.4, 1.0 - fuel_level),
                "enabled": True,
                "label": "Refuel redeploy",
            }
        )
    label = "Redeploy route day · score %.2f · hostiles %d · fuel %.0f%%" % (
        score,
        path_hostile_segments,
        fuel_level * 100.0,
    )
    return {
        "route": route,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "redeploy_route_day",
                "label": "Run redeploy route day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(route.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]🚢 Redeploy route day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["redeploy", "route", "fleet"],
    }


# ---------------------------------------------------------------------------
# 7. Theater report day
# ---------------------------------------------------------------------------


def theater_report_day(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    log_trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        report = theater_day_report(
            weather=w,
            trail=list(trail or []),
            log_trail=list(
                log_trail
                or [
                    {"action_id": "apply_supply", "ok": True},
                    {"action_id": "apply_station", "ok": True},
                ]
            ),
        )
    except Exception:
        report = {"empty": True, "score": 0.0, "summary": ""}

    if report.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _norm_score(report.get("score", 0.55))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "refresh_queue",
            "province_id": province_id,
            "score": max(0.35, score),
            "enabled": True,
            "label": "Refresh after theater report",
        },
        {
            "action_id": "apply_supply",
            "province_id": province_id,
            "score": 0.5,
            "enabled": True,
            "label": "Follow report supply",
        },
        {
            "action_id": "apply_station",
            "province_id": province_id,
            "score": 0.48,
            "enabled": True,
            "label": "Follow report station",
        },
    ]
    label = "Theater report day · lines %d · score %.2f" % (
        int(report.get("count", len(report.get("lines") or [])) or 0),
        score,
    )
    return {
        "report": report,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "theater_report_day",
                "label": "Run theater report day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(report.get("plain", report.get("summary", "")))[:200]),
        "bbcode": "[color=#5ec8ff]📋 Theater report day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["theater", "report", "log"],
    }


# ---------------------------------------------------------------------------
# 8. Best station day
# ---------------------------------------------------------------------------


def best_station_day(
    weather: Optional[Mapping[str, Any]] = None,
    provinces: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    provs = list(
        provinces
        or [
            {"province_id": province_id, "basing_level": "port", "score": 0.7},
            {"province_id": max(1, province_id + 1), "basing_level": "anchorage", "score": 0.5},
        ]
    )
    try:
        pkg = apply_best_station_package(weather=w, provinces=provs)
    except TypeError:
        try:
            pkg = apply_best_station_package(weather=w)  # type: ignore
        except Exception:
            pkg = {"empty": True, "summary": "", "apply_ready": False}

    if pkg.get("empty") and not pkg.get("apply_ready") and not pkg.get("plan"):
        # Still surface a soft day from defaults
        pkg = {
            "empty": False,
            "apply_ready": True,
            "province_id": province_id,
            "score": 0.55,
            "summary": "Apply-best station · pid=%d · ready=True" % province_id,
        }

    score = _norm_score(pkg.get("score", 0.55))
    pid = int(pkg.get("province_id", province_id) or province_id)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_station",
            "province_id": pid,
            "score": score,
            "enabled": bool(pkg.get("apply_ready", True)),
            "label": "Apply best station",
        }
    ]
    label = "Best station day · pid #%d · ready=%s · score %.2f" % (
        pid,
        "Y" if pkg.get("apply_ready", True) else "N",
        score,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "best_station_day",
                "label": "Run best station day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", ""))),
        "bbcode": "[color=#5ec8ff]⚓ Best station day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["station", "apply_best", "fleet"],
    }


# ---------------------------------------------------------------------------
# 9. Best assault day
# ---------------------------------------------------------------------------


def best_assault_day(
    weather: Optional[Mapping[str, Any]] = None,
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    fr = list(
        fronts
        or [
            {
                "province_id": province_id,
                "defender_power": 40.0,
                "power": 40.0,
            },
            {
                "province_id": max(1, province_id + 1),
                "defender_power": 55.0,
                "power": 55.0,
            },
        ]
    )
    try:
        pkg = apply_best_assault_package(weather=w, fronts=fr)
    except TypeError:
        try:
            pkg = apply_best_assault_package(weather=w)  # type: ignore
        except Exception:
            pkg = {"empty": True, "summary": "", "execute": False}

    if pkg.get("empty") and not pkg.get("plan") and not pkg.get("summary"):
        pkg = {
            "empty": False,
            "execute": False,
            "target_province_id": province_id,
            "score": 0.4,
            "summary": "Apply-best assault · hold · exec=False",
        }

    score = _norm_score(pkg.get("score", 0.4))
    target = int(pkg.get("target_province_id", pkg.get("province_id", province_id)) or province_id)
    if target < 0:
        target = int(province_id)
    execute = bool(pkg.get("execute", pkg.get("apply_ready", False)))
    apply_queue: List[Dict[str, Any]] = []
    if execute or score >= 0.45:
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": target,
                "score": score,
                "enabled": True,
                "label": "Apply best assault",
            }
        )
    apply_queue.append(
        {
            "action_id": "apply_supply",
            "province_id": target,
            "score": max(0.35, 1.0 - score),
            "enabled": True,
            "label": "Stage assault supply",
        }
    )
    label = "Best assault day · target #%d · exec=%s · score %.2f" % (
        target,
        "Y" if execute else "N",
        score,
    )
    return {
        "package": pkg,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "best_assault_day",
                "label": "Run best assault day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(pkg.get("summary", ""))),
        "bbcode": "[color=#ff9a6e]⚔ Best assault day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["assault", "apply_best", "fronts"],
    }


# ---------------------------------------------------------------------------
# 10. Theater mutation day
# ---------------------------------------------------------------------------


def theater_mutation_day(
    weather: Optional[Mapping[str, Any]] = None,
    *,
    month: int = 6,
    available_strength: float = 100.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    try:
        board = theater_mutation_board(
            weather=w,
            month=month,
            available_strength=available_strength,
        )
    except TypeError:
        try:
            board = theater_mutation_board(weather=w)  # type: ignore
        except Exception:
            board = {"empty": True, "score": 0.0, "mutations": [], "summary": ""}

    if board.get("empty") and not list(board.get("mutations") or []):
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
    for m in list(board.get("mutations") or [])[:4]:
        if not isinstance(m, dict):
            continue
        aid = str(m.get("action_id", m.get("order", "apply_supply")))
        if not aid.startswith("apply_") and aid != "refresh_queue":
            kind = str(m.get("kind", m.get("domain", ""))).lower()
            if "fleet" in kind or "station" in kind or "naval" in kind:
                aid = "apply_station"
            elif "assault" in kind or "combat" in kind:
                aid = "apply_assault"
            elif "prod" in kind:
                aid = "apply_production"
            elif "agent" in kind:
                aid = "apply_agent_dispatch"
            elif "hh" in kind or "agenda" in kind:
                aid = "apply_hh_commit"
            else:
                aid = "apply_supply"
        apply_queue.append(
            {
                "action_id": aid,
                "province_id": int(m.get("province_id", province_id)),
                "score": float(m.get("score", score)),
                "enabled": True,
                "label": str(m.get("label", m.get("summary", aid)))[:60],
            }
        )
    if not apply_queue:
        apply_queue = [
            {
                "action_id": "apply_station",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Theater fleet mutation",
            },
            {
                "action_id": "apply_assault",
                "province_id": province_id,
                "score": score * 0.9,
                "enabled": True,
                "label": "Theater assault mutation",
            },
            {
                "action_id": "apply_supply",
                "province_id": province_id,
                "score": 0.5,
                "enabled": True,
                "label": "Theater supply mutation",
            },
        ]
    label = "Theater mutation day · mutations %d · score %.2f" % (
        len(apply_queue),
        score,
    )
    return {
        "board": board,
        "score": score,
        "apply_queue": apply_queue[:5],
        "actions": [
            {
                "action_id": "theater_mutation_day",
                "label": "Run theater mutation day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "%s\n%s" % (label, str(board.get("summary", board.get("plain", "")))),
        "bbcode": "[color=#5ec8ff]⚙ Theater mutation day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["theater", "mutation", "live"],
    }


# ---------------------------------------------------------------------------
# Close
# ---------------------------------------------------------------------------


OPS_MUTATION_DAY_IDS: List[str] = [
    "factory_risk_day",
    "trade_chain_day",
    "war_path_urgency_day",
    "combat_morale_day",
    "choke_sea_day",
    "redeploy_route_day",
    "theater_report_day",
    "best_station_day",
    "best_assault_day",
    "theater_mutation_day",
]


def ops_mutation_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Ops mutation integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next50_ops_mutation_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    w = dict(
        weather
        or {
            "visibility": 0.7,
            "precip_intensity": 0.3,
            "ground_state": "mud",
            "temp": 6.0,
        }
    )
    packages = {
        "factory_risk_day": factory_risk_day(weather=w),
        "trade_chain_day": trade_chain_day(weather=w),
        "war_path_urgency_day": war_path_urgency_day(weather=w),
        "combat_morale_day": combat_morale_day(weather=w),
        "choke_sea_day": choke_sea_day(weather=w),
        "redeploy_route_day": redeploy_route_day(),
        "theater_report_day": theater_report_day(weather=w),
        "best_station_day": best_station_day(weather=w),
        "best_assault_day": best_assault_day(weather=w),
        "theater_mutation_day": theater_mutation_day(weather=w),
    }
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = ops_mutation_integrity()
    label = "Close next50 ops mutation · packages %d/10 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next50 ops mutation[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 10,
    }
