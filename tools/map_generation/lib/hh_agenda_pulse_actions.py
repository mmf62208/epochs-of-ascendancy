"""HH pulse+actions digest — combine monthly pulse with action picks (not full agenda screen).

Empty trail → empty (no spam).
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Sequence

from hh_agenda_pulse import format_hh_agenda_pulse  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore


def format_hh_pulse_actions_digest(
    trail: Sequence[Mapping[str, Any]],
    *,
    month_label: str = "",
    max_actions: int = 3,
) -> Dict[str, Any]:
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if not entries:
        return {
            "plain": "",
            "bbcode": "",
            "empty": True,
            "count": 0,
            "actions": [],
            "summary": "",
        }
    pulse = format_hh_agenda_pulse(entries, month_label=month_label)
    actions = pick_agenda_actions(entries, max_actions=max_actions)
    action_lines = list(actions.get("lines") or [])
    digest_lines = [pulse.get("headline", "Hand pulse")]
    digest_lines.append(
        "Trail %d · pulse ready" % int(pulse.get("count", 0))
    )
    for ln in action_lines[:max_actions]:
        digest_lines.append("Action: %s" % ln)
    plain = "\n".join(digest_lines)
    bb_parts = [
        "[color=#c084fc]◈ %s[/color]" % pulse.get("headline", "Hand pulse"),
        "[color=#8899aa]Trail %d · actions %d[/color]"
        % (int(pulse.get("count", 0)), len(action_lines)),
    ]
    for ln in action_lines[:max_actions]:
        bb_parts.append("[color=#8899aa]→ %s[/color]" % ln)
    return {
        "headline": pulse.get("headline", ""),
        "plain": plain,
        "bbcode": "\n".join(bb_parts),
        "empty": False,
        "count": int(pulse.get("count", 0)),
        "actions": actions,
        "action_lines": action_lines,
        "pulse": pulse,
        "summary": digest_lines[0],
    }
