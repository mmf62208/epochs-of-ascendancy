"""HH / agent counterplay options pilot (not full deep AI).

Given an HH map signal shape, produce ordered counterplay options with
distinct non-trivial priority for sabotage / economic_pressure / infiltration.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence

# Option templates by action class
_OPTIONS = {
    "sabotage": [
        {"id": "deploy_counterintel", "label": "Deploy counter-intel agents", "cost": "medium", "priority": 90},
        {"id": "repair_infra", "label": "Rush infrastructure repair", "cost": "high", "priority": 75},
        {"id": "increase_security", "label": "Raise province security", "cost": "low", "priority": 60},
    ],
    "economic_pressure": [
        {"id": "trade_diversion", "label": "Divert trade routes", "cost": "medium", "priority": 85},
        {"id": "stockpile_release", "label": "Release strategic stockpile", "cost": "high", "priority": 70},
        {"id": "subsidize_industry", "label": "Subsidize local industry", "cost": "medium", "priority": 55},
    ],
    "infiltration": [
        {"id": "loyalty_purge", "label": "Loyalty security sweep", "cost": "high", "priority": 88},
        {"id": "propaganda", "label": "Counter-propaganda campaign", "cost": "low", "priority": 65},
        {"id": "agent_hunt", "label": "Hunt enemy agents", "cost": "medium", "priority": 80},
    ],
    "default": [
        {"id": "investigate", "label": "Open intelligence investigation", "cost": "low", "priority": 50},
        {"id": "policy_response", "label": "Issue policy response", "cost": "medium", "priority": 40},
    ],
}


def counterplay_options_for_signal(
    signal: Mapping[str, Any],
    *,
    max_options: int = 3,
) -> Dict[str, Any]:
    """Build ordered counterplay options from an HH map signal dict."""
    sig = dict(signal or {})
    action = str(sig.get("action_class", sig.get("class", "influence"))).strip().lower()
    if not action:
        action = "default"
    pool = list(_OPTIONS.get(action) or _OPTIONS["default"])
    # Influence scales priority slightly
    influence = float(sig.get("influence", 0.5) or 0.5)
    scored: List[Dict[str, Any]] = []
    for opt in pool:
        o = dict(opt)
        o["priority"] = float(o.get("priority", 50)) * (0.85 + 0.3 * influence)
        o["action_class"] = action
        o["province_id"] = int(sig.get("province_id", -1) or -1)
        scored.append(o)
    scored.sort(key=lambda x: -float(x["priority"]))
    top = scored[: max(1, int(max_options))]
    lines = [
        "%s (%s · prio %.0f)" % (t["label"], t["cost"], float(t["priority"]))
        for t in top
    ]
    return {
        "action_class": action,
        "province_id": int(sig.get("province_id", -1) or -1),
        "options": top,
        "lines": lines,
        "count": len(top),
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#c084fc]◇[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
        "empty": len(top) == 0,
        "summary": "Counterplay vs %s: %s" % (action, "; ".join(t["label"] for t in top)),
    }


def format_counterplay_inspector_bbcode(result: Mapping[str, Any]) -> str:
    if not result or result.get("empty"):
        return ""
    header = "[color=#c084fc]── Agent counterplay ──[/color]"
    sub = "[color=#8899aa]%s[/color]" % result.get("summary", "")
    body = result.get("bbcode") or ""
    return "\n".join(x for x in [header, sub, body] if x)
