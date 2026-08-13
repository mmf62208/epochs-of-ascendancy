"""Agent coverage plan pilot — province coverage vs HH threat (beyond network deploy)."""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence


def plan_agent_coverage(
    threats: Sequence[Mapping[str, Any]],
    *,
    available_agents: int = 5,
    network_strength: float = 0.3,
) -> Dict[str, Any]:
    """Allocate agents across threatened provinces by influence × weakness."""
    avail = max(0, int(available_agents))
    scored: List[Dict[str, Any]] = []
    for t in threats or []:
        if not isinstance(t, dict):
            continue
        if not bool(t.get("active", True)):
            continue
        pid = int(t.get("province_id", t.get("id", -1)) or -1)
        if pid < 0:
            continue
        inf = float(t.get("influence", t.get("threat", 0.5)) or 0.5)
        loyalty = float(t.get("loyalty", 0.5) or 0.5)
        net = float(t.get("network_strength", network_strength) or network_strength)
        need = inf * (1.2 - loyalty) * (1.1 - net)
        scored.append(
            {
                "province_id": pid,
                "action_class": str(t.get("action_class", "influence")),
                "influence": inf,
                "need": float(need),
                "agents": 0,
            }
        )
    scored.sort(key=lambda x: (-float(x["need"]), int(x["province_id"])))
    remaining = avail
    for row in scored:
        if remaining <= 0:
            break
        assign = 1 if remaining == 1 else max(1, min(remaining, 1 + int(row["need"] * 2)))
        assign = min(assign, remaining)
        row["agents"] = assign
        remaining -= assign
    covered = sum(1 for r in scored if int(r["agents"]) > 0)
    lines = [
        "Coverage %d/%d threats · agents used %d/%d"
        % (covered, len(scored), avail - remaining, avail)
    ]
    for r in scored[:4]:
        if int(r["agents"]) <= 0:
            continue
        lines.append(
            "#%d %s · %d agents (need %.2f)"
            % (int(r["province_id"]), r["action_class"], int(r["agents"]), float(r["need"]))
        )
    if not scored or avail <= 0:
        return {
            "assignments": [],
            "covered": 0,
            "agents_used": 0,
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
        }
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#c084fc]◎ Coverage[/color] [color=#8899aa]%s[/color]" % lines[0]]
        + [
            "[color=#8899aa]· #%d %s ×%d[/color]"
            % (int(r["province_id"]), r["action_class"], int(r["agents"]))
            for r in scored
            if int(r["agents"]) > 0
        ][:4]
    )
    return {
        "assignments": scored,
        "covered": covered,
        "agents_used": avail - remaining,
        "available_agents": avail,
        "empty": False,
        "plain": plain,
        "bbcode": bbcode,
        "summary": lines[0],
        "count": len(scored),
    }
