"""Inspector product-depth chip budget + resource/damage operational skim.

Caps the flood of day-package chips while always keeping high-priority naval/HH
surfaces. Mirrors live ProvinceInsight product-depth block selection.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence


# Priority bands for product-depth inspector chips (higher = keep first).
CHIP_PRIORITIES: Dict[str, int] = {
    "naval_skim": 100,
    "hh_player_path": 95,
    "fleet_campaign_day": 90,
    "combat_campaign_day": 90,
    "joint_campaign_day": 85,
    "weather_crisis_day": 80,
    "agent_campaign_day": 80,
    "industry_surge_day": 75,
    "logistics_day": 75,
    "force_readiness_day": 70,
    "strategic_continuity_day": 70,
    "joint_command_day": 65,
    "naval_campaign_day": 65,
    "combat_ops_day": 60,
    "fleet_redeploy_day": 60,
    "air_ops_day": 55,
    "forecast_day": 50,
    "war_cabinet": 45,
    "campaign_strip": 45,
    "convoy_pkg": 40,
    "theater_ready": 40,
    "default": 30,
}

ALWAYS_SHOW = frozenset({"naval_skim", "hh_player_path", "combat_campaign_day", "fleet_campaign_day"})


def chip_priority(chip_id: str) -> int:
    return int(CHIP_PRIORITIES.get(str(chip_id), CHIP_PRIORITIES["default"]))


def budget_product_depth_chips(
    chips: Sequence[Mapping[str, Any]],
    *,
    max_chips: int = 8,
    compact: bool = True,
    always_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Select up to max_chips product-depth chips by priority.

    Each chip: {id, bbcode|plain|summary, priority?}. Empty bbcode skipped.
    When compact=False, returns all non-empty chips (still ranked).
    """
    always = {str(x) for x in (always_ids or ALWAYS_SHOW)}
    scored: List[Dict[str, Any]] = []
    for raw in chips or []:
        if not isinstance(raw, Mapping):
            continue
        cid = str(raw.get("id", raw.get("chip_id", "")) or "")
        text = str(
            raw.get("bbcode")
            or raw.get("plain")
            or raw.get("summary")
            or raw.get("text")
            or ""
        ).strip()
        if not text or not cid:
            continue
        pri = int(raw.get("priority", chip_priority(cid)))
        scored.append(
            {
                "id": cid,
                "priority": pri,
                "bbcode": text,
                "always": cid in always,
            }
        )
    # Rank: always first (by pri), then others by pri, stable id
    scored.sort(key=lambda c: (-1 if c["always"] else 0, -int(c["priority"]), str(c["id"])))
    limit = int(max_chips) if compact else max(len(scored), 1)
    selected = scored[: max(0, limit)]
    selected_ids = [str(c["id"]) for c in selected]
    hidden = [str(c["id"]) for c in scored if c["id"] not in selected_ids]
    label = (
        "Inspector product-depth · show %d/%d · hidden %d · budget %d"
        % (len(selected), len(scored), len(hidden), limit if compact else len(scored))
    )
    return {
        "chips": selected,
        "selected_ids": selected_ids,
        "hidden_ids": hidden,
        "shown": len(selected),
        "total": len(scored),
        "hidden": len(hidden),
        "max_chips": limit,
        "compact": bool(compact),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]📋 Inspector chips[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": len(selected) == 0 and len(scored) == 0,
        "integration": ["inspector", "product_depth", "cognitive_load"],
    }


def resource_damage_operational_skim(
    *,
    primary_resource: str = "oil",
    resource_level: float = 0.6,
    infrastructure: float = 50.0,
    damage_strength: float = 0.0,
    sabotage: bool = False,
    site_damaged: int = 0,
    zoom: float = 0.45,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Operational-zoom skim for resources + damage (readability at mid zoom)."""
    res = str(primary_resource or "none").strip().lower() or "none"
    level = max(0.0, min(1.5, float(resource_level)))
    infra = max(0.0, min(100.0, float(infrastructure)))
    dmg = max(0.0, min(1.0, float(damage_strength)))
    if sabotage:
        dmg = max(dmg, 0.35)
    if int(site_damaged) > 0:
        dmg = max(dmg, min(0.7, 0.15 * int(site_damaged)))
    z = max(0.05, min(2.0, float(zoom)))
    # At operational zoom (~0.35–0.55), emphasize icons; far out, mute
    visible = z >= 0.32
    icon_weight = 0.0
    if visible:
        icon_weight = min(1.0, 0.35 + level * 0.5 + (z - 0.32) * 1.2)
    urgency = dmg * 0.6 + max(0.0, 0.5 - level) * 0.3 + max(0.0, 40.0 - infra) / 100.0
    urgency = min(1.0, urgency)
    score = max(0.05, (1.0 - urgency) * 0.55 + icon_weight * 0.45)
    dmg_tag = "sabo" if sabotage else ("dmg" if dmg >= 0.2 else "clean")
    label = (
        "Res/dmg skim · #%d · %s %.0f%% · infra %.0f · %s · zoom %.2f%s"
        % (
            province_id,
            res,
            level * 100.0,
            infra,
            dmg_tag,
            z,
            "" if visible else " · icons off",
        )
    )
    return {
        "province_id": province_id,
        "primary_resource": res,
        "resource_level": level,
        "infrastructure": infra,
        "damage_strength": dmg,
        "sabotage": bool(sabotage),
        "site_damaged": int(site_damaged),
        "zoom": z,
        "icons_visible": visible,
        "icon_weight": icon_weight,
        "urgency": urgency,
        "score": score,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]⛏ Res/dmg skim[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["resources", "damage", "operational_zoom"],
    }


def sealane_contest_skim(
    *,
    is_choke: bool = False,
    zone_relation: str = "contested",
    sea_trade_mult: float = 1.0,
    escort_coverage: float = 0.7,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Sealane contest skim for naval feel at operational zoom."""
    zone = str(zone_relation or "no_zone").strip().lower() or "no_zone"
    sea = max(0.2, min(1.5, float(sea_trade_mult)))
    escort = max(0.0, min(1.2, float(escort_coverage)))
    contest = 0.2
    if zone == "hostile":
        contest = 0.85
    elif zone == "contested":
        contest = 0.55
    elif zone == "friendly":
        contest = 0.15
    if is_choke:
        contest = min(1.0, contest + 0.15)
    if escort < 0.5:
        contest = min(1.0, contest + 0.1)
    score = max(0.05, (1.0 - contest) * 0.5 + sea * 0.3 + escort * 0.2)
    label = (
        "Sealane contest · #%d · %s · choke %s · sea×%.2f · escort %.0f%% · contest %.0f%%"
        % (
            province_id,
            zone,
            "yes" if is_choke else "no",
            sea,
            escort * 100.0,
            contest * 100.0,
        )
    )
    return {
        "province_id": province_id,
        "is_choke": bool(is_choke),
        "zone_relation": zone,
        "sea_trade_mult": sea,
        "escort_coverage": escort,
        "contest": contest,
        "score": score,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🌊 Sealane contest[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["choke", "sea_zone", "escort"],
    }


def close_inspector_product_depth_loop() -> Dict[str, Any]:
    chips = [
        {"id": "air_ops_day", "bbcode": "air"},
        {"id": "naval_skim", "bbcode": "naval skim line"},
        {"id": "hh_player_path", "bbcode": "hh path"},
        {"id": "combat_campaign_day", "bbcode": "combat day"},
        {"id": "fleet_campaign_day", "bbcode": "fleet day"},
        {"id": "weather_crisis_day", "bbcode": "wx"},
        {"id": "industry_surge_day", "bbcode": "industry"},
        {"id": "agent_campaign_day", "bbcode": "agent"},
        {"id": "forecast_day", "bbcode": "forecast"},
        {"id": "convoy_pkg", "bbcode": "convoy"},
        {"id": "war_cabinet", "bbcode": "cabinet"},
    ]
    budget = budget_product_depth_chips(chips, max_chips=8, compact=True)
    res = resource_damage_operational_skim(
        sabotage=True, resource_level=0.4, zoom=0.42, province_id=1
    )
    sea = sealane_contest_skim(is_choke=True, zone_relation="hostile", province_id=1)
    label = (
        "Close inspector depth · chips %d/%d · res urg %.2f · sealane contest %.2f"
        % (
            int(budget.get("shown", 0)),
            int(budget.get("total", 0)),
            float(res.get("urgency", 0)),
            float(sea.get("contest", 0)),
        )
    )
    return {
        "budget": budget,
        "resource": res,
        "sealane": sea,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close inspector depth[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
