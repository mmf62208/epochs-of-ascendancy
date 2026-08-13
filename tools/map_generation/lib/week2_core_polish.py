"""Week-2 core polish: day-package apply audit, save-slot flair, infra/site consistency.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Mapping, Optional, Sequence


# Panel day packages that must remain live-routed via GameData.apply_order_panel_action.
CANONICAL_DAY_ACTIONS: List[str] = [
    "day_ops_integrated",
    "theater_day_cabinet",
    "logistics_day",
    "war_economy_day",
    "combat_campaign_day",
    "fleet_campaign_day",
    "weather_crisis_day",
    "agent_campaign_day",
    "hh_campaign_day",
    "hh_player_path",
    "industry_surge_day",
    "joint_command_day",
    "strategic_continuity_day",
    "force_readiness_day",
    "naval_interdiction_day",
    "apply_supply",
    "apply_station",
    "apply_production",
    "apply_hh_commit",
]


def day_package_apply_audit(
    panel_source: str = "",
    gamedata_source: str = "",
    *,
    required: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Audit that panel day action_ids appear in GameData.apply_order_panel_action body.

    Pure structural check on shipped GD source (no Godot runtime).
    """
    need = list(required or CANONICAL_DAY_ACTIONS)
    # Prefer DAY_PACKAGE_ACTION_IDS const when present
    panel_ids: List[str] = []
    m = re.search(
        r"DAY_PACKAGE_ACTION_IDS[^=]*=\s*\[(.*?)\]",
        panel_source or "",
        re.S,
    )
    if m:
        panel_ids = re.findall(r'"([a-z0-9_]+)"', m.group(1))
    for a in need:
        if a not in panel_ids:
            panel_ids.append(a)

    # Extract apply_order_panel_action function body
    router = ""
    gm = re.search(
        r"func apply_order_panel_action\s*\([^)]*\)\s*->\s*Dictionary:\s*\n(.*?)(?=\nfunc |\Z)",
        gamedata_source or "",
        re.S,
    )
    if gm:
        router = gm.group(1)

    routed: List[str] = []
    dead: List[str] = []
    for aid in panel_ids:
        # Match action id string in router (aid == "x" or begins_with patterns)
        if not router:
            dead.append(aid)
            continue
        if (
            ('"%s"' % aid) in router
            or ("'%s'" % aid) in router
            or (aid.startswith("save_slot") and "save_slot:" in router)
            or (aid.startswith("load_slot") and "load_slot:" in router)
        ):
            routed.append(aid)
        else:
            dead.append(aid)

    ok = len(dead) == 0 and len(routed) > 0
    label = (
        "Day apply audit · panel %d · routed %d · dead %d · %s"
        % (len(panel_ids), len(routed), len(dead), "PASS" if ok else "FAIL")
    )
    return {
        "panel_ids": panel_ids,
        "routed": routed,
        "dead": dead,
        "routed_count": len(routed),
        "dead_count": len(dead),
        "ok": ok,
        "score": 1.0 if ok else max(0.1, 1.0 - len(dead) / max(1, len(panel_ids))),
        "summary": label,
        "plain": label
        + ((" · dead: " + ", ".join(dead[:8])) if dead else ""),
        "bbcode": "[color=#%s]✓ Day apply audit[/color] [color=#8899aa]%s[/color]"
        % ("6ecf8e" if ok else "ff6e6e", label),
        "empty": False,
        "integration": ["order_panel", "apply_router", "dead_buttons"],
    }


def save_slot_browser_flair(
    rows: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    max_rows: int = 8,
) -> Dict[str, Any]:
    """Enhance save-slot browser rows with flair markers for empty/occupied/special.

    Input rows: list_slots_for_ui shape {slot, occupied, label, can_load, can_save}.
    """
    raw = list(rows or [])
    if not raw:
        # Pilot empty browser so flair is still demonstrable
        raw = [
            {"slot": "quicksave", "occupied": False, "label": "quicksave · empty", "can_load": False, "can_save": True},
            {"slot": "autosave", "occupied": True, "label": "autosave · world_full · GER", "can_load": True, "can_save": True, "metadata": {"scenario_id": "world_full", "player_tag": "GER"}},
            {"slot": "slot1", "occupied": False, "label": "slot1 · empty", "can_load": False, "can_save": True},
        ]
    flaired: List[Dict[str, Any]] = []
    empty_n = 0
    occ_n = 0
    for r in raw[: max(1, int(max_rows))]:
        if not isinstance(r, Mapping):
            continue
        slot = str(r.get("slot", "")).strip() or "unnamed"
        occupied = bool(r.get("occupied", False))
        base = str(r.get("label", slot)).strip()
        if occupied:
            occ_n += 1
            mark = "★" if slot in ("autosave",) else ("⚡" if slot == "quicksave" else "●")
            flair_label = "%s %s" % (mark, base)
            tint = "occupied"
        else:
            empty_n += 1
            mark = "○"
            flair_label = "%s %s" % (mark, base if "empty" in base else (base + " · empty"))
            tint = "empty"
        flaired.append(
            {
                "slot": slot,
                "occupied": occupied,
                "status": "occupied" if occupied else "empty",
                "label": base,
                "flair_label": flair_label,
                "marker": mark,
                "tint": tint,
                "can_load": bool(r.get("can_load", occupied)),
                "can_save": bool(r.get("can_save", True)),
                "action_save": "save_slot:%s" % slot,
                "action_load": "load_slot:%s" % slot,
            }
        )
    label = "Save-slot flair · %d rows · occupied %d · empty %d" % (
        len(flaired),
        occ_n,
        empty_n,
    )
    plain_lines = [label] + [str(x.get("flair_label", "")) for x in flaired[:6]]
    return {
        "rows": flaired,
        "occupied_count": occ_n,
        "empty_count": empty_n,
        "count": len(flaired),
        "score": 0.55 if flaired else 0.0,
        "summary": label,
        "plain": "\n".join(plain_lines),
        "bbcode": "[color=#5ec8ff]💾 Save-slot flair[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": len(flaired) == 0,
        "actions": [
            {"action_id": "save_slot:quicksave", "label": "Quicksave", "enabled": True},
        ],
        "integration": ["save_slots", "flair", "ui"],
    }


def infra_site_consistency_skim(
    *,
    infrastructure: float = 50.0,
    site_count: int = 0,
    site_damaged: int = 0,
    project_active: int = 0,
    project_sabotaged: int = 0,
    facility_tier: str = "full",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Consistency skim: special sites vs infrastructure vs projects.

    Flags mismatches (sites on low infra, damaged without sabotage signal, etc.).
    """
    infra = max(0.0, min(100.0, float(infrastructure)))
    sites = max(0, int(site_count))
    damaged = max(0, min(sites, int(site_damaged)))
    projects = max(0, int(project_active))
    sabo = max(0, int(project_sabotaged))
    tier = str(facility_tier or "none").strip().lower() or "none"

    issues: List[str] = []
    if sites >= 1 and infra < 20.0:
        issues.append("sites_on_low_infra")
    if damaged > 0 and sabo == 0 and damaged >= sites:
        issues.append("all_sites_damaged")
    if projects > 0 and infra < 15.0:
        issues.append("project_on_low_infra")
    if tier in ("none", "") and (sites > 0 or projects > 0):
        issues.append("facility_tier_mismatch")
    if sabo > projects and projects >= 0:
        issues.append("sabo_exceeds_projects")

    consistency = 1.0 - 0.18 * len(issues)
    if damaged > 0:
        consistency -= 0.05 * min(3, damaged)
    consistency = max(0.05, min(1.0, consistency))
    score = consistency
    label = (
        "Infra/site skim · #%d · infra %.0f · sites %d (dmg %d) · projects %d (sabo %d) · tier %s · issues %d"
        % (province_id, infra, sites, damaged, projects, sabo, tier, len(issues))
    )
    return {
        "province_id": province_id,
        "infrastructure": infra,
        "site_count": sites,
        "site_damaged": damaged,
        "project_active": projects,
        "project_sabotaged": sabo,
        "facility_tier": tier,
        "issues": issues,
        "issue_count": len(issues),
        "consistency": consistency,
        "score": score,
        "ok": len(issues) == 0,
        "summary": label,
        "plain": label
        + ((" · " + ", ".join(issues)) if issues else " · consistent"),
        "bbcode": "[color=#e8c060]🏗 Infra/site skim[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["infrastructure", "special_sites", "projects"],
    }


def close_week2_core_polish_loop(
    panel_source: str = "",
    gamedata_source: str = "",
) -> Dict[str, Any]:
    audit = day_package_apply_audit(panel_source, gamedata_source)
    slots = save_slot_browser_flair()
    infra = infra_site_consistency_skim(
        infrastructure=12.0, site_count=2, site_damaged=1, project_active=1
    )
    label = (
        "Close week2 polish · apply %s · slots %d · infra issues %d"
        % (
            "PASS" if audit.get("ok") else "FAIL",
            int(slots.get("count", 0)),
            int(infra.get("issue_count", 0)),
        )
    )
    return {
        "audit": audit,
        "slots": slots,
        "infra": infra,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close week2 polish[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
