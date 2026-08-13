"""Multi-front assault priority pilot — rank targets by power ratio + weather (beyond briefing)."""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore


def rank_assault_targets(
    targets: Sequence[Mapping[str, Any]],
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 1.0,
    max_targets: int = 5,
) -> Dict[str, Any]:
    """Each target: {province_id, defender_power, weather_mult?, name?}"""
    scored: List[Dict[str, Any]] = []
    for t in targets or []:
        if not isinstance(t, dict):
            continue
        pid = int(t.get("province_id", t.get("id", -1)) or -1)
        if pid < 0:
            continue
        dfn = max(0.1, float(t.get("defender_power", t.get("defense", 80.0)) or 80.0))
        wmult = max(0.2, min(1.2, float(t.get("weather_mult", 1.0) or 1.0)))
        est = estimate_multi_phase_combat(
            attacker_power, dfn, attacker_supply=attacker_supply, weather_mult=wmult
        )
        overall = float(est.get("overall_attacker_win_chance", 0.0))
        # Priority: higher win chance + slightly prefer weaker defenders
        priority = overall * 100.0 + (100.0 / dfn)
        scored.append(
            {
                "province_id": pid,
                "name": str(t.get("name", t.get("province_name", ""))),
                "defender_power": dfn,
                "weather_mult": wmult,
                "overall": overall,
                "priority": float(priority),
                "recommendation": (
                    "press" if overall >= 0.65 else ("marginal" if overall >= 0.45 else "avoid")
                ),
            }
        )
    scored.sort(key=lambda x: (-float(x["priority"]), int(x["province_id"])))
    top = scored[: max(1, int(max_targets))]
    if not scored:
        return {
            "targets": [],
            "best_province_id": -1,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
        }
    best = top[0]
    lines = [
        "Assault priority · #%d win %.0f%% · %s"
        % (int(best["province_id"]), float(best["overall"]) * 100.0, best["recommendation"])
    ]
    for row in top[1:3]:
        lines.append(
            "alt #%d win %.0f%%" % (int(row["province_id"]), float(row["overall"]) * 100.0)
        )
    plain = "\n".join(lines)
    bbcode = "\n".join(
        [
            "[color=#ff9a6e]⚔ Front priority[/color] [color=#8899aa]#%d · %.0f%%[/color]"
            % (int(best["province_id"]), float(best["overall"]) * 100.0)
        ]
        + [
            "[color=#8899aa]· #%d %.0f%%[/color]"
            % (int(r["province_id"]), float(r["overall"]) * 100.0)
            for r in top[1:3]
        ]
    )
    return {
        "targets": top,
        "all": scored,
        "best_province_id": int(best["province_id"]),
        "best": best,
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0],
        "count": len(scored),
    }
