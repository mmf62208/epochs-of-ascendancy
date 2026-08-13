"""Multi-phase combat estimate pilot (not full multi-phase combat UI).

Chains approach → engage → disengage with distinct non-trivial modifiers.
Pure decision helper for assault estimate surfaces.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Sequence

PHASES = ("approach", "engage", "disengage")

# Base power multipliers per phase (attacker perspective)
_PHASE_ATK = {
    "approach": 0.85,  # exposed movement / prep
    "engage": 1.15,  # full contact
    "disengage": 0.70,  # extraction risk
}
_PHASE_DEF = {
    "approach": 1.05,  # defenders prepare
    "engage": 1.00,
    "disengage": 1.10,  # pursuit advantage
}


def estimate_phase(
    phase: str,
    attacker_power: float,
    defender_power: float,
    *,
    attacker_supply: float = 1.0,
    weather_mult: float = 1.0,
) -> Dict[str, Any]:
    """Estimate one combat phase outcome scores."""
    p = str(phase or "engage").strip().lower()
    if p not in _PHASE_ATK:
        p = "engage"
    # Weather hurts attacker more (offensive tempo); defender keeps base phase mod.
    atk = max(0.0, float(attacker_power)) * _PHASE_ATK[p] * max(0.2, float(attacker_supply)) * max(0.2, float(weather_mult))
    dfn = max(0.0, float(defender_power)) * _PHASE_DEF[p]
    ratio = atk / dfn if dfn > 1e-9 else (2.0 if atk > 0 else 0.0)
    # Simple win chance clamp
    win = max(0.05, min(0.95, 0.5 + (ratio - 1.0) * 0.25))
    return {
        "phase": p,
        "attacker_effective": float(atk),
        "defender_effective": float(dfn),
        "power_ratio": float(ratio),
        "attacker_win_chance": float(win),
        "label": p,
    }


def estimate_multi_phase_combat(
    attacker_power: float,
    defender_power: float,
    *,
    attacker_supply: float = 1.0,
    weather_mult: float = 1.0,
    phases: Sequence[str] = PHASES,
) -> Dict[str, Any]:
    """Run full approach→engage→disengage estimate chain.

    Phases produce distinct effective powers; overall score is product-influenced
    mean of win chances (non-trivial vs single engage-only).
    """
    phase_list = [str(p).lower() for p in (phases or PHASES) if str(p).strip()]
    if not phase_list:
        phase_list = list(PHASES)
    results: List[Dict[str, Any]] = []
    # Attrition across phases: powers bleed slightly
    atk = float(attacker_power)
    dfn = float(defender_power)
    for p in phase_list:
        est = estimate_phase(
            p,
            atk,
            dfn,
            attacker_supply=attacker_supply,
            weather_mult=weather_mult,
        )
        results.append(est)
        # Post-phase attrition
        if est["attacker_win_chance"] >= 0.5:
            dfn *= 0.92
            atk *= 0.97
        else:
            atk *= 0.90
            dfn *= 0.98
    win_chances = [float(r["attacker_win_chance"]) for r in results]
    overall = sum(win_chances) / float(len(win_chances)) if win_chances else 0.0
    # Engage phase must differ from approach
    engage = next((r for r in results if r["phase"] == "engage"), results[-1] if results else {})
    approach = next((r for r in results if r["phase"] == "approach"), results[0] if results else {})
    return {
        "phases": results,
        "phase_names": [r["phase"] for r in results],
        "overall_attacker_win_chance": float(overall),
        "engage_win_chance": float(engage.get("attacker_win_chance", 0.0)),
        "approach_win_chance": float(approach.get("attacker_win_chance", 0.0)),
        "attacker_power_start": float(attacker_power),
        "defender_power_start": float(defender_power),
        "summary": (
            "multi-phase %.0f%% (approach %.0f%% · engage %.0f%%)"
            % (
                overall * 100.0,
                float(approach.get("attacker_win_chance", 0.0)) * 100.0,
                float(engage.get("attacker_win_chance", 0.0)) * 100.0,
            )
        ),
        "empty": len(results) == 0,
    }


def format_multi_phase_estimate_bbcode(estimate: Mapping[str, Any]) -> str:
    if not estimate or estimate.get("empty"):
        return ""
    lines = ["[color=#ff9a6e]⚔ Multi-phase estimate[/color] [color=#8899aa]%s[/color]" % estimate.get("summary", "")]
    for r in estimate.get("phases") or []:
        lines.append(
            "[color=#8899aa]· %s — atk×%.2f def×%.2f win %.0f%%[/color]"
            % (
                r.get("phase"),
                float(r.get("attacker_effective", 0.0)),
                float(r.get("defender_effective", 0.0)),
                float(r.get("attacker_win_chance", 0.0)) * 100.0,
            )
        )
    return "\n".join(lines)
