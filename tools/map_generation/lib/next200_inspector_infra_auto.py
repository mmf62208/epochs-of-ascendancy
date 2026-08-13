"""Next-200 inspector/surface, infrastructure/investment, daily theater auto (20 packages).

A) Inspector / product-surface (1–7)
B) Infrastructure / investment (8–14)
C) Daily theater auto-command (15–20)

1 panel_surface_ops_day · 2 tooltip_chip_ops_day · 3 insight_budget_ops_day
4 order_surface_ops_day · 5 product_chip_ops_day · 6 surface_refresh_ops_day
7 inspector_surface_close_day · 8 infra_invest_ops_day · 9 special_site_ops_day
10 construction_ops_day · 11 infra_project_ops_day · 12 investment_status_ops_day
13 infra_site_joint_day · 14 infra_invest_close_day · 15 daily_auto_ops_day
16 theater_tick_ops_day · 17 multi_domain_auto_ops_day · 18 daily_apply_ops_day
19 theater_auto_joint_day · 20 inspector_infra_auto_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from ops_depth import order_panel_actions, order_panel_refresh_surface  # type: ignore
from theater_commander import player_order_surface_strip  # type: ignore
from week4_polish_depth import tooltip_sfx_flair_strip  # type: ignore
from inspector_product_depth import budget_product_depth_chips  # type: ignore
from map_next_list_helpers import format_infra_project_flair  # type: ignore
from map_polish_formatters import (  # type: ignore
    format_investment_status_line,
    special_site_map_visual,
)
from weather_ops_polish import infra_weather_wear  # type: ignore
from week2_core_polish import infra_site_consistency_skim  # type: ignore
from daily_command_tick import (  # type: ignore
    format_command_log_surface,
    multi_province_day_plan,
    daily_theater_auto_tick,
    daily_apply_integrity_gate,
    day_apply_budget,
)
from order_panel_ux_depth import order_panel_section_plan  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from week2_core_polish import day_package_apply_audit  # type: ignore


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
        "integration": list(integration or ["next200", "inspector_infra_auto"]),
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


# A) Inspector / product-surface


def panel_surface_ops_day(province_id: int = 1) -> Dict[str, Any]:
    panel = order_panel_actions(province_id=province_id)
    sections = order_panel_section_plan()
    score = _norm(float(panel.get("score", 0.7)))
    if score < 0.3:
        score = 0.7
    q = [
        _q("refresh_queue", province_id, score, "panel surface refresh"),
        _q("apply_supply", province_id, 0.5, "panel surface supply"),
    ]
    return _day(
        "panel_surface_ops_day",
        "Panel surface ops day",
        "Panel surface · actions %d · score %.2f" % (int(panel.get("count", 0)), score),
        score,
        q,
        "#c084fc",
        "📋",
        ["inspector", "panel", "surface"],
        {"panel": panel, "sections": sections, "panel_count": int(panel.get("count", 0))},
    )


def tooltip_chip_ops_day(province_id: int = 1) -> Dict[str, Any]:
    flair = tooltip_sfx_flair_strip()
    score = _norm(float(flair.get("score", 0.85)))
    q = [
        _q("refresh_queue", province_id, score, "tooltip chip refresh"),
        _q("apply_assault", province_id, 0.5, "tooltip chip assault"),
    ]
    return _day(
        "tooltip_chip_ops_day",
        "Tooltip chip ops day",
        "Tooltip chip · flair · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "✨",
        ["inspector", "tooltip", "chip"],
        {"flair": flair},
    )


def insight_budget_ops_day(province_id: int = 1) -> Dict[str, Any]:
    chips = budget_product_depth_chips(
        [
            {"id": "panel", "bbcode": "panel"},
            {"id": "infra", "bbcode": "infra"},
            {"id": "auto", "bbcode": "auto"},
            {"id": "invest", "bbcode": "invest"},
            {"id": "tick", "bbcode": "tick"},
        ],
        max_chips=4,
    )
    score = _norm(0.5 + 0.05 * int(chips.get("shown", chips.get("count", 3)) or 3))
    q = [
        _q("refresh_queue", province_id, score, "insight budget refresh"),
        _q("apply_station", province_id, 0.5, "insight budget station"),
    ]
    return _day(
        "insight_budget_ops_day",
        "Insight budget ops day",
        "Insight budget · shown %d · score %.2f"
        % (int(chips.get("shown", 0)), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["inspector", "budget", "chips"],
        {"chips": chips, "chip_count": int(chips.get("shown", 0))},
    )


def order_surface_ops_day(province_id: int = 1) -> Dict[str, Any]:
    strip = player_order_surface_strip()
    score = 0.7 if not bool(strip.get("empty", True)) else 0.45
    if strip.get("count") is not None:
        score = _norm(0.45 + 0.05 * int(strip.get("count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "order surface refresh"),
        _q("apply_supply", province_id, 0.55, "order surface supply"),
        _q("apply_station", province_id, 0.5, "order surface station"),
    ]
    return _day(
        "order_surface_ops_day",
        "Order surface ops day",
        "Order surface · lines %d · score %.2f" % (int(strip.get("count", 0)), score),
        score,
        q,
        "#c084fc",
        "🖥",
        ["inspector", "order", "surface"],
        {"strip": strip, "panel_count": int(strip.get("count", 0))},
    )


def product_chip_ops_day(province_id: int = 1) -> Dict[str, Any]:
    chips = budget_product_depth_chips(
        [{"id": "a", "bbcode": "A"}, {"id": "b", "bbcode": "B"}, {"id": "c", "bbcode": "C"}],
        max_chips=3,
    )
    flair = tooltip_sfx_flair_strip()
    score = _norm(0.5 * float(flair.get("score", 0.8)) + 0.5 * 0.7)
    q = [
        _q("refresh_queue", province_id, score, "product chip refresh"),
        _q("apply_production", province_id, 0.5, "product chip production"),
    ]
    return _day(
        "product_chip_ops_day",
        "Product chip ops day",
        "Product chip · budget · flair · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["inspector", "product", "chip"],
        {"chips": chips, "flair": flair},
    )


def surface_refresh_ops_day(province_id: int = 1) -> Dict[str, Any]:
    try:
        refresh = order_panel_refresh_surface()
    except TypeError:
        refresh = order_panel_actions(province_id=province_id)
    log = format_command_log_surface(
        [{"summary": "panel", "score": 0.7}, {"summary": "surface", "score": 0.6}]
    )
    score = _norm(float(refresh.get("score", 0.65)))
    q = [
        _q("refresh_queue", province_id, score, "surface refresh primary"),
        _q("apply_supply", province_id, 0.5, "surface refresh supply"),
    ]
    return _day(
        "surface_refresh_ops_day",
        "Surface refresh ops day",
        "Surface refresh · panel · log · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "↻",
        ["inspector", "refresh", "surface"],
        {"refresh": refresh, "log": log},
    )


def inspector_surface_close_day(province_id: int = 1) -> Dict[str, Any]:
    panel = order_panel_actions(province_id=province_id)
    flair = tooltip_sfx_flair_strip()
    chips = budget_product_depth_chips(
        [{"id": "x", "bbcode": "x"}, {"id": "y", "bbcode": "y"}], max_chips=2
    )
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(panel.get("score", 0.5))
        + 0.35 * float(flair.get("score", 0.5))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "inspector surface close refresh"),
        _q("apply_supply", province_id, 0.55, "inspector surface close supply"),
        _q("apply_station", province_id, 0.45, "inspector surface close station"),
    ]
    return _day(
        "inspector_surface_close_day",
        "Inspector surface close day",
        "Inspector surface close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#c084fc",
        "∞",
        ["inspector", "surface", "close"],
        {"panel": panel, "flair": flair, "chips": chips, "gate": gate, "ok": ok},
    )


# B) Infrastructure / investment


def infra_invest_ops_day(province_id: int = 1) -> Dict[str, Any]:
    status = format_investment_status_line(
        {"active": True, "progress": 40.0, "eta_days": 6, "target_level": 2, "work_per_day": 8.0},
        1,
    )
    flair = format_infra_project_flair("Province", kind="progress", new_level=2, eta_days=6)
    score = _norm(float(flair.get("score", 0.65)) if isinstance(flair, dict) else 0.65)
    if score < 0.3:
        score = 0.65
    q = [
        _q("apply_production", province_id, score, "infra invest production"),
        _q("apply_supply", province_id, 0.5, "infra invest supply"),
    ]
    return _day(
        "infra_invest_ops_day",
        "Infra invest ops day",
        "Infra invest · status · flair · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏗",
        ["infra", "invest", "ops"],
        {"status": status, "flair": flair, "invest_score": score},
    )


def special_site_ops_day(province_id: int = 1) -> Dict[str, Any]:
    visual = special_site_map_visual()
    skim = infra_site_consistency_skim()
    score = 0.7 if not bool(visual.get("empty", False)) else 0.5
    q = [
        _q("apply_production", province_id, score, "special site production"),
        _q("apply_station", province_id, 0.5, "special site station"),
    ]
    return _day(
        "special_site_ops_day",
        "Special site ops day",
        "Special site · visual · consistency · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "◆",
        ["infra", "special_site", "ops"],
        {"visual": visual, "skim": skim},
    )


def construction_ops_day(province_id: int = 1) -> Dict[str, Any]:
    wear = infra_weather_wear(_wx())
    flair = format_infra_project_flair("Province", kind="complete", new_level=2, eta_days=0)
    score = _norm(
        0.5 * float(wear.get("wear", wear.get("score", 0.4)) if isinstance(wear.get("wear", None), (int, float)) else 0.55)
        + 0.5 * float(flair.get("score", 0.6) if isinstance(flair, dict) else 0.6)
    )
    if score < 0.3:
        score = 0.6
    q = [
        _q("apply_production", province_id, score, "construction ops production"),
        _q("apply_supply", province_id, 0.55, "construction ops supply"),
    ]
    return _day(
        "construction_ops_day",
        "Construction ops day",
        "Construction · wear · project · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏗",
        ["infra", "construction", "ops"],
        {"wear": wear, "flair": flair},
    )


def infra_project_ops_day(province_id: int = 1) -> Dict[str, Any]:
    flair = format_infra_project_flair("Province", kind="progress", new_level=3, eta_days=10, cost_pp=12)
    status = format_investment_status_line(
        {"active": True, "progress": 55.0, "eta_days": 10, "target_level": 3}, 2
    )
    score = _norm(float(flair.get("score", 0.65)) if isinstance(flair, dict) else 0.65)
    if score < 0.3:
        score = 0.65
    q = [
        _q("apply_production", province_id, score, "infra project production"),
        _q("apply_focus", province_id, 0.5, "infra project focus"),
        _q("apply_supply", province_id, 0.45, "infra project supply"),
    ]
    return _day(
        "infra_project_ops_day",
        "Infra project ops day",
        "Infra project · flair · status · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "🏗",
        ["infra", "project", "ops"],
        {"flair": flair, "status": status, "invest_score": score},
    )


def investment_status_ops_day(province_id: int = 1) -> Dict[str, Any]:
    status = format_investment_status_line(
        {"active": True, "progress": 70.0, "eta_days": 3, "target_level": 2, "is_sabotaged": False},
        1,
    )
    score = 0.72 if status else 0.4
    q = [
        _q("apply_production", province_id, score, "investment status production"),
        _q("apply_supply", province_id, 0.5, "investment status supply"),
    ]
    return _day(
        "investment_status_ops_day",
        "Investment status ops day",
        "Investment status · line · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "📈",
        ["infra", "investment", "status"],
        {"status": status, "invest_score": score},
    )


def infra_site_joint_day(province_id: int = 1) -> Dict[str, Any]:
    visual = special_site_map_visual()
    skim = infra_site_consistency_skim()
    wear = infra_weather_wear(_wx())
    score = _norm(0.4 * 0.7 + 0.3 * 0.6 + 0.3 * float(wear.get("score", 0.55) if isinstance(wear.get("score", None), (int, float)) else 0.55))
    q = [
        _q("apply_production", province_id, score, "infra site joint production"),
        _q("apply_station", province_id, 0.55, "infra site joint station"),
        _q("apply_supply", province_id, 0.5, "infra site joint supply"),
    ]
    return _day(
        "infra_site_joint_day",
        "Infra site joint day",
        "Infra site joint · site · wear · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "◈",
        ["infra", "site", "joint"],
        {"visual": visual, "skim": skim, "wear": wear},
    )


def infra_invest_close_day(province_id: int = 1) -> Dict[str, Any]:
    flair = format_infra_project_flair("Province", kind="complete", new_level=2)
    visual = special_site_map_visual()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(flair.get("score", 0.65) if isinstance(flair, dict) else 0.65)
        + 0.35 * 0.7
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, score, "infra invest close production"),
        _q("apply_supply", province_id, 0.55, "infra invest close supply"),
        _q("apply_station", province_id, 0.45, "infra invest close station"),
    ]
    return _day(
        "infra_invest_close_day",
        "Infra invest close day",
        "Infra invest close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["infra", "invest", "close"],
        {"flair": flair, "visual": visual, "gate": gate, "ok": ok, "invest_score": score},
    )


# C) Daily theater auto-command


def daily_auto_ops_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    budget = day_apply_budget()
    score = _norm(float(budget.get("score", 0.65)))
    if not bool(tick.get("empty", False)):
        score = _norm(max(score, 0.65))
    q = [
        _q("apply_station", province_id, score, "daily auto station"),
        _q("apply_supply", province_id, 0.55, "daily auto supply"),
        _q("apply_assault", province_id, 0.45, "daily auto assault"),
    ]
    return _day(
        "daily_auto_ops_day",
        "Daily auto ops day",
        "Daily auto · tick · budget · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⏱",
        ["daily", "auto", "theater"],
        {"tick": tick, "budget": budget},
    )


def theater_tick_ops_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    ranked = multi_province_day_plan([province_id, province_id + 1, province_id + 2])
    score = _norm(float(ranked.get("score", 0.7)))
    q = [
        _q("apply_station", province_id, score, "theater tick station"),
        _q("apply_supply", province_id, 0.5, "theater tick supply"),
        _q("apply_assault", province_id, 0.45, "theater tick assault"),
    ]
    return _day(
        "theater_tick_ops_day",
        "Theater tick ops day",
        "Theater tick · auto · multi · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["theater", "tick", "auto"],
        {"tick": tick, "ranked": ranked, "rank_score": score},
    )


def multi_domain_auto_ops_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    log = format_command_log_surface(
        [{"summary": "fleet", "score": 0.6}, {"summary": "combat", "score": 0.65}, {"summary": "supply", "score": 0.7}]
    )
    score = _norm(0.55 + 0.05 * int(log.get("count", 0)))
    q = [
        _q("apply_station", province_id, score, "multi domain auto station"),
        _q("apply_assault", province_id, 0.55, "multi domain auto assault"),
        _q("apply_supply", province_id, 0.5, "multi domain auto supply"),
        _q("apply_production", province_id, 0.45, "multi domain auto production"),
    ]
    return _day(
        "multi_domain_auto_ops_day",
        "Multi domain auto ops day",
        "Multi domain auto · tick · log · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◆",
        ["daily", "multi_domain", "auto"],
        {"tick": tick, "log": log},
    )


def daily_apply_ops_day(province_id: int = 1) -> Dict[str, Any]:
    gate = daily_apply_integrity_gate()
    budget = day_apply_budget()
    score = _norm(0.5 * float(budget.get("score", 0.6)) + 0.5 * (0.8 if gate.get("ok") else 0.35))
    q = [
        _q("refresh_queue", province_id, score, "daily apply refresh"),
        _q("apply_supply", province_id, 0.55, "daily apply supply"),
        _q("apply_station", province_id, 0.5, "daily apply station"),
    ]
    return _day(
        "daily_apply_ops_day",
        "Daily apply ops day",
        "Daily apply · integrity · budget · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "✓",
        ["daily", "apply", "auto"],
        {"gate": gate, "budget": budget},
    )


def theater_auto_joint_day(province_id: int = 1) -> Dict[str, Any]:
    tick = daily_theater_auto_tick()
    ranked = multi_province_day_plan([province_id, province_id + 1])
    budget = day_apply_budget()
    score = _norm(
        0.4 * float(ranked.get("score", 0.5))
        + 0.3 * float(budget.get("score", 0.5))
        + 0.3 * 0.65
    )
    q = [
        _q("apply_station", province_id, score, "theater auto joint station"),
        _q("apply_assault", province_id, 0.55, "theater auto joint assault"),
        _q("apply_supply", province_id, 0.5, "theater auto joint supply"),
    ]
    return _day(
        "theater_auto_joint_day",
        "Theater auto joint day",
        "Theater auto joint · tick · multi · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◈",
        ["theater", "auto", "joint"],
        {"tick": tick, "ranked": ranked, "budget": budget},
    )


def inspector_infra_auto_close_day(province_id: int = 1) -> Dict[str, Any]:
    panel = order_panel_actions(province_id=province_id)
    flair = format_infra_project_flair("Province", kind="progress", new_level=2, eta_days=5)
    tick = daily_theater_auto_tick()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(panel.get("score", 0.5))
        + 0.25 * float(flair.get("score", 0.6) if isinstance(flair, dict) else 0.6)
        + 0.25 * 0.65
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, float(panel.get("score", 0.55)), "close inspector refresh"),
        _q("apply_production", province_id, 0.55, "close infra production"),
        _q("apply_station", province_id, 0.5, "close auto station"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "inspector_infra_auto_close_day",
        "Inspector infra auto close day",
        "Inspector infra auto close · surface · invest · auto · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["inspector", "infra", "auto", "close"],
        {
            "panel": panel,
            "flair": flair,
            "tick": tick,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


INSPECTOR_INFRA_AUTO_DAY_IDS: List[str] = [
    "panel_surface_ops_day",
    "tooltip_chip_ops_day",
    "insight_budget_ops_day",
    "order_surface_ops_day",
    "product_chip_ops_day",
    "surface_refresh_ops_day",
    "inspector_surface_close_day",
    "infra_invest_ops_day",
    "special_site_ops_day",
    "construction_ops_day",
    "infra_project_ops_day",
    "investment_status_ops_day",
    "infra_site_joint_day",
    "infra_invest_close_day",
    "daily_auto_ops_day",
    "theater_tick_ops_day",
    "multi_domain_auto_ops_day",
    "daily_apply_ops_day",
    "theater_auto_joint_day",
    "inspector_infra_auto_close_day",
]


DAY_FUNCS = [
    panel_surface_ops_day,
    tooltip_chip_ops_day,
    insight_budget_ops_day,
    order_surface_ops_day,
    product_chip_ops_day,
    surface_refresh_ops_day,
    inspector_surface_close_day,
    infra_invest_ops_day,
    special_site_ops_day,
    construction_ops_day,
    infra_project_ops_day,
    investment_status_ops_day,
    infra_site_joint_day,
    infra_invest_close_day,
    daily_auto_ops_day,
    theater_tick_ops_day,
    multi_domain_auto_ops_day,
    daily_apply_ops_day,
    theater_auto_joint_day,
    inspector_infra_auto_close_day,
]


def inspector_infra_auto_integrity() -> Dict[str, Any]:
    panel = order_panel_actions()
    flair = format_infra_project_flair("Province", kind="progress", new_level=2, eta_days=5)
    tick = daily_theater_auto_tick()
    gate = execution_integrity_gate()
    ok = (
        not bool(panel.get("empty", False))
        and bool(flair)
        and not bool(tick.get("empty", False))
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "panel_score": float(panel.get("score", 0)),
        "invest": str(flair.get("summary", flair) if isinstance(flair, dict) else flair)[:40],
        "tick_ok": not bool(tick.get("empty", False)),
        "gate": gate,
        "summary": "Inspector-infra-auto integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next200_inspector_infra_auto_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = inspector_infra_auto_integrity()
    label = "Close next200 inspector-infra-auto · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next200 inspector-infra-auto[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
