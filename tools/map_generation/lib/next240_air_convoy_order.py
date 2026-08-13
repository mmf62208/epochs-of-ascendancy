"""Next-240 air-land multi-domain · convoy/sealane logistics · order→map-effect→feedback (20).

A) Air-land / multi-domain (1–7)
B) Convoy / sealane wartime logistics (8–14)
C) Order execute / map-effect / next-day feedback (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from integrated_theater_ops import air_ops_package, convoy_package_compose  # type: ignore
from campaign_cohesion import air_land_joint_package  # type: ignore
from campaign_execution import (  # type: ignore
    map_effect_resolve,
    next_day_feedback,
    air_land_order_package,
    execution_integrity_gate,
    close_the_loop,
)
from gameplay_loops import sealane_joint_health, sole_mult_integrity  # type: ignore
from weather_effects import air_sortie_readiness  # type: ignore
from strategic_continuity_day import order_execute_day  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from theater_ops_polish import campaign_day_risk  # type: ignore


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _q(aid: str, pid: int, score: float, label: str) -> Dict[str, Any]:
    return {
        "action_id": aid,
        "province_id": max(1, int(pid)),
        "score": float(score),
        "enabled": True,
        "label": label,
    }


def _day(
    action_id: str,
    title: str,
    summary: str,
    score: float,
    apply_queue: List[Dict[str, Any]],
    color: str = "#5ec8ff",
    marker: str = "★",
    integration: Optional[List[str]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": "Run %s" % title, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]"
        % (color, marker, title, summary),
        "empty": False,
        "integration": list(integration or ["next240", "air_convoy_order"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.75,
        "precip": 0.25,
        "precip_intensity": 0.25,
        "wind": 0.3,
        "ground_state": "dry",
        "temperature_c": 12.0,
    }


def _tgts(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "defender_power": 45.0, "id": province_id, "power": 40.0},
        {"province_id": province_id + 1, "defender_power": 55.0, "id": province_id + 1, "power": 50.0},
    ]


# A) Air-land / multi-domain


def air_sortie_depth_day(province_id: int = 1) -> Dict[str, Any]:
    air = air_ops_package(_wx(), month=6)
    sortie = air_sortie_readiness(_wx())
    score = _norm(
        0.55 * float(air.get("effective", air.get("score", 0.55)))
        + 0.45 * float(sortie.get("effectiveness", 0.55))
    )
    q = [
        _q("apply_assault", province_id, score, "air sortie depth assault"),
        _q("apply_station", province_id, 0.5, "air sortie depth station"),
    ]
    return _day(
        "air_sortie_depth_day",
        "Air sortie depth day",
        "Air sortie depth · ops · readiness · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "✈",
        ["air", "sortie", "depth"],
        {"air": air, "sortie": sortie, "air_score": score},
    )


def air_land_joint_depth_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_joint_package(
        weather=_wx(), month=6, targets=_tgts(province_id), attacker_power=100.0
    )
    order = air_land_order_package(weather=_wx(), month=6, attacker_power=100.0, province_id=province_id)
    score = _norm(
        0.55 * float(joint.get("score", 0.55))
        + 0.45 * float(order.get("score", 0.55) if not order.get("empty") else 0.4)
    )
    q = [
        _q("apply_assault", province_id, score, "air land joint depth assault"),
        _q("apply_supply", province_id, 0.55, "air land joint depth supply"),
        _q("apply_station", province_id, 0.45, "air land joint depth station"),
    ]
    return _day(
        "air_land_joint_depth_day",
        "Air land joint depth day",
        "Air-land joint depth · package · order · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "⚔",
        ["air", "land", "joint"],
        {"joint": joint, "order": order, "air_score": score},
    )


def multi_domain_ops_day(province_id: int = 1) -> Dict[str, Any]:
    air = air_ops_package(_wx(), month=6)
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    ranked = rank_assault_targets(_tgts(province_id), attacker_power=100.0, attacker_supply=0.85)
    win = float((ranked.get("best") or {}).get("overall", 0.5) or 0.5)
    score = _norm(
        0.35 * float(air.get("effective", 0.55))
        + 0.35 * float(joint.get("score", 0.55))
        + 0.3 * win
    )
    q = [
        _q("apply_assault", province_id, score, "multi domain assault"),
        _q("apply_station", province_id, 0.55, "multi domain station"),
        _q("apply_supply", province_id, 0.5, "multi domain supply"),
        _q("apply_production", province_id, 0.4, "multi domain production"),
    ]
    return _day(
        "multi_domain_ops_day",
        "Multi domain ops day",
        "Multi-domain ops · air · land · front · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "◆",
        ["air", "multi_domain", "ops"],
        {"air": air, "joint": joint, "ranked": ranked, "air_score": score},
    )


def air_front_readiness_day(province_id: int = 1) -> Dict[str, Any]:
    sortie = air_sortie_readiness(_wx())
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    risk = campaign_day_risk(_wx(), month=6)
    score = _norm(
        0.4 * float(sortie.get("effectiveness", 0.55))
        + 0.4 * float(joint.get("score", 0.55))
        + 0.2 * (1.0 - float(risk.get("risk", 0.3)))
    )
    q = [
        _q("apply_assault", province_id, score, "air front readiness assault"),
        _q("apply_supply", province_id, 0.5, "air front readiness supply"),
    ]
    return _day(
        "air_front_readiness_day",
        "Air front readiness day",
        "Air front readiness · sortie · joint · risk · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "◎",
        ["air", "front", "readiness"],
        {"sortie": sortie, "joint": joint, "risk": risk, "air_score": score},
    )


def domain_joint_ops_day(province_id: int = 1) -> Dict[str, Any]:
    air = air_ops_package(_wx(), month=6)
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=70.0, weather=_wx()
    )
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    score = _norm(
        0.35 * float(air.get("effective", 0.55))
        + 0.3 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.5)
        + 0.35 * float(joint.get("score", 0.55))
    )
    q = [
        _q("apply_assault", province_id, score, "domain joint assault"),
        _q("apply_station", province_id, 0.55, "domain joint station"),
        _q("apply_supply", province_id, 0.5, "domain joint supply"),
    ]
    return _day(
        "domain_joint_ops_day",
        "Domain joint ops day",
        "Domain joint · air · convoy · land · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "◈",
        ["air", "domain", "joint"],
        {"air": air, "convoy": convoy, "joint": joint, "air_score": score},
    )


def air_land_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    order = air_land_order_package(weather=_wx(), month=6, province_id=province_id)
    air = air_ops_package(_wx(), month=6)
    score = _norm(
        0.4 * float(joint.get("score", 0.55))
        + 0.3 * float(order.get("score", 0.55) if not order.get("empty") else 0.4)
        + 0.3 * float(air.get("effective", 0.55))
    )
    q = [
        _q("apply_assault", province_id, score, "air land campaign assault"),
        _q("apply_supply", province_id, 0.55, "air land campaign supply"),
        _q("apply_station", province_id, 0.45, "air land campaign station"),
    ]
    return _day(
        "air_land_campaign_day",
        "Air land campaign day",
        "Air-land campaign · joint · order · ops · score %.2f" % score,
        score,
        q,
        "#7dd3fc",
        "📋",
        ["air", "land", "campaign"],
        {"joint": joint, "order": order, "air": air, "air_score": score},
    )


def air_domain_close_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    air = air_ops_package(_wx(), month=6)
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(joint.get("score", 0.55))
        + 0.35 * float(air.get("effective", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, score, "air domain close assault"),
        _q("apply_station", province_id, 0.55, "air domain close station"),
        _q("apply_supply", province_id, 0.45, "air domain close supply"),
    ]
    return _day(
        "air_domain_close_day",
        "Air domain close day",
        "Air domain close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#7dd3fc",
        "✓",
        ["air", "domain", "close"],
        {"joint": joint, "air": air, "gate": gate, "ok": ok, "air_score": score},
    )


# B) Convoy / sealane


def convoy_escort_depth_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(
        ["friendly", "contested", "hostile"],
        available_fleet_strength=80.0,
        cargo_value=120.0,
        weather=_wx(),
    )
    score = _norm(float(convoy.get("score", 0.6) if not convoy.get("empty") else 0.45))
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "convoy escort depth station"),
        _q("apply_supply", province_id, 0.55, "convoy escort depth supply"),
    ]
    return _day(
        "convoy_escort_depth_day",
        "Convoy escort depth day",
        "Convoy escort depth · %s · score %.2f" % (convoy.get("summary", "convoy"), score),
        score,
        q,
        "#38bdf8",
        "⛵",
        ["convoy", "escort", "depth"],
        {"convoy": convoy, "convoy_score": score},
    )


def sealane_health_ops_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(
        ["friendly", "contested"], sea_trade_mult=1.05, weather=_wx(), available_fleet=70.0
    )
    score = _norm(float(sealane.get("score", 0.6)))
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_station", province_id, score, "sealane health station"),
        _q("apply_supply", province_id, 0.55, "sealane health supply"),
        _q("apply_production", province_id, 0.45, "sealane health production"),
    ]
    return _day(
        "sealane_health_ops_day",
        "Sealane health ops day",
        "Sealane health · %s · score %.2f" % (sealane.get("summary", "sealane"), score),
        score,
        q,
        "#38bdf8",
        "🌊",
        ["sealane", "health", "ops"],
        {"sealane": sealane, "convoy_score": score},
    )


def trade_pressure_ops_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(
        ["contested", "hostile"], sea_trade_mult=0.9, weather=_wx(), available_fleet=55.0
    )
    convoy = convoy_package_compose(
        ["contested", "hostile"], available_fleet_strength=55.0, weather=_wx()
    )
    score = _norm(
        0.5 * float(sealane.get("score", 0.55))
        + 0.5 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.45)
    )
    q = [
        _q("apply_supply", province_id, score, "trade pressure supply"),
        _q("apply_station", province_id, 0.55, "trade pressure station"),
        _q("apply_production", province_id, 0.45, "trade pressure production"),
    ]
    return _day(
        "trade_pressure_ops_day",
        "Trade pressure ops day",
        "Trade pressure · sealane · convoy · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "📦",
        ["trade", "pressure", "ops"],
        {"sealane": sealane, "convoy": convoy, "convoy_score": score},
    )


def convoy_sealane_joint_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=75.0, weather=_wx()
    )
    sealane = sealane_joint_health(
        ["friendly", "contested"], sea_trade_mult=1.0, weather=_wx(), available_fleet=75.0
    )
    score = _norm(
        0.5 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.45)
        + 0.5 * float(sealane.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "convoy sealane joint station"),
        _q("apply_supply", province_id, 0.55, "convoy sealane joint supply"),
        _q("apply_assault", province_id, 0.4, "convoy sealane joint assault"),
    ]
    return _day(
        "convoy_sealane_joint_day",
        "Convoy sealane joint day",
        "Convoy sealane joint · escort · health · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "◈",
        ["convoy", "sealane", "joint"],
        {"convoy": convoy, "sealane": sealane, "convoy_score": score},
    )


def sealane_logistics_ops_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(
        ["friendly", "friendly", "contested"],
        sea_trade_mult=1.1,
        weather=_wx(),
        available_fleet=90.0,
    )
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=90.0, cargo_value=150.0, weather=_wx()
    )
    score = _norm(
        0.55 * float(sealane.get("score", 0.55))
        + 0.45 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.45)
    )
    q = [
        _q("apply_supply", province_id, score, "sealane logistics supply"),
        _q("apply_station", province_id, 0.55, "sealane logistics station"),
        _q("apply_production", province_id, 0.45, "sealane logistics production"),
    ]
    return _day(
        "sealane_logistics_ops_day",
        "Sealane logistics ops day",
        "Sealane logistics · health · convoy · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "⛽",
        ["sealane", "logistics", "ops"],
        {"sealane": sealane, "convoy": convoy, "convoy_score": score},
    )


def wartime_trade_ops_day(province_id: int = 1) -> Dict[str, Any]:
    sealane = sealane_joint_health(
        ["hostile", "contested"], sea_trade_mult=0.85, weather=_wx(), available_fleet=50.0
    )
    convoy = convoy_package_compose(
        ["hostile", "contested"], available_fleet_strength=50.0, weather=_wx()
    )
    risk = campaign_day_risk(_wx(), month=9)
    score = _norm(
        0.4 * float(sealane.get("score", 0.5))
        + 0.35 * float(convoy.get("score", 0.5) if not convoy.get("empty") else 0.4)
        + 0.25 * (1.0 - float(risk.get("risk", 0.3)))
    )
    q = [
        _q("apply_station", province_id, score, "wartime trade station"),
        _q("apply_supply", province_id, 0.55, "wartime trade supply"),
        _q("apply_production", province_id, 0.45, "wartime trade production"),
    ]
    return _day(
        "wartime_trade_ops_day",
        "Wartime trade ops day",
        "Wartime trade · contested lanes · risk · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "⚠",
        ["trade", "wartime", "ops"],
        {"sealane": sealane, "convoy": convoy, "risk": risk, "convoy_score": score},
    )


def convoy_sealane_close_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=70.0, weather=_wx()
    )
    sealane = sealane_joint_health(
        ["friendly", "contested"], sea_trade_mult=1.0, weather=_wx(), available_fleet=70.0
    )
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.45)
        + 0.35 * float(sealane.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "convoy sealane close station"),
        _q("apply_supply", province_id, 0.55, "convoy sealane close supply"),
        _q("apply_production", province_id, 0.45, "convoy sealane close production"),
    ]
    return _day(
        "convoy_sealane_close_day",
        "Convoy sealane close day",
        "Convoy sealane close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#38bdf8",
        "✓",
        ["convoy", "sealane", "close"],
        {"convoy": convoy, "sealane": sealane, "gate": gate, "ok": ok, "convoy_score": score},
    )


# C) Order / map-effect / feedback


def order_execute_depth_day(province_id: int = 1) -> Dict[str, Any]:
    order = order_execute_day(weather=_wx(), trail=[{"class": "sabotage", "influence": 0.5}], province_id=province_id)
    score = _norm(float(order.get("score", 0.55) if not order.get("empty") else 0.45))
    if score < 0.2:
        score = 0.55
    q = list(order.get("apply_queue") or [])[:3]
    if not q:
        q = [
            _q("apply_assault", province_id, score, "order execute depth assault"),
            _q("apply_station", province_id, 0.5, "order execute depth station"),
        ]
    return _day(
        "order_execute_depth_day",
        "Order execute depth day",
        "Order execute depth · %s · score %.2f" % (order.get("summary", "execute"), score),
        score,
        q,
        "#c084fc",
        "▶",
        ["order", "execute", "depth"],
        {"order": order, "order_score": score},
    )


def map_effect_resolve_day(province_id: int = 1) -> Dict[str, Any]:
    effect = map_effect_resolve(order="DEPLOY FLEET STATION", province_id=province_id, score=0.7)
    combat = map_effect_resolve(order="PRESS COMBAT ASSAULT", province_id=province_id, score=0.65)
    score = _norm(
        0.5 * float(effect.get("score", 0.55)) + 0.5 * float(combat.get("score", 0.55))
    )
    q = [
        _q("apply_station", province_id, score, "map effect resolve station"),
        _q("apply_assault", province_id, 0.55, "map effect resolve assault"),
        _q("refresh_queue", province_id, 0.5, "map effect resolve refresh"),
    ]
    return _day(
        "map_effect_resolve_day",
        "Map effect resolve day",
        "Map effect resolve · naval · combat · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "★",
        ["order", "map_effect", "resolve"],
        {"effect": effect, "combat": combat, "order_score": score},
    )


def next_day_feedback_depth_day(province_id: int = 1) -> Dict[str, Any]:
    fb = next_day_feedback(before_score=0.42, after_score=0.68, order="apply_assault")
    effect = map_effect_resolve(order="apply_assault PRESS", province_id=province_id, score=0.68)
    score = _norm(
        0.55 * (0.65 if fb.get("trend") == "improved" else 0.45)
        + 0.45 * float(effect.get("score", 0.55))
    )
    q = [
        _q("refresh_queue", province_id, score, "next day feedback refresh"),
        _q("apply_supply", province_id, 0.55, "next day feedback supply"),
        _q("apply_station", province_id, 0.45, "next day feedback station"),
    ]
    return _day(
        "next_day_feedback_depth_day",
        "Next day feedback depth day",
        "Next-day feedback depth · %s · score %.2f" % (fb.get("summary", "feedback"), score),
        score,
        q,
        "#c084fc",
        "↻",
        ["order", "feedback", "depth"],
        {"feedback": fb, "effect": effect, "order_score": score},
    )


def order_effect_joint_day(province_id: int = 1) -> Dict[str, Any]:
    order = order_execute_day(weather=_wx(), province_id=province_id)
    effect = map_effect_resolve(order="DEPLOY FLEET + SUPPLY ROUTE", province_id=province_id, score=0.72)
    fb = next_day_feedback(0.5, 0.72, order="DEPLOY FLEET + SUPPLY ROUTE")
    score = _norm(
        0.35 * float(order.get("score", 0.55) if not order.get("empty") else 0.45)
        + 0.35 * float(effect.get("score", 0.55))
        + 0.3 * (0.65 if fb.get("trend") == "improved" else 0.45)
    )
    q = [
        _q("apply_station", province_id, score, "order effect joint station"),
        _q("apply_supply", province_id, 0.55, "order effect joint supply"),
        _q("refresh_queue", province_id, 0.5, "order effect joint refresh"),
    ]
    return _day(
        "order_effect_joint_day",
        "Order effect joint day",
        "Order effect joint · execute · map · feedback · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["order", "effect", "joint"],
        {"order": order, "effect": effect, "feedback": fb, "order_score": score},
    )


def feedback_loop_ops_day(province_id: int = 1) -> Dict[str, Any]:
    before = 0.48
    after = 0.71
    fb = next_day_feedback(before, after, order="apply_production SURGE")
    effect = map_effect_resolve(order="PROD LINE primary PRIORITY SURGE", province_id=province_id, score=after)
    order = order_execute_day(weather=_wx(), province_id=province_id)
    score = _norm(
        0.4 * abs(float(fb.get("delta", 0.2))) * 2.0
        + 0.3 * float(effect.get("score", 0.55))
        + 0.3 * float(order.get("score", 0.55) if not order.get("empty") else 0.45)
    )
    q = [
        _q("apply_production", province_id, score, "feedback loop production"),
        _q("refresh_queue", province_id, 0.55, "feedback loop refresh"),
        _q("apply_supply", province_id, 0.45, "feedback loop supply"),
    ]
    return _day(
        "feedback_loop_ops_day",
        "Feedback loop ops day",
        "Feedback loop · delta · map · execute · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "∞",
        ["order", "feedback", "loop"],
        {"feedback": fb, "effect": effect, "order": order, "order_score": score},
    )


def air_convoy_order_close_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(province_id))
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=70.0, weather=_wx()
    )
    effect = map_effect_resolve(order="PRESS COMBAT + DEPLOY FLEET", province_id=province_id, score=0.7)
    fb = next_day_feedback(0.5, 0.7, order="PRESS COMBAT + DEPLOY FLEET")
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(joint.get("score", 0.55))
        + 0.25 * float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.45)
        + 0.25 * float(effect.get("score", 0.55))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, float(joint.get("score", 0.55)), "close air-land assault"),
        _q("apply_station", province_id, float(convoy.get("score", 0.55) if not convoy.get("empty") else 0.5), "close convoy station"),
        _q("refresh_queue", province_id, float(effect.get("score", 0.55)), "close map effect refresh"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "air_convoy_order_close_day",
        "Air convoy order close day",
        "Air convoy order close · air · convoy · order · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["air", "convoy", "order", "close"],
        {
            "joint": joint,
            "convoy": convoy,
            "effect": effect,
            "feedback": fb,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


AIR_CONVOY_ORDER_DAY_IDS: List[str] = [
    "air_sortie_depth_day",
    "air_land_joint_depth_day",
    "multi_domain_ops_day",
    "air_front_readiness_day",
    "domain_joint_ops_day",
    "air_land_campaign_day",
    "air_domain_close_day",
    "convoy_escort_depth_day",
    "sealane_health_ops_day",
    "trade_pressure_ops_day",
    "convoy_sealane_joint_day",
    "sealane_logistics_ops_day",
    "wartime_trade_ops_day",
    "convoy_sealane_close_day",
    "order_execute_depth_day",
    "map_effect_resolve_day",
    "next_day_feedback_depth_day",
    "order_effect_joint_day",
    "feedback_loop_ops_day",
    "air_convoy_order_close_day",
]


DAY_FUNCS = [
    air_sortie_depth_day,
    air_land_joint_depth_day,
    multi_domain_ops_day,
    air_front_readiness_day,
    domain_joint_ops_day,
    air_land_campaign_day,
    air_domain_close_day,
    convoy_escort_depth_day,
    sealane_health_ops_day,
    trade_pressure_ops_day,
    convoy_sealane_joint_day,
    sealane_logistics_ops_day,
    wartime_trade_ops_day,
    convoy_sealane_close_day,
    order_execute_depth_day,
    map_effect_resolve_day,
    next_day_feedback_depth_day,
    order_effect_joint_day,
    feedback_loop_ops_day,
    air_convoy_order_close_day,
]


def air_convoy_order_integrity() -> Dict[str, Any]:
    joint = air_land_joint_package(weather=_wx(), month=6, targets=_tgts(1))
    convoy = convoy_package_compose(
        ["friendly", "contested"], available_fleet_strength=70.0, weather=_wx()
    )
    effect = map_effect_resolve(order="apply_station", province_id=1, score=0.6)
    gate = execution_integrity_gate()
    ok = (
        float(joint.get("score", 0)) > 0.0
        and not bool(convoy.get("empty", True))
        and not bool(effect.get("empty", False))
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "air_score": float(joint.get("score", 0)),
        "convoy_score": float(convoy.get("score", 0) if not convoy.get("empty") else 0),
        "effect_score": float(effect.get("score", 0)),
        "gate": gate,
        "summary": "Air-convoy-order integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next240_air_convoy_order_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = air_convoy_order_integrity()
    label = "Close next240 air-convoy-order · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if gate.get("ok") and non_empty >= 20 else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next240 air-convoy-order[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
