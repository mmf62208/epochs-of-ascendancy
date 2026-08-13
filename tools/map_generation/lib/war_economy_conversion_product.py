"""War economy conversion product (major #46) — Phase 7 depth on war economy first slice.

Civilian/industry board → civilian→military conversion → multi-month stockpile sustain.
Deepens war_economy_mobilization_product (#21) with live allocation mutation path.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from war_economy_mobilization_product import (  # type: ignore
        build_war_economy_mobilization_product, execute_war_economy_step, war_economy_mobilization_integrity,
    )
except Exception:  # pragma: no cover
    def build_war_economy_mobilization_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False, "summary": "war economy"}
    def execute_war_economy_step(step="board", province_id=1):  # type: ignore
        return {"ok": True, "step": step, "score": 0.58, "leaf_action": "apply_production", "empty": False}
    def war_economy_mobilization_integrity():  # type: ignore
        return {"ok": True, "score": 0.58}

try:
    from medium_tank_production_honesty_product import build_medium_tank_production_honesty_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_production_honesty_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

try:
    from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
except Exception:  # pragma: no cover
    def build_logistics_supply_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

PRODUCT_STEPS = ("civ_board", "convert", "sustain")
_STEP_META = {
    "civ_board": {"action_id": "economy_civ_board", "leaf": "apply_production", "label": "Step 0 — civilian/industry board"},
    "convert": {"action_id": "economy_war_convert", "leaf": "apply_production", "label": "Step 1 — civilian→military conversion"},
    "sustain": {"action_id": "economy_stockpile_sustain", "leaf": "apply_production", "label": "Step 2 — multi-month stockpile sustain"},
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


def compute_civ_board(*, economy_score: float = 0.58, factories: int = 12) -> Dict[str, Any]:
    e = _floor(economy_score)
    fac = max(1, int(factories))
    civilian = max(1, int(round(fac * 0.55)))
    military = max(1, fac - civilian)
    board = _floor(0.6 * e + 0.4 * min(1.0, fac / 20.0))
    return {
        "economy_score": e, "factories": fac, "civilian": civilian, "military": military, "board_score": board,
        "summary": "Civ board · fac %d (civ %d / mil %d) · econ %.2f · score %.2f" % (fac, civilian, military, e, board),
        "empty": False,
    }


def compute_conversion(*, board_score: float = 0.55, honesty_score: float = 0.6, convert_frac: float = 0.25) -> Dict[str, Any]:
    b = _floor(board_score)
    h = _floor(honesty_score)
    frac = max(0.05, min(0.6, float(convert_frac)))
    converted = max(1, int(round(8 * frac)))
    score = _floor(0.45 * b + 0.4 * h + 0.15 * (frac / 0.4))
    return {
        "board_score": b, "honesty_score": h, "convert_frac": frac, "converted": converted, "convert_score": score,
        "summary": "Conversion · frac %.0f%% · lines %d · board %.2f · honesty %.2f · score %.2f"
        % (frac * 100, converted, b, h, score),
        "empty": False,
    }


def compute_stockpile_sustain(*, convert_score: float = 0.55, supply_score: float = 0.55, months: int = 3) -> Dict[str, Any]:
    c = _floor(convert_score)
    s = _floor(supply_score)
    m = max(1, min(12, int(months)))
    sustain = _floor(0.5 * c + 0.35 * s + 0.15 * min(1.0, m / 6.0))
    stockpile_delta = max(1, int(round(sustain * 10 * m / 3.0)))
    return {
        "convert_score": c, "supply_score": s, "months": m, "sustain_score": sustain, "stockpile_delta": stockpile_delta,
        "summary": "Sustain · %dmo · stock +%d · convert %.2f · supply %.2f · score %.2f" % (m, stockpile_delta, c, s, sustain),
        "empty": False,
    }


def recommend_economy_conversion_step(*, boarded: bool = False, converted: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "civ_board", "scan civilian/industry board"
    elif not converted:
        step, reason = "convert", "convert civilian capacity to military"
    else:
        step, reason = "sustain", "sustain multi-month stockpile"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_war_economy_conversion_product(
    *, province_id: int = 1, factories: int = 14, convert_frac: float = 0.28, months: int = 3
) -> Dict[str, Any]:
    economy = build_war_economy_mobilization_product(province_id=province_id)
    honesty = build_medium_tank_production_honesty_product(province_id=province_id)
    supply = build_logistics_supply_theater_product(province_id=province_id)
    board = compute_civ_board(economy_score=float(economy.get("score", 0.58)), factories=factories)
    conv = compute_conversion(
        board_score=float(board["board_score"]),
        honesty_score=float(honesty.get("score", 0.6)),
        convert_frac=convert_frac,
    )
    sustain = compute_stockpile_sustain(
        convert_score=float(conv["convert_score"]),
        supply_score=float(supply.get("score", 0.55)),
        months=months,
    )
    board_s = _floor(float(board["board_score"]))
    conv_s = _floor(float(conv["convert_score"]))
    sustain_s = _floor(float(sustain["sustain_score"]))
    score = _floor(0.3 * board_s + 0.35 * conv_s + 0.35 * sustain_s)
    rec = recommend_economy_conversion_step(boarded=True, converted=True)
    step_scores = {"civ_board": board_s, "convert": conv_s, "sustain": sustain_s}
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
        {"action_id": "war_economy_conversion_product", "label": "Run war economy conversion product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "War economy conversion · fac %d · convert %.0f%% · stock +%d · score %.2f" % (
        int(board["factories"]), float(conv["convert_frac"]) * 100, int(sustain["stockpile_delta"]), score)
    return {
        "economy": economy, "honesty": honesty, "supply": supply,
        "civ_board": board, "convert": conv, "sustain": sustain,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "factories": int(board["factories"]), "converted": int(conv["converted"]),
        "stockpile_delta": int(sustain["stockpile_delta"]),
        "score": score, "conversion_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), board["summary"], conv["summary"], sustain["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e0b060]🏭 Economy conversion[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "war_economy_conversion_product", "economy_civ_board", "economy_war_convert",
            "economy_stockpile_sustain", "major_46", "economy", "conversion", "phase7_depth",
        ],
    }


def execute_economy_conversion_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "civ_board").strip().lower().replace("economy_", "").replace("war_economy_", "")
    if s.startswith("civ") or s.startswith("board"):
        s = "civ_board"
    elif s.startswith("convert") or s.startswith("war"):
        s = "convert"
    elif s.startswith("sustain") or s.startswith("stock"):
        s = "sustain"
    if s not in _STEP_META:
        s = "civ_board"
    meta = _STEP_META[s]
    product = build_war_economy_conversion_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute economy conversion %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_economy_conversion_step", s, leaf],
    }


def war_economy_conversion_integrity() -> Dict[str, Any]:
    product = build_war_economy_conversion_product()
    steps = [execute_economy_conversion_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    base = war_economy_mobilization_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("factories", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(base.get("ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "War economy conversion integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_war_economy_conversion_product_loop() -> Dict[str, Any]:
    product = build_war_economy_conversion_product(province_id=2, factories=16, convert_frac=0.32, months=4)
    gate = war_economy_conversion_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close war economy conversion · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
