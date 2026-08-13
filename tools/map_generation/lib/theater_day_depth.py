"""Theater-day depth: readiness board, war cabinet day, convoy/supply day, joint combat timeline.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from integrated_theater_ops import (  # type: ignore
    theater_readiness_board,
    convoy_package_compose,
    war_cabinet_board,
    supply_chain_health,
    assault_readiness_compose,
    fleet_weather_mission_package,
)
from theater_ops_polish import campaign_day_risk  # type: ignore
from day_ops_depth import (  # type: ignore
    estimate_naval_multi_phase,
    day_ops_integrated_plan,
)
from product_depth import multi_phase_combat_ui_product, weather_mult_from  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def joint_combat_timeline(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    fuel_level: float = 0.75,
    visibility: Optional[float] = None,
) -> Dict[str, Any]:
    """Ordered joint land + naval phase timeline for command surface."""
    w = dict(weather or {})
    vis = float(visibility if visibility is not None else w.get("visibility", 1.0) or 1.0)
    land = multi_phase_combat_ui_product(
        attacker_power=attacker_power,
        defender_power=defender_power,
        attacker_supply=attacker_supply,
        weather=w,
    )
    naval = estimate_naval_multi_phase(
        attacker_power=attacker_power * 0.9,
        defender_power=defender_power * 0.85,
        visibility=vis,
        fuel_level=fuel_level,
    )
    timeline: List[Dict[str, Any]] = []
    for row in list(land.get("phase_rows") or []):
        if isinstance(row, dict):
            timeline.append(
                {
                    "domain": "land",
                    "phase": row.get("phase"),
                    "win_chance": row.get("win_chance"),
                    "label": "land/%s" % row.get("label", row.get("phase", "")),
                }
            )
    for row in list(naval.get("phase_rows") or []):
        if isinstance(row, dict):
            timeline.append(
                {
                    "domain": "naval",
                    "phase": row.get("phase"),
                    "win_chance": row.get("win_chance"),
                    "label": "naval/%s" % row.get("label", row.get("phase", "")),
                }
            )
    score = (_score(land, "score") + _score(naval, "score")) / 2.0
    apply_ready = bool(land.get("apply_ready")) or bool(naval.get("apply_ready"))
    label = "Joint combat timeline · land %d · naval %d · score %.2f" % (
        len(land.get("phase_rows") or []),
        len(naval.get("phase_rows") or []),
        score,
    )
    return {
        "land": land,
        "naval": naval,
        "timeline": timeline,
        "phase_count": len(timeline),
        "score": score,
        "apply_ready": apply_ready,
        "actions": [
            {
                "action_id": "apply_assault",
                "label": "Stage land assault",
                "enabled": bool(land.get("apply_ready", True)),
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Apply naval posture",
                "enabled": bool(naval.get("apply_ready", fuel_level >= 0.25)),
            },
        ],
        "summary": label,
        "plain": "\n".join([label] + [str(t.get("label", "")) for t in timeline]),
        "bbcode": "[color=#ff9a6e]⚔⚓ Timeline[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(timeline) == 0,
        "integration": ["land_phases", "naval_phases", "timeline"],
    }


def convoy_supply_day_package(
    path_zone_relations: Optional[Sequence[str]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    available_fleet: float = 80.0,
    sea_mult: float = 1.0,
) -> Dict[str, Any]:
    """Convoy package + supply chain health for day sustain apply."""
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
    convoy = convoy_package_compose(path, available_fleet, 100.0, weather=w)
    supply = supply_chain_health(100.0, sea_mult=sea_mult, weather=w)
    health = _score(supply, "health", "score", default=0.7)
    recommend_wait = bool(convoy.get("recommend_wait", False))
    apply_ready = not recommend_wait and health >= 0.35
    score = health * (0.75 if recommend_wait else 1.0)
    label = "Convoy/supply day · health %.0f%% · wait=%s · score %.2f" % (
        health * 100.0,
        "yes" if recommend_wait else "no",
        score,
    )
    return {
        "convoy": convoy,
        "supply": supply,
        "score": score,
        "apply_ready": apply_ready,
        "recommend_wait": recommend_wait,
        "actions": [
            {
                "action_id": "apply_supply",
                "label": "Sustain supply / convoy route",
                "enabled": apply_ready,
            },
            {
                "action_id": "fleet_autonomy",
                "label": "Escort posture",
                "enabled": True,
            },
        ],
        "summary": label,
        "plain": "\n".join(
            [label, str(convoy.get("summary", "")), str(supply.get("summary", ""))]
        ),
        "bbcode": "[color=#5ec8ff]⛵ Supply day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["convoy", "supply_chain", "apply_supply"],
    }


def theater_day_cabinet_package(
    weather: Optional[Mapping[str, Any]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    path_zone_relations: Optional[Sequence[str]] = None,
    fuel_level: float = 0.7,
) -> Dict[str, Any]:
    """Theater readiness + war cabinet + convoy/supply for one command day."""
    w = dict(weather or {})
    fleet_pkg = fleet_weather_mission_package(
        mission="patrol",
        available_strength=100.0 * max(0.2, float(fuel_level)),
        zone_relation="contested",
        weather=w,
    )
    assault = assault_readiness_compose(
        targets=[{"id": 1, "power": 40.0}],
        attacker_power=100.0,
        attacker_supply=0.85,
        weather=w,
    )
    try:
        day_risk = campaign_day_risk(weather=w)
    except TypeError:
        try:
            day_risk = campaign_day_risk(w)  # type: ignore
        except Exception:
            day_risk = {"summary": "day risk", "score": 0.5, "empty": False}

    readiness = theater_readiness_board(fleet_pkg, assault, day_risk)
    cabinet = war_cabinet_board(
        weather=w, signal=signal, trail=trail or []
    )
    convoy = convoy_supply_day_package(path_zone_relations, weather=w)
    timeline = joint_combat_timeline(weather=w, fuel_level=fuel_level)

    # Empty only if readiness empty AND no trail/signal for cabinet context
    if readiness.get("empty") and not (signal or trail):
        # still allow convoy/timeline surfaces
        pass

    score = (
        (0.5 if readiness.get("empty") else 0.7)
        + _score(cabinet, "score", default=0.5) * 0.0  # cabinet may lack score
        + _score(convoy, "score")
        + _score(timeline, "score")
    ) / 3.0
    # better score mix
    r_score = 0.3 if readiness.get("empty") else 0.7
    score = (r_score + _score(convoy, "score") + _score(timeline, "score")) / 3.0

    apply_queue: List[Dict[str, Any]] = []
    if convoy.get("apply_ready"):
        apply_queue.append(
            {"action_id": "apply_supply", "province_id": 1, "score": _score(convoy, "score")}
        )
    if timeline.get("apply_ready"):
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "province_id": 1,
                "score": _score(timeline, "score"),
            }
        )
    if trail:
        apply_queue.append(
            {"action_id": "apply_hh_commit", "province_id": -1, "score": 0.45}
        )
    if signal and bool(dict(signal).get("active", True)):
        apply_queue.append(
            {
                "action_id": "apply_agent_dispatch",
                "province_id": int(dict(signal).get("province_id", 1) or 1),
                "score": 0.5,
            }
        )

    label = "Theater day cabinet · ready=%s · convoy %.2f · timeline %.2f" % (
        "no" if readiness.get("empty") else "yes",
        _score(convoy, "score"),
        _score(timeline, "score"),
    )
    return {
        "readiness": readiness,
        "cabinet": cabinet,
        "convoy": convoy,
        "timeline": timeline,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "theater_day_cabinet",
                "label": "Run theater day cabinet",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(readiness.get("summary", "")),
                str(cabinet.get("summary", "")),
                str(convoy.get("summary", "")),
                str(timeline.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]🗺 Theater day[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["readiness", "war_cabinet", "convoy_supply", "timeline"],
    }


def theater_day_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Theater day integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_theater_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {"precip_intensity": 0.9, "visibility": 0.25, "ground_state": "mud"}
    t_clear = theater_day_cabinet_package(weather=clear, trail=[{"class": "sabotage"}])
    t_foul = theater_day_cabinet_package(weather=foul, trail=[{"class": "sabotage"}])
    tl_c = joint_combat_timeline(weather=clear)
    tl_f = joint_combat_timeline(weather=foul)
    convoy_c = convoy_supply_day_package(weather=clear)
    convoy_f = convoy_supply_day_package(weather=foul)
    day = day_ops_integrated_plan(
        theaters=[{"theater_id": "A", "province_ids": [1], "fuel_level": 0.7}],
        signals=[
            {
                "active": True,
                "action_class": "sabotage",
                "influence": 0.6,
                "province_id": 1,
            }
        ],
        trail=[{"class": "sabotage"}],
        weather=weather or clear,
    )
    gate = theater_day_integrity()
    wx_shift = abs(float(tl_c["score"]) - float(tl_f["score"]))
    label = "Close theater day · timeline Δwx %.3f · convoy_wait foul=%s · %s" % (
        wx_shift,
        convoy_f.get("recommend_wait"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "cabinet_clear": t_clear,
        "cabinet_foul": t_foul,
        "timeline_clear": tl_c,
        "timeline_foul": tl_f,
        "convoy_clear": convoy_c,
        "convoy_foul": convoy_f,
        "day_ops": day,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
