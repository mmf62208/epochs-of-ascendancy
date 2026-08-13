"""Multi-phase combat product surface (major #1) — not day-package stubs.

Interactive product package:
- approach → engage → disengage estimate chain
- phase ribbon + per-phase action_ids
- follow-on recommendation (press / hold / disengage)
- full sequence apply_queue for live panel path
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from combat_phase_ui import format_phase_ribbon  # type: ignore
from product_depth import multi_phase_combat_ui_product  # type: ignore
from combat_phase_estimate import estimate_phase  # type: ignore


PHASE_ORDER = ("approach", "engage", "disengage")

# Leaf action routing per phase (player-facing product actions)
_PHASE_ACTION = {
    "approach": {
        "action_id": "phase_approach",
        "leaf": "apply_supply",
        "label": "Approach — soften / supply prep",
        "score_key": "win_chance",
    },
    "engage": {
        "action_id": "phase_engage",
        "leaf": "apply_assault",
        "label": "Engage — stage multi-phase assault",
        "score_key": "win_chance",
    },
    "disengage": {
        "action_id": "phase_disengage",
        "leaf": "apply_station",
        "label": "Disengage — hold / extract",
        "score_key": "win_chance",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def recommend_combat_phase_step(
    overall: float,
    *,
    engage_win: float = 0.5,
    approach_win: float = 0.5,
) -> Dict[str, Any]:
    """Recommend next player step from multi-phase overall."""
    o = _norm(overall)
    eng = _norm(engage_win)
    app = _norm(approach_win)
    if o >= 0.55 and eng >= 0.5:
        step = "press"
        phase = "engage"
        action_id = "phase_engage"
        reason = "overall favorable — press engage"
    elif o >= 0.4 and app < 0.45:
        step = "soften"
        phase = "approach"
        action_id = "phase_approach"
        reason = "marginal — approach/soften first"
    elif o < 0.35 or eng < 0.35:
        step = "disengage"
        phase = "disengage"
        action_id = "phase_disengage"
        reason = "unfavorable — disengage / hold"
    else:
        step = "hold"
        phase = "approach"
        action_id = "phase_approach"
        reason = "hold tempo — prep approach"
    return {
        "step": step,
        "phase": phase,
        "action_id": action_id,
        "reason": reason,
        "overall": o,
        "engage_win": eng,
        "approach_win": app,
        "empty": False,
        "summary": "Recommend %s · %s · overall %.0f%%" % (step, phase, o * 100.0),
    }


def _phase_action_row(
    phase_est: Mapping[str, Any],
    province_id: int,
    *,
    recommended: bool = False,
) -> Dict[str, Any]:
    phase = str(phase_est.get("phase", "engage")).lower()
    meta = _PHASE_ACTION.get(phase, _PHASE_ACTION["engage"])
    win = float(phase_est.get("attacker_win_chance", 0.0))
    enabled = win >= 0.25 or phase == "disengage"
    label = str(meta["label"])
    if recommended:
        label = "★ " + label
    return {
        "index": int(phase_est.get("index", 0)) if "index" in phase_est else -1,
        "phase": phase,
        "win_chance": win,
        "attacker_effective": float(phase_est.get("attacker_effective", 0.0)),
        "defender_effective": float(phase_est.get("defender_effective", 0.0)),
        "action_id": meta["action_id"],
        "leaf_action": meta["leaf"],
        "label": "%s · win %.0f%%"
        % (
            label,
            win * 100.0,
        ),
        "enabled": enabled,
        "recommended": recommended,
        "province_id": max(1, int(province_id)),
        "score": win,
    }


def build_multi_phase_combat_product(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    *,
    attacker_supply: float = 0.85,
    weather_mult: float = 1.0,
    weather: Optional[Mapping[str, Any]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Full product package: UI product + per-phase actions + recommendation + sequence queue."""
    # Prefer weather dict path when provided (product_depth uses weather mapping)
    if weather is not None:
        ui = multi_phase_combat_ui_product(
            attacker_power=float(attacker_power),
            defender_power=float(defender_power),
            attacker_supply=float(attacker_supply),
            weather=weather,
            province_id=int(province_id),
        )
        wmult = float(ui.get("weather_mult", weather_mult))
        est = dict(ui.get("estimate") or {})
        if not est:
            est = estimate_multi_phase_combat(
                float(attacker_power),
                float(defender_power),
                attacker_supply=float(attacker_supply),
                weather_mult=wmult,
            )
    else:
        wmult = max(0.2, float(weather_mult))
        est = estimate_multi_phase_combat(
            float(attacker_power),
            float(defender_power),
            attacker_supply=float(attacker_supply),
            weather_mult=wmult,
        )
        ui = multi_phase_combat_ui_product(
            attacker_power=float(attacker_power),
            defender_power=float(defender_power),
            attacker_supply=float(attacker_supply),
            weather={"visibility": wmult, "precip": max(0.0, 1.0 - wmult), "ground_state": "mud"},
            province_id=int(province_id),
        )

    overall = float(est.get("overall_attacker_win_chance", ui.get("overall", 0.0)))
    engage_win = float(est.get("engage_win_chance", 0.5))
    approach_win = float(est.get("approach_win_chance", 0.5))
    rec = recommend_combat_phase_step(
        overall, engage_win=engage_win, approach_win=approach_win
    )

    phase_actions: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, r in enumerate(list(est.get("phases") or [])):
        if not isinstance(r, dict):
            continue
        row_src = dict(r)
        row_src["index"] = i
        recommended = str(r.get("phase", "")).lower() == str(rec.get("phase", ""))
        row = _phase_action_row(row_src, province_id, recommended=recommended)
        phase_actions.append(row)
        apply_queue.append(
            {
                "action_id": row["leaf_action"],
                "province_id": max(1, int(province_id)),
                "score": float(row["win_chance"]),
                "enabled": bool(row["enabled"]),
                "label": row["label"],
                "phase": row["phase"],
                "product_action": row["action_id"],
            }
        )

    # Sequence plan: recommended first, then remaining enabled phases
    sequence: List[Dict[str, Any]] = []
    rec_phase = str(rec.get("phase", "engage"))
    for row in phase_actions:
        if row["phase"] == rec_phase:
            sequence.append(row)
    for row in phase_actions:
        if row["phase"] != rec_phase and row.get("enabled"):
            sequence.append(row)

    ribbon = format_phase_ribbon(
        est, attacker_power=attacker_power, defender_power=defender_power
    )
    apply_ready = overall >= 0.35 and float(attacker_power) > 0.0
    score = _norm(overall * (0.85 + 0.15 * wmult))

    primary_actions: List[Dict[str, Any]] = [
        {
            "action_id": "multi_phase_combat_product",
            "label": "Run multi-phase combat product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "phase_engage")),
            "label": "Recommended: %s" % rec.get("step", "hold"),
            "enabled": apply_ready or str(rec.get("step")) == "disengage",
        },
    ]
    for row in phase_actions:
        primary_actions.append(
            {
                "action_id": row["action_id"],
                "label": row["label"],
                "enabled": bool(row["enabled"]),
                "phase": row["phase"],
            }
        )

    label = (
        "Multi-phase product · %d phases · overall %.0f%% · %s · wx×%.2f · #%d"
        % (
            len(phase_actions),
            overall * 100.0,
            str(rec.get("step", "hold")),
            wmult,
            max(1, int(province_id)),
        )
    )
    plain_lines = [label, str(rec.get("summary", "")), str(ribbon.get("ribbon_plain", ribbon.get("summary", "")))]
    for row in phase_actions:
        plain_lines.append(str(row.get("label", "")))

    return {
        "ui": ui,
        "estimate": est,
        "ribbon": ribbon,
        "recommendation": rec,
        "phase_actions": phase_actions,
        "phase_rows": phase_actions,  # panel compat
        "phase_count": len(phase_actions),
        "sequence": sequence,
        "apply_queue": apply_queue,
        "overall": overall,
        "weather_mult": wmult,
        "attacker_power": float(attacker_power),
        "defender_power": float(defender_power),
        "attacker_supply": float(attacker_supply),
        "province_id": max(1, int(province_id)),
        "score": score,
        "apply_ready": apply_ready,
        "follow_on": str(rec.get("step", "hold")),
        "actions": primary_actions,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#ff9a6e]⚔ Multi-phase product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": len(phase_actions) == 0,
        "integration": [
            "multi_phase_combat_product",
            "phase_approach",
            "phase_engage",
            "phase_disengage",
            "major_1",
        ],
    }


def execute_combat_phase_plan(
    phase: str,
    province_id: int = 1,
    *,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather_mult: float = 1.0,
) -> Dict[str, Any]:
    """Resolve one phase into a leaf apply payload for live managers."""
    p = str(phase or "engage").strip().lower()
    if p not in _PHASE_ACTION:
        p = "engage"
    est = estimate_phase(
        p,
        float(attacker_power),
        float(defender_power),
        attacker_supply=float(attacker_supply),
        weather_mult=float(weather_mult),
    )
    meta = _PHASE_ACTION[p]
    win = float(est.get("attacker_win_chance", 0.5))
    enabled = win >= 0.25 or p == "disengage"
    q = [
        {
            "action_id": meta["leaf"],
            "province_id": max(1, int(province_id)),
            "score": win,
            "enabled": enabled,
            "label": meta["label"],
            "phase": p,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute %s · win %.0f%% · leaf %s · #%d" % (
        p,
        win * 100.0,
        meta["leaf"],
        max(1, int(province_id)),
    )
    return {
        "phase": p,
        "estimate": est,
        "leaf_action": meta["leaf"],
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": win,
        "enabled": enabled,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#ff9a6e]⚔ Phase %s[/color] [color=#8899aa]%s[/color]" % (p, label),
        "empty": False,
        "ok": enabled,
        "integration": ["execute_combat_phase", p, meta["leaf"]],
    }


def multi_phase_combat_product_integrity(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    product = build_multi_phase_combat_product(
        attacker_power, defender_power, province_id=1
    )
    eng = execute_combat_phase_plan("engage", province_id=1)
    app = execute_combat_phase_plan("approach", province_id=1)
    dis = execute_combat_phase_plan("disengage", province_id=1)
    ok = (
        not bool(product.get("empty"))
        and int(product.get("phase_count", 0)) >= 3
        and len(product.get("apply_queue") or []) >= 3
        and bool(product.get("recommendation"))
        and bool(eng.get("ok", True))
        and bool(app.get("ok", True))
        and bool(dis.get("ok", True))
    )
    return {
        "ok": ok,
        "phase_count": int(product.get("phase_count", 0)),
        "overall": float(product.get("overall", 0)),
        "follow_on": str(product.get("follow_on", "")),
        "summary": "Multi-phase combat product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_multi_phase_combat_product_loop() -> Dict[str, Any]:
    product = build_multi_phase_combat_product(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    foul = build_multi_phase_combat_product(100.0, 80.0, attacker_supply=0.7, weather_mult=0.55)
    gate = multi_phase_combat_product_integrity()
    # Weather must change overall (non-trivial product)
    clear_o = float(product.get("overall", 0))
    foul_o = float(foul.get("overall", 0))
    wx_shift = abs(clear_o - foul_o)
    ok = bool(gate.get("ok")) and wx_shift > 0.01 and int(product.get("phase_count", 0)) >= 3
    label = (
        "Close multi-phase combat product · phases %d · wx_shift %.3f · %s"
        % (int(product.get("phase_count", 0)), wx_shift, "PASS" if ok else "FAIL")
    )
    return {
        "product": product,
        "foul": foul,
        "gate": gate,
        "wx_shift": wx_shift,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#ff9a6e]✓ Multi-phase combat product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
