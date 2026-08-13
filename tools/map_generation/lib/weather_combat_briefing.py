"""Weather combat briefing pilot — card + ribbon + wx mult package (beyond weather ribbon alone)."""
from __future__ import annotations

from typing import Any, Dict

from assault_estimate_card import build_assault_estimate_card  # type: ignore
from combat_phase_ui import format_phase_ribbon  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore


def build_weather_combat_briefing(
    attacker_power: float,
    defender_power: float,
    *,
    weather_mult: float = 1.0,
    attacker_supply: float = 1.0,
    province_name: str = "",
) -> Dict[str, Any]:
    wmult = max(0.2, min(1.2, float(weather_mult)))
    est = estimate_multi_phase_combat(
        attacker_power, defender_power, attacker_supply=attacker_supply, weather_mult=wmult
    )
    ribbon = format_phase_ribbon(est)
    card = build_assault_estimate_card(
        attacker_power, defender_power, attacker_supply=attacker_supply, weather_mult=wmult,
        province_name=province_name,
    )
    overall = float(est.get("overall_attacker_win_chance", 0.0))
    rec = str(card.get("recommendation", ""))
    headline = "Wx briefing ×%.2f · win %.0f%%" % (wmult, overall * 100.0)
    if province_name:
        headline = "%s @ %s" % (headline, province_name)
    plain_lines = [
        headline,
        str(ribbon.get("ribbon_plain", "")),
        rec,
    ]
    plain = "\n".join(ln for ln in plain_lines if str(ln).strip())
    bbcode = "\n".join(
        [
            "[color=#ff9a6e]⚔ %s[/color]" % headline,
            str(ribbon.get("bbcode", "")),
            "[color=#8899aa]%s[/color]" % rec if rec else "",
        ]
    ).strip()
    return {
        "weather_mult": wmult,
        "overall": overall,
        "estimate": est,
        "ribbon": ribbon,
        "card": card,
        "recommendation": rec,
        "headline": headline,
        "plain": plain,
        "bbcode": bbcode,
        "empty": bool(card.get("empty", False)) and bool(ribbon.get("empty", False)),
        "summary": headline,
        "favorable": overall >= 0.65,
    }
