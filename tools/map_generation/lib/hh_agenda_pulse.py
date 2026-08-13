"""Monthly HH agenda pulse digest — beyond panel/screen/action-pick.

Empty trail → empty digest (no spam).
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence

from hh_agenda_trail import format_hh_agenda_panel  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore


def format_hh_agenda_pulse(
    trail: Sequence[Mapping[str, Any]],
    *,
    month_label: str = "",
) -> Dict[str, Any]:
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if not entries:
        return {
            "plain": "",
            "bbcode": "",
            "empty": True,
            "count": 0,
            "headline": "",
            "summary": "",
        }
    panel = format_hh_agenda_panel(entries, max_lines=4)
    actions = pick_agenda_actions(entries, max_actions=2)
    # Headline from latest entry
    last = entries[-1]
    ac = str(last.get("action_class", "influence"))
    pname = str(last.get("province_name", last.get("province_id", "")))
    headline = "Hand pulse: %s" % ac
    if pname:
        headline += " @ %s" % pname
    if month_label:
        headline = "%s · %s" % (month_label, headline)
    classes = panel.get("class_order") or []
    digest_lines = [
        headline,
        "Trail %d · classes: %s" % (panel.get("count", 0), ", ".join(classes) if classes else "—"),
    ]
    if actions.get("lines"):
        digest_lines.append("Next: %s" % actions["lines"][0])
    plain = "\n".join(digest_lines)
    bbcode = "\n".join(
        [
            "[color=#c084fc]◈ %s[/color]" % headline,
            "[color=#8899aa]Trail %d · %s[/color]"
            % (panel.get("count", 0), ", ".join(classes) if classes else "—"),
        ]
        + (
            ["[color=#8899aa]Next: %s[/color]" % actions["lines"][0]]
            if actions.get("lines")
            else []
        )
    )
    return {
        "headline": headline,
        "plain": plain,
        "bbcode": bbcode,
        "empty": False,
        "count": int(panel.get("count", 0)),
        "class_order": classes,
        "actions": actions,
        "summary": headline,
    }
