#!/usr/bin/env python3
"""Pure sea-zone control summary from province ownership within a zone.

Stub for naval feel: majority owner among zone provinces with tags; contested
when a second tag holds a material share. Empty zone → unowned.
"""

from __future__ import annotations

from collections import Counter
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Union


def _norm_tag(tag: Any) -> str:
    return str(tag or "").strip().upper()


def compute_sea_zone_control(
    zone_name: str,
    province_ids: Sequence[Union[int, str]],
    owners_by_pid: Mapping[Any, Any],
    *,
    contested_ratio: float = 0.25,
) -> Dict[str, Any]:
    """Return control summary for one sea-zone theater.

    owners_by_pid: province_id (str or int) -> country tag.
    """
    name = (zone_name or "").strip() or "Unknown Sea"
    counts: Counter = Counter()
    tagged_pids: List[int] = []
    for raw in province_ids or []:
        pid = int(raw)
        tag = _norm_tag(
            owners_by_pid.get(pid, owners_by_pid.get(str(pid), ""))
        )
        if tag:
            counts[tag] += 1
            tagged_pids.append(pid)

    total_tagged = sum(counts.values())
    if total_tagged <= 0:
        return {
            "zone": name,
            "controller": "",
            "owner": "",
            "contested": False,
            "unowned": True,
            "tag_counts": {},
            "province_count": len(list(province_ids or [])),
            "controlled_count": 0,
            "summary": "%s — unowned open waters" % name,
            "label": "Unowned",
        }

    ranked = counts.most_common()
    primary = ranked[0][0]
    primary_n = ranked[0][1]
    contested = False
    if len(ranked) > 1:
        second_n = ranked[1][1]
        if second_n / float(total_tagged) >= contested_ratio:
            contested = True

    tag_counts = {t: int(n) for t, n in ranked}
    if contested:
        summary = "%s — contested (%s lead, multi-nation presence)" % (name, primary)
        label = "Contested · %s" % primary
    else:
        summary = "%s — controlled by %s" % (name, primary)
        label = primary

    return {
        "zone": name,
        "controller": primary,
        "owner": primary,
        "contested": contested,
        "unowned": False,
        "tag_counts": tag_counts,
        "province_count": len(list(province_ids or [])),
        "controlled_count": total_tagged,
        "summary": summary,
        "label": label,
    }


def sea_zone_strategic_modifiers(control: Mapping[str, Any]) -> Dict[str, Any]:
    """Supply/trade multipliers from sea-zone control state.

    Distinct non-trivial values:
      controlled: supply 1.12, trade 1.10 (friendly sealanes)
      contested:  supply 0.92, trade 0.88 (convoy risk)
      unowned:    supply 1.00, trade 0.95 (neutral / no exclusive rights)
    """
    unowned = bool(control.get("unowned", False))
    contested = bool(control.get("contested", False))
    ctrl = str(control.get("controller", "")).strip().upper()
    if unowned or not ctrl:
        state = "unowned"
        supply = 1.00
        trade = 0.95
        label = "neutral waters"
    elif contested:
        state = "contested"
        supply = 0.92
        trade = 0.88
        label = "contested sealanes"
    else:
        state = "controlled"
        supply = 1.12
        trade = 1.10
        label = "controlled sealanes"
    return {
        "state": state,
        "controller": ctrl,
        "supply_multiplier": float(supply),
        "trade_multiplier": float(trade),
        "label": label,
        "summary": "supply ×%.2f · trade ×%.2f (%s)" % (supply, trade, label),
    }


def friendly_sea_zone_multipliers(
    control: Mapping[str, Any],
    friendly_tag: str = "",
) -> Dict[str, Any]:
    """Strategic multipliers relative to a friendly nation.

    - no/empty control (landlocked or unknown zone): 1.0 / 1.0 (no sealane effect)
    - unowned: supply 1.00, trade 0.95
    - contested: supply 0.92, trade 0.88
    - controlled by friendly: supply 1.12, trade 1.10
    - controlled by enemy: supply 0.85, trade 0.80 (hostile sealanes)
    """
    if not control:
        return {
            "state": "none",
            "relation": "no_zone",
            "supply_multiplier": 1.0,
            "trade_multiplier": 1.0,
            "label": "no sea zone",
            "summary": "supply ×1.00 · trade ×1.00 (no sea zone)",
            "applies": False,
        }
    base = sea_zone_strategic_modifiers(control)
    friend = str(friendly_tag or "").strip().upper()
    ctrl = str(base.get("controller", "")).strip().upper()
    state = str(base.get("state", "unowned"))
    if state == "unowned" or not ctrl:
        return {
            "state": "unowned",
            "relation": "neutral",
            "supply_multiplier": 1.00,
            "trade_multiplier": 0.95,
            "label": "neutral waters",
            "summary": "supply ×1.00 · trade ×0.95 (neutral waters)",
            "applies": True,
            "controller": ctrl,
        }
    if state == "contested":
        return {
            "state": "contested",
            "relation": "contested",
            "supply_multiplier": 0.92,
            "trade_multiplier": 0.88,
            "label": "contested sealanes",
            "summary": "supply ×0.92 · trade ×0.88 (contested sealanes)",
            "applies": True,
            "controller": ctrl,
        }
    # Exclusive control
    if friend and ctrl == friend:
        return {
            "state": "controlled",
            "relation": "friendly",
            "supply_multiplier": 1.12,
            "trade_multiplier": 1.10,
            "label": "friendly sealanes",
            "summary": "supply ×1.12 · trade ×1.10 (friendly sealanes)",
            "applies": True,
            "controller": ctrl,
        }
    if friend and ctrl and ctrl != friend:
        return {
            "state": "controlled",
            "relation": "hostile",
            "supply_multiplier": 0.85,
            "trade_multiplier": 0.80,
            "label": "hostile sealanes",
            "summary": "supply ×0.85 · trade ×0.80 (hostile sealanes)",
            "applies": True,
            "controller": ctrl,
        }
    # No friendly tag: fall back to raw strategic modifiers
    return {
        "state": state,
        "relation": "neutral",
        "supply_multiplier": float(base.get("supply_multiplier", 1.0)),
        "trade_multiplier": float(base.get("trade_multiplier", 1.0)),
        "label": str(base.get("label", "")),
        "summary": str(base.get("summary", "")),
        "applies": True,
        "controller": ctrl,
    }


def combine_path_multipliers(
    multipliers: Sequence[float],
    *,
    default: float = 1.0,
    min_v: float = 0.5,
    max_v: float = 1.25,
) -> float:
    """Average finite path multipliers; empty → default (landlocked-safe)."""
    vals = [float(x) for x in (multipliers or []) if x is not None]
    if not vals:
        return float(default)
    avg = sum(vals) / float(len(vals))
    if avg < min_v:
        return float(min_v)
    if avg > max_v:
        return float(max_v)
    return float(avg)


def apply_sea_zone_multiplier(
    base_amount: float,
    multiplier: float,
    *,
    min_v: float = 0.5,
    max_v: float = 1.25,
) -> float:
    """Scale a supply/trade scalar by a sea-zone multiplier (clamped)."""
    m = float(multiplier)
    if m < min_v:
        m = min_v
    if m > max_v:
        m = max_v
    return float(base_amount) * m


def format_sea_zone_control_badge(
    control: Mapping[str, Any],
    *,
    color_tech: str = "[color=#5ec8ff]",
    color_muted: str = "[color=#8899aa]",
    color_warn: str = "[color=#ff9a6e]",
    include_modifiers: bool = True,
) -> str:
    """BBCode badge line for inspector (mirrors ProvinceInsight sea zone style)."""
    zone = str(control.get("zone", "Sea")).strip() or "Sea"
    mods = sea_zone_strategic_modifiers(control)
    mod_bit = ""
    if include_modifiers:
        mod_bit = " · %s" % mods["summary"]
    if bool(control.get("unowned", False)):
        return (
            "%s🌊 Sea zone[/color] %s%s — unowned open waters%s[/color]"
            % (color_tech, color_muted, zone, mod_bit)
        )
    ctrl = str(control.get("controller", "")).strip().upper()
    if bool(control.get("contested", False)):
        return (
            "%s🌊 Sea zone[/color] %s%s[/color] %s— contested · lead %s%s[/color]"
            % (color_tech, color_muted, zone, color_warn, ctrl or "?", mod_bit)
        )
    return (
        "%s🌊 Sea zone[/color] %s%s — controlled by %s%s[/color]"
        % (color_tech, color_muted, zone, ctrl or "?", mod_bit)
    )


def control_for_zones_payload(
    zones: Sequence[Mapping[str, Any]],
    owners_by_pid: Mapping[Any, Any],
) -> List[Dict[str, Any]]:
    """Batch control for sea_zone_theaters.json zones array."""
    out: List[Dict[str, Any]] = []
    for z in zones or []:
        if not isinstance(z, dict):
            continue
        name = str(z.get("name", ""))
        pids = z.get("province_ids") or z.get("provinces") or []
        out.append(compute_sea_zone_control(name, pids, owners_by_pid))
    return out
