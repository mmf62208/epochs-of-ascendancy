"""Logistics day depth: sealane/choke package, leader-formation station day, command strip compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import (  # type: ignore
    basing_fleet_fuel_logistics,
    sealane_joint_health,
    leader_weather_assign,
    sole_mult_integrity,
)
from integrated_theater_ops import choke_sea_weather_package  # type: ignore
from war_economy_day import theater_day_command_strip  # type: ignore
from theater_day_depth import convoy_supply_day_package  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def sealane_choke_logistics_day(
    path_zone_relations: Optional[Sequence[str]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    sea_trade_mult: float = 1.0,
    is_choke: bool = True,
    friendly: bool = True,
    available_fleet: float = 80.0,
    basing_level: str = "port",
    fuel_level: float = 0.65,
) -> Dict[str, Any]:
    """Sealane joint health + choke×sea×wx + basing logistics for day apply."""
    path = list(path_zone_relations or ["friendly", "contested", "hostile"])
    if not path:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "actions": [],
        }
    w = dict(weather or {})
    try:
        sealane = sealane_joint_health(
            path, sea_trade_mult=sea_trade_mult, weather=w, available_fleet=available_fleet
        )
    except TypeError:
        try:
            sealane = sealane_joint_health(path, sea_trade_mult, w, available_fleet)  # type: ignore
        except Exception:
            sealane = {"score": 0.6, "summary": "sealane stub", "empty": False}

    try:
        choke = choke_sea_weather_package(
            weather=w, is_choke=is_choke, friendly=friendly
        )
    except TypeError:
        choke = choke_sea_weather_package(None, w, is_choke, friendly)  # type: ignore

    basing = basing_fleet_fuel_logistics(
        basing_level=basing_level,
        fuel_level=fuel_level,
        available_strength=available_fleet,
        weather=w,
    )
    convoy = convoy_supply_day_package(path, weather=w, available_fleet=available_fleet)

    s_score = _score(sealane, "score")
    c_score = _score(choke, "combined_score", "score", default=0.7)
    if c_score > 2.0:
        c_score = min(1.5, c_score)
    c_score = max(0.1, min(1.5, c_score))
    b_score = _score(basing, "logistics_score", "score", default=0.4)
    if b_score > 2.0:
        b_score = min(1.0, b_score / 10.0 if b_score > 10 else b_score)
    b_score = max(0.05, min(1.2, b_score))

    score = (s_score * 0.4 + min(1.0, c_score) * 0.3 + min(1.0, b_score) * 0.3)
    apply_ready = bool(convoy.get("apply_ready", True)) and fuel_level >= 0.2
    label = "Sealane/choke logistics day · sealane %.2f · choke %.2f · basing %.2f" % (
        s_score,
        min(1.0, c_score),
        min(1.0, b_score),
    )
    return {
        "sealane": sealane,
        "choke": choke,
        "basing": basing,
        "convoy": convoy,
        "score": score,
        "apply_ready": apply_ready,
        "actions": [
            {
                "action_id": "apply_supply",
                "label": "Sustain sealane supply",
                "enabled": apply_ready,
            },
            {
                "action_id": "apply_station",
                "label": "Station for basing/refuel",
                "enabled": fuel_level < 0.55 or basing_level != "none",
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Fleet logistics posture",
                "enabled": True,
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(sealane.get("summary", "")),
                str(choke.get("summary", "")),
                str(basing.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]🌊 Logistics day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sealane", "choke_sea", "basing_logistics", "apply"],
    }


def leader_formation_station_day(
    stations: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    leader_skill: float = 0.55,
    fuel_level: float = 0.6,
    max_stations: int = 3,
) -> Dict[str, Any]:
    """Rank formation station candidates with leader×weather; empty stations → empty."""
    w = dict(weather or {})
    rows_in = [dict(s) for s in list(stations or []) if isinstance(s, dict)]
    if not rows_in:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    leader = leader_weather_assign(leader_skill=leader_skill, weather=w)
    move_eff = _score(leader, "effective_move", default=1.0)

    scored: List[Dict[str, Any]] = []
    for s in rows_in:
        pid = int(s.get("province_id", s.get("id", -1)) or -1)
        if pid < 0:
            continue
        basing = str(s.get("basing_level", s.get("level", "port")))
        fuel = float(s.get("fuel_level", fuel_level) or fuel_level)
        basing_pkg = basing_fleet_fuel_logistics(
            basing_level=basing, fuel_level=fuel, weather=w
        )
        log_s = _score(basing_pkg, "logistics_score", "score", default=0.4)
        if log_s > 2.0:
            log_s = min(1.0, log_s)
        score = log_s * (0.7 + 0.3 * move_eff) * (0.6 + 0.4 * max(0.15, min(1.0, fuel)))
        scored.append(
            {
                "province_id": pid,
                "basing_level": basing,
                "fuel_level": fuel,
                "score": score,
                "action_id": "apply_station",
                "enabled": fuel >= 0.15,
                "basing": basing_pkg,
            }
        )
    scored.sort(key=lambda x: -float(x.get("score", 0.0)))
    apply_queue = scored[: max(0, int(max_stations))]
    if not apply_queue:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    mean = sum(float(q["score"]) for q in apply_queue) / float(len(apply_queue))
    label = "Leader-formation station day · %d stations · leader×wx %.2f · score %.2f" % (
        len(apply_queue),
        move_eff,
        mean,
    )
    return {
        "leader": leader,
        "apply_queue": apply_queue,
        "score": mean,
        "actions": [
            {
                "action_id": "leader_station_day",
                "label": "Apply leader station day",
                "enabled": any(q.get("enabled") for q in apply_queue),
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                "#%d %s fuel %.0f%% score %.2f"
                % (
                    int(q["province_id"]),
                    q.get("basing_level"),
                    float(q.get("fuel_level", 0)) * 100.0,
                    float(q.get("score", 0)),
                )
                for q in apply_queue[:5]
            ]
        ),
        "bbcode": "[color=#5ec8ff]★ Station day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["leader_wx", "basing_logistics", "apply_station"],
    }


def logistics_day_package(
    weather: Optional[Mapping[str, Any]] = None,
    stations: Optional[Sequence[Mapping[str, Any]]] = None,
    path_zone_relations: Optional[Sequence[str]] = None,
    *,
    fuel_level: float = 0.6,
    leader_skill: float = 0.55,
) -> Dict[str, Any]:
    """Compose sealane/choke logistics + leader station day into one apply queue."""
    w = dict(weather or {})
    sealane = sealane_choke_logistics_day(
        path_zone_relations, weather=w, fuel_level=fuel_level
    )
    station = leader_formation_station_day(
        stations
        or [
            {"province_id": 1, "basing_level": "port", "fuel_level": fuel_level},
            {"province_id": 2, "basing_level": "anchorage", "fuel_level": max(0.2, fuel_level - 0.25)},
        ],
        weather=w,
        leader_skill=leader_skill,
        fuel_level=fuel_level,
    )
    strip = theater_day_command_strip(sealane, station, None)

    apply_queue: List[Dict[str, Any]] = []
    for a in list(sealane.get("actions") or []):
        if isinstance(a, dict) and a.get("enabled", True):
            apply_queue.append(
                {
                    "action_id": a.get("action_id"),
                    "province_id": 1,
                    "score": float(sealane.get("score", 0.5)),
                }
            )
    for q in list(station.get("apply_queue") or []):
        if isinstance(q, dict) and q.get("enabled", True):
            apply_queue.append(
                {
                    "action_id": q.get("action_id", "apply_station"),
                    "province_id": q.get("province_id"),
                    "score": float(q.get("score", 0.5)),
                }
            )
    apply_queue = apply_queue[:6]
    score = (
        _score(sealane, "score")
        + (0.0 if station.get("empty") else _score(station, "score"))
    ) / 2.0
    label = "Logistics day · sealane/choke %.2f · stations %d · strip %d" % (
        _score(sealane, "score"),
        len(station.get("apply_queue") or []),
        int(strip.get("count", 0)),
    )
    return {
        "sealane_choke": sealane,
        "station": station,
        "strip": strip,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "logistics_day",
                "label": "Run logistics day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(sealane.get("summary", "")),
                str(station.get("summary", "")),
                str(strip.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]📦 Logistics day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sealane_choke", "leader_station", "strip"],
    }


def logistics_day_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Logistics day integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_logistics_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {"precip_intensity": 0.85, "visibility": 0.3}
    s_c = sealane_choke_logistics_day(weather=clear, fuel_level=0.7)
    s_f = sealane_choke_logistics_day(weather=foul, fuel_level=0.7)
    st = leader_formation_station_day(
        [
            {"province_id": 1, "basing_level": "port", "fuel_level": 0.7},
            {"province_id": 2, "basing_level": "none", "fuel_level": 0.25},
        ],
        weather=clear,
    )
    empty_st = leader_formation_station_day([])
    day = logistics_day_package(weather=weather or clear)
    gate = logistics_day_integrity()
    wx_shift = abs(float(s_c["score"]) - float(s_f["score"]))
    label = "Close logistics day · Δwx %.3f · stations %d · empty_st %s · %s" % (
        wx_shift,
        len(st.get("apply_queue") or []),
        empty_st.get("empty"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "sealane_clear": s_c,
        "sealane_foul": s_f,
        "station": st,
        "empty_station": empty_st,
        "day": day,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
