#!/usr/bin/env python3
"""Pure map-polish formatters (infra invest, special sites, naval chokepoints).

Canonical pure helpers used by CI tests and mirrored by
`scripts/map/MapPolishFormatters.gd` (ProvinceInsight / overlay / inspector path).

All functions take plain dicts/primitives — no Godot runtime required.
"""

from __future__ import annotations

from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Union

# BBCode color tokens must match ProvinceInsight / MapPolishFormatters.gd
COLOR_HEADER = "[color=#6eb5ff]"
COLOR_TECH = "[color=#6ec8ff]"
COLOR_WARN = "[color=#ff9a6e]"
COLOR_MUTED = "[color=#8899aa]"

KNOWN_EFFECT_KEYS = (
    "supply_throughput_bonus",
    "trade_capacity",
    "naval_repair_bonus",
    "air_recon_bonus",
    "defense_bonus",
    "construction_speed_bonus",
)


def format_investment_modifier_bits(mods: Optional[Dict[str, Any]]) -> List[str]:
    """Engineer/tech/stability/sabotage bits from a project modifiers dict."""
    if not mods:
        return []
    bits: List[str] = []
    if "engineer" in mods and float(mods["engineer"]) != 0.0:
        bits.append("Eng %+.1f" % float(mods["engineer"]))
    if "tech" in mods and float(mods["tech"]) != 0.0:
        bits.append("Tech %+.1f" % float(mods["tech"]))
    if "stability" in mods and float(mods["stability"]) != 0.0:
        bits.append("Stab %+.1f" % float(mods["stability"]))
    if "regional" in mods and float(mods["regional"]) != 0.0:
        bits.append("Reg %+.1f" % float(mods["regional"]))
    if "sabotage" in mods and float(mods["sabotage"]) != 0.0:
        bits.append("Sab %.1f" % float(mods["sabotage"]))
    return bits


def format_investment_status_line(
    status: Dict[str, Any],
    default_infra: int = 1,
) -> str:
    """BBCode invest line from InfrastructureDevelopmentManager.get_project_status-shaped dict.

    Empty dict / inactive → empty string (no project).
    """
    if not status or not bool(status.get("active", False)):
        return ""

    pct = int(round(float(status.get("progress", 0.0))))
    eta = int(status.get("eta_days", 0))
    target = int(status.get("target_level", default_infra + 1))
    sabotaged = bool(status.get("is_sabotaged", False))
    work = float(status.get("work_per_day", 0.0))
    mods = status.get("modifiers") if isinstance(status.get("modifiers"), dict) else {}

    color = COLOR_WARN if sabotaged else COLOR_TECH
    icon = "⚠" if sabotaged else "🚧"
    sab = " (under sabotage)" if sabotaged else ""
    line = "%s%s Infra Investment → Lv.%d  %d%%%s (ETA %dd" % (
        color,
        icon,
        target,
        pct,
        sab,
        eta,
    )
    if work > 0.0:
        line += ", %.1f/day" % work
    line += ")[/color]"

    mod_bits = format_investment_modifier_bits(mods)
    if mod_bits:
        mod_color = COLOR_WARN if sabotaged else COLOR_MUTED
        line += "\n%sMods: %s[/color]" % (mod_color, " · ".join(mod_bits))
    if sabotaged:
        line += "\n%sCancel or clear agents to recover progress rate.[/color]" % COLOR_WARN
    return line


def format_invest_panel_state(
    status: Dict[str, Any],
    cur_infra: int,
    cur_dev: int = 0,
) -> Dict[str, Any]:
    """Panel-facing state for MapRenderer invest UI (progress/cancel/sabo).

    Returns keys: has_project, label, progress_pct, sabotaged, show_cancel,
    show_progress, modifiers_label, button_text, button_disabled.
    """
    has_project = bool(status.get("active", False)) if status else False
    if not has_project:
        return {
            "has_project": False,
            "label": "Infra: %d  ·  Dev: %d  (Invest to raise)" % (cur_infra, cur_dev),
            "progress_pct": 0,
            "sabotaged": False,
            "show_cancel": False,
            "show_progress": False,
            "modifiers_label": "",
            "button_text": "Invest in Infrastructure",
            "button_disabled": False,
        }

    pct = int(round(float(status.get("progress", 0.0))))
    eta = int(status.get("eta_days", 0))
    target = int(status.get("target_level", cur_infra + 1))
    sabotaged = bool(status.get("is_sabotaged", False))
    sab_note = " ⚠ Sabotage slowing progress" if sabotaged else ""
    label = "Infra Project: %d%% → Lv.%d (ETA %d days)%s" % (pct, target, eta, sab_note)
    mods = status.get("modifiers") if isinstance(status.get("modifiers"), dict) else {}
    mod_bits = format_investment_modifier_bits(mods)
    # Panel uses slightly different eng format historically ("Eng +x" without sign on positive)
    panel_bits: List[str] = []
    if mods:
        if "engineer" in mods:
            panel_bits.append("Eng +%.1f" % float(mods["engineer"]))
        if "tech" in mods:
            panel_bits.append("Tech +%.1f" % float(mods["tech"]))
        if "stability" in mods:
            panel_bits.append("Stab %.1f" % float(mods["stability"]))
        if "regional" in mods:
            panel_bits.append("Reg +%.1f" % float(mods["regional"]))
        if "sabotage" in mods:
            panel_bits.append("Sab %.1f" % float(mods["sabotage"]))
    mod_str = " | ".join(panel_bits) if panel_bits else "Base work rate"
    modifiers_label = "Curr Lv: Infra %d / Dev %d  ·  Mods: %s" % (cur_infra, cur_dev, mod_str)
    if sabotaged:
        modifiers_label += "  ·  ⚠ sabo active"
    return {
        "has_project": True,
        "label": label,
        "progress_pct": max(0, min(100, pct)),
        "sabotaged": sabotaged,
        "show_cancel": True,
        "show_progress": True,
        "modifiers_label": modifiers_label,
        "button_text": "Project Active",
        "button_disabled": True,
        "mod_bits": mod_bits,
    }


def format_site_effect_bits(
    supply_bonus: float = 0.0,
    trade_capacity: float = 0.0,
    effects: Optional[Dict[str, Any]] = None,
    construction_progress: Optional[float] = None,
    damage_level: int = 0,
) -> List[str]:
    """Effect chip list for a special site (live values + definition effects)."""
    effects = effects or {}
    supply_b = float(supply_bonus)
    trade_b = float(trade_capacity)
    if supply_b <= 0.0 and "supply_throughput_bonus" in effects:
        supply_b = float(effects["supply_throughput_bonus"])
    if trade_b <= 0.0 and "trade_capacity" in effects:
        trade_b = float(effects["trade_capacity"])

    bits: List[str] = []
    if supply_b > 0.0:
        bits.append("+%d supply" % int(supply_b))
    if trade_b > 0.0:
        bits.append("+%d trade" % int(trade_b))
    if float(effects.get("naval_repair_bonus", 0) or 0) > 0.0:
        bits.append("+%d naval repair" % int(effects["naval_repair_bonus"]))
    if float(effects.get("air_recon_bonus", 0) or 0) > 0.0:
        bits.append("+%d recon" % int(effects["air_recon_bonus"]))
    if float(effects.get("defense_bonus", 0) or 0) > 0.0:
        bits.append("+%d def" % int(effects["defense_bonus"]))
    if float(effects.get("construction_speed_bonus", 0) or 0) > 0.0:
        bits.append("+%d build spd" % int(effects["construction_speed_bonus"]))
    for k, val in effects.items():
        key = str(k)
        if key in KNOWN_EFFECT_KEYS:
            continue
        if isinstance(val, (int, float)) and float(val) > 0.0:
            bits.append("+%d %s" % (int(val), key.replace("_", " ")))
    if construction_progress is not None:
        prog = int(round(max(0.0, min(1.0, float(construction_progress))) * 100.0))
        bits.append("building %d%%" % prog)
    if damage_level > 0:
        bits.append("dmg %d" % int(damage_level))
    return bits


def format_overlay_effect_chip(supply_bonus: float, trade_capacity: float) -> str:
    """Compact map-draw chip (+12S +40T)."""
    parts: List[str] = []
    if supply_bonus > 0:
        parts.append("+%dS" % int(supply_bonus))
    if trade_capacity > 0:
        parts.append("+%dT" % int(trade_capacity))
    return " ".join(parts)


def format_special_site_line(
    site_id: str,
    display_name: str,
    tier: int,
    state_icon: str,
    effect_bits: Sequence[str],
    compact: bool = True,
    description: str = "",
) -> str:
    """One special-site tooltip/inspector line."""
    display = display_name if display_name else site_id.replace("_", " ")
    eff_str = " · ".join(effect_bits) if effect_bits else "no passive effects"
    if compact:
        return "%s%s %s T%d[/color] %s%s[/color]" % (
            COLOR_TECH,
            state_icon,
            display,
            tier,
            COLOR_MUTED,
            eff_str,
        )
    line = "%s%s %s (T%d) — %s[/color]" % (COLOR_TECH, state_icon, display, tier, eff_str)
    if description:
        line += "\n%s%s[/color]" % (COLOR_MUTED, description)
    return line


def format_special_sites_block(site_lines: Sequence[str], compact: bool = True) -> str:
    if not site_lines:
        return ""
    if compact:
        return "%sSites:[/color] " % COLOR_HEADER + " | ".join(site_lines)
    return "%s── Special sites ──[/color]\n" % COLOR_HEADER + "\n".join(site_lines)


def load_chokepoint_id_set(chokepoint_payload: Dict[str, Any]) -> Set[int]:
    """Parse MapManager naval_chokepoints.json payload → set of province ids."""
    raw = chokepoint_payload.get("chokepoint_province_ids", [])
    return {int(x) for x in raw}


def is_chokepoint_member(province_id: int, chokepoint_ids: Iterable[int]) -> bool:
    """Membership check used by has_strategic_chokepoint / highlight / tint."""
    return int(province_id) in set(int(x) for x in chokepoint_ids)


def format_chokepoint_badge(
    supply_bonus_multiplier: float = 1.18,
    controller_tag: str = "",
    owner_tag: str = "",
) -> str:
    """Legacy badge; prefer format_chokepoint_contest_badge when contest state is known."""
    contest = compute_chokepoint_contest(
        controller_tag=controller_tag,
        owner_tag=owner_tag,
        supply_bonus_multiplier=supply_bonus_multiplier,
    )
    return format_chokepoint_contest_badge(contest)


def compute_chokepoint_contest(
    province_id: int = 0,
    controller_tag: str = "",
    owner_tag: str = "",
    supply_bonus_multiplier: float = 1.18,
) -> Dict[str, Any]:
    """Contest state for a naval chokepoint province.

    - unowned: no owner and no controller
    - contested: owner and controller both set and differ
    - controlled: single clear controller (owner fills controller if empty)
    """
    ctrl = (controller_tag or "").strip().upper()
    own = (owner_tag or "").strip().upper()
    if not ctrl and own:
        ctrl = own
    unowned = not ctrl and not own
    contested = bool(own and ctrl and own != ctrl)
    if unowned:
        state = "unowned"
        summary = "Naval chokepoint — unowned strait"
        label = "Unowned"
    elif contested:
        state = "contested"
        summary = "Naval chokepoint — contested (controller %s, owner %s)" % (ctrl, own)
        label = "Contested · %s" % ctrl
    else:
        state = "controlled"
        summary = "Naval chokepoint — controlled by %s" % ctrl
        label = ctrl
    return {
        "province_id": int(province_id),
        "controller": ctrl,
        "owner": own,
        "state": state,
        "contested": contested,
        "unowned": unowned,
        "controlled": state == "controlled",
        "summary": summary,
        "label": label,
        "supply_bonus_multiplier": float(supply_bonus_multiplier),
    }


def format_chokepoint_contest_badge(contest: Mapping[str, Any]) -> str:
    """BBCode inspector line for choke contest state."""
    mult = float(contest.get("supply_bonus_multiplier", 1.18))
    if bool(contest.get("unowned", False)):
        return (
            "%s⚓ Naval chokepoint[/color] %s— unowned strait (×%.2f supply/trade)[/color]"
            % (COLOR_TECH, COLOR_MUTED, mult)
        )
    ctrl = str(contest.get("controller", "")).strip().upper()
    own = str(contest.get("owner", "")).strip().upper()
    if bool(contest.get("contested", False)):
        return (
            "%s⚓ Naval chokepoint[/color] %s— contested · controller %s (owner %s) · ×%.2f[/color]"
            % (COLOR_WARN, COLOR_MUTED, ctrl or "?", own or "?", mult)
        )
    return (
        "%s⚓ Naval chokepoint[/color] %s— controlled by %s · ×%.2f supply/trade[/color]"
        % (COLOR_TECH, COLOR_MUTED, ctrl or "?", mult)
    )


def site_state_icon(
    completed: bool = False,
    under_construction: bool = False,
    damaged: bool = False,
) -> str:
    if damaged:
        return "💥"
    if completed:
        return "✓"
    if under_construction:
        return "🚧"
    return "⚠"


def format_inspector_topline(
    province_name: str,
    owner_tag: str = "",
    region_name: str = "",
    sea_zone_name: str = "",
) -> Dict[str, Any]:
    """Top-line inspector identity: name, owner, strategic region, sea zone.

    Pure strings only — call site resolves MapManager region/sea zone.
    """
    name = (province_name or "Province").strip() or "Province"
    owner = (owner_tag or "").strip().upper()
    if not owner:
        owner_disp = "Unowned"
    else:
        owner_disp = owner
    region = (region_name or "").strip()
    sea = (sea_zone_name or "").strip()

    summary_bits: List[str] = [name, owner_disp]
    if region:
        summary_bits.append(region)
    if sea:
        summary_bits.append("⚓ " + sea)
    plain_summary = " · ".join(summary_bits)

    bb_bits: List[str] = [
        "%s%s[/color]" % (COLOR_HEADER, name),
        "%s%s[/color]" % (COLOR_MUTED, owner_disp),
    ]
    if region:
        bb_bits.append("%s%s[/color]" % (COLOR_TECH, region))
    if sea:
        bb_bits.append("%s⚓ %s[/color]" % (COLOR_TECH, sea))
    bbcode = " · ".join(bb_bits)

    return {
        "title": name,
        "owner": owner_disp,
        "owner_line": "Owner: %s" % owner_disp,
        "region": region,
        "region_line": ("Region: %s" % region) if region else "",
        "sea_zone": sea,
        "sea_zone_line": ("Sea zone: %s" % sea) if sea else "",
        "plain_summary": plain_summary,
        "bbcode": bbcode,
        "has_region": bool(region),
        "has_sea_zone": bool(sea),
    }


def special_site_map_visual(
    completed: bool = False,
    under_construction: bool = False,
    damaged: bool = False,
    construction_progress: float = 0.0,
) -> Dict[str, Any]:
    """Map marker visual contract for special sites (pulse / ring / tint).

    Damaged always distinct from healthy complete; under-construction pulses
    with progress ring; completed healthy gets completion pulse (no damage cracks).
    """
    icon = site_state_icon(completed, under_construction, damaged)
    prog = max(0.0, min(1.0, float(construction_progress)))
    if damaged:
        return {
            "icon": icon,
            "tint_key": "damaged",
            "pulse": False,
            "completion_pulse": False,
            "progress_ring": False,
            "ring_progress": 0.0,
            "show_damage_cracks": True,
            "show_effect_chip": False,
        }
    if under_construction:
        return {
            "icon": icon,
            "tint_key": "under_construction",
            "pulse": True,
            "completion_pulse": False,
            "progress_ring": True,
            "ring_progress": max(0.05, prog),
            "show_damage_cracks": False,
            "show_effect_chip": False,
        }
    if completed:
        return {
            "icon": icon,
            "tint_key": "complete",
            "pulse": True,
            "completion_pulse": True,
            "progress_ring": False,
            "ring_progress": 1.0,
            "show_damage_cracks": False,
            "show_effect_chip": True,
        }
    return {
        "icon": icon,
        "tint_key": "idle",
        "pulse": False,
        "completion_pulse": False,
        "progress_ring": False,
        "ring_progress": 0.0,
        "show_damage_cracks": False,
        "show_effect_chip": False,
    }
