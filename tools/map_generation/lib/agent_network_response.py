"""Agent network response pilot — escalate network ops after HH signal (not deep AI)."""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from agent_mission_priority import rank_agent_missions  # type: ignore


def plan_agent_network_response(
    signal: Mapping[str, Any],
    *,
    network_strength: float = 0.3,
    available_agents: int = 3,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    sig = dict(signal or {})
    if not sig or not bool(sig.get("active", True)):
        if not sig.get("action_class") and not sig.get("province_id"):
            return {
                "actions": [],
                "plain": "",
                "bbcode": "",
                "empty": True,
                "summary": "",
                "deploy_count": 0,
            }
    ac = str(sig.get("action_class", "influence")).lower()
    threat = float(sig.get("influence", sig.get("strength", 0.55)) or 0.55)
    ranked = rank_agent_missions(
        hh_action_class=ac,
        threat=threat,
        network_strength=network_strength,
        loyalty=loyalty,
        max_missions=3,
    )
    deploy = max(1, min(int(available_agents), 1 + int(threat * 3)))
    actions: List[Dict[str, Any]] = []
    for i, m in enumerate(ranked.get("missions") or []):
        if i >= deploy:
            break
        actions.append(
            {
                "mission": m.get("mission"),
                "agents": 1 if i > 0 else max(1, deploy - (len(ranked.get("missions") or []) - 1)),
                "score": m.get("score"),
                "province_id": int(sig.get("province_id", -1) or -1),
            }
        )
    # Normalize agent counts
    if actions:
        actions[0]["agents"] = max(1, deploy - (len(actions) - 1))
    lines = [
        "Deploy %d · %s (score %.0f)"
        % (int(a["agents"]), a["mission"], float(a.get("score", 0)))
        for a in actions
    ]
    return {
        "actions": actions,
        "deploy_count": deploy,
        "best_mission": ranked.get("best_mission", ""),
        "lines": lines,
        "count": len(actions),
        "empty": len(actions) == 0,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#c084fc]◎[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
        "summary": "Network response: %s (%d agents)"
        % (ranked.get("best_mission", "none"), deploy),
        "missions": ranked,
    }
