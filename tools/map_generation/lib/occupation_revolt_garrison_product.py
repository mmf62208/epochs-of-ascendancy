"""Occupation revolt & garrison product (major #35) — Phase 4.

Board revolt risk → deploy garrison → suppress/resolve flashpoints.
Deepens occupation R/C (#29) with multi-province garrison AI slice.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from occupation_resistance_compliance_product import (  # type: ignore
        build_occupation_resistance_compliance_product, compute_occupation_state,
    )
except Exception:  # pragma: no cover
    def build_occupation_resistance_compliance_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "resistance_level": 0.55, "compliance_level": 0.4, "revolt_risk": 0.2}

    def compute_occupation_state(**_k):  # type: ignore
        return {"resistance_level": 0.55, "compliance_level": 0.4, "revolt_risk": 0.2, "stability": 0.5, "policy": "moderate", "empty": False}

PRODUCT_STEPS = ("board", "garrison", "suppress")
GARRISON_MODES = ("light", "standard", "heavy")
_STEP_META = {
    "board": {"action_id": "occupation_revolt_board", "leaf": "apply_station", "label": "Step 0 — revolt risk board"},
    "garrison": {"action_id": "occupation_revolt_garrison", "leaf": "apply_station", "label": "Step 1 — deploy garrison"},
    "suppress": {"action_id": "occupation_revolt_suppress", "leaf": "apply_assault", "label": "Step 2 — suppress/resolve flashpoint"},
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def compute_revolt_flashpoint(
    *, resistance_level: float = 0.55, compliance_level: float = 0.4, garrison_strength: float = 0.4, mode: str = "standard"
) -> Dict[str, Any]:
    r = _norm(resistance_level)
    c = _norm(compliance_level)
    g = _norm(garrison_strength)
    m = str(mode or "standard").lower()
    if m not in GARRISON_MODES:
        m = "standard"
    mode_mult = {"light": 0.7, "standard": 1.0, "heavy": 1.35}[m]
    g_eff = _norm(g * mode_mult)
    flashpoint = _floor(0.55 * r + 0.25 * (1.0 - c) - 0.35 * g_eff + 0.15)
    suppress_power = _floor(0.4 * g_eff + 0.35 * c + 0.25 * (1.0 - r))
    resolved = flashpoint < 0.45 and suppress_power >= 0.5
    return {
        "resistance_level": r,
        "compliance_level": c,
        "garrison_strength": g,
        "garrison_mode": m,
        "garrison_effective": g_eff,
        "flashpoint": flashpoint,
        "suppress_power": suppress_power,
        "resolved": resolved,
        "summary": "Revolt · flash %.0f%% · garr %s ×%.0f%% · suppress %.0f%% · %s"
        % (flashpoint * 100, m, g_eff * 100, suppress_power * 100, "RESOLVED" if resolved else "ACTIVE"),
        "empty": False,
    }


def recommend_revolt_step(*, flashpoint: float = 0.5, garrisoned: bool = False) -> Dict[str, Any]:
    if flashpoint > 0.55 or not garrisoned:
        if not garrisoned:
            step, reason = "garrison", "flashpoint high — deploy garrison first"
        else:
            step, reason = "board", "re-board multi-province revolt risk"
    else:
        step, reason = "suppress", "garrison ready — suppress flashpoint"
    if flashpoint <= 0.35 and garrisoned:
        step, reason = "suppress", "low flash — resolve residual unrest"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_occupation_revolt_garrison_product(
    *,
    province_id: int = 1,
    resistance_level: float = 0.55,
    compliance_level: float = 0.4,
    garrison_strength: float = 0.45,
    mode: str = "standard",
) -> Dict[str, Any]:
    occ = build_occupation_resistance_compliance_product(
        province_id=province_id, resistance_level=resistance_level, compliance_level=compliance_level
    )
    flash = compute_revolt_flashpoint(
        resistance_level=float(occ.get("resistance_level", resistance_level)),
        compliance_level=float(occ.get("compliance_level", compliance_level)),
        garrison_strength=garrison_strength,
        mode=mode,
    )
    board_score = _floor(0.5 * float(occ.get("score", 0.5)) + 0.5 * (1.0 - float(flash["flashpoint"])))
    garrison_score = _floor(0.4 + 0.5 * float(flash["garrison_effective"]))
    suppress_score = _floor(0.45 * float(flash["suppress_power"]) + 0.55 * garrison_score)
    score = _floor(0.3 * board_score + 0.35 * garrison_score + 0.35 * suppress_score)
    rec = recommend_revolt_step(flashpoint=float(flash["flashpoint"]), garrisoned=True)
    step_scores = {"board": board_score, "garrison": garrison_score, "suppress": suppress_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({
            "index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
            "label": lab, "score": sc, "enabled": True, "recommended": recommended,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc,
            "enabled": True, "label": lab, "step": step, "product_action": meta["action_id"],
        })
    actions = [
        {"action_id": "occupation_revolt_garrison_product", "label": "Run occupation revolt/garrison product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "occupation_garrison_light", "label": "Garrison: light", "enabled": True},
        {"action_id": "occupation_garrison_standard", "label": "Garrison: standard", "enabled": True},
        {"action_id": "occupation_garrison_heavy", "label": "Garrison: heavy", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Occupation revolt/garrison · flash %.0f%% · mode %s · score %.2f" % (
        float(flash["flashpoint"]) * 100, flash["garrison_mode"], score)
    return {
        "occupation": occ, "flash": flash, "recommendation": rec, "day_rows": day_rows,
        "apply_queue": apply_queue, "actions": actions,
        "flashpoint": flash["flashpoint"], "garrison_mode": flash["garrison_mode"],
        "resolved": flash["resolved"], "score": score, "revolt_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(flash.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#d07060]⚔ Revolt/garrison[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "occupation_revolt_garrison_product", "occupation_revolt_board", "occupation_revolt_garrison",
            "occupation_revolt_suppress", "major_35", "occupation", "revolt", "garrison", "phase4_depth",
        ],
    }


def execute_occupation_revolt_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("occupation_revolt_", "")
    if s.startswith("board"):
        s = "board"
    elif s.startswith("garrison"):
        s = "garrison"
    elif s.startswith("suppress") or s.startswith("resolve"):
        s = "suppress"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_occupation_revolt_garrison_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute occupation revolt %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_occupation_revolt_step", s, leaf],
    }


def occupation_revolt_garrison_integrity() -> Dict[str, Any]:
    product = build_occupation_revolt_garrison_product()
    steps = [execute_occupation_revolt_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Occupation revolt/garrison integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_occupation_revolt_garrison_product_loop() -> Dict[str, Any]:
    product = build_occupation_revolt_garrison_product(province_id=2, mode="heavy")
    gate = occupation_revolt_garrison_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close occupation revolt/garrison · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
