#!/usr/bin/env python3
"""Pure helpers for next TODO slice: DebugOverlay split, damage/sabotage map visuals, HH monthly map signal.

Mirrored by scripts/map/MapNextListHelpers.gd — keep outputs in sync.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

# Section titles classified as Dev Harness (default collapsed). Everything else is Player Map.
DEV_HARNESS_SECTION_TITLES = frozenset(
    {
        "Zero-Interference Full Europe Playtest Harness",
        "Demographic Map Test (Relocation/Settlement)",
        "Map Gen — Phase 1 (Proposed Splits)",
        "Phase 1 Test Tools",
        "Map Visual Editor (Starter)",
        "Province Border Editor (In-Game)",
        "Aircraft Prototyping (Skeleton)",
    }
)

PLAYER_MAP_SECTION_TITLES = frozenset(
    {
        "Player Map",
        "Infrastructure Projects",
        "Time & Simulation",
        "Quick Actions",
        "Map Modes",
    }
)

# Tint keys consumeable by MapRenderer / overlay (must match GD mirror)
TINT_SABOTAGE = "infra_sabotage"
TINT_DEPOT = "depot_sabotage"
TINT_SITE_DAMAGE = "site_damage"
TINT_PROJECT_SABO = "project_sabotage"
TINT_HH_INFLUENCE = "hh_influence"
TINT_CLEAN = "clean"


def is_dev_harness_section(title: str) -> bool:
    t = (title or "").strip()
    if t in DEV_HARNESS_SECTION_TITLES:
        return True
    # Heuristic fallbacks for future harness sections
    low = t.lower()
    if "harness" in low or "playtest" in low or "map gen" in low or "editor" in low:
        return True
    if "prototyping" in low or "test tools" in low:
        return True
    return False


def section_start_collapsed(title: str) -> bool:
    """Dev Harness starts collapsed; Player Map sections start expanded."""
    return is_dev_harness_section(title)


def section_kind(title: str) -> str:
    return "dev_harness" if is_dev_harness_section(title) else "player_map"


def classify_map_damage(state: Dict[str, Any]) -> Dict[str, Any]:
    """Classify province map visual for damage/sabotage from live state flags.

    Expected keys (all optional): under_infra_sabotage (bool), depot_sabotage_level (0-1),
    site_damaged_count (int), project_sabotaged (bool), agent_pressure_kind (str),
    infrastructure (int).
    Returns role, tint_key, marker, strength (0-1), label, is_damaged.
    """
    under = bool(state.get("under_infra_sabotage", False))
    depot = float(state.get("depot_sabotage_level", 0.0) or 0.0)
    sites = int(state.get("site_damaged_count", 0) or 0)
    proj = bool(state.get("project_sabotaged", False))
    kind = str(state.get("agent_pressure_kind", "") or "")
    infra = int(state.get("infrastructure", 50) or 50)

    if under or kind == "sabotage":
        strength = 0.42 if under else 0.28
        if infra <= 15:
            strength = min(0.65, strength + 0.12)
        return {
            "role": TINT_SABOTAGE,
            "tint_key": TINT_SABOTAGE,
            "marker": "⚠",
            "strength": round(strength, 3),
            "label": "Infrastructure sabotage",
            "is_damaged": True,
        }
    if depot > 0.05:
        strength = min(0.55, 0.18 + depot * 0.45)
        return {
            "role": TINT_DEPOT,
            "tint_key": TINT_DEPOT,
            "marker": "⛟",
            "strength": round(strength, 3),
            "label": "Depot sabotage %.0f%%" % (depot * 100.0),
            "is_damaged": True,
        }
    if sites > 0:
        strength = min(0.5, 0.2 + sites * 0.1)
        return {
            "role": TINT_SITE_DAMAGE,
            "tint_key": TINT_SITE_DAMAGE,
            "marker": "💥",
            "strength": round(strength, 3),
            "label": "Special site damage ×%d" % sites,
            "is_damaged": True,
        }
    if proj:
        return {
            "role": TINT_PROJECT_SABO,
            "tint_key": TINT_PROJECT_SABO,
            "marker": "⚠",
            "strength": 0.32,
            "label": "Investment project sabotaged",
            "is_damaged": True,
        }
    if kind == "disrupt":
        return {
            "role": "supply_pressure",
            "tint_key": "supply_pressure",
            "marker": "⛟",
            "strength": 0.2,
            "label": "Supply pressure",
            "is_damaged": True,
        }
    return {
        "role": TINT_CLEAN,
        "tint_key": TINT_CLEAN,
        "marker": "",
        "strength": 0.0,
        "label": "",
        "is_damaged": False,
    }


def format_hh_monthly_map_signal(
    year: int,
    month: int,
    province_id: int,
    province_name: str,
    action_class: str,
    influence: float,
    owner_tag: str = "",
) -> Dict[str, Any]:
    """Build player-facing Hidden Hand monthly map/inspector payload.

    action_class: sabotage | economic_pressure | infiltration | propaganda | influence | black_market
    """
    action = (action_class or "influence").strip().lower()
    if action not in (
        "sabotage",
        "propaganda",
        "influence",
        "black_market",
        "economic_pressure",
        "infiltration",
    ):
        action = "influence"
    name = province_name or ("Province %d" % int(province_id))
    titles = {
        "sabotage": "Hidden Hand sabotage",
        "propaganda": "Hidden Hand propaganda",
        "influence": "Hidden Hand influence",
        "black_market": "Hidden Hand black market",
        "economic_pressure": "Hidden Hand economic pressure",
        "infiltration": "Hidden Hand infiltration",
    }
    markers = {
        "sabotage": "⚠",
        "propaganda": "📢",
        "influence": "👁",
        "black_market": "💰",
        "economic_pressure": "💵",
        "infiltration": "◈",
    }
    title = titles[action]
    marker = markers[action]
    inf = max(0.0, min(1.0, float(influence)))
    body = (
        "%s in %s (#%d)%s — influence %.0f%%. Counter with agents or policy."
        % (
            title,
            name,
            int(province_id),
            (" [%s]" % owner_tag) if owner_tag else "",
            inf * 100.0,
        )
    )
    inspector_line = "[color=#c084fc]%s %s[/color] [color=#8899aa]%s · %04d-%02d[/color]" % (
        marker,
        title,
        name,
        int(year),
        int(month),
    )
    if action == "sabotage":
        tint = TINT_SABOTAGE
        map_effect = "infra_damage"
        sfx = "error"
    elif action == "economic_pressure":
        tint = "supply_pressure"
        map_effect = "industrial_pressure"
        sfx = "confirm"
    elif action == "infiltration":
        tint = "loyalty_strain"
        map_effect = "loyalty_infiltration"
        sfx = "map"
    else:
        tint = TINT_HH_INFLUENCE
        map_effect = ""
        sfx = "select"
    return {
        "active": True,
        "year": int(year),
        "month": int(month),
        "province_id": int(province_id),
        "province_name": name,
        "owner_tag": owner_tag or "",
        "action_class": action,
        "action_kind": "hh_signal",
        "influence": round(inf, 3),
        "title": title,
        "marker": marker,
        "tint_key": tint,
        "strength": round(0.22 + inf * 0.28, 3),
        "toast": body,
        "sfx": sfx,
        "duration": 4.5 if map_effect else 3.5,
        "news_headline": title,
        "news_body": body,
        "inspector_line": inspector_line,
        "label": "%s %s" % (marker, title),
        "map_effect": map_effect,
        "tooltip_chip": inspector_line,
    }


# The three map-visible HH fingerprints (distinct marker + tint + map_effect).
HH_MAP_VISIBLE_CLASSES = ("sabotage", "economic_pressure", "infiltration")


def pick_hh_action_class(month: int, hand_influence: float) -> str:
    """Deterministic monthly action class from calendar + influence."""
    m = int(month) % 12
    if hand_influence >= 0.45 and m % 3 == 0:
        return "sabotage"
    if hand_influence >= 0.35 and m % 3 == 1:
        return "economic_pressure"
    # Third map-visible class: institutional infiltration / loyalty strain
    if hand_influence >= 0.30 and m % 3 == 2:
        return "infiltration"
    if m % 4 == 1:
        return "propaganda"
    if m % 5 == 2:
        return "black_market"
    return "influence"


def pick_hh_secondary_action_class(
    month: int, hand_influence: float, primary_action: str
) -> str:
    """Complementary second fingerprint so two HH map signals can coexist."""
    primary = (primary_action or "influence").strip().lower()
    m = int(month) % 12
    hand = max(0.0, min(1.0, float(hand_influence)))
    if primary == "sabotage":
        return "infiltration" if hand >= 0.35 else "economic_pressure"
    if primary == "economic_pressure":
        return "infiltration" if hand >= 0.3 else "sabotage"
    if primary == "infiltration":
        return "sabotage" if hand >= 0.4 else "economic_pressure"
    if primary == "propaganda":
        return "infiltration" if m % 2 == 0 else "black_market"
    if primary == "black_market":
        return "infiltration" if hand >= 0.3 else "propaganda"
    if hand >= 0.4 and m % 2 == 0:
        return "economic_pressure"
    return "infiltration" if hand >= 0.28 else "propaganda"


def default_harness_visible() -> bool:
    """F5 play default: Dev Harness content hidden."""
    return False


def default_player_map_visible() -> bool:
    return True


# --- Map action flair (select + invest/project complete) ---

def format_province_select_flair(
    province_name: str,
    owner_tag: str = "",
    region_name: str = "",
    terrain: str = "",
    damage_label: str = "",
    hh_active: bool = False,
    is_chokepoint: bool = False,
    sea_zone_name: str = "",
    is_coastal: bool = False,
) -> Dict[str, Any]:
    """Player-facing toast + tooltip chip when selecting a province on the map."""
    name = (province_name or "Province").strip()
    owner = (owner_tag or "").strip().upper()
    region = (region_name or "").strip()
    terr = (terrain or "").strip().capitalize()
    sea = (sea_zone_name or "").strip()
    bits: List[str] = [name]
    if owner:
        bits.append(owner)
    if region:
        bits.append(region)
    if sea:
        bits.append("⚓ " + sea)
    elif is_chokepoint:
        bits.append("⚓ Naval chokepoint")
    elif is_coastal:
        bits.append("🌊 Coast")
    if terr:
        bits.append(terr)
    toast = "Selected · " + " · ".join(bits)
    if damage_label:
        toast += " · ⚠ %s" % damage_label
    if hh_active:
        toast += " · 👁 Hand activity here"
    tooltip_chip = "[color=#6eb5ff]◎ Selected[/color] [color=#8899aa]%s[/color]" % name
    if owner:
        tooltip_chip += " [color=#a0c0ff]%s[/color]" % owner
    if sea:
        tooltip_chip += " [color=#5ec8ff]⚓ %s[/color]" % sea
    elif is_chokepoint:
        tooltip_chip += " [color=#5ec8ff]⚓ Chokepoint[/color]"
    elif is_coastal:
        tooltip_chip += " [color=#5ec8ff]🌊 Coast[/color]"
    navalish = bool(is_chokepoint or sea or is_coastal)
    sfx = "confirm" if navalish else "select"
    return {
        "toast": toast,
        "tooltip_chip": tooltip_chip,
        "sfx": sfx,
        "duration": 2.0 if navalish else 1.8,
        "province_name": name,
        "owner_tag": owner,
        "is_chokepoint": bool(is_chokepoint),
        "sea_zone_name": sea,
        "is_coastal": bool(is_coastal),
        "action_kind": "select",
    }


def format_infra_project_flair(
    province_name: str,
    kind: str = "complete",
    new_level: int = 0,
    eta_days: int = 0,
    cost_pp: int = 0,
) -> Dict[str, Any]:
    """Toast/sfx payload for invest start or project complete."""
    name = (province_name or "Province").strip()
    k = (kind or "complete").strip().lower()
    if k in ("start", "invest", "started"):
        toast = "Infrastructure investment started in %s" % name
        if eta_days > 0:
            toast += " — ETA ~%d days" % int(eta_days)
        if cost_pp > 0:
            toast += " (spent %d Mandate)" % int(cost_pp)
        sfx = "confirm"
        title = "Investment started"
        action_kind = "invest_start"
    elif k in ("cancel", "cancelled"):
        toast = "Infrastructure project cancelled in %s" % name
        sfx = "error"
        title = "Investment cancelled"
        action_kind = "invest_cancel"
    else:
        toast = "Infrastructure project complete in %s" % name
        if new_level > 0:
            toast += " → level %d" % int(new_level)
        sfx = "achievement"
        title = "Infrastructure complete"
        action_kind = "invest_complete"
    return {
        "toast": toast,
        "title": title,
        "sfx": sfx,
        "duration": 3.0 if k not in ("cancel", "cancelled") else 2.2,
        "province_name": name,
        "kind": k,
        "new_level": int(new_level),
        "news_headline": title,
        "news_body": toast,
        "action_kind": action_kind,
        "tooltip_chip": "[color=#6ec8ff]%s[/color] [color=#8899aa]%s[/color]" % (title, name),
    }


def format_capture_assault_flair(
    province_name: str,
    attacker_tag: str = "",
    defender_tag: str = "",
    captured: bool = False,
    outcome: str = "",
    winner: str = "",
) -> Dict[str, Any]:
    """Toast/sfx payload after province assault (capture victory or hold/repulse)."""
    name = (province_name or "Province").strip()
    atk = (attacker_tag or "").strip().upper()
    dfn = (defender_tag or "").strip().upper()
    win = (winner or "").strip().lower()
    outc = (outcome or "").strip()
    if captured:
        toast = "%s captured %s" % (atk or "Attacker", name)
        if outc:
            toast += " (%s)" % outc
        sfx = "achievement"
        title = "Province captured"
        action_kind = "capture"
        tooltip = "[color=#7dffb2]⚔ Captured[/color] [color=#8899aa]%s[/color]" % name
        if atk:
            tooltip += " [color=#a0c0ff]%s[/color]" % atk
    elif win == "attacker":
        toast = "Attack repulsed at %s" % name
        if outc:
            toast += " — %s" % outc
        sfx = "confirm"
        title = "Assault repulsed"
        action_kind = "assault_repulse"
        tooltip = "[color=#ff9a6e]⚔ Repulsed[/color] [color=#8899aa]%s[/color]" % name
    else:
        toast = "%s held %s" % (dfn or "Defender", name)
        if outc:
            toast += " — %s" % outc
        sfx = "map"
        title = "Province held"
        action_kind = "assault_hold"
        tooltip = "[color=#6eb5ff]⚔ Held[/color] [color=#8899aa]%s[/color]" % name
        if dfn:
            tooltip += " [color=#a0c0ff]%s[/color]" % dfn
    return {
        "toast": toast,
        "title": title,
        "sfx": sfx,
        "duration": 4.0 if captured else 3.5,
        "province_name": name,
        "attacker_tag": atk,
        "defender_tag": dfn,
        "captured": bool(captured),
        "winner": win,
        "outcome": outc,
        "action_kind": action_kind,
        "tooltip_chip": tooltip,
        "news_headline": title,
        "news_body": toast,
    }


# --- HH counterplay ---

def apply_hh_counterplay(
    hand_influence: float,
    signal: Optional[Dict[str, Any]] = None,
    method: str = "counter_intel",
    clear_signal: bool = True,
    reduction: float = 0.12,
) -> Dict[str, Any]:
    """Reduce Hidden Hand influence and optionally clear monthly map signal.

    Returns player-facing payload + new_influence + updated_signal.
    """
    old = max(0.0, min(1.0, float(hand_influence)))
    red = max(0.02, min(0.5, float(reduction)))
    method_key = (method or "counter_intel").strip().lower()
    if method_key in ("policy", "reform"):
        red = max(red, 0.08)
    elif method_key in ("agent", "counter_intel", "sweep"):
        red = max(red, 0.12)
    new_inf = max(0.0, min(1.0, old - red))
    sig = dict(signal or {})
    pid = int(sig.get("province_id", -1)) if sig else -1
    pname = str(sig.get("province_name", "")) if sig else ""
    cleared = False
    if clear_signal and sig and bool(sig.get("active", False)):
        sig = dict(sig)
        sig["active"] = False
        sig["cleared_by"] = method_key
        sig["strength"] = 0.0
        sig["toast"] = "Hand activity disrupted"
        cleared = True
    delta = old - new_inf
    toast = "Counter-intel: Hidden Hand influence −%.0f%% (now %.0f%%)" % (delta * 100.0, new_inf * 100.0)
    if cleared and pname:
        toast += " · map signal cleared on %s" % pname
    elif cleared:
        toast += " · monthly map signal cleared"
    inspector = (
        "[color=#6ec8ff]🛡 Counter-intel[/color] [color=#8899aa]Hand −%.0f%% → %.0f%%[/color]"
        % (delta * 100.0, new_inf * 100.0)
    )
    return {
        "success": delta > 0.001 or cleared,
        "method": method_key,
        "old_influence": round(old, 3),
        "new_influence": round(new_inf, 3),
        "reduction": round(delta, 3),
        "signal_cleared": cleared,
        "province_id": pid,
        "province_name": pname,
        "updated_signal": sig,
        "toast": toast,
        "news_headline": "Hidden Hand pushed back",
        "news_body": toast,
        "inspector_line": inspector,
        "label": "🛡 Counter-intel",
    }
