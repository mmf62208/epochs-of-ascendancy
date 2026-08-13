"""Agent escalation ladder pilot — threat → ordered escalations (beyond coverage plan)."""
from __future__ import annotations

from typing import Any, Dict, List, Mapping


LADDER = (
    "monitor",
    "counterintel",
    "network_expand",
    "sabotage_defense",
    "active_disruption",
    "emergency_lockdown",
)


def plan_agent_escalation(
    signal: Mapping[str, Any],
    *,
    network_strength: float = 0.3,
    available_agents: int = 3,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    sig = dict(signal or {})
    if not sig or (not bool(sig.get("active", True)) and not sig.get("action_class")):
        if not sig.get("action_class") and not sig.get("province_id"):
            return {
                "steps": [],
                "empty": True,
                "plain": "",
                "bbcode": "",
                "summary": "",
                "level": 0,
            }
    threat = float(sig.get("influence", sig.get("threat", 0.55)) or 0.55)
    net = max(0.0, min(1.0, float(network_strength)))
    loy = max(0.0, min(1.0, float(loyalty)))
    agents = max(0, int(available_agents))
    # Level 0–5
    level = int(min(5, max(0, threat * 4.0 + (0.5 - net) * 2.0 + (0.5 - loy) * 1.5)))
    if agents <= 0:
        level = min(level, 1)
    steps: List[Dict[str, Any]] = []
    for i, name in enumerate(LADDER):
        if i > level:
            break
        steps.append(
            {
                "step": i,
                "action": name,
                "agents": 1 if i > 0 else max(1, min(agents, 1 + int(threat * 2))),
                "active": i == level,
            }
        )
    if not steps:
        return {
            "steps": [],
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "level": 0,
        }
    top = steps[-1]
    lines = [
        "Escalation L%d · %s (threat %.0f%%)"
        % (level, top["action"], threat * 100.0)
    ]
    for s in steps:
        mark = ">" if s["active"] else "·"
        lines.append("%s %s" % (mark, s["action"]))
    plain = "\n".join(lines)
    bbcode = "\n".join(
        [
            "[color=#c084fc]◎ Escalation L%d[/color] [color=#8899aa]%s[/color]"
            % (level, top["action"])
        ]
        + [
            "[color=#8899aa]%s %s[/color]" % (">" if s["active"] else "·", s["action"])
            for s in steps
        ]
    )
    return {
        "steps": steps,
        "level": level,
        "top_action": top["action"],
        "threat": threat,
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0],
        "count": len(steps),
    }
