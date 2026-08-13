"""Next-180 production/OOB, air-ops multi-front, focus/strategic (20 packages).

A) Production / OOB equip continuity (1–7)
B) Air-ops / multi-front assault (8–14)
C) Focus / strategic continuity (15–20)

1 prod_factory_risk_ops_day · 2 medium_equip_horizon_ops_day · 3 production_priority_ops_day
4 oob_equip_continuity_day · 5 factory_line_ops_day · 6 stockpile_growth_ops_day
7 production_oob_close_day · 8 air_sortie_front_ops_day · 9 multi_front_rank_ops_day
10 air_land_joint_ops_day · 11 assault_front_ops_day · 12 air_forecast_ops_day
13 multi_front_supply_ops_day · 14 air_front_close_day · 15 focus_path_ops_day
16 war_cabinet_ops_day · 17 strategic_strip_ops_day · 18 focus_priority_ops_day
19 strategic_continuity_ops_day · 20 prod_air_focus_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from gameplay_loops import oob_factory_risk_loop, sole_mult_integrity  # type: ignore
from live_mutation import (  # type: ignore
    production_priority_mutation,
    air_land_stage_mutation,
    focus_mutation_path,
    supply_route_mutation,
)
from campaign_execution import (  # type: ignore
    production_order_resolve,
    air_land_order_package,
    focus_order_path,
    execution_integrity_gate,
    close_the_loop,
)
from campaign_cohesion import air_land_joint_package, production_campaign_risk  # type: ignore
from multi_front_assault import rank_assault_targets  # type: ignore
from integrated_theater_ops import war_cabinet_board, assault_readiness_compose  # type: ignore
from weather_effects import air_sortie_readiness  # type: ignore
from theater_ops_polish import focus_weather_aware_score  # type: ignore
from air_forecast_day import air_forecast_assault_day  # type: ignore


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
        "integration": list(integration or ["next180", "prod_air_focus"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.68,
        "precip_intensity": 0.35,
        "ground_state": "mud",
        "temp": 6.0,
        "wind": 0.2,
    }


def _leaf_queue(raw: Any, province_id: int, fallback: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    leaf: List[Dict[str, Any]] = []
    if isinstance(raw, list):
        for item in raw:
            if not isinstance(item, Mapping):
                continue
            aid = str(item.get("action_id", ""))
            if not aid or aid.endswith("_day"):
                continue
            row = dict(item)
            if not row.get("province_id"):
                row["province_id"] = province_id
            leaf.append(row)
    return leaf[:4] if leaf else fallback


# A) Production / OOB


def prod_factory_risk_ops_day(province_id: int = 1) -> Dict[str, Any]:
    loop = oob_factory_risk_loop()
    risk = production_campaign_risk()
    score = _norm(float(loop.get("effective_output", loop.get("production_mult", 0.7))))
    if loop.get("risk") is not None:
        score = _norm(max(score, 1.0 - float(risk.get("risk", loop.get("risk", 0.3)))))
    q = [
        _q("apply_production", province_id, score, "prod factory risk primary"),
        _q("apply_supply", province_id, 0.5, "prod factory risk supply"),
    ]
    return _day(
        "prod_factory_risk_ops_day",
        "Prod factory risk ops day",
        "Prod factory risk ops · out %.2f · score %.2f"
        % (float(loop.get("effective_output", 0)), score),
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "factory", "oob"],
        {"loop": loop, "risk": risk, "equip_score": score},
    )


def medium_equip_horizon_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    score = _norm(float(equip.get("score", 0.55)))
    q = [
        _q("apply_production", province_id, score, "medium equip horizon primary"),
        _q("apply_supply", province_id, 0.5, "medium equip horizon supply"),
    ]
    return _day(
        "medium_equip_horizon_ops_day",
        "Medium equip horizon ops day",
        "Medium equip horizon · %s · score %.2f" % (equip.get("summary", "equip"), score),
        score,
        q,
        "#e8c547",
        "🛡",
        ["production", "equip", "oob"],
        {"equip": equip, "equip_score": score},
    )


def production_priority_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation()
    order = production_order_resolve()
    score = _norm(max(float(mut.get("score", 0.5)), float(order.get("score", 0.5))))
    q = [
        _q("apply_production", province_id, score, "production priority ops primary"),
        _q("apply_supply", province_id, 0.5, "production priority ops supply"),
    ]
    return _day(
        "production_priority_ops_day",
        "Production priority ops day",
        "Production priority ops · mut · order · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "priority", "ops"],
        {"mutation": mut, "order": order},
    )


def oob_equip_continuity_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    loop = oob_factory_risk_loop()
    score = _norm(
        0.5 * float(equip.get("score", 0.55))
        + 0.5 * float(loop.get("effective_output", 0.7))
    )
    q = [
        _q("apply_production", province_id, score, "oob equip continuity production"),
        _q("apply_supply", province_id, 0.55, "oob equip continuity supply"),
        _q("apply_station", province_id, 0.45, "oob equip continuity station"),
    ]
    return _day(
        "oob_equip_continuity_day",
        "OOB equip continuity day",
        "OOB equip continuity · equip · factory · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "∞",
        ["oob", "equip", "continuity"],
        {"equip": equip, "loop": loop, "equip_score": score},
    )


def factory_line_ops_day(province_id: int = 1) -> Dict[str, Any]:
    order = production_order_resolve()
    risk = production_campaign_risk()
    score = _norm(max(float(order.get("score", 0.5)), 1.0 - float(risk.get("risk", 0.3))))
    q = [
        _q("apply_production", province_id, score, "factory line ops primary"),
        _q("apply_supply", province_id, 0.5, "factory line ops supply"),
    ]
    return _day(
        "factory_line_ops_day",
        "Factory line ops day",
        "Factory line ops · priority · risk · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏭",
        ["production", "factory", "line"],
        {"order": order, "risk": risk},
    )


def stockpile_growth_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation()
    equip = medium_horizon_equip_plan()
    score = _norm(
        0.55 * float(mut.get("score", 0.5)) + 0.45 * float(equip.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "stockpile growth primary"),
        _q("apply_supply", province_id, 0.55, "stockpile growth supply"),
    ]
    return _day(
        "stockpile_growth_ops_day",
        "Stockpile growth ops day",
        "Stockpile growth ops · priority · equip · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "📦",
        ["production", "stockpile", "growth"],
        {"mutation": mut, "equip": equip},
    )


def production_oob_close_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    loop = oob_factory_risk_loop()
    mut = production_priority_mutation()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(equip.get("score", 0.55))
        + 0.3 * float(loop.get("effective_output", 0.7))
        + 0.2 * float(mut.get("score", 0.5))
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, score, "production oob close production"),
        _q("apply_supply", province_id, 0.55, "production oob close supply"),
        _q("apply_station", province_id, 0.45, "production oob close station"),
    ]
    return _day(
        "production_oob_close_day",
        "Production OOB close day",
        "Production OOB close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["production", "oob", "close"],
        {"equip": equip, "loop": loop, "mutation": mut, "gate": gate, "ok": ok, "equip_score": score},
    )


# B) Air-ops / multi-front


def air_sortie_front_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = air_sortie_readiness(_wx())
    score = _norm(float(ready.get("effectiveness", 0.5)))
    q = [
        _q("apply_assault", province_id, score, "air sortie front primary"),
        _q("apply_supply", province_id, 0.5, "air sortie front supply"),
    ]
    return _day(
        "air_sortie_front_ops_day",
        "Air sortie front ops day",
        "Air sortie front · %s · score %.2f" % (ready.get("summary", "sortie"), score),
        score,
        q,
        "#7dd3a0",
        "✈",
        ["air", "sortie", "front"],
        {"readiness": ready},
    )


def multi_front_rank_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [
            {"province_id": province_id, "defender_power": 50, "supply": 0.55},
            {"province_id": province_id + 1, "defender_power": 40, "supply": 0.7},
            {"province_id": province_id + 2, "defender_power": 60, "supply": 0.5},
        ],
        attacker_power=100.0,
        attacker_supply=0.85,
        max_targets=5,
    )
    best = int(ranked.get("best_province_id", province_id) or province_id)
    score = 0.62 if not bool(ranked.get("empty", False)) else 0.4
    q = [
        _q("apply_assault", best if best > 0 else province_id, score, "multi front rank primary"),
        _q("apply_supply", province_id, 0.5, "multi front rank supply"),
    ]
    return _day(
        "multi_front_rank_ops_day",
        "Multi front rank ops day",
        "Multi front rank · best #%d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "◎",
        ["air", "multi_front", "rank"],
        {"ranked": ranked, "best_province_id": best},
    )


def air_land_joint_ops_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_joint_package()
    order = air_land_order_package()
    score = _norm(max(float(joint.get("score", 0.5)), float(order.get("score", 0.5))))
    q = [
        _q("apply_assault", province_id, score, "air land joint primary"),
        _q("apply_supply", province_id, 0.55, "air land joint supply"),
        _q("apply_station", province_id, 0.45, "air land joint station"),
    ]
    return _day(
        "air_land_joint_ops_day",
        "Air land joint ops day",
        "Air land joint ops · package · order · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "⚔",
        ["air", "land", "joint"],
        {"joint": joint, "order": order},
    )


def assault_front_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = assault_readiness_compose(
        [{"province_id": province_id, "defender_power": 45, "supply": 0.6}],
        100.0,
    )
    mut = air_land_stage_mutation()
    score = _norm(max(0.6, float(mut.get("score", 0.5))))
    q = [
        _q("apply_assault", province_id, score, "assault front primary"),
        _q("apply_supply", province_id, 0.5, "assault front supply"),
    ]
    return _day(
        "assault_front_ops_day",
        "Assault front ops day",
        "Assault front ops · ready · stage · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["assault", "front", "ops"],
        {"readiness": ready, "mutation": mut},
    )


def air_forecast_ops_day(province_id: int = 1) -> Dict[str, Any]:
    day = air_forecast_assault_day()
    score = _norm(float(day.get("score", 0.55)))
    q = _leaf_queue(
        day.get("apply_queue"),
        province_id,
        [
            _q("apply_assault", province_id, score, "air forecast ops primary"),
            _q("apply_supply", province_id, 0.5, "air forecast ops supply"),
        ],
    )
    return _day(
        "air_forecast_ops_day",
        "Air forecast ops day",
        "Air forecast ops · %s · score %.2f" % (day.get("summary", "forecast"), score),
        score,
        q,
        "#7dd3a0",
        "☁",
        ["air", "forecast", "ops"],
        {"forecast": day},
    )


def multi_front_supply_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ranked = rank_assault_targets(
        [{"province_id": province_id, "defender_power": 48, "supply": 0.6}],
        attacker_power=100.0,
        attacker_supply=0.75,
    )
    supply = supply_route_mutation()
    score = _norm(0.5 * 0.6 + 0.5 * float(supply.get("score", 0.5)))
    q = [
        _q("apply_supply", province_id, float(supply.get("score", score)), "multi front supply primary"),
        _q("apply_assault", province_id, 0.55, "multi front supply assault"),
        _q("apply_station", province_id, 0.45, "multi front supply station"),
    ]
    return _day(
        "multi_front_supply_ops_day",
        "Multi front supply ops day",
        "Multi front supply · rank · route · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "📦",
        ["multi_front", "supply", "ops"],
        {"ranked": ranked, "supply": supply},
    )


def air_front_close_day(province_id: int = 1) -> Dict[str, Any]:
    ready = air_sortie_readiness(_wx())
    joint = air_land_joint_package()
    ranked = rank_assault_targets(
        [{"province_id": province_id, "defender_power": 45}],
        attacker_power=100.0,
    )
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(ready.get("effectiveness", 0.5))
        + 0.3 * float(joint.get("score", 0.5))
        + 0.2 * 0.6
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, score, "air front close assault"),
        _q("apply_supply", province_id, 0.55, "air front close supply"),
        _q("apply_station", province_id, 0.45, "air front close station"),
    ]
    return _day(
        "air_front_close_day",
        "Air front close day",
        "Air front close · sortie · joint · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#7dd3a0",
        "∞",
        ["air", "front", "close"],
        {"readiness": ready, "joint": joint, "ranked": ranked, "gate": gate, "ok": ok},
    )


# C) Focus / strategic


def focus_path_ops_day(province_id: int = 1) -> Dict[str, Any]:
    path = focus_order_path()
    mut = focus_mutation_path()
    score = _norm(max(float(path.get("score", 0.5)), float(mut.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "focus path ops primary"),
        _q("apply_hh_commit", province_id, 0.5, "focus path ops hh"),
        _q("apply_production", province_id, 0.45, "focus path ops production"),
    ]
    return _day(
        "focus_path_ops_day",
        "Focus path ops day",
        "Focus path ops · order · mut · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "path", "strategic"],
        {"path": path, "mutation": mut},
    )


def war_cabinet_ops_day(province_id: int = 1) -> Dict[str, Any]:
    cabinet = war_cabinet_board()
    focus = focus_weather_aware_score(50.0, "industrial_effort")
    raw = float(focus.get("score", 50.0))
    fscore = _norm(raw / 100.0 if raw > 2.0 else raw)
    score = _norm(0.55 * fscore + 0.45 * 0.65)
    q = [
        _q("apply_focus", province_id, score, "war cabinet ops focus"),
        _q("apply_hh_commit", province_id, 0.55, "war cabinet ops hh"),
        _q("apply_production", province_id, 0.5, "war cabinet ops production"),
    ]
    return _day(
        "war_cabinet_ops_day",
        "War cabinet ops day",
        "War cabinet ops · board · focus · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🏛",
        ["strategic", "war_cabinet", "ops"],
        {"cabinet": cabinet, "focus": focus},
    )


def strategic_strip_ops_day(province_id: int = 1) -> Dict[str, Any]:
    path = focus_order_path()
    cabinet = war_cabinet_board()
    risk = production_campaign_risk()
    score = _norm(
        0.4 * float(path.get("score", 0.5))
        + 0.3 * 0.65
        + 0.3 * (1.0 - float(risk.get("risk", 0.3)))
    )
    q = [
        _q("refresh_queue", province_id, score, "strategic strip refresh"),
        _q("apply_focus", province_id, 0.55, "strategic strip focus"),
        _q("apply_production", province_id, 0.5, "strategic strip production"),
    ]
    return _day(
        "strategic_strip_ops_day",
        "Strategic strip ops day",
        "Strategic strip ops · focus · cabinet · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["strategic", "strip", "ops"],
        {"path": path, "cabinet": cabinet, "risk": risk},
    )


def focus_priority_ops_day(province_id: int = 1) -> Dict[str, Any]:
    focus = focus_weather_aware_score(55.0, "armament_effort")
    mut = focus_mutation_path()
    raw = float(focus.get("score", 55.0))
    fscore = _norm(raw / 100.0 if raw > 2.0 else raw)
    score = _norm(0.55 * fscore + 0.45 * float(mut.get("score", 0.5)))
    q = [
        _q("apply_focus", province_id, score, "focus priority ops primary"),
        _q("apply_production", province_id, 0.55, "focus priority ops production"),
        _q("apply_hh_commit", province_id, 0.45, "focus priority ops hh"),
    ]
    return _day(
        "focus_priority_ops_day",
        "Focus priority ops day",
        "Focus priority ops · wx · mut · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "priority", "strategic"],
        {"focus": focus, "mutation": mut},
    )


def strategic_continuity_ops_day(province_id: int = 1) -> Dict[str, Any]:
    path = focus_order_path()
    mut = production_priority_mutation()
    cabinet = war_cabinet_board()
    score = _norm(
        0.4 * float(path.get("score", 0.5))
        + 0.4 * float(mut.get("score", 0.5))
        + 0.2 * 0.65
    )
    q = [
        _q("apply_focus", province_id, score, "strategic continuity focus"),
        _q("apply_production", province_id, float(mut.get("score", 0.5)), "strategic continuity production"),
        _q("apply_hh_commit", province_id, 0.5, "strategic continuity hh"),
    ]
    return _day(
        "strategic_continuity_ops_day",
        "Strategic continuity ops day",
        "Strategic continuity · focus · prod · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "∞",
        ["strategic", "continuity", "ops"],
        {"path": path, "mutation": mut, "cabinet": cabinet},
    )


def prod_air_focus_close_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    ready = air_sortie_readiness(_wx())
    focus = focus_weather_aware_score(50.0, "industrial_effort")
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    raw = float(focus.get("score", 50.0))
    fscore = _norm(raw / 100.0 if raw > 2.0 else raw)
    score = _norm(
        0.25 * float(equip.get("score", 0.55))
        + 0.25 * float(ready.get("effectiveness", 0.5))
        + 0.25 * fscore
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "close production equip"),
        _q("apply_assault", province_id, float(ready.get("effectiveness", 0.5)), "close air assault"),
        _q("apply_focus", province_id, fscore, "close focus"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "prod_air_focus_close_day",
        "Prod air focus close day",
        "Prod air focus close · equip · air · focus · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["production", "air", "focus", "close"],
        {
            "equip": equip,
            "readiness": ready,
            "focus": focus,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "equip_score": float(equip.get("score", 0.55)),
        },
    )


PROD_AIR_FOCUS_DAY_IDS: List[str] = [
    "prod_factory_risk_ops_day",
    "medium_equip_horizon_ops_day",
    "production_priority_ops_day",
    "oob_equip_continuity_day",
    "factory_line_ops_day",
    "stockpile_growth_ops_day",
    "production_oob_close_day",
    "air_sortie_front_ops_day",
    "multi_front_rank_ops_day",
    "air_land_joint_ops_day",
    "assault_front_ops_day",
    "air_forecast_ops_day",
    "multi_front_supply_ops_day",
    "air_front_close_day",
    "focus_path_ops_day",
    "war_cabinet_ops_day",
    "strategic_strip_ops_day",
    "focus_priority_ops_day",
    "strategic_continuity_ops_day",
    "prod_air_focus_close_day",
]


DAY_FUNCS = [
    prod_factory_risk_ops_day,
    medium_equip_horizon_ops_day,
    production_priority_ops_day,
    oob_equip_continuity_day,
    factory_line_ops_day,
    stockpile_growth_ops_day,
    production_oob_close_day,
    air_sortie_front_ops_day,
    multi_front_rank_ops_day,
    air_land_joint_ops_day,
    assault_front_ops_day,
    air_forecast_ops_day,
    multi_front_supply_ops_day,
    air_front_close_day,
    focus_path_ops_day,
    war_cabinet_ops_day,
    strategic_strip_ops_day,
    focus_priority_ops_day,
    strategic_continuity_ops_day,
    prod_air_focus_close_day,
]


def prod_air_focus_integrity() -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    ready = air_sortie_readiness(_wx())
    focus = focus_weather_aware_score(50.0, "industrial_effort")
    gate = execution_integrity_gate()
    ok = (
        float(equip.get("score", 0)) > 0.0
        and float(ready.get("effectiveness", 0)) > 0.0
        and float(focus.get("score", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "equip_score": float(equip.get("score", 0)),
        "sortie": float(ready.get("effectiveness", 0)),
        "focus_score": float(focus.get("score", 0)),
        "gate": gate,
        "summary": "Prod-air-focus integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next180_prod_air_focus_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = prod_air_focus_integrity()
    label = "Close next180 prod-air-focus · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next180 prod-air-focus[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
