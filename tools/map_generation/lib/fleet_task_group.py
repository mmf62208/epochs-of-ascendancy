"""Fleet task-group composition pilot — screen/strike/support mix (beyond redeploy route).

Not full fleet AI: allocates available naval strength into SCREEN / STRIKE / SUPPORT
roles based on mission and zone threat.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping


ROLES = ("SCREEN", "STRIKE", "SUPPORT")


def compose_task_group(
    *,
    available_strength: float = 100.0,
    mission: str = "patrol",
    zone_relation: str = "contested",
    escort_need: float = 0.0,
) -> Dict[str, Any]:
    strength = max(0.0, float(available_strength))
    mission_l = str(mission or "patrol").lower()
    rel = str(zone_relation or "no_zone").lower()
    need = max(0.0, float(escort_need))

    # Base mix by mission
    if mission_l in ("convoy", "escort", "cover"):
        weights = {"SCREEN": 0.55, "STRIKE": 0.20, "SUPPORT": 0.25}
    elif mission_l in ("strike", "projection", "raid"):
        weights = {"SCREEN": 0.25, "STRIKE": 0.55, "SUPPORT": 0.20}
    elif mission_l in ("refuel", "base", "hold"):
        weights = {"SCREEN": 0.30, "STRIKE": 0.15, "SUPPORT": 0.55}
    else:  # patrol / default
        weights = {"SCREEN": 0.40, "STRIKE": 0.35, "SUPPORT": 0.25}

    if rel == "hostile":
        weights["SCREEN"] = weights.get("SCREEN", 0.3) + 0.10
        weights["STRIKE"] = weights.get("STRIKE", 0.3) + 0.05
    elif rel == "friendly":
        weights["SUPPORT"] = weights.get("SUPPORT", 0.2) + 0.08
    if need >= 25.0:
        weights["SCREEN"] = weights.get("SCREEN", 0.3) + 0.15

    total_w = sum(weights.values()) or 1.0
    alloc = {
        role: strength * (weights.get(role, 0.0) / total_w) for role in ROLES
    }
    primary = max(alloc.items(), key=lambda kv: (kv[1], kv[0]))[0]
    lines = [
        "Task group · primary %s · strength %.0f · %s" % (primary, strength, mission_l)
    ]
    for role in ROLES:
        lines.append("%s %.0f (%.0f%%)" % (role, alloc[role], 100.0 * alloc[role] / max(1.0, strength)))
    return {
        "mission": mission_l,
        "zone_relation": rel,
        "available_strength": strength,
        "allocation": alloc,
        "primary_role": primary,
        "empty": strength <= 0.0,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            [
                "[color=#5ec8ff]🚢 Task group[/color] [color=#8899aa]%s · %s[/color]"
                % (primary, mission_l)
            ]
            + [
                "[color=#8899aa]· %s %.0f[/color]" % (r, alloc[r]) for r in ROLES
            ]
        ),
        "summary": lines[0],
    }
