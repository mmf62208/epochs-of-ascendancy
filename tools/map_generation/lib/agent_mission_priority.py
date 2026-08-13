"""Agent mission priority pilot (not full deep AI).

Ranks mission types for a target province using threat, HH signal class, and
network strength.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

MISSIONS = (
    "counterintel",
    "sabotage_defense",
    "propaganda",
    "network_expand",
    "assassination_watch",
    "economic_shield",
)


def score_agent_mission(
    mission: str,
    *,
    hh_action_class: str = "",
    threat: float = 0.5,
    network_strength: float = 0.3,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    m = str(mission or "network_expand").strip().lower()
    if m not in MISSIONS:
        m = "network_expand"
    ac = str(hh_action_class or "").strip().lower()
    th = max(0.0, min(1.0, float(threat)))
    net = max(0.0, min(1.0, float(network_strength)))
    loy = max(0.0, min(1.0, float(loyalty)))

    base = {
        "counterintel": 55.0,
        "sabotage_defense": 50.0,
        "propaganda": 48.0,
        "network_expand": 45.0,
        "assassination_watch": 40.0,
        "economic_shield": 47.0,
    }[m]

    if ac == "sabotage":
        if m in ("sabotage_defense", "counterintel"):
            base += 30.0
    elif ac == "infiltration":
        if m in ("counterintel", "propaganda", "assassination_watch"):
            base += 28.0
    elif ac == "economic_pressure":
        if m in ("economic_shield", "network_expand"):
            base += 26.0

    base += th * 25.0
    if m == "network_expand":
        base += (1.0 - net) * 20.0
    if m == "propaganda":
        base += (1.0 - loy) * 22.0
    if m == "counterintel" and net < 0.3:
        base -= 8.0

    return {
        "mission": m,
        "score": float(base),
        "hh_action_class": ac,
        "threat": th,
        "network_strength": net,
        "loyalty": loy,
    }


def rank_agent_missions(
    *,
    hh_action_class: str = "",
    threat: float = 0.5,
    network_strength: float = 0.3,
    loyalty: float = 0.5,
    max_missions: int = 4,
) -> Dict[str, Any]:
    scored = [
        score_agent_mission(
            m,
            hh_action_class=hh_action_class,
            threat=threat,
            network_strength=network_strength,
            loyalty=loyalty,
        )
        for m in MISSIONS
    ]
    scored.sort(key=lambda x: (-float(x["score"]), x["mission"]))
    top = scored[: max(1, int(max_missions))]
    best = top[0] if top else {}
    lines = ["%s (%.1f)" % (t["mission"], t["score"]) for t in top]
    return {
        "best_mission": str(best.get("mission", "")),
        "best_score": float(best.get("score", 0.0)) if best else 0.0,
        "missions": top,
        "lines": lines,
        "count": len(top),
        "empty": len(top) == 0,
        "summary": "Agent priority: %s" % best.get("mission", "none"),
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#c084fc]◇[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
    }
