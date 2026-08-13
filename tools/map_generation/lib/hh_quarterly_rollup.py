"""HH quarterly rollup pilot — 3-month class totals (beyond monthly brief).

Empty trail → empty (no spam).
"""
from __future__ import annotations

from collections import Counter
from typing import Any, Dict, List, Mapping, Sequence


def format_hh_quarterly_rollup(
    trail: Sequence[Mapping[str, Any]],
    *,
    quarter_label: str = "",
) -> Dict[str, Any]:
    entries = [dict(e) for e in (trail or []) if isinstance(e, dict)]
    if not entries:
        return {
            "plain": "",
            "bbcode": "",
            "empty": True,
            "count": 0,
            "summary": "",
            "class_totals": {},
        }
    # Use last up to 3 months of entries by (year, month) uniqueness, else last 6 trail slots
    months: List[tuple] = []
    seen = set()
    for e in reversed(entries):
        key = (int(e.get("year", 0) or 0), int(e.get("month", 0) or 0))
        if key in seen:
            continue
        seen.add(key)
        months.append(key)
        if len(months) >= 3:
            break
    month_set = set(months) if months else None
    window: List[Dict[str, Any]] = []
    for e in entries:
        key = (int(e.get("year", 0) or 0), int(e.get("month", 0) or 0))
        if month_set is None or key in month_set or not any(months):
            window.append(e)
    if not window:
        window = list(entries)[-6:]
    counts: Counter = Counter()
    total_inf = 0.0
    for e in window:
        ac = str(e.get("action_class", "influence"))
        counts[ac] += 1
        total_inf += float(e.get("influence", e.get("strength", 0.0)) or 0.0)
    ranked = counts.most_common()
    title = "Quarterly Hand rollup"
    if quarter_label:
        title = "%s · %s" % (quarter_label, title)
    headline = "%s · events %d · classes %d · avg inf %.0f%%" % (
        title,
        len(window),
        len(ranked),
        (total_inf / max(1, len(window))) * 100.0,
    )
    lines = [headline]
    for ac, n in ranked[:4]:
        lines.append("%s ×%d" % (ac, n))
    plain = "\n".join(lines)
    bbcode = "\n".join(
        ["[color=#c084fc]◈ %s[/color]" % headline]
        + ["[color=#8899aa]· %s ×%d[/color]" % (ac, n) for ac, n in ranked[:4]]
    )
    return {
        "headline": headline,
        "plain": plain,
        "bbcode": bbcode,
        "empty": False,
        "count": len(window),
        "class_totals": {ac: int(n) for ac, n in ranked},
        "class_order": [ac for ac, _ in ranked],
        "summary": headline,
        "months_covered": len(months) if months else 1,
    }
