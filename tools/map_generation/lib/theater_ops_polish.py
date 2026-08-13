"""Theater ops polish pilots beyond ops-expand weather suite.

Campaign day risk, convoy weather window, production alert, sea×naval ops,
morale weather, depot capacity, daylight combat, choke+weather, focus weather pick,
inspector ops dashboard.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from weather_effects import (  # type: ignore
    combat_weather_multiplier,
    naval_spotting_multiplier,
    production_weather_multiplier,
    season_label,
    supply_throughput_weather_multiplier,
)
from weather_ops_polish import weather_pressure_index  # type: ignore


def campaign_day_risk(weather: Mapping[str, Any], month: int = 1) -> Dict[str, Any]:
    pressure = weather_pressure_index(weather or {})
    season = season_label(month)
    # Winter + high pressure = riskier campaign day
    season_bump = 0.12 if season.get("season") == "winter" else (
        0.05 if season.get("season") == "autumn" else 0.0
    )
    risk = max(0.0, min(1.0, float(pressure["pressure"]) + season_bump))
    label = "Campaign day risk %.0f%% · %s · pressure %.0f%%" % (
        risk * 100.0,
        season.get("season", "?"),
        float(pressure["pressure"]) * 100.0,
    )
    return {
        "risk": float(risk),
        "season": season.get("season", ""),
        "pressure": float(pressure["pressure"]),
        "label": label,
        "plain": label,
        "bbcode": "[color=#f87171]📅 Day risk[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "severe": risk >= 0.55,
        "empty": False,
    }


def convoy_weather_window(
    forecasts: Sequence[Mapping[str, Any]],
) -> Dict[str, Any]:
    """Pick best day index for convoy (highest naval spot × supply mult)."""
    scored: List[Dict[str, Any]] = []
    for i, w in enumerate(forecasts or []):
        if not isinstance(w, dict):
            continue
        spot = naval_spotting_multiplier(w)
        supply = supply_throughput_weather_multiplier(w)
        score = spot * 0.55 + supply * 0.45
        scored.append(
            {
                "day_index": int(w.get("day_index", i)),
                "score": float(score),
                "spot": float(spot),
                "supply": float(supply),
            }
        )
    scored.sort(key=lambda x: (-float(x["score"]), int(x["day_index"])))
    if not scored:
        return {
            "best_day": -1,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
        }
    best = scored[0]
    label = "Convoy window · day %d score %.2f (spot ×%.2f)" % (
        int(best["day_index"]),
        float(best["score"]),
        float(best["spot"]),
    )
    return {
        "best_day": int(best["day_index"]),
        "best": best,
        "ranked": scored,
        "empty": False,
        "plain": label,
        "bbcode": "[color=#5ec8ff]⛵ Convoy window[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
    }


def production_weather_alert(weather: Mapping[str, Any], threshold: float = 0.85) -> Dict[str, Any]:
    mult = production_weather_multiplier(weather or {})
    if mult >= float(threshold):
        return {
            "alert": False,
            "mult": float(mult),
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
        }
    label = "Production alert · output ×%.2f (below %.0f%%)" % (mult, threshold * 100.0)
    return {
        "alert": True,
        "mult": float(mult),
        "empty": False,
        "plain": label,
        "bbcode": "[color=#f87171]🏭 %s[/color]" % label,
        "summary": label,
    }


def sea_naval_weather_ops(
    sea_supply_mult: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    sea = max(0.15, min(1.5, float(sea_supply_mult)))
    spot = naval_spotting_multiplier(weather or {})
    combined = max(0.1, min(1.4, sea * (0.5 + 0.5 * spot)))
    label = "Sea×naval ops ×%.2f (sea %.2f · spot ×%.2f)" % (combined, sea, spot)
    return {
        "sea_mult": float(sea),
        "spot_mult": float(spot),
        "combined": float(combined),
        "plain": label,
        "bbcode": "[color=#5ec8ff]⚓ Sea×naval[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def combat_morale_weather(weather: Mapping[str, Any]) -> Dict[str, Any]:
    c = combat_weather_multiplier(weather or {})
    # Morale drag: foul weather reduces attacker morale 0–0.25
    drag = max(0.0, min(0.25, (1.0 - c) * 0.4))
    morale = max(0.5, 1.0 - drag)
    label = "Morale wx ×%.2f (drag %.0f%%)" % (morale, drag * 100.0)
    return {
        "morale_mult": float(morale),
        "drag": float(drag),
        "combat_mult": float(c),
        "plain": label,
        "bbcode": "[color=#ff9a6e]🛡 Morale wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def depot_weather_capacity(weather: Mapping[str, Any], base_capacity: float = 100.0) -> Dict[str, Any]:
    supply = supply_throughput_weather_multiplier(weather or {})
    cap = max(10.0, float(base_capacity) * supply)
    label = "Depot capacity %.0f (base %.0f · wx ×%.2f)" % (cap, base_capacity, supply)
    return {
        "capacity": float(cap),
        "base_capacity": float(base_capacity),
        "weather_mult": float(supply),
        "plain": label,
        "bbcode": "[color=#5ec8ff]📦 Depot wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def daylight_combat_mod(month: int) -> Dict[str, Any]:
    s = season_label(month)
    hours = float(s.get("daylight_hours", 12.0))
    # 9h → 0.9, 15h → 1.08
    mult = max(0.85, min(1.12, 0.75 + hours / 30.0))
    label = "Daylight combat ×%.2f (%s · %.0fh)" % (mult, s.get("season", ""), hours)
    return {
        "daylight_hours": hours,
        "season": s.get("season", ""),
        "combat_mult": float(mult),
        "plain": label,
        "bbcode": "[color=#5ec8ff]☀ Daylight[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
        "month": int(month),
    }


def choke_weather_synergy(
    *,
    is_choke: bool = False,
    controller_friendly: bool = True,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    if not is_choke:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
        }
    storm = float((weather or {}).get("precip_intensity", 0.0) or 0.0)
    spot = naval_spotting_multiplier(weather or {})
    control_mult = 1.12 if controller_friendly else 0.88
    risk = max(0.0, min(1.0, storm * 0.5 + (1.0 - spot) * 0.4))
    score = control_mult * (1.0 - risk * 0.3)
    label = "Choke×wx score ×%.2f (ctrl %.2f · risk %.0f%%)" % (
        score,
        control_mult,
        risk * 100.0,
    )
    return {
        "score": float(score),
        "control_mult": float(control_mult),
        "risk": float(risk),
        "empty": False,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🗺 Choke×wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
    }


def focus_weather_aware_score(
    base_score: float,
    focus_id: str = "",
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Boost industrial/military focuses under foul weather (home production urgency)."""
    base = float(base_score)
    pressure = float(weather_pressure_index(weather or {})["pressure"])
    fid = str(focus_id or "").lower()
    boost = 0.0
    if pressure >= 0.4 and any(k in fid for k in ("indust", "armament", "military", "infra", "war")):
        boost = 8.0 + pressure * 12.0
    elif pressure >= 0.55 and any(k in fid for k in ("naval", "fleet", "convoy")):
        boost = 6.0 + pressure * 8.0
    score = base + boost
    label = "Focus wx · %s score %.0f (+%.0f)" % (focus_id or "focus", score, boost)
    return {
        "focus_id": focus_id,
        "base_score": base,
        "boost": float(boost),
        "score": float(score),
        "pressure": pressure,
        "plain": label,
        "bbcode": "[color=#c084fc]◆ Focus wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def format_ops_dashboard(
    *,
    day_risk: Optional[Mapping[str, Any]] = None,
    task_group: Optional[Mapping[str, Any]] = None,
    assault: Optional[Mapping[str, Any]] = None,
    escalation: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    lines: List[str] = []
    bb: List[str] = ["[color=#5ec8ff]── Ops dashboard ──[/color]"]
    for block in (day_risk, task_group, assault, escalation):
        if not block or block.get("empty"):
            continue
        summary = str(block.get("summary", block.get("plain", ""))).strip()
        if not summary:
            continue
        lines.append(summary.split("\n")[0])
        bb.append("[color=#8899aa]· %s[/color]" % summary.split("\n")[0])
    if not lines:
        return {"plain": "", "bbcode": "", "empty": True, "summary": "", "lines": []}
    return {
        "lines": lines,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(bb),
        "empty": False,
        "summary": lines[0],
        "count": len(lines),
    }
