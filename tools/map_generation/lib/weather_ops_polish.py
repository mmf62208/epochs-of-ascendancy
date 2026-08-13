"""Weather/supply/naval polish pilots beyond deepen suite.

Pressure index, route weather rank, freeze/thaw, fog gate, infra wear, air alert,
joint focus/agent pick, compact weather section.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from weather_effects import (  # type: ignore
    air_sortie_readiness,
    combat_weather_multiplier,
    movement_multiplier,
    naval_spotting_multiplier,
    supply_throughput_weather_multiplier,
)


def weather_pressure_index(weather: Mapping[str, Any]) -> Dict[str, Any]:
    """0–1 pressure: higher = worse weather for ops."""
    w = dict(weather or {})
    c = combat_weather_multiplier(w)
    s = supply_throughput_weather_multiplier(w)
    m = movement_multiplier(w)
    # Invert mults into pressure (1.0 mult → low pressure)
    pressure = max(0.0, min(1.0, (3.0 - (c + s + m)) / 2.2))
    label = "Weather pressure %.0f%% (c×%.2f s×%.2f m×%.2f)" % (pressure * 100.0, c, s, m)
    return {
        "pressure": float(pressure),
        "combat_mult": float(c),
        "supply_mult": float(s),
        "move_mult": float(m),
        "label": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🌪 Pressure[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "severe": pressure >= 0.55,
    }


def rank_supply_route_weather_risk(
    path_weather: Sequence[Mapping[str, Any]],
) -> Dict[str, Any]:
    """Rank path segments by supply weather risk (lowest mult = highest risk)."""
    rows: List[Dict[str, Any]] = []
    for i, w in enumerate(path_weather or []):
        if not isinstance(w, dict):
            continue
        mult = supply_throughput_weather_multiplier(w)
        pid = int(w.get("province_id", w.get("id", i)) or i)
        rows.append(
            {
                "province_id": pid,
                "supply_mult": float(mult),
                "risk": float(1.0 - mult),
                "ground_state": str(w.get("ground_state", "dry")),
            }
        )
    rows.sort(key=lambda x: (-float(x["risk"]), int(x["province_id"])))
    if not rows:
        return {
            "ranked": [],
            "worst_province_id": -1,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
        }
    worst = rows[0]
    label = "Route wx risk worst #%d (×%.2f · %s)" % (
        int(worst["province_id"]),
        float(worst["supply_mult"]),
        worst["ground_state"],
    )
    return {
        "ranked": rows,
        "worst_province_id": int(worst["province_id"]),
        "worst": worst,
        "empty": False,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🛤 Route wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
    }


def trade_weather_multiplier(weather: Mapping[str, Any]) -> float:
    """Trade flow factor from weather (storm/mud hurt more than mild cold)."""
    s = supply_throughput_weather_multiplier(weather or {})
    # Trade slightly more sensitive than supply
    return max(0.3, min(1.1, s * 0.95 + 0.05))


def naval_engagement_weather_tip(weather: Mapping[str, Any]) -> Dict[str, Any]:
    spot = naval_spotting_multiplier(weather or {})
    vis = float((weather or {}).get("visibility", 1.0) or 1.0)
    storm = float((weather or {}).get("precip_intensity", 0.0) or 0.0)
    if spot < 0.35:
        tip = "Low spot — favor ambush/sub screen"
    elif storm > 0.6:
        tip = "Storm seas — carrier strike degraded"
    elif vis > 0.85:
        tip = "Clear seas — surface gunnery favored"
    else:
        tip = "Moderate vis — balanced naval posture"
    label = "Naval wx tip · spot ×%.2f · %s" % (spot, tip)
    return {
        "spot_mult": float(spot),
        "tip": tip,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🌊 Naval tip[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def air_grounding_alert(weather: Mapping[str, Any]) -> Dict[str, Any]:
    ready = air_sortie_readiness(weather or {})
    grounded = bool(ready.get("grounded", False))
    if not grounded and float(ready.get("effectiveness", 1.0)) >= 0.5:
        return {
            "grounded": False,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "effectiveness": float(ready.get("effectiveness", 1.0)),
        }
    label = "Air alert · %s" % ready.get("summary", "sortie degraded")
    return {
        "grounded": grounded,
        "effectiveness": float(ready.get("effectiveness", 1.0)),
        "empty": False,
        "plain": label,
        "bbcode": "[color=#f87171]✈ %s[/color]" % label,
        "summary": label,
    }


def freeze_thaw_transition(
    current_ground: str,
    temp: float,
    precip_intensity: float = 0.0,
) -> Dict[str, Any]:
    g = str(current_ground or "dry").lower()
    t = float(temp)
    p = float(precip_intensity)
    nxt = g
    note = "stable"
    if t < -1.0 and g in ("mud", "wet", "dry") and p > 0.15:
        nxt = "frozen" if g != "snow_covered" else "snow_covered"
        note = "freeze-in"
    elif t < -2.0 and p > 0.25:
        nxt = "snow_covered"
        note = "snowfall"
    elif t > 3.0 and g in ("frozen", "snow_covered", "ice"):
        nxt = "mud" if p > 0.2 else "wet"
        note = "thaw"
    elif t > 8.0 and g in ("mud", "wet") and p < 0.1:
        nxt = "dry"
        note = "dry-out"
    changed = nxt != g
    label = "Ground %s → %s (%s)" % (g, nxt, note) if changed else "Ground %s stable" % g
    return {
        "from": g,
        "to": nxt,
        "changed": changed,
        "note": note,
        "plain": label,
        "bbcode": "[color=#5ec8ff]❄ Ground[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def infra_weather_wear(weather: Mapping[str, Any]) -> Dict[str, Any]:
    w = dict(weather or {})
    g = str(w.get("ground_state", "dry")).lower()
    storm = float(w.get("precip_intensity", 0.0) or 0.0)
    wear = 1.0
    if g in ("snow_covered", "ice", "frozen"):
        wear = 0.8
    elif g == "mud":
        wear = 0.9
    wear *= 1.0 - storm * 0.1
    wear = max(0.5, min(1.2, wear))
    label = "Infra wear factor ×%.2f (%s)" % (wear, g)
    return {
        "wear_factor": float(wear),
        "ground_state": g,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🛠 Infra wx[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def coastal_fog_naval_gate(weather: Mapping[str, Any]) -> Dict[str, Any]:
    vis = float((weather or {}).get("visibility", 1.0) or 1.0)
    storm = float((weather or {}).get("precip_intensity", 0.0) or 0.0)
    fog = vis < 0.4 or (vis < 0.55 and storm > 0.35)
    ops = max(0.1, min(1.0, vis * (1.0 - storm * 0.4)))
    if fog:
        label = "Fog gate CLOSED · ops ×%.2f" % ops
    else:
        label = "Fog gate open · ops ×%.2f" % ops
    return {
        "fog": fog,
        "ops_mult": float(ops),
        "can_surface_strike": not fog or ops >= 0.45,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🌫 Fog[/color] [color=#8899aa]%s[/color]" % label,
        "summary": label,
        "empty": False,
    }


def joint_focus_agent_priority(
    focus_picks: Sequence[Mapping[str, Any]],
    agent_missions: Sequence[Mapping[str, Any]],
    *,
    max_items: int = 3,
) -> Dict[str, Any]:
    """Merge focus picks and agent missions into one priority board."""
    items: List[Dict[str, Any]] = []
    for f in focus_picks or []:
        if not isinstance(f, dict):
            continue
        items.append(
            {
                "kind": "focus",
                "id": str(f.get("id", f.get("focus_id", f.get("name", "focus")))),
                "score": float(f.get("score", f.get("priority", 0.0)) or 0.0),
            }
        )
    for a in agent_missions or []:
        if not isinstance(a, dict):
            continue
        items.append(
            {
                "kind": "agent",
                "id": str(a.get("mission", a.get("id", "mission"))),
                "score": float(a.get("score", 0.0) or 0.0),
            }
        )
    items.sort(key=lambda x: (-float(x["score"]), x["kind"], x["id"]))
    top = items[: max(1, int(max_items))]
    if not top:
        return {
            "items": [],
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
        }
    lines = ["Joint priority board"]
    for it in top:
        lines.append("%s · %s (%.0f)" % (it["kind"], it["id"], float(it["score"])))
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#c084fc]◆ Joint board[/color]"]
        + [
            "[color=#8899aa]· %s %s[/color]" % (it["kind"], it["id"])
            for it in top
        ]
    )
    return {
        "items": top,
        "all": items,
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0] + " · " + top[0]["id"],
        "count": len(top),
        "best": top[0],
    }


def format_inspector_weather_section(
    weather: Mapping[str, Any],
    *,
    include_forecast_label: str = "",
) -> Dict[str, Any]:
    """Compact multi-chip weather block for inspector (may be empty if no weather)."""
    if not weather:
        return {"plain": "", "bbcode": "", "empty": True, "summary": "", "lines": []}
    pressure = weather_pressure_index(weather)
    freeze = freeze_thaw_transition(
        str(weather.get("ground_state", "dry")),
        float(weather.get("temp", 10.0) or 10.0),
        float(weather.get("precip_intensity", 0.0) or 0.0),
    )
    air = air_grounding_alert(weather)
    lines = [pressure["plain"], freeze["plain"]]
    if not air.get("empty"):
        lines.append(air["plain"])
    if include_forecast_label:
        lines.append(include_forecast_label)
    plain = "\n".join(lines)
    bb_lines = [
        "[color=#5ec8ff]── Weather ops ──[/color]",
        pressure["bbcode"],
        freeze["bbcode"],
    ]
    if not air.get("empty"):
        bb_lines.append(air["bbcode"])
    return {
        "lines": lines,
        "plain": plain,
        "bbcode": "\n".join(bb_lines),
        "empty": False,
        "summary": pressure["label"],
        "pressure": pressure,
        "freeze": freeze,
        "air": air,
    }
