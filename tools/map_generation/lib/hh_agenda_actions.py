"""HH agenda action-pick pilot — pick next player action from trail context.

Empty trail → empty result (no spam). Not a full agenda screen system.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from agent_counterplay import counterplay_options_for_signal  # type: ignore
from hh_agenda_trail import format_hh_agenda_screen  # type: ignore


def pick_agenda_actions(
    trail: Sequence[Mapping[str, Any]],
    *,
    max_actions: int = 3,
) -> Dict[str, Any]:
    """From latest trail entries, build ordered player action picks."""
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if not entries:
        return {
            "actions": [],
            "lines": [],
            "plain": "",
            "bbcode": "",
            "empty": True,
            "count": 0,
            "summary": "",
            "screen": format_hh_agenda_screen([]),
        }
    # Prefer latest primary-like entries
    latest = list(reversed(entries[-6:]))
    actions: List[Dict[str, Any]] = []
    seen = set()
    for e in latest:
        ac = str(e.get("action_class", "influence")).lower()
        sig = {
            "action_class": ac,
            "province_id": int(e.get("province_id", -1) or -1),
            "influence": float(e.get("influence", 0.55) or 0.55),
            "province_name": str(e.get("province_name", "")),
        }
        cp = counterplay_options_for_signal(sig, max_options=2)
        for opt in cp.get("options") or []:
            key = str(opt.get("id", ""))
            if key in seen:
                continue
            seen.add(key)
            actions.append(
                {
                    "id": key,
                    "label": str(opt.get("label", key)),
                    "priority": float(opt.get("priority", 0)),
                    "action_class": ac,
                    "province_id": sig["province_id"],
                    "cost": str(opt.get("cost", "medium")),
                }
            )
        if len(actions) >= max_actions * 2:
            break
    actions.sort(key=lambda x: -float(x["priority"]))
    top = actions[: max(1, int(max_actions))]
    lines = [
        "%s [%s · %s · pid %s]"
        % (a["label"], a["action_class"], a["cost"], a["province_id"])
        for a in top
    ]
    screen = format_hh_agenda_screen(
        entries,
        counterplay_summary=lines[0] if lines else "",
    )
    return {
        "actions": top,
        "lines": lines,
        "count": len(top),
        "empty": len(top) == 0,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#c084fc]▶[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
        "summary": "Agenda actions: %s" % ("; ".join(a["label"] for a in top)),
        "screen": screen,
    }
