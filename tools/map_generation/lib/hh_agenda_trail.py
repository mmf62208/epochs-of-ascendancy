#!/usr/bin/env python3
"""Pure helpers for Hidden Hand multi-month map agenda trail.

Stores compact monthly signal summaries (primary + optional secondary) in a
capped rolling list for inspector/debug (not a full agenda UI).
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

DEFAULT_TRAIL_CAPACITY = 6
MIN_TRAIL_CAPACITY = 3


def signal_to_trail_entry(signal: Dict[str, Any], *, is_secondary: bool = False) -> Dict[str, Any]:
    """Compress a map-signal-shaped dict into a trail entry."""
    sig = signal or {}
    action = str(sig.get("action_class", "influence")).strip().lower() or "influence"
    title = str(sig.get("title", "")).strip()
    if not title:
        title = "Hidden Hand %s" % action.replace("_", " ")
    marker = str(sig.get("marker", "")).strip()
    label = str(sig.get("label", "")).strip()
    if not label:
        label = ("%s %s" % (marker, title)).strip() if marker else title
    return {
        "year": int(sig.get("year", 0)),
        "month": int(sig.get("month", 0)),
        "province_id": int(sig.get("province_id", -1)),
        "province_name": str(sig.get("province_name", "")),
        "owner_tag": str(sig.get("owner_tag", "")),
        "action_class": action,
        "title": title,
        "marker": marker,
        "label": label,
        "map_effect": str(sig.get("map_effect", "")),
        "tint_key": str(sig.get("tint_key", "")),
        "is_secondary": bool(is_secondary or sig.get("is_secondary", False)),
        "summary": _entry_summary(
            int(sig.get("year", 0)),
            int(sig.get("month", 0)),
            action,
            str(sig.get("province_name", "")),
            bool(is_secondary or sig.get("is_secondary", False)),
        ),
    }


def _entry_summary(
    year: int, month: int, action: str, province_name: str, is_secondary: bool
) -> str:
    role = "secondary" if is_secondary else "primary"
    where = province_name or "unknown"
    ym = "%04d-%02d" % (int(year), int(month)) if year > 0 else "????-??"
    return "%s %s · %s · %s" % (ym, role, action.replace("_", " "), where)


def append_hh_agenda_trail(
    trail: Optional[Sequence[Dict[str, Any]]],
    primary: Dict[str, Any],
    secondary: Optional[Dict[str, Any]] = None,
    capacity: int = DEFAULT_TRAIL_CAPACITY,
) -> List[Dict[str, Any]]:
    """Append primary (+ optional secondary) entries; keep last `capacity` entries."""
    cap = max(MIN_TRAIL_CAPACITY, int(capacity))
    out: List[Dict[str, Any]] = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if primary:
        out.append(signal_to_trail_entry(primary, is_secondary=False))
    if secondary and isinstance(secondary, dict) and secondary:
        # Only append meaningful secondary pulses
        if bool(secondary.get("active", True)) or secondary.get("action_class"):
            out.append(signal_to_trail_entry(secondary, is_secondary=True))
    if len(out) > cap:
        out = out[-cap:]
    return out


def format_hh_agenda_trail(
    trail: Sequence[Dict[str, Any]],
    *,
    max_lines: int = 6,
) -> Dict[str, Any]:
    """Player/debug facing summary of the multi-month HH agenda trail."""
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    lines: List[str] = []
    classes: List[str] = []
    for e in entries:
        summary = str(e.get("summary", "")).strip()
        if not summary:
            summary = _entry_summary(
                int(e.get("year", 0)),
                int(e.get("month", 0)),
                str(e.get("action_class", "influence")),
                str(e.get("province_name", "")),
                bool(e.get("is_secondary", False)),
            )
        lines.append(summary)
        classes.append(str(e.get("action_class", "")))
    show = lines[-max(1, int(max_lines)) :] if lines else []
    bbcode = "\n".join(
        "[color=#c084fc]◈[/color] [color=#8899aa]%s[/color]" % ln for ln in show
    )
    return {
        "count": len(entries),
        "capacity_hint": DEFAULT_TRAIL_CAPACITY,
        "lines": show,
        "all_lines": lines,
        "action_classes": classes,
        "plain": "\n".join(show),
        "bbcode": bbcode,
        "empty": len(entries) == 0,
    }


def format_hh_agenda_panel(
    trail: Sequence[Dict[str, Any]],
    *,
    max_lines: int = 6,
    title: str = "Hidden Hand Agenda",
) -> Dict[str, Any]:
    """Multi-entry agenda UI panel payload (pilot — not full screen system).

    Builds ordered lines, class histogram, and BBCode block suitable for
    inspector/debug panel from the real trail store shape.
    """
    trail_fmt = format_hh_agenda_trail(trail, max_lines=max_lines)
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    # Empty trail → empty panel (no zero-action header spam)
    if not entries or bool(trail_fmt.get("empty", True)):
        return {
            "title": str(title).strip() or "Hidden Hand Agenda",
            "subtitle": "",
            "count": 0,
            "class_order": [],
            "class_counts": {},
            "lines": [],
            "panel_lines": [],
            "plain": "",
            "bbcode": "",
            "empty": True,
            "trail": trail_fmt,
        }
    class_counts: Dict[str, int] = {}
    for c in trail_fmt.get("action_classes") or []:
        key = str(c or "influence").strip() or "influence"
        class_counts[key] = class_counts.get(key, 0) + 1
    # Distinct classes in order of first appearance
    class_order: List[str] = []
    for c in trail_fmt.get("action_classes") or []:
        s = str(c or "").strip()
        if s and s not in class_order:
            class_order.append(s)
    header = str(title).strip() or "Hidden Hand Agenda"
    subtitle = "%d recent actions · %d classes" % (
        int(trail_fmt.get("count", 0)),
        len(class_order),
    )
    body_lines = list(trail_fmt.get("lines") or [])
    panel_lines = [header, subtitle] + body_lines
    bb_header = "[color=#c084fc]── ◈ %s ──[/color]" % header
    bb_sub = "[color=#8899aa]%s[/color]" % subtitle
    bb_body = trail_fmt.get("bbcode") or ""
    bbcode = "\n".join(x for x in [bb_header, bb_sub, bb_body] if x)
    return {
        "title": header,
        "subtitle": subtitle,
        "count": int(trail_fmt.get("count", 0)),
        "class_order": class_order,
        "class_counts": class_counts,
        "lines": body_lines,
        "panel_lines": panel_lines,
        "plain": "\n".join(panel_lines),
        "bbcode": bbcode,
        "empty": False,
        "trail": trail_fmt,
    }


def format_hh_agenda_screen(
    trail: Sequence[Dict[str, Any]],
    *,
    max_lines: int = 6,
    counterplay_summary: str = "",
) -> Dict[str, Any]:
    """Agenda *screen* layout pilot: sections Recent / By class / Actions.

    Empty trail → empty plain/bbcode (no zero-action header spam).
    Beyond panel: multi-section structure for a future full UI.
    """
    panel = format_hh_agenda_panel(trail, max_lines=max_lines)
    if panel.get("empty"):
        return {
            "title": "Hidden Hand Agenda",
            "sections": [],
            "plain": "",
            "bbcode": "",
            "empty": True,
            "count": 0,
            "panel": panel,
        }
    class_lines = [
        "%s ×%d" % (k, int(v))
        for k, v in sorted(
            (panel.get("class_counts") or {}).items(),
            key=lambda kv: (-int(kv[1]), str(kv[0])),
        )
    ]
    recent = list(panel.get("lines") or [])
    sections = [
        {"id": "header", "title": "Hidden Hand Agenda", "lines": [panel.get("subtitle", "")]},
        {"id": "recent", "title": "Recent", "lines": recent},
        {"id": "by_class", "title": "By class", "lines": class_lines},
    ]
    if str(counterplay_summary or "").strip():
        sections.append(
            {
                "id": "actions",
                "title": "Suggested counterplay",
                "lines": [str(counterplay_summary).strip()],
            }
        )
    plain_parts: List[str] = []
    bb_parts: List[str] = []
    for sec in sections:
        title = str(sec.get("title", ""))
        plain_parts.append("## %s" % title)
        bb_parts.append("[color=#c084fc]── %s ──[/color]" % title)
        for ln in sec.get("lines") or []:
            t = str(ln).strip()
            if not t:
                continue
            plain_parts.append(t)
            bb_parts.append("[color=#8899aa]%s[/color]" % t)
        plain_parts.append("")
    plain = "\n".join(plain_parts).strip()
    bbcode = "\n".join(bb_parts)
    return {
        "title": "Hidden Hand Agenda",
        "sections": sections,
        "section_ids": [s["id"] for s in sections],
        "plain": plain,
        "bbcode": bbcode,
        "empty": False,
        "count": int(panel.get("count", 0)),
        "panel": panel,
    }
