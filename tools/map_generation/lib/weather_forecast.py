"""Weather forecast stub + sea×weather supply + storm convoy risk (pilots).

Not full meteorological sim — deterministic next-day stub and combined
multipliers for live map/supply call sites.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Optional, Sequence

from weather_effects import (  # type: ignore
    air_sortie_readiness,
    combat_weather_multiplier,
    naval_spotting_multiplier,
    storm_interdiction_bump,
    supply_throughput_weather_multiplier,
)


def forecast_next_day(weather: Mapping[str, Any]) -> Dict[str, Any]:
    """Deterministic next-day weather stub from current conditions."""
    w = dict(weather or {})
    temp = float(w.get("temp", 10.0) or 10.0)
    precip = float(w.get("precip_intensity", 0.0) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    wind = float(w.get("wind", 0.2) or 0.2)
    ground = str(w.get("ground_state", "dry")).lower()
    # Slight mean-reversion + persistence
    next_temp = temp * 0.9 + 10.0 * 0.1
    next_precip = min(1.0, max(0.0, precip * 0.7 + (0.15 if precip > 0.5 else 0.0)))
    next_vis = min(1.0, max(0.1, vis * 0.85 + 0.15 * (1.0 - next_precip)))
    next_wind = min(1.0, max(0.05, wind * 0.8 + next_precip * 0.15))
    next_ground = ground
    if next_precip > 0.55 and next_temp > 2.0:
        next_ground = "mud"
    elif next_temp < -2.0 and next_precip > 0.2:
        next_ground = "snow_covered"
    elif next_precip < 0.15 and ground in ("mud", "wet"):
        next_ground = "dry"
    nxt = {
        "temp": float(next_temp),
        "precip_intensity": float(next_precip),
        "visibility": float(next_vis),
        "wind": float(next_wind),
        "ground_state": next_ground,
    }
    combat = combat_weather_multiplier(nxt)
    supply = supply_throughput_weather_multiplier(nxt)
    label = "Tomorrow · %s · vis %.0f%% · combat ×%.2f" % (
        next_ground,
        next_vis * 100.0,
        combat,
    )
    return {
        "forecast": nxt,
        "combat_mult": combat,
        "supply_mult": supply,
        "label": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]📅 Forecast[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def sea_weather_supply_multiplier(
    sea_supply_mult: float,
    weather: Mapping[str, Any],
) -> Dict[str, Any]:
    """Combine sea-zone control supply mult with weather supply mult."""
    sea = max(0.15, min(1.5, float(sea_supply_mult if sea_supply_mult is not None else 1.0)))
    wmult = supply_throughput_weather_multiplier(weather or {})
    combined = max(0.12, min(1.4, sea * wmult))
    return {
        "sea_mult": float(sea),
        "weather_mult": float(wmult),
        "combined": float(combined),
        "summary": "sea×weather supply ×%.2f (sea %.2f · wx %.2f)" % (combined, sea, wmult),
        "plain": "supply ×%.2f" % combined,
        "bbcode": (
            "[color=#5ec8ff]⚓ Sea×weather[/color] [color=#8899aa]supply ×%.2f[/color]"
            % combined
        ),
    }


def storm_convoy_risk(
    weather: Mapping[str, Any],
    *,
    path_zone_relations: Optional[Sequence[str]] = None,
    cargo_value: float = 100.0,
    base_interdiction: float = 0.1,
) -> Dict[str, Any]:
    """Escort/storm risk chip: storm interdiction + path hostility."""
    from naval_convoy_escort import score_convoy_escort_need  # type: ignore

    bump = storm_interdiction_bump(weather or {}, base_interdiction)
    rels = list(path_zone_relations or ["contested"])
    need = score_convoy_escort_need(
        rels,
        cargo_value=cargo_value,
        interdiction_chance=float(bump["interdiction_chance"]),
    )
    risk = float(need["risk"])
    storm = float((weather or {}).get("precip_intensity", 0.0) or 0.0)
    label = "Storm convoy risk %.0f%% · escort need %.1f" % (risk * 100.0, need["escort_need"])
    return {
        "risk": risk,
        "escort_need": float(need["escort_need"]),
        "interdiction_chance": float(bump["interdiction_chance"]),
        "storm": storm,
        "recommend_escort": bool(need["recommend_escort"]),
        "label": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🌊 Storm convoy[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def weather_aware_phase_ribbon(
    attacker_power: float,
    defender_power: float,
    weather_mult: float = 1.0,
) -> Dict[str, Any]:
    """Combat phase ribbon with weather mult applied to estimate."""
    from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
    from combat_phase_ui import format_phase_ribbon  # type: ignore

    est = estimate_multi_phase_combat(
        attacker_power, defender_power, weather_mult=float(weather_mult)
    )
    ribbon = format_phase_ribbon(est)
    label = "Weather×%.2f · %s" % (float(weather_mult), ribbon.get("ribbon_plain", ""))
    return {
        "estimate": est,
        "ribbon": ribbon,
        "weather_mult": float(weather_mult),
        "overall": float(est.get("overall_attacker_win_chance", 0.0)),
        "plain": label,
        "bbcode": (
            "[color=#ff9a6e]⚔ Wx ribbon ×%.2f[/color] %s"
            % (float(weather_mult), ribbon.get("bbcode", ""))
        ),
        "empty": bool(ribbon.get("empty", False)),
        "summary": label,
    }


def format_extreme_event_chip(events: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    from weather_effects import rank_extreme_events  # type: ignore

    ranked = rank_extreme_events(events)
    if ranked.get("empty"):
        return {
            "plain": "",
            "bbcode": "",
            "empty": True,
            "summary": "",
            "worst": {},
        }
    worst = ranked.get("worst") or {}
    label = "Extreme: %s sev %s" % (worst.get("type", "?"), worst.get("severity", "?"))
    return {
        "worst": worst,
        "ranked": ranked.get("ranked", []),
        "plain": label,
        "bbcode": "[color=#f87171]⚠ %s[/color]" % label,
        "empty": False,
        "summary": label,
    }


def format_season_daylight_chip(month: int) -> Dict[str, Any]:
    from weather_effects import season_label  # type: ignore

    s = season_label(month)
    label = s.get("summary", "")
    return {
        "season": s.get("season", ""),
        "daylight_hours": s.get("daylight_hours", 12.0),
        "plain": label,
        "bbcode": "[color=#5ec8ff]☀ Season[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "summary": label,
        "month": int(month),
    }


def air_sortie_weather_gate(weather: Mapping[str, Any]) -> Dict[str, Any]:
    """Alias surface for air mission weather_eff path."""
    ready = air_sortie_readiness(weather or {})
    return {
        **ready,
        "weather_eff": float(ready.get("effectiveness", 1.0)),
        "plain": ready.get("summary", ""),
        "bbcode": (
            "[color=#5ec8ff]✈ Air wx[/color] [color=#8899aa]%s[/color]"
            % ready.get("summary", "")
        ),
    }


def naval_spot_weather_mult(weather: Mapping[str, Any]) -> Dict[str, Any]:
    mult = naval_spotting_multiplier(weather or {})
    return {
        "mult": float(mult),
        "plain": "naval spot ×%.2f" % mult,
        "bbcode": "[color=#5ec8ff]👁 Naval spot[/color] [color=#8899aa]×%.2f[/color]" % mult,
        "summary": "naval spot ×%.2f" % mult,
    }
