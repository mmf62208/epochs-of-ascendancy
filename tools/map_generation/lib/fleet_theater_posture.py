"""Fleet theater posture plan pilot — multi-province rank summary (not full fleet AI).

Aggregates per-province posture rankings into a theater-level plan: dominant
posture, fuel-stressed ports, projection candidates.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence

from fleet_redeploy_posture import rank_fleet_postures  # type: ignore


def plan_fleet_theater_posture(
    province_inputs: Sequence[Mapping[str, Any]],
    *,
    default_fuel: float = 0.85,
) -> Dict[str, Any]:
    """Build theater posture plan from per-province basing/fuel/zone inputs.

    Each input: {province_id, basing_level, fuel_level?, zone_relation?, escort_need?, can_service?}
    """
    rows: List[Dict[str, Any]] = []
    for raw in province_inputs or []:
        if not isinstance(raw, dict):
            continue
        pid = int(raw.get("province_id", raw.get("id", -1)) or -1)
        if pid < 0:
            continue
        fuel = float(raw.get("fuel_level", default_fuel) or default_fuel)
        ranked = rank_fleet_postures(
            basing_level=str(raw.get("basing_level", "none")),
            fuel_level=fuel,
            zone_relation=str(raw.get("zone_relation", "no_zone")),
            escort_need=float(raw.get("escort_need", 0.0) or 0.0),
            can_service=bool(raw.get("can_service", False)),
        )
        rows.append(
            {
                "province_id": pid,
                "best_posture": ranked.get("best_posture", ""),
                "best_score": float(ranked.get("best_score", 0.0)),
                "fuel_level": fuel,
                "summary": ranked.get("summary", ""),
            }
        )
    if not rows:
        return {
            "provinces": [],
            "dominant_posture": "",
            "refuel_count": 0,
            "projection_count": 0,
            "count": 0,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
        }
    # Dominant by mode of best_posture weighted by score
    scores: Dict[str, float] = {}
    refuel = 0
    projection = 0
    for r in rows:
        p = str(r["best_posture"])
        scores[p] = scores.get(p, 0.0) + float(r["best_score"])
        if p == "REFUEL_RETURN":
            refuel += 1
        if p == "POWER_PROJECTION":
            projection += 1
    dominant = max(scores.items(), key=lambda kv: (kv[1], kv[0]))[0] if scores else ""
    rows.sort(key=lambda x: (-float(x["best_score"]), int(x["province_id"])))
    top = rows[:3]
    lines = [
        "Theater posture %s · %d ports · refuel %d · project %d"
        % (dominant, len(rows), refuel, projection)
    ]
    for t in top:
        lines.append(
            "#%d %s (%.0f)"
            % (int(t["province_id"]), t["best_posture"], float(t["best_score"]))
        )
    plain = "\n".join(lines)
    bbcode = "\n".join(
        [
            "[color=#5ec8ff]🚢 Theater fleet[/color] [color=#8899aa]%s · %d ports[/color]"
            % (dominant, len(rows))
        ]
        + [
            "[color=#8899aa]· #%d %s[/color]" % (int(t["province_id"]), t["best_posture"])
            for t in top
        ]
    )
    return {
        "provinces": rows,
        "dominant_posture": dominant,
        "refuel_count": refuel,
        "projection_count": projection,
        "count": len(rows),
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0],
        "top": top,
    }
