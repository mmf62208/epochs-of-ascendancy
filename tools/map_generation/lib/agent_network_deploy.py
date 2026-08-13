"""Agent network response deploy plan chip (missions → deploy counts; not deep AI)."""
from __future__ import annotations

from typing import Any, Dict, Mapping

from agent_network_response import plan_agent_network_response  # type: ignore


def format_network_deploy_plan(
    signal: Mapping[str, Any],
    *,
    network_strength: float = 0.3,
    available_agents: int = 3,
    loyalty: float = 0.5,
) -> Dict[str, Any]:
    plan = plan_agent_network_response(
        signal,
        network_strength=network_strength,
        available_agents=available_agents,
        loyalty=loyalty,
    )
    if plan.get("empty"):
        return {
            "plain": "",
            "bbcode": "",
            "empty": True,
            "deploy_count": 0,
            "summary": "",
            "actions": [],
        }
    deploy = int(plan.get("deploy_count", 0))
    best = str(plan.get("best_mission", ""))
    lines = list(plan.get("lines") or [])
    headline = "Deploy plan · %d agents · %s" % (deploy, best or "missions")
    plain_lines = [headline] + lines
    bb = [
        "[color=#c084fc]◎ Deploy plan[/color] [color=#8899aa]%d · %s[/color]"
        % (deploy, best or "—")
    ]
    for ln in lines[:3]:
        bb.append("[color=#8899aa]· %s[/color]" % ln)
    return {
        "plain": "\n".join(plain_lines),
        "bbcode": "\n".join(bb),
        "empty": False,
        "deploy_count": deploy,
        "best_mission": best,
        "actions": plan.get("actions", []),
        "lines": lines,
        "summary": headline,
        "plan": plan,
    }
