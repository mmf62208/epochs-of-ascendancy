"""Order panel UX depth: collapsible section plan + primary/secondary day actions.

Keeps all live apply routes available while reducing cognitive load: only a few
sections start expanded; the rest start collapsed with one-click expand.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence


# Section plan for Theater Command Center day packages.
# start_expanded: true for primary decision surfaces; false for depth catalogues.
SECTION_DEFS: List[Dict[str, Any]] = [
    {
        "id": "primary",
        "title": "Primary day ops",
        "kind": "primary",
        "priority": 100,
        "start_expanded": True,
        "actions": [
            {"action_id": "day_ops_integrated", "label": "Run integrated day ops"},
            {"action_id": "theater_day_cabinet", "label": "Run theater day cabinet"},
            {"action_id": "logistics_day", "label": "Run logistics day"},
            {"action_id": "war_economy_day", "label": "Run war economy day"},
        ],
    },
    {
        "id": "combat",
        "title": "Combat & joint",
        "kind": "combat",
        "priority": 80,
        "start_expanded": True,
        "actions": [
            {"action_id": "combat_campaign_day", "label": "Run combat campaign day"},
            {"action_id": "combat_ops_day", "label": "Run combat ops day"},
            {"action_id": "joint_command_day", "label": "Run joint command day"},
            {"action_id": "joint_campaign_day", "label": "Run joint campaign day"},
            {"action_id": "multi_front_assault_day", "label": "Stage multi-front assaults"},
            {"action_id": "reinforced_assault_day", "label": "Stage reinforced assault day"},
            {"action_id": "air_forecast_day", "label": "Run air-forecast assault day"},
            {"action_id": "air_land_joint_day", "label": "Run air-land joint day"},
            {"action_id": "strategic_continuity_day", "label": "Run strategic continuity day"},
            {"action_id": "order_execute_day", "label": "Run order execute day"},
            {"action_id": "focus_war_path_day", "label": "Run focus war path day"},
            {"action_id": "force_readiness_day", "label": "Run force readiness day"},
            {"action_id": "force_posture_day", "label": "Run force posture day"},
            {"action_id": "theater_readiness_day", "label": "Run theater readiness day"},
            {"action_id": "move_path_day", "label": "Run move path day"},
        ],
    },
    {
        "id": "naval",
        "title": "Naval & fleet",
        "kind": "naval",
        "priority": 75,
        "start_expanded": False,
        "actions": [
            {"action_id": "fleet_campaign_day", "label": "Run fleet campaign day"},
            {"action_id": "fleet_redeploy_day", "label": "Run fleet redeploy day"},
            {"action_id": "fleet_task_group_day", "label": "Run fleet task group day"},
            {"action_id": "naval_campaign_day", "label": "Run naval campaign day"},
            {"action_id": "naval_interdiction_day", "label": "Run naval interdiction day"},
            {"action_id": "leader_station_day", "label": "Apply leader station day"},
        ],
    },
    {
        "id": "weather",
        "title": "Weather crisis",
        "kind": "weather",
        "priority": 55,
        "start_expanded": False,
        "actions": [
            {"action_id": "weather_crisis_day", "label": "Run weather crisis day"},
            {"action_id": "ground_transition_day", "label": "Run ground transition day"},
            {"action_id": "fog_air_crisis_day", "label": "Run fog/air crisis day"},
        ],
    },
    {
        "id": "intel",
        "title": "Agents & Hidden Hand",
        "kind": "hh",
        "priority": 70,
        "start_expanded": False,
        "actions": [
            {"action_id": "agent_campaign_day", "label": "Run agent campaign day"},
            {"action_id": "agent_response_day", "label": "Run agent response day"},
            {"action_id": "hh_campaign_day", "label": "Run HH campaign day"},
            {"action_id": "intel_counter_day", "label": "Run intel counter day"},
        ],
    },
    {
        "id": "industry",
        "title": "Industry surge",
        "kind": "industry",
        "priority": 50,
        "start_expanded": False,
        "actions": [
            {"action_id": "industry_surge_day", "label": "Run industry surge day"},
            {"action_id": "production_surge_day", "label": "Run production surge day"},
            {"action_id": "depot_capacity_day", "label": "Run depot capacity day"},
        ],
    },
]


def order_panel_section_plan(
    *,
    compact: bool = True,
    force_expand_ids: Optional[Sequence[str]] = None,
    max_expanded: int = 2,
) -> Dict[str, Any]:
    """Return collapsible section plan for order panel day packages.

    When compact=True, only high-priority sections start expanded (capped by
    max_expanded), unless force_expand_ids overrides.
    """
    force = {str(x) for x in (force_expand_ids or [])}
    sections: List[Dict[str, Any]] = []
    expanded = 0
    total_actions = 0
    for raw in SECTION_DEFS:
        sec = dict(raw)
        actions = [dict(a) for a in list(sec.get("actions") or [])]
        for a in actions:
            a["enabled"] = bool(a.get("enabled", True))
        total_actions += len(actions)
        sid = str(sec.get("id", ""))
        want = bool(sec.get("start_expanded", False))
        if sid in force:
            want = True
        if compact and want and expanded >= max_expanded and sid not in force:
            # Keep primary always if listed force-open kinds
            if str(sec.get("kind")) not in ("primary",):
                want = False
        if want:
            expanded += 1
        sec["actions"] = actions
        sec["start_expanded"] = want
        sec["action_count"] = len(actions)
        sections.append(sec)

    collapsed = sum(1 for s in sections if not s.get("start_expanded"))
    label = (
        "Order panel sections · %d groups · %d expanded · %d collapsed · %d actions"
        % (len(sections), expanded, collapsed, total_actions)
    )
    return {
        "sections": sections,
        "expanded_count": expanded,
        "collapsed_count": collapsed,
        "action_count": total_actions,
        "compact": bool(compact),
        "max_expanded": int(max_expanded),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]📋 Panel sections[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["order_panel", "collapse", "day_packages"],
    }


def order_panel_action_ids(plan: Optional[Mapping[str, Any]] = None) -> List[str]:
    """Flat list of all action_ids in the section plan (live routes must remain)."""
    p = plan or order_panel_section_plan()
    out: List[str] = []
    for sec in list(p.get("sections") or []):
        if not isinstance(sec, Mapping):
            continue
        for a in list(sec.get("actions") or []):
            if isinstance(a, Mapping) and a.get("action_id"):
                out.append(str(a["action_id"]))
    return out


def order_panel_primary_actions(plan: Optional[Mapping[str, Any]] = None) -> List[Dict[str, Any]]:
    """Actions from sections that start expanded (default skim set)."""
    p = plan or order_panel_section_plan()
    out: List[Dict[str, Any]] = []
    for sec in list(p.get("sections") or []):
        if not isinstance(sec, Mapping) or not sec.get("start_expanded"):
            continue
        for a in list(sec.get("actions") or []):
            if isinstance(a, Mapping):
                out.append(dict(a))
    return out


def naval_campaign_skim(
    basing_level: str = "port",
    fuel_level: float = 0.65,
    zone_relation: str = "contested",
    is_choke: bool = False,
    sea_trade_mult: float = 1.0,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Compact naval skim line for inspector/panel (basing · fuel · zone · choke)."""
    basing = str(basing_level or "none").strip().lower() or "none"
    fuel = max(0.05, min(1.2, float(fuel_level)))
    zone = str(zone_relation or "no_zone").strip().lower() or "no_zone"
    sea = max(0.2, min(1.5, float(sea_trade_mult)))
    choke_tag = "choke" if is_choke else "open"
    urgency = 0.25
    if fuel < 0.45:
        urgency += 0.25
    if zone in ("hostile", "contested"):
        urgency += 0.2
    if is_choke:
        urgency += 0.15
    if basing in ("none", "anchorage") and fuel < 0.6:
        urgency += 0.1
    urgency = min(1.0, urgency)
    score = max(0.05, 1.0 - urgency * 0.55 + (sea - 1.0) * 0.2)
    label = (
        "Naval skim · #%d · %s · fuel %.0f%% · zone %s · %s · sea×%.2f"
        % (province_id, basing, fuel * 100.0, zone, choke_tag, sea)
    )
    return {
        "province_id": province_id,
        "basing_level": basing,
        "fuel_level": fuel,
        "zone_relation": zone,
        "is_choke": bool(is_choke),
        "sea_trade_mult": sea,
        "urgency": urgency,
        "score": score,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]⚓ Naval skim[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["basing", "fuel", "zone", "choke"],
    }


def hh_agenda_player_path(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    max_actions: int = 3,
) -> Dict[str, Any]:
    """One-click HH player path: primary commit + counterplay without full trail dump."""
    t = list(trail or [])
    if not t:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }
    # Score from latest influence
    last = t[-1] if isinstance(t[-1], Mapping) else {}
    influence = 0.4
    try:
        influence = float(last.get("influence", last.get("score", 0.4)) or 0.4)
    except (TypeError, ValueError):
        influence = 0.4
    action_class = str(last.get("class", last.get("action_class", "sabotage")) or "sabotage")
    score = max(0.15, min(1.0, influence if influence <= 1.5 else influence / 100.0))
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_hh_commit",
            "province_id": -1,
            "score": max(0.35, score),
            "enabled": True,
            "label": "Commit HH agenda",
        },
        {
            "action_id": "apply_counterplay",
            "province_id": province_id,
            "score": max(0.3, score * 0.9),
            "enabled": True,
            "label": "Counter-intel",
            "action_class": action_class,
        },
    ]
    if score >= 0.45:
        apply_queue.append(
            {
                "action_id": "apply_agent_dispatch",
                "province_id": province_id,
                "score": score,
                "enabled": True,
                "label": "Dispatch agents",
                "action_class": action_class,
            }
        )
    apply_queue = apply_queue[: max(1, int(max_actions))]
    label = "HH player path · trail %d · class %s · score %.2f · q %d" % (
        len(t),
        action_class,
        score,
        len(apply_queue),
    )
    return {
        "trail_count": len(t),
        "action_class": action_class,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "hh_player_path",
                "label": "Run HH player path",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]🕵 HH player path[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["hh_commit", "counterplay", "dispatch"],
    }


def medium_horizon_equip_plan(
    *,
    infantry_stock: float = 5.0,
    tank_stock: float = 0.0,
    tank_line_progress: float = 0.15,
    days_horizon: int = 60,
    factories: int = 14,
) -> Dict[str, Any]:
    """Medium-horizon equip honesty: will a second line class move under ≤60d?

    Pure estimate — infantry is proven at 20d; tanks need multi-month unless
    factories/progress are high enough. Returns seed recommendation for honesty.
    """
    days = max(1, int(days_horizon))
    fac = max(0, int(factories))
    inf = max(0.0, float(infantry_stock))
    tanks = max(0.0, float(tank_stock))
    progress = max(0.0, min(1.0, float(tank_line_progress)))
    # Rough: each factory-day adds ~progress_rate toward one tank unit
    rate = 0.012 * max(1, fac // 4)  # ~slow medium tank line
    projected = progress + rate * days
    will_complete = projected >= 1.0
    delta_tanks = 1.0 if will_complete else 0.0
    # Seed recommendation if tanks cannot move
    seed_needed = not will_complete and tanks < 1.0
    seed_design = "infantry_k98_bolt_action" if seed_needed else ""
    if seed_needed and fac >= 10:
        # Prefer light armor seed as second class when industry exists
        seed_design = "light_tank_line_seed"
    score = 0.55 if will_complete else (0.35 if seed_needed else 0.4)
    label = (
        "Medium-horizon equip · %dd · tanks stock %.0f · progress %.0f%% → %.0f%% · %s"
        % (
            days,
            tanks,
            progress * 100.0,
            min(100.0, projected * 100.0),
            "complete" if will_complete else ("seed second line" if seed_needed else "partial"),
        )
    )
    apply_queue: List[Dict[str, Any]] = []
    if seed_needed:
        apply_queue.append(
            {
                "action_id": "apply_production",
                "province_id": -1,
                "score": 0.5,
                "enabled": True,
                "priority": "secondary",
                "design_hint": seed_design,
            }
        )
    return {
        "days_horizon": days,
        "infantry_stock": inf,
        "tank_stock": tanks,
        "tank_line_progress": progress,
        "projected_progress": min(1.5, projected),
        "will_complete_tank": will_complete,
        "seed_needed": seed_needed,
        "seed_design": seed_design,
        "factories": fac,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "medium_horizon_equip",
                "label": "Review medium-horizon equip",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]🏭 Medium-horizon equip[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["production", "oob", "stockpile"],
    }


def close_order_panel_ux_depth_loop() -> Dict[str, Any]:
    plan = order_panel_section_plan(compact=True, max_expanded=2)
    ids = order_panel_action_ids(plan)
    primary = order_panel_primary_actions(plan)
    naval = naval_campaign_skim(is_choke=True, fuel_level=0.4, zone_relation="hostile")
    hh = hh_agenda_player_path(
        [{"class": "sabotage", "influence": 0.55, "month": 1}], province_id=1
    )
    equip = medium_horizon_equip_plan(tank_stock=0.0, tank_line_progress=0.1, days_horizon=60)
    label = (
        "Close panel UX · sections %d · actions %d · primary %d · naval urg %.2f · hh q %d · equip %s"
        % (
            len(plan.get("sections") or []),
            len(ids),
            len(primary),
            float(naval.get("urgency", 0)),
            len(hh.get("apply_queue") or []),
            "seed" if equip.get("seed_needed") else "ok",
        )
    )
    return {
        "plan": plan,
        "action_ids": ids,
        "primary": primary,
        "naval": naval,
        "hh": hh,
        "equip": equip,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close panel UX[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }
