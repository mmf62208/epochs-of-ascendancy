"""Pure weather combat/supply/move multipliers (mirrors WeatherManager decisions).

Inputs are weather-shaped dicts: temp, precip_intensity, visibility, wind, ground_state.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

GROUND_MOVE = {
    "dry": 1.0,
    "wet": 0.9,
    "mud": 0.75,
    "frozen": 0.85,
    "snow_covered": 0.85,
    "ice": 0.8,
}


def movement_multiplier(
    weather: Mapping[str, Any],
    *,
    unit_tags: Optional[Sequence[str]] = None,
) -> float:
    w = dict(weather or {})
    g = str(w.get("ground_state", "dry")).lower()
    tags = [str(t).lower() for t in (unit_tags or [])]
    base = float(GROUND_MOVE.get(g, 1.0))
    if g == "mud" and any(t in tags for t in ("armor", "motorized", "mechanized")):
        base = min(base, 0.45)
    if g in ("frozen", "snow_covered") and "armor" in tags:
        base *= 1.15
    vis = float(w.get("visibility", 1.0) or 1.0)
    if vis < 0.3:
        base *= 0.6
    return max(0.15, min(1.5, base))


def combat_weather_multiplier(weather: Mapping[str, Any]) -> float:
    """Attacker-side combat effectiveness (0.2–1.1)."""
    w = dict(weather or {})
    vis = float(w.get("visibility", 1.0) or 1.0)
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    wind = float(w.get("wind", 0.2) or 0.2)
    mult = vis * (1.0 - storm * 0.55) * (1.0 - max(0.0, wind - 0.4) * 0.2)
    return max(0.2, min(1.1, mult))


def supply_throughput_weather_multiplier(weather: Mapping[str, Any]) -> float:
    w = dict(weather or {})
    g = str(w.get("ground_state", "dry")).lower()
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    mult = 1.0
    if g == "mud":
        mult *= 0.7
    elif g in ("snow_covered", "ice", "frozen"):
        mult *= 0.85
    mult *= 1.0 - storm * 0.25
    return max(0.35, min(1.15, mult))


def production_weather_multiplier(weather: Mapping[str, Any]) -> float:
    w = dict(weather or {})
    t = float(w.get("temp", 10.0) or 10.0)
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    mult = 1.0
    if t < -15:
        mult *= 0.85
    elif t > 38:
        mult *= 0.9
    mult *= 1.0 - storm * 0.15
    return max(0.5, min(1.1, mult))


def naval_spotting_multiplier(weather: Mapping[str, Any]) -> float:
    w = dict(weather or {})
    vis = float(w.get("visibility", 1.0) or 1.0)
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    spot = vis * (1.0 - storm * 0.5)
    return max(0.05, min(1.2, spot))


def air_sortie_readiness(weather: Mapping[str, Any]) -> Dict[str, Any]:
    w = dict(weather or {})
    vis = float(w.get("visibility", 1.0) or 1.0)
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    wind = float(w.get("wind", 0.2) or 0.2)
    eff = max(0.05, min(1.0, vis * (1.0 - storm * 0.8) * (1.0 - max(0.0, wind - 0.5) * 0.3)))
    grounded = eff < 0.25
    return {
        "effectiveness": float(eff),
        "grounded": grounded,
        "can_sortie": not grounded,
        "summary": "air sortie %.0f%%%s" % (eff * 100.0, " GROUNDED" if grounded else ""),
    }


def storm_interdiction_bump(
    weather: Mapping[str, Any],
    base_interdiction: float = 0.1,
) -> Dict[str, Any]:
    w = dict(weather or {})
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    bump = storm * 0.18 + max(0.0, 0.5 - vis) * 0.12
    chance = max(0.0, min(0.95, float(base_interdiction) + bump))
    return {
        "base": float(base_interdiction),
        "bump": float(bump),
        "interdiction_chance": chance,
        "summary": "interdiction %.0f%% (+%.0f%% weather)" % (chance * 100.0, bump * 100.0),
    }


def season_label(month: int) -> Dict[str, Any]:
    m = int(month)
    if m in (12, 1, 2):
        season = "winter"
    elif m in (3, 4, 5):
        season = "spring"
    elif m in (6, 7, 8):
        season = "summer"
    else:
        season = "autumn"
    # Daylight hours rough mid-lat
    daylight = {"winter": 9.0, "spring": 12.5, "summer": 15.0, "autumn": 11.0}[season]
    return {
        "month": m,
        "season": season,
        "daylight_hours": daylight,
        "summary": "%s · ~%.0fh daylight" % (season, daylight),
    }


def rank_extreme_events(events: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    scored = []
    for e in events or []:
        if not isinstance(e, dict):
            continue
        sev = int(e.get("severity", e.get("level", 1)) or 1)
        et = str(e.get("type", e.get("event_type", "storm")))
        score = float(sev * 10)
        if et in ("emp_detonation", "nuke_atmo", "x_flare"):
            score += 25.0
        elif et in ("typhoon", "quake"):
            score += 15.0
        scored.append({"type": et, "severity": sev, "score": score})
    scored.sort(key=lambda x: (-float(x["score"]), x["type"]))
    best = scored[0] if scored else {}
    return {
        "ranked": scored,
        "worst": best,
        "empty": len(scored) == 0,
        "summary": (
            "worst event %s sev %s" % (best.get("type"), best.get("severity"))
            if best
            else "no extreme events"
        ),
    }


def format_weather_chip(weather: Mapping[str, Any], *, season: str = "") -> Dict[str, Any]:
    w = dict(weather or {})
    g = str(w.get("ground_state", "dry"))
    t = float(w.get("temp", 10.0) or 10.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    label = "Temp %.0f°C · %s · vis %.0f%%" % (t, g, vis * 100.0)
    if season:
        label = "%s · %s" % (season, label)
    combat = combat_weather_multiplier(w)
    supply = supply_throughput_weather_multiplier(w)
    return {
        "label": label,
        "combat_mult": combat,
        "supply_mult": supply,
        "bbcode": "[color=#5ec8ff]🌤 Weather[/color] [color=#8899aa]%s · combat ×%.2f · supply ×%.2f[/color]"
        % (label, combat, supply),
        "plain": label,
    }


def format_weather_legend() -> Dict[str, Any]:
    lines = [
        "dry · normal move/supply",
        "mud · heavy move penalty (armor worse)",
        "snow/frozen · mild move hit; winter wear",
        "storm/low vis · air/naval/spotting down; interdiction up",
    ]
    return {
        "lines": lines,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#5ec8ff]·[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
        "summary": "weather legend %d lines" % len(lines),
    }


def parse_weather_ready_line(line: str) -> Dict[str, Any]:
    text = str(line or "")
    ok = "WeatherManager ready" in text or "Weather:" in text
    return {"ok": ok, "raw": text, "summary": "weather marker %s" % ("found" if ok else "missing")}
