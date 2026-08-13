"""HH monthly brief pilot — pulse + actions + class rollup (beyond pulse+actions alone).

Empty trail → empty (no spam).
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Sequence

from hh_agenda_pulse_actions import format_hh_pulse_actions_digest  # type: ignore
from hh_agenda_trail import format_hh_agenda_panel  # type: ignore


def format_hh_monthly_brief(
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
            "summary": "",
            "class_order": [],
        }
    digest = format_hh_pulse_actions_digest(entries, month_label=month_label, max_actions=max_actions)
    panel = format_hh_agenda_panel(entries, max_lines=6)
    classes = list(panel.get("class_order") or [])
    # Influence rollup
    total_inf = 0.0
    for e in entries:
        total_inf += float(e.get("influence", e.get("strength", 0.0)) or 0.0)
    avg_inf = total_inf / max(1, len(entries))
    title = "Monthly Hand brief"
    if month_label:
        title = "%s · %s" % (month_label, title)
    headline = "%s · trail %d · avg inf %.0f%% · classes %s" % (
        title,
        len(entries),
        avg_inf * 100.0,
        ", ".join(classes) if classes else "—",
    )
    body = str(digest.get("plain", "")).strip()
    plain = headline if not body else "%s\n%s" % (headline, body)
    bb_parts = [
        "[color=#c084fc]◈ %s[/color]" % headline,
    ]
    if body:
        for ln in body.split("\n")[:6]:
            t = ln.strip()
            if t:
                bb_parts.append("[color=#8899aa]%s[/color]" % t)
    return {
        "headline": headline,
        "plain": plain,
        "bbcode": "\n".join(bb_parts),
        "empty": False,
        "count": len(entries),
        "class_order": classes,
        "avg_influence": float(avg_inf),
        "digest": digest,
        "summary": headline,
    }
