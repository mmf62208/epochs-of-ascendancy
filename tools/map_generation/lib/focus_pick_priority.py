"""Focus tree / national focus pick priority pilot (not full deep AI).

Scores focus options from cost, prereqs-ready, era fit, and pillar pressure.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence


def score_focus_option(
    focus: Mapping[str, Any],
    *,
    completed_ids: Optional[Sequence[str]] = None,
    year: int = 1936,
    pillar_weights: Optional[Mapping[str, float]] = None,
) -> Dict[str, Any]:
    """Score one focus option. Higher = better next pick."""
    f = dict(focus or {})
    fid = str(f.get("id", f.get("focus_id", ""))).strip()
    name = str(f.get("name", f.get("title", fid))).strip() or fid or "focus"
    cost = float(f.get("cost", f.get("days", 70)) or 70)
    prereqs = list(f.get("prerequisites", f.get("requires", [])) or [])
    done = {str(x) for x in (completed_ids or [])}
    prereq_ok = all(str(p) in done for p in prereqs) if prereqs else True
    era_min = int(f.get("era_min", f.get("available_year", 1918)) or 1918)
    era_max = int(f.get("era_max", 2026) or 2026)
    era_ok = era_min <= int(year) <= era_max

    score = 100.0
    if not prereq_ok:
        score = -100.0
    elif not era_ok:
        score = -50.0
    else:
        # Prefer medium cost; very long focuses slightly less urgent
        score += max(0.0, 40.0 - abs(cost - 70.0) * 0.25)
        # Pillar affinity
        pillar = str(f.get("pillar", f.get("category", ""))).strip().lower()
        weights = dict(pillar_weights or {})
        if pillar and pillar in weights:
            score += float(weights[pillar]) * 20.0
        # Already completed → bottom
        if fid and fid in done:
            score = -200.0
        # Bonus for unlock tags
        unlocks = f.get("unlocks") or f.get("effects") or {}
        if isinstance(unlocks, dict) and unlocks:
            score += min(15.0, float(len(unlocks)) * 3.0)
        if bool(f.get("priority_hint")):
            score += float(f.get("priority_hint", 0))

    return {
        "id": fid,
        "name": name,
        "score": float(score),
        "cost": cost,
        "prereq_ok": prereq_ok,
        "era_ok": era_ok,
        "available": prereq_ok and era_ok and (not fid or fid not in done),
    }


def rank_focus_picks(
    focuses: Sequence[Mapping[str, Any]],
    *,
    completed_ids: Optional[Sequence[str]] = None,
    year: int = 1936,
    pillar_weights: Optional[Mapping[str, float]] = None,
    max_picks: int = 5,
) -> Dict[str, Any]:
    """Rank focus options; return ordered available picks."""
    scored = [
        score_focus_option(
            f,
            completed_ids=completed_ids,
            year=year,
            pillar_weights=pillar_weights,
        )
        for f in (focuses or [])
        if isinstance(f, dict)
    ]
    scored.sort(key=lambda x: (-float(x["score"]), x.get("id", "")))
    available = [s for s in scored if s.get("available")]
    top = available[: max(1, int(max_picks))] if available else []
    best = top[0] if top else {}
    lines = ["%s (score %.1f · cost %.0f)" % (t["name"], t["score"], t["cost"]) for t in top]
    return {
        "best_id": str(best.get("id", "")),
        "best_name": str(best.get("name", "")),
        "best_score": float(best.get("score", 0.0)) if best else 0.0,
        "picks": top,
        "lines": lines,
        "count": len(top),
        "empty": len(top) == 0,
        "summary": (
            "Focus pick: %s" % best.get("name")
            if best
            else "Focus pick: none available"
        ),
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            "[color=#6ec8ff]◆[/color] [color=#8899aa]%s[/color]" % ln for ln in lines
        ),
    }
