"""Naval basing level + fleet capacity (pure decision helper).

Classifies provinces into basing tiers from domain / port / choke / site signals.
No Godot dependency — mirrored by MapPolishFormatters.compute_naval_basing.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Optional

# Distinct non-trivial capacity by level (documented pilot tiers).
LEVEL_NONE = "none"
LEVEL_ANCHORAGE = "anchorage"
LEVEL_PORT = "port"
LEVEL_MAJOR = "major_base"

CAPACITY_NONE = 0
CAPACITY_ANCHORAGE = 2
CAPACITY_PORT = 6
CAPACITY_MAJOR = 12


def _norm_domain(domain: str, is_sea: bool = False) -> str:
    d = str(domain or "").strip().lower()
    if not d and is_sea:
        return "sea"
    return d


def compute_naval_basing(
    *,
    domain: str = "",
    is_sea: bool = False,
    is_coastal: bool = False,
    has_port: bool = False,
    port_tier: int = 0,
    has_naval_shipyard: bool = False,
    has_naval_base: bool = False,
    is_chokepoint: bool = False,
    facility_tier: str = "",
    in_sea_zone: bool = False,
    province_id: int = 0,
) -> Dict[str, Any]:
    """Return basing level, capacity, and summary for a province-shaped input.

    Levels (highest wins):
      none       — landlocked / lake / open sea without port infrastructure
      anchorage  — coastal access, no developed port
      port       — port flag / port site / full facility coastal / strait
      major_base — naval shipyard/base, port_tier≥3, or choke with port/strait

    Capacity is non-trivial and strictly ordered none < anchorage < port < major.
    """
    dom = _norm_domain(domain, is_sea=is_sea)
    coastal = bool(is_coastal) or dom in ("coastal_land", "coastal")
    strait = dom == "strait"
    sea_domain = bool(is_sea) or dom in ("sea", "ocean")
    landlocked = dom in ("land", "") and not coastal and not strait and not sea_domain
    lake = dom == "lake"
    fac = str(facility_tier or "").strip().lower()
    p_tier = max(0, int(port_tier or 0))
    portish = bool(has_port) or p_tier >= 1
    shipyard = bool(has_naval_shipyard) or bool(has_naval_base)
    choke = bool(is_chokepoint) or strait

    # Open sea / lake / pure land without naval hooks → none
    if lake or (landlocked and not choke and not portish and not shipyard):
        level = LEVEL_NONE
        capacity = CAPACITY_NONE
        label = "no basing"
        reason = "landlocked" if landlocked else "lake"
    elif sea_domain and not choke and not portish and not shipyard and not coastal:
        level = LEVEL_NONE
        capacity = CAPACITY_NONE
        label = "open waters"
        reason = "sea_no_base"
    else:
        # Major base
        if (
            shipyard
            or p_tier >= 3
            or (choke and (portish or strait or p_tier >= 2))
        ):
            level = LEVEL_MAJOR
            capacity = CAPACITY_MAJOR
            if shipyard:
                capacity += 4
            if choke:
                capacity += 2
            if p_tier >= 3:
                capacity += 2
            capacity = min(capacity, 20)
            label = "major naval base"
            reason = "shipyard" if shipyard else ("port_tier3" if p_tier >= 3 else "choke_port")
        elif portish or p_tier >= 2 or (coastal and fac == "full") or strait:
            level = LEVEL_PORT
            capacity = CAPACITY_PORT
            if p_tier >= 2:
                capacity += 2
            if choke:
                capacity += 2
            if fac == "full":
                capacity += 1
            if bool(in_sea_zone):
                capacity += 1
            capacity = min(capacity, 12)
            label = "port"
            reason = "port" if portish or p_tier >= 2 else ("facility" if fac == "full" else "strait")
        elif coastal or choke or bool(in_sea_zone):
            level = LEVEL_ANCHORAGE
            capacity = CAPACITY_ANCHORAGE
            if bool(in_sea_zone):
                capacity += 1
            if choke:
                capacity += 1
            label = "anchorage"
            reason = "coastal" if coastal else ("choke" if choke else "sea_zone")
        else:
            level = LEVEL_NONE
            capacity = CAPACITY_NONE
            label = "no basing"
            reason = "no_naval_signal"

    summary = "%s · capacity %d" % (label, int(capacity))
    return {
        "province_id": int(province_id),
        "level": level,
        "capacity": int(capacity),
        "label": label,
        "reason": reason,
        "summary": summary,
        "is_naval": level != LEVEL_NONE,
        "domain": dom,
        "is_coastal": coastal,
        "is_chokepoint": choke,
        "has_port": portish,
        "port_tier": p_tier,
        "has_naval_shipyard": shipyard,
        "in_sea_zone": bool(in_sea_zone),
    }


def format_naval_basing_badge(
    basing: Mapping[str, Any],
    *,
    color_tech: str = "[color=#5ec8ff]",
    color_muted: str = "[color=#8899aa]",
    color_warn: str = "[color=#ff9a6e]",
) -> str:
    """BBCode inspector line for basing (empty if none)."""
    level = str(basing.get("level", LEVEL_NONE))
    if level == LEVEL_NONE or not bool(basing.get("is_naval", level != LEVEL_NONE)):
        return ""
    cap = int(basing.get("capacity", 0))
    label = str(basing.get("label", level)).strip() or level
    bits = [label, "capacity %d" % cap]
    if bool(basing.get("is_chokepoint")):
        bits.append("choke")
    if int(basing.get("port_tier") or 0) >= 2:
        bits.append("port-t%d" % int(basing.get("port_tier")))
    if bool(basing.get("has_naval_shipyard")):
        bits.append("shipyard")
    detail = " · ".join(bits)
    color = color_warn if level == LEVEL_MAJOR else color_tech
    return "%s⚓ Naval basing[/color] %s— %s[/color]" % (color, color_muted, detail)


def basing_from_province_signals(signals: Mapping[str, Any]) -> Dict[str, Any]:
    """Convenience: unpack a signal dict (for batch/world samples)."""
    return compute_naval_basing(
        domain=str(signals.get("domain", "")),
        is_sea=bool(signals.get("is_sea", False)),
        is_coastal=bool(signals.get("is_coastal", False)),
        has_port=bool(signals.get("has_port", False)),
        port_tier=int(signals.get("port_tier", 0) or 0),
        has_naval_shipyard=bool(signals.get("has_naval_shipyard", False)),
        has_naval_base=bool(signals.get("has_naval_base", False)),
        is_chokepoint=bool(signals.get("is_chokepoint", False)),
        facility_tier=str(signals.get("facility_tier", "")),
        in_sea_zone=bool(signals.get("in_sea_zone", False)),
        province_id=int(signals.get("province_id", 0) or 0),
    )


def level_rank(level: str) -> int:
    order = {
        LEVEL_NONE: 0,
        LEVEL_ANCHORAGE: 1,
        LEVEL_PORT: 2,
        LEVEL_MAJOR: 3,
    }
    return int(order.get(str(level), 0))


# Per-day basing service rates (fuel 0–1 scale; org/readiness/strength 0–1 scale).
# Port tier matches historical flat at_port recovery so mid-tier behavior stays familiar.
_BASE_RATES = {
    LEVEL_NONE: {
        "refuel_rate": 0.0,
        "repair_org_rate": 0.0,
        "repair_readiness_rate": 0.0,
        "repair_strength_rate": 0.0,
    },
    LEVEL_ANCHORAGE: {
        "refuel_rate": 0.10,
        "repair_org_rate": 0.015,
        "repair_readiness_rate": 0.012,
        "repair_strength_rate": 0.008,
    },
    LEVEL_PORT: {
        "refuel_rate": 0.25,
        "repair_org_rate": 0.04,
        "repair_readiness_rate": 0.03,
        "repair_strength_rate": 0.02,
    },
    LEVEL_MAJOR: {
        "refuel_rate": 0.40,
        "repair_org_rate": 0.06,
        "repair_readiness_rate": 0.05,
        "repair_strength_rate": 0.035,
    },
}


def basing_repair_refuel_rates(
    basing: Optional[Mapping[str, Any]] = None,
    *,
    level: str = "",
    capacity: int = -1,
) -> Dict[str, Any]:
    """Map basing level/capacity → daily repair/refuel rates.

    Distinct non-trivial ordering:
      none (0) < anchorage < port < major_base
    Capacity above the level baseline adds a small positive scale (capped).
    Landlocked/none never receive port-tier recovery.
    """
    b = dict(basing or {})
    lv = str(level or b.get("level", LEVEL_NONE)).strip().lower() or LEVEL_NONE
    if lv not in _BASE_RATES:
        lv = LEVEL_NONE
    cap = int(capacity if capacity >= 0 else b.get("capacity", 0) or 0)
    if not bool(b.get("is_naval", lv != LEVEL_NONE)) and lv != LEVEL_NONE:
        # Explicit non-naval basing dict forces none
        if "is_naval" in b and not b.get("is_naval"):
            lv = LEVEL_NONE
            cap = 0

    base = dict(_BASE_RATES[lv])
    # Capacity scaling: each point above level baseline adds ~1.5% up to +25%
    baseline_cap = {
        LEVEL_NONE: 0,
        LEVEL_ANCHORAGE: CAPACITY_ANCHORAGE,
        LEVEL_PORT: CAPACITY_PORT,
        LEVEL_MAJOR: CAPACITY_MAJOR,
    }.get(lv, 0)
    extra = max(0, cap - baseline_cap)
    scale = 1.0 + min(0.25, extra * 0.015)
    if lv == LEVEL_NONE or cap <= 0 and lv == LEVEL_NONE:
        scale = 1.0

    refuel = float(base["refuel_rate"]) * scale
    org = float(base["repair_org_rate"]) * scale
    ready = float(base["repair_readiness_rate"]) * scale
    strength = float(base["repair_strength_rate"]) * scale
    can_service = lv != LEVEL_NONE and (refuel > 0.0 or org > 0.0)
    return {
        "level": lv,
        "capacity": cap,
        "refuel_rate": refuel,
        "repair_org_rate": org,
        "repair_readiness_rate": ready,
        "repair_strength_rate": strength,
        "can_service": can_service,
        "scale": scale,
        "summary": (
            "refuel ×%.3f/d · org ×%.3f/d · ready ×%.3f/d · str ×%.3f/d (%s)"
            % (refuel, org, ready, strength, lv)
        ),
    }
