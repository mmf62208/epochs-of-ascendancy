"""Multi-phase combat UI label pilot (not full multi-phase combat UI).

Builds ordered phase ribbon labels and BBCode from multi-phase estimate payloads.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore

PHASE_ICONS = {
    "approach": "↗",
    "engage": "⚔",
    "disengage": "↘",
}


def format_phase_ribbon(
    estimate: Optional[Mapping[str, Any]] = None,
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    """Build UI ribbon segments for approach → engage → disengage."""
    est = dict(estimate) if estimate else estimate_multi_phase_combat(
        attacker_power, defender_power
    )
    if est.get("empty"):
        return {
            "segments": [],
            "labels": [],
            "ribbon_plain": "",
            "bbcode": "",
            "empty": True,
            "summary": "",
        }
    segments: List[Dict[str, Any]] = []
    labels: List[str] = []
    for r in est.get("phases") or []:
        phase = str(r.get("phase", "engage"))
        win = float(r.get("attacker_win_chance", 0.0))
        icon = PHASE_ICONS.get(phase, "·")
        label = "%s %s %.0f%%" % (icon, phase, win * 100.0)
        labels.append(label)
        segments.append(
            {
                "phase": phase,
                "icon": icon,
                "win_chance": win,
                "label": label,
                "attacker_effective": float(r.get("attacker_effective", 0.0)),
                "defender_effective": float(r.get("defender_effective", 0.0)),
            }
        )
    ribbon = " → ".join(labels)
    bb_parts = [
        "[color=#ff9a6e]%s[/color] [color=#8899aa]%s %.0f%%[/color]"
        % (s["icon"], s["phase"], s["win_chance"] * 100.0)
        for s in segments
    ]
    bbcode = (
        "[color=#ff9a6e]⚔ Phase ribbon[/color] "
        + " [color=#667788]→[/color] ".join(bb_parts)
    )
    return {
        "segments": segments,
        "labels": labels,
        "ribbon_plain": ribbon,
        "bbcode": bbcode,
        "empty": len(segments) == 0,
        "summary": ribbon,
        "overall": float(est.get("overall_attacker_win_chance", 0.0)),
        "estimate": est,
    }
