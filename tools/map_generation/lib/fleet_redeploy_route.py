"""Fleet redeploy route plan pilot — origin→destination score (beyond theater posture).

Not full fleet AI: ranks candidate destination ports for redeploy given fuel,
basing, and zone hostility along a simple origin→dest pair.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence


def score_redeploy_route(
    *,
    origin_basing: str = "none",
    dest_basing: str = "port",
    fuel_level: float = 0.85,
    path_hostile_segments: int = 0,
    path_length: int = 1,
    dest_zone_relation: str = "friendly",
) -> Dict[str, Any]:
    fuel = max(0.1, min(1.2, float(fuel_level)))
    rank = {"none": 0, "anchorage": 1, "port": 2, "major_base": 3}
    o = rank.get(str(origin_basing).lower(), 0)
    d = rank.get(str(dest_basing).lower(), 0)
    n = max(1, int(path_length))
    hostile = max(0, int(path_hostile_segments))
    rel = str(dest_zone_relation or "no_zone").lower()

    score = 40.0 + d * 12.0 - o * 3.0
    score *= 0.7 + 0.3 * fuel
    score -= hostile * 8.0
    score -= max(0, n - 2) * 4.0
    if fuel < 0.35 and d >= 2:
        score += 18.0  # need service at dest
    if rel == "hostile":
        score -= 15.0
    elif rel == "contested":
        score -= 8.0
    elif rel == "friendly":
        score += 10.0
    if d == 0:
        score -= 25.0
    return {
        "score": float(score),
        "fuel_level": fuel,
        "dest_basing": dest_basing,
        "path_hostile_segments": hostile,
        "path_length": n,
        "dest_zone_relation": rel,
        "recommend": score >= 45.0,
        "summary": "redeploy route score %.1f (dest %s · H%d · fuel %.0f%%)"
        % (score, dest_basing, hostile, fuel * 100.0),
    }


def plan_fleet_redeploy_routes(
    candidates: Sequence[Mapping[str, Any]],
    *,
    fuel_level: float = 0.85,
    origin_basing: str = "anchorage",
) -> Dict[str, Any]:
    """Rank destination candidates for redeploy from origin basing."""
    scored: List[Dict[str, Any]] = []
    for raw in candidates or []:
        if not isinstance(raw, dict):
            continue
        pid = int(raw.get("province_id", raw.get("id", -1)) or -1)
        if pid < 0:
            continue
        row = score_redeploy_route(
            origin_basing=str(raw.get("origin_basing", origin_basing)),
            dest_basing=str(raw.get("basing_level", raw.get("dest_basing", "port"))),
            fuel_level=float(raw.get("fuel_level", fuel_level) or fuel_level),
            path_hostile_segments=int(raw.get("path_hostile_segments", 0) or 0),
            path_length=int(raw.get("path_length", 1) or 1),
            dest_zone_relation=str(raw.get("zone_relation", raw.get("dest_zone_relation", "friendly"))),
        )
        row["province_id"] = pid
        scored.append(row)
    scored.sort(key=lambda x: (-float(x["score"]), int(x["province_id"])))
    if not scored:
        return {
            "routes": [],
            "best_province_id": -1,
            "best_score": 0.0,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
        }
    best = scored[0]
    lines = [
        "Redeploy → #%d score %.0f (%s)"
        % (int(best["province_id"]), float(best["score"]), best.get("dest_basing", ""))
    ]
    for r in scored[1:3]:
        lines.append(
            "alt #%d %.0f" % (int(r["province_id"]), float(r["score"]))
        )
    plain = "\n".join(lines)
    bbcode = "\n".join(
        [
            "[color=#5ec8ff]🚢 Redeploy route[/color] [color=#8899aa]#%d · score %.0f[/color]"
            % (int(best["province_id"]), float(best["score"]))
        ]
        + [
            "[color=#8899aa]· #%d %.0f[/color]" % (int(r["province_id"]), float(r["score"]))
            for r in scored[1:3]
        ]
    )
    return {
        "routes": scored,
        "best_province_id": int(best["province_id"]),
        "best_score": float(best["score"]),
        "best": best,
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0],
        "count": len(scored),
    }
