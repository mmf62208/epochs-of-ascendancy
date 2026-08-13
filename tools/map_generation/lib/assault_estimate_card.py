"""Assault estimate card pilot — multi-phase combat surface beyond ribbon.

Builds a compact card: power, phase ribbon, overall chance, recommendation.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Optional

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from combat_phase_ui import format_phase_ribbon  # type: ignore


def build_assault_estimate_card(
    attacker_power: float,
    defender_power: float,
    *,
    attacker_supply: float = 1.0,
    weather_mult: float = 1.0,
    province_name: str = "",
) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(
        attacker_power,
        defender_power,
        attacker_supply=attacker_supply,
        weather_mult=weather_mult,
    )
    ribbon = format_phase_ribbon(est)
    overall = float(est.get("overall_attacker_win_chance", 0.0))
    if overall >= 0.65:
        rec = "Favorable — press assault"
    elif overall >= 0.45:
        rec = "Marginal — wait for supply/reinforce"
    else:
        rec = "Unfavorable — avoid or soften first"
    title = "Assault estimate"
    if province_name:
        title = "Assault estimate · %s" % province_name
    lines = [
        title,
        "Power %.0f vs %.0f · overall %.0f%%"
        % (float(attacker_power), float(defender_power), overall * 100.0),
        ribbon.get("ribbon_plain", ""),
        rec,
    ]
    lines = [ln for ln in lines if str(ln).strip()]
    bbcode = "\n".join(
        [
            "[color=#ff9a6e]⚔ %s[/color]" % title,
            "[color=#8899aa]Power %.0f vs %.0f · overall %.0f%%[/color]"
            % (float(attacker_power), float(defender_power), overall * 100.0),
            str(ribbon.get("bbcode", "")),
            "[color=#8899aa]%s[/color]" % rec,
        ]
    )
    return {
        "title": title,
        "overall": overall,
        "recommendation": rec,
        "ribbon": ribbon,
        "estimate": est,
        "lines": lines,
        "plain": "\n".join(lines),
        "bbcode": bbcode,
        "empty": bool(est.get("empty")),
        "favorable": overall >= 0.65,
    }
