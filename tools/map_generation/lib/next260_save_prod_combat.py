"""Next-260 save/session continuity · production/industry surge · multi-phase combat (20).

A) Save / session continuity (1–7)
B) Production / industry wartime surge (8–14)
C) Combat multi-phase product surface (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from priority_systems import save_slot_browser_package  # type: ignore
from week2_core_polish import save_slot_browser_flair  # type: ignore
from campaign_execution import (  # type: ignore
    execution_integrity_gate,
    close_the_loop,
    production_order_resolve,
    combat_order_execute,
)
from gameplay_loops import sole_mult_integrity, oob_factory_risk_loop  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore
from campaign_cohesion import production_campaign_risk  # type: ignore
from integrated_theater_ops import factory_risk_compose, assault_readiness_compose  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from product_depth import multi_phase_combat_ui_product  # type: ignore


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _q(aid: str, pid: int, score: float, label: str) -> Dict[str, Any]:
    return {
        "action_id": aid,
        "province_id": max(1, int(pid)),
        "score": float(score),
        "enabled": True,
        "label": label,
    }


def _day(
    action_id: str,
    title: str,
    summary: str,
    score: float,
    apply_queue: List[Dict[str, Any]],
    color: str = "#5ec8ff",
    marker: str = "★",
    integration: Optional[List[str]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": "Run %s" % title, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]"
        % (color, marker, title, summary),
        "empty": False,
        "integration": list(integration or ["next260", "save_prod_combat"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.7,
        "precip": 0.3,
        "precip_intensity": 0.3,
        "ground_state": "mud",
        "wind": 0.25,
        "temperature_c": 8.0,
    }


def _slots() -> List[Dict[str, Any]]:
    return [
        {"slot_id": "quicksave", "label": "quicksave · world_full", "occupied": True},
        {"slot_id": "autosave", "label": "autosave · empty", "occupied": False},
        {"slot_id": "slot1", "label": "slot1 · campaign", "occupied": True},
        {"slot_id": "slot2", "label": "slot2 · empty", "occupied": False},
    ]


def _targets(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "defender_power": 70.0, "defender_supply": 0.8, "name": "Front"},
        {"province_id": province_id + 1, "defender_power": 55.0, "defender_supply": 0.7, "name": "Flank"},
    ]


# A) Save / session continuity


def save_slot_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    flair = save_slot_browser_flair(_slots(), max_rows=8)
    score = _norm(
        0.55 * float(pkg.get("score", 0.7)) + 0.45 * float(flair.get("score", 0.55))
    )
    q = [
        _q("refresh_queue", province_id, score, "save slot depth refresh"),
        _q("apply_supply", province_id, 0.5, "save slot depth supply"),
    ]
    return _day(
        "save_slot_depth_day",
        "Save slot depth day",
        "Save slot depth · slots %d · score %.2f" % (int(pkg.get("count", 0)), score),
        score,
        q,
        "#e8c547",
        "💾",
        ["save", "slot", "depth"],
        {"package": pkg, "flair": flair, "save_score": score, "slot_ok": True},
    )


def autosave_session_depth_day(province_id: int = 1) -> Dict[str, Any]:
    flair = save_slot_browser_flair(
        [{"slot": "autosave", "occupied": True, "label": "Autosave"}, {"slot": "1", "occupied": False}],
        max_rows=8,
    )
    pkg = save_slot_browser_package(_slots())
    score = _norm(
        0.6 * float(flair.get("score", 0.65)) + 0.4 * float(pkg.get("score", 0.6))
    )
    q = [
        _q("refresh_queue", province_id, score, "autosave session depth refresh"),
        _q("apply_production", province_id, 0.5, "autosave session depth production"),
    ]
    return _day(
        "autosave_session_depth_day",
        "Autosave session depth day",
        "Autosave session depth · occupied %d · score %.2f"
        % (int(flair.get("occupied_count", 0)), score),
        score,
        q,
        "#e8c547",
        "💾",
        ["save", "autosave", "session"],
        {"flair": flair, "package": pkg, "save_score": score},
    )


def campaign_session_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    score = _norm(
        0.4 * float(pkg.get("score", 0.6))
        + 0.35 * (0.8 if gate.get("ok") else 0.3)
        + 0.25 * (0.75 if sole.get("integrity_ok", True) else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "campaign session depth refresh"),
        _q("apply_station", province_id, 0.55, "campaign session depth station"),
        _q("apply_supply", province_id, 0.5, "campaign session depth supply"),
    ]
    return _day(
        "campaign_session_depth_day",
        "Campaign session depth day",
        "Campaign session depth · browser · gate · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "📋",
        ["save", "campaign", "session"],
        {"package": pkg, "gate": gate, "sole": sole, "save_score": score},
    )


def save_resume_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    flair = save_slot_browser_flair(_slots(), max_rows=8)
    sole = sole_mult_integrity()
    score = _norm(
        0.45 * float(pkg.get("score", 0.5))
        + 0.4 * float(flair.get("score", 0.5))
        + 0.15 * (0.7 if sole.get("integrity_ok", True) else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "save resume depth refresh"),
        _q("apply_focus", province_id, 0.5, "save resume depth focus"),
        _q("apply_station", province_id, 0.45, "save resume depth station"),
    ]
    return _day(
        "save_resume_depth_day",
        "Save resume depth day",
        "Save resume depth · package · flair · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "↻",
        ["save", "resume", "session"],
        {"package": pkg, "flair": flair, "sole": sole, "save_score": score},
    )


def session_checkpoint_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    flair = save_slot_browser_flair(_slots(), max_rows=8)
    sole = sole_mult_integrity()
    score = _norm(0.5 + 0.08 * min(4, int(pkg.get("count", 0))) + 0.05 * int(flair.get("occupied_count", 0)))
    q = [
        _q("refresh_queue", province_id, score, "session checkpoint depth refresh"),
        _q("apply_production", province_id, 0.5, "session checkpoint depth production"),
        _q("apply_supply", province_id, 0.45, "session checkpoint depth supply"),
    ]
    return _day(
        "session_checkpoint_depth_day",
        "Session checkpoint depth day",
        "Session checkpoint depth · slots · sole · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "✓",
        ["save", "checkpoint", "session"],
        {"package": pkg, "flair": flair, "sole": sole, "save_score": score},
    )


def save_audit_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    flair = save_slot_browser_flair(_slots(), max_rows=8)
    gate = execution_integrity_gate()
    occupied = int(pkg.get("occupied_count", flair.get("occupied_count", 0)) or 0)
    score = _norm(
        0.45 * float(pkg.get("score", 0.55))
        + 0.3 * float(flair.get("score", 0.55))
        + 0.25 * (0.8 if gate.get("ok") else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "save audit depth refresh"),
        _q("apply_station", province_id, 0.5, "save audit depth station"),
        _q("apply_supply", province_id, 0.45, "save audit depth supply"),
    ]
    return _day(
        "save_audit_depth_day",
        "Save audit depth day",
        "Save audit depth · occupied %d · score %.2f" % (occupied, score),
        score,
        q,
        "#e8c547",
        "✓",
        ["save", "audit", "session"],
        {"package": pkg, "flair": flair, "gate": gate, "save_score": score},
    )


def save_session_close_depth_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    flair = save_slot_browser_flair(_slots(), max_rows=8)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.3 * float(pkg.get("score", 0.5))
        + 0.3 * float(flair.get("score", 0.5))
        + 0.4 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "save session close depth refresh"),
        _q("apply_supply", province_id, 0.55, "save session close depth supply"),
        _q("apply_production", province_id, 0.45, "save session close depth production"),
    ]
    return _day(
        "save_session_close_depth_day",
        "Save session close depth day",
        "Save session close depth · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "✓",
        ["save", "session", "close"],
        {
            "package": pkg,
            "flair": flair,
            "gate": gate,
            "sole": sole,
            "ok": ok,
            "save_score": score,
        },
    )


# B) Production / industry wartime surge


def factory_risk_surge_day(province_id: int = 1) -> Dict[str, Any]:
    risk = factory_risk_compose(_wx())
    loop = oob_factory_risk_loop(weather=_wx())
    prod = 1.0 - float(risk.get("risk", 0.25))
    score = _norm(
        0.5 * prod + 0.5 * float(loop.get("effective_output", 0.7))
    )
    q = [
        _q("apply_production", province_id, score, "factory risk surge production"),
        _q("apply_supply", province_id, 0.55, "factory risk surge supply"),
        _q("apply_station", province_id, 0.45, "factory risk surge station"),
    ]
    return _day(
        "factory_risk_surge_day",
        "Factory risk surge day",
        "Factory risk surge · risk · oob · score %.2f" % score,
        score,
        q,
        "#f87171",
        "🏭",
        ["production", "factory", "risk", "surge"],
        {"risk": risk, "loop": loop, "prod_score": score},
    )


def production_priority_depth_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation(weather=_wx())
    order = production_order_resolve(weather=_wx())
    score = _norm(
        0.55 * float(mut.get("score", 0.55)) + 0.45 * float(order.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "production priority depth primary"),
        _q("apply_supply", province_id, 0.5, "production priority depth supply"),
    ]
    return _day(
        "production_priority_depth_day",
        "Production priority depth day",
        "Production priority depth · mut · order · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "🏭",
        ["production", "priority", "depth"],
        {"mutation": mut, "order": order, "prod_score": score},
    )


def stockpile_surge_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation(weather=_wx(), base_output=1.1)
    order = production_order_resolve(weather=_wx(), base_output=1.1)
    loop = oob_factory_risk_loop(weather=_wx(), base_output=1.1)
    score = _norm(
        0.4 * float(mut.get("score", 0.55))
        + 0.3 * float(order.get("score", 0.55))
        + 0.3 * float(loop.get("effective_output", 0.7))
    )
    q = [
        _q("apply_production", province_id, score, "stockpile surge production"),
        _q("apply_supply", province_id, 0.55, "stockpile surge supply"),
        _q("apply_station", province_id, 0.4, "stockpile surge station"),
    ]
    return _day(
        "stockpile_surge_ops_day",
        "Stockpile surge ops day",
        "Stockpile surge ops · mut · order · oob · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "📦",
        ["production", "stockpile", "surge"],
        {"mutation": mut, "order": order, "loop": loop, "prod_score": score},
    )


def line_continuity_depth_day(province_id: int = 1) -> Dict[str, Any]:
    order = production_order_resolve(weather=_wx(), line_id="primary")
    loop = oob_factory_risk_loop(weather=_wx())
    pcr = production_campaign_risk(weather=_wx())
    score = _norm(
        0.4 * float(order.get("score", 0.55))
        + 0.35 * float(loop.get("effective_output", 0.7))
        + 0.25 * (1.0 - float(pcr.get("risk", pcr.get("score", 0.3))))
    )
    q = [
        _q("apply_production", province_id, score, "line continuity depth production"),
        _q("apply_supply", province_id, 0.55, "line continuity depth supply"),
    ]
    return _day(
        "line_continuity_depth_day",
        "Line continuity depth day",
        "Line continuity depth · order · oob · risk · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "∞",
        ["production", "line", "continuity"],
        {"order": order, "loop": loop, "risk": pcr, "prod_score": score},
    )


def industry_surge_joint_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation(weather=_wx())
    risk = factory_risk_compose(_wx())
    loop = oob_factory_risk_loop(weather=_wx())
    pcr = production_campaign_risk(weather=_wx())
    score = _norm(
        0.3 * float(mut.get("score", 0.55))
        + 0.25 * (1.0 - float(risk.get("risk", 0.25)))
        + 0.25 * float(loop.get("effective_output", 0.7))
        + 0.2 * (1.0 - float(pcr.get("risk", 0.3)))
    )
    q = [
        _q("apply_production", province_id, score, "industry surge joint production"),
        _q("apply_supply", province_id, 0.55, "industry surge joint supply"),
        _q("apply_station", province_id, 0.45, "industry surge joint station"),
        _q("apply_focus", province_id, 0.4, "industry surge joint focus"),
    ]
    return _day(
        "industry_surge_joint_day",
        "Industry surge joint day",
        "Industry surge joint · mut · risk · oob · score %.2f" % score,
        score,
        q,
        "#f87171",
        "◈",
        ["production", "industry", "surge", "joint"],
        {
            "mutation": mut,
            "risk": risk,
            "loop": loop,
            "campaign_risk": pcr,
            "prod_score": score,
        },
    )


def production_oob_depth_day(province_id: int = 1) -> Dict[str, Any]:
    loop = oob_factory_risk_loop(weather=_wx())
    mut = production_priority_mutation(weather=_wx())
    order = production_order_resolve(weather=_wx())
    score = _norm(
        0.4 * float(loop.get("effective_output", 0.7))
        + 0.3 * float(mut.get("score", 0.55))
        + 0.3 * float(order.get("score", 0.55))
    )
    q = [
        _q("apply_production", province_id, score, "production oob depth production"),
        _q("apply_supply", province_id, 0.55, "production oob depth supply"),
        _q("apply_station", province_id, 0.45, "production oob depth station"),
    ]
    return _day(
        "production_oob_depth_day",
        "Production OOB depth day",
        "Production OOB depth · loop · mut · order · score %.2f" % score,
        score,
        q,
        "#fbbf24",
        "◎",
        ["production", "oob", "depth"],
        {"loop": loop, "mutation": mut, "order": order, "prod_score": score},
    )


def production_surge_close_day(province_id: int = 1) -> Dict[str, Any]:
    mut = production_priority_mutation(weather=_wx())
    loop = oob_factory_risk_loop(weather=_wx())
    risk = factory_risk_compose(_wx())
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.25 * float(mut.get("score", 0.55))
        + 0.25 * float(loop.get("effective_output", 0.7))
        + 0.25 * (1.0 - float(risk.get("risk", 0.25)))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_production", province_id, score, "production surge close production"),
        _q("apply_supply", province_id, 0.55, "production surge close supply"),
        _q("apply_station", province_id, 0.45, "production surge close station"),
    ]
    return _day(
        "production_surge_close_day",
        "Production surge close day",
        "Production surge close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#fbbf24",
        "✓",
        ["production", "surge", "close"],
        {
            "mutation": mut,
            "loop": loop,
            "risk": risk,
            "gate": gate,
            "ok": ok,
            "prod_score": score,
        },
    )


# C) Combat multi-phase product surface


def multi_phase_estimate_depth_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    ui = multi_phase_combat_ui_product(
        attacker_power=100.0, defender_power=80.0, attacker_supply=0.85, weather=_wx(), province_id=province_id
    )
    overall = float(est.get("overall_attacker_win_chance", 0.45))
    score = _norm(0.55 * overall + 0.45 * float(ui.get("score", overall)))
    q = [
        _q("apply_assault", province_id, score, "multi phase estimate depth assault"),
        _q("apply_supply", province_id, 0.5, "multi phase estimate depth supply"),
    ]
    return _day(
        "multi_phase_estimate_depth_day",
        "Multi phase estimate depth day",
        "Multi-phase estimate depth · overall %.0f%% · score %.2f" % (overall * 100.0, score),
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["combat", "multi_phase", "estimate"],
        {"estimate": est, "ui": ui, "combat_score": score, "overall": overall},
    )


def assault_ready_surface_day(province_id: int = 1) -> Dict[str, Any]:
    ready = assault_readiness_compose(
        _targets(province_id), attacker_power=100.0, attacker_supply=0.85, weather=_wx()
    )
    est = estimate_multi_phase_combat(100.0, 70.0, attacker_supply=0.85, weather_mult=0.9)
    overall = float(est.get("overall_attacker_win_chance", 0.45))
    ranked = ready.get("ranked") or {}
    best = ranked.get("best") if isinstance(ranked, dict) else None
    win = float((best or {}).get("overall", overall)) if isinstance(best, dict) else overall
    score = _norm(0.55 * win + 0.45 * overall)
    q = [
        _q("apply_assault", province_id, score, "assault ready surface primary"),
        _q("apply_supply", province_id, 0.55, "assault ready surface supply"),
        _q("apply_station", province_id, 0.45, "assault ready surface station"),
    ]
    return _day(
        "assault_ready_surface_day",
        "Assault ready surface day",
        "Assault ready surface · win %.0f%% · score %.2f" % (win * 100.0, score),
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["combat", "assault", "ready"],
        {"readiness": ready, "estimate": est, "combat_score": score},
    )


def combat_order_surface_day(province_id: int = 1) -> Dict[str, Any]:
    order = combat_order_execute(
        targets=_targets(province_id),
        attacker_power=100.0,
        attacker_supply=0.85,
        weather=_wx(),
        month=6,
        province_id=province_id,
    )
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    score = _norm(
        0.55 * float(order.get("score", 0.5))
        + 0.45 * float(est.get("overall_attacker_win_chance", 0.45))
    )
    q = [
        _q("apply_assault", province_id, score, "combat order surface assault"),
        _q("apply_supply", province_id, 0.5, "combat order surface supply"),
        _q("apply_focus", province_id, 0.45, "combat order surface focus"),
    ]
    return _day(
        "combat_order_surface_day",
        "Combat order surface day",
        "Combat order surface · step · estimate · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "⚔",
        ["combat", "order", "surface"],
        {"order": order, "estimate": est, "combat_score": score},
    )


def phase_product_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ui = multi_phase_combat_ui_product(
        attacker_power=110.0, defender_power=75.0, attacker_supply=0.9, weather=_wx(), province_id=province_id
    )
    est = estimate_multi_phase_combat(110.0, 75.0, attacker_supply=0.9, weather_mult=0.95)
    score = _norm(
        0.55 * float(ui.get("score", 0.45))
        + 0.45 * float(est.get("overall_attacker_win_chance", 0.45))
    )
    q = [
        _q("apply_assault", province_id, score, "phase product ops assault"),
        _q("apply_supply", province_id, 0.5, "phase product ops supply"),
    ]
    return _day(
        "phase_product_ops_day",
        "Phase product ops day",
        "Phase product ops · UI · estimate · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "◆",
        ["combat", "phase", "product"],
        {"ui": ui, "estimate": est, "combat_score": score},
    )


def multi_phase_joint_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    ui = multi_phase_combat_ui_product(
        attacker_power=100.0, defender_power=80.0, attacker_supply=0.85, weather=_wx(), province_id=province_id
    )
    ready = assault_readiness_compose(
        _targets(province_id), attacker_power=100.0, attacker_supply=0.85, weather=_wx()
    )
    order = combat_order_execute(
        targets=_targets(province_id),
        attacker_power=100.0,
        attacker_supply=0.85,
        weather=_wx(),
        province_id=province_id,
    )
    score = _norm(
        0.3 * float(est.get("overall_attacker_win_chance", 0.45))
        + 0.25 * float(ui.get("score", 0.45))
        + 0.25 * float(order.get("score", 0.5))
        + 0.2 * float((ready.get("ranked") or {}).get("best", {}).get("overall", 0.4)
                      if isinstance(ready.get("ranked"), dict)
                      else 0.4)
    )
    q = [
        _q("apply_assault", province_id, score, "multi phase joint assault"),
        _q("apply_supply", province_id, 0.55, "multi phase joint supply"),
        _q("apply_station", province_id, 0.45, "multi phase joint station"),
        _q("apply_focus", province_id, 0.4, "multi phase joint focus"),
    ]
    return _day(
        "multi_phase_joint_day",
        "Multi phase joint day",
        "Multi-phase joint · estimate · UI · ready · order · score %.2f" % score,
        score,
        q,
        "#ff9a6e",
        "◈",
        ["combat", "multi_phase", "joint"],
        {
            "estimate": est,
            "ui": ui,
            "readiness": ready,
            "order": order,
            "combat_score": score,
        },
    )


def save_prod_combat_close_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    mut = production_priority_mutation(weather=_wx())
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(pkg.get("score", 0.55))
        + 0.25 * float(mut.get("score", 0.55))
        + 0.25 * float(est.get("overall_attacker_win_chance", 0.45))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, float(pkg.get("score", 0.55)), "close save refresh"),
        _q("apply_production", province_id, float(mut.get("score", 0.55)), "close production"),
        _q("apply_assault", province_id, float(est.get("overall_attacker_win_chance", 0.45)), "close combat assault"),
        _q("apply_supply", province_id, 0.45, "close supply"),
    ]
    return _day(
        "save_prod_combat_close_day",
        "Save prod combat close day",
        "Save prod combat close · save · prod · combat · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["save", "production", "combat", "close"],
        {
            "package": pkg,
            "mutation": mut,
            "estimate": est,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "save_score": float(pkg.get("score", 0.55)),
            "prod_score": float(mut.get("score", 0.55)),
            "combat_score": float(est.get("overall_attacker_win_chance", 0.45)),
        },
    )


SAVE_PROD_COMBAT_DAY_IDS: List[str] = [
    "save_slot_depth_day",
    "autosave_session_depth_day",
    "campaign_session_depth_day",
    "save_resume_depth_day",
    "session_checkpoint_depth_day",
    "save_audit_depth_day",
    "save_session_close_depth_day",
    "factory_risk_surge_day",
    "production_priority_depth_day",
    "stockpile_surge_ops_day",
    "line_continuity_depth_day",
    "industry_surge_joint_day",
    "production_oob_depth_day",
    "production_surge_close_day",
    "multi_phase_estimate_depth_day",
    "assault_ready_surface_day",
    "combat_order_surface_day",
    "phase_product_ops_day",
    "multi_phase_joint_day",
    "save_prod_combat_close_day",
]

DAY_FUNCS = [
    save_slot_depth_day,
    autosave_session_depth_day,
    campaign_session_depth_day,
    save_resume_depth_day,
    session_checkpoint_depth_day,
    save_audit_depth_day,
    save_session_close_depth_day,
    factory_risk_surge_day,
    production_priority_depth_day,
    stockpile_surge_ops_day,
    line_continuity_depth_day,
    industry_surge_joint_day,
    production_oob_depth_day,
    production_surge_close_day,
    multi_phase_estimate_depth_day,
    assault_ready_surface_day,
    combat_order_surface_day,
    phase_product_ops_day,
    multi_phase_joint_day,
    save_prod_combat_close_day,
]


def save_prod_combat_integrity() -> Dict[str, Any]:
    pkg = save_slot_browser_package(_slots())
    mut = production_priority_mutation(weather=_wx())
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    gate = execution_integrity_gate()
    ok = (
        float(pkg.get("score", 0)) > 0.0
        and float(mut.get("score", 0)) > 0.0
        and float(est.get("overall_attacker_win_chance", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "save_score": float(pkg.get("score", 0)),
        "prod_score": float(mut.get("score", 0)),
        "combat_score": float(est.get("overall_attacker_win_chance", 0)),
        "gate": gate,
        "summary": "Save-prod-combat integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next260_save_prod_combat_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = save_prod_combat_integrity()
    label = "Close next260 save-prod-combat · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if gate.get("ok") and non_empty >= 20 else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next260 save-prod-combat[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
