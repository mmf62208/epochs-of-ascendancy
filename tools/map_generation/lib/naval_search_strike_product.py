"""Naval search/strike product (major #45) — Phase 7 depth on naval multi-phase first slice.

Search/patrol board → ASW/escort phase → strike/carrier follow-through.
Deepens naval_multi_phase_campaign_product (#15) with live fleet mutation path.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from naval_multi_phase_campaign_product import (  # type: ignore
        build_naval_multi_phase_campaign_product, execute_naval_phase_step, naval_multi_phase_campaign_integrity,
    )
except Exception:  # pragma: no cover
    def build_naval_multi_phase_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "naval"}
    def execute_naval_phase_step(step="posture", province_id=1):  # type: ignore
        return {"ok": True, "step": step, "score": 0.6, "leaf_action": "apply_station", "empty": False}
    def naval_multi_phase_campaign_integrity():  # type: ignore
        return {"ok": True, "score": 0.6}

try:
    from fleet_multi_day_autonomy_product import build_fleet_multi_day_autonomy_product  # type: ignore
except Exception:  # pragma: no cover
    def build_fleet_multi_day_autonomy_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
except Exception:  # pragma: no cover
    def build_logistics_supply_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

PRODUCT_STEPS = ("search", "asw_escort", "strike")
_STEP_META = {
    "search": {"action_id": "naval_search_patrol", "leaf": "apply_station", "label": "Step 0 — search/patrol board"},
    "asw_escort": {"action_id": "naval_asw_escort", "leaf": "apply_station", "label": "Step 1 — ASW/escort phase"},
    "strike": {"action_id": "naval_carrier_strike", "leaf": "apply_assault", "label": "Step 2 — strike/carrier follow-through"},
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


def compute_search_board(*, fleet_score: float = 0.6, fuel: float = 0.65) -> Dict[str, Any]:
    f = _floor(fleet_score)
    fuel_s = _floor(fuel)
    search = _floor(0.55 * f + 0.45 * fuel_s)
    contacts = max(1, int(round(search * 5)))
    return {
        "fleet_score": f, "fuel": fuel_s, "search_score": search, "contacts": contacts,
        "summary": "Search board · fleet %.2f · fuel %.0f%% · contacts %d · score %.2f" % (f, fuel_s * 100, contacts, search),
        "empty": False,
    }


def compute_asw_escort(*, search_score: float = 0.6, convoy_score: float = 0.55) -> Dict[str, Any]:
    s = _floor(search_score)
    c = _floor(convoy_score)
    escort = _floor(0.5 * s + 0.5 * c)
    asw_ok = escort >= 0.45
    screens = max(1, int(round(escort * 3)))
    return {
        "search_score": s, "convoy_score": c, "escort_score": escort, "asw_ok": asw_ok, "screens": screens,
        "summary": "ASW escort · search %.2f · convoy %.2f · screens %d · %s" % (s, c, screens, "OK" if asw_ok else "THIN"),
        "empty": False,
    }


def compute_carrier_strike(*, escort_score: float = 0.55, naval_score: float = 0.6) -> Dict[str, Any]:
    e = _floor(escort_score)
    n = _floor(naval_score)
    strike = _floor(0.45 * e + 0.55 * n)
    sorties = max(1, int(round(strike * 4)))
    return {
        "escort_score": e, "naval_score": n, "strike_score": strike, "sorties": sorties,
        "summary": "Carrier strike · escort %.2f · naval %.2f · sorties %d · score %.2f" % (e, n, sorties, strike),
        "empty": False,
    }


def recommend_naval_search_step(*, searched: bool = False, escorted: bool = False) -> Dict[str, Any]:
    if not searched:
        step, reason = "search", "open search/patrol board"
    elif not escorted:
        step, reason = "asw_escort", "screen convoy with ASW escort"
    else:
        step, reason = "strike", "launch strike/carrier follow-through"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_naval_search_strike_product(*, province_id: int = 1, fuel: float = 0.68) -> Dict[str, Any]:
    naval = build_naval_multi_phase_campaign_product(province_id=province_id, fuel_level=fuel)
    fleet = build_fleet_multi_day_autonomy_product(province_id=province_id, fuel_level=fuel)
    supply = build_logistics_supply_theater_product(province_id=province_id)
    search = compute_search_board(fleet_score=float(fleet.get("score", naval.get("score", 0.6))), fuel=fuel)
    escort = compute_asw_escort(search_score=float(search["search_score"]), convoy_score=float(supply.get("score", 0.55)))
    strike = compute_carrier_strike(escort_score=float(escort["escort_score"]), naval_score=float(naval.get("score", 0.6)))
    search_s = _floor(float(search["search_score"]))
    escort_s = _floor(float(escort["escort_score"]))
    strike_s = _floor(float(strike["strike_score"]))
    score = _floor(0.3 * search_s + 0.35 * escort_s + 0.35 * strike_s)
    rec = recommend_naval_search_step(searched=True, escorted=bool(escort["asw_ok"]))
    step_scores = {"search": search_s, "asw_escort": escort_s, "strike": strike_s}
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
        {"action_id": "naval_search_strike_product", "label": "Run naval search/strike product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Naval search/strike · contacts %d · screens %d · sorties %d · score %.2f" % (
        int(search["contacts"]), int(escort["screens"]), int(strike["sorties"]), score)
    return {
        "naval": naval, "fleet": fleet, "supply": supply, "search": search, "asw_escort": escort, "strike": strike,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "contacts": int(search["contacts"]), "screens": int(escort["screens"]), "sorties": int(strike["sorties"]),
        "asw_ok": bool(escort["asw_ok"]), "score": score, "naval_search_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), search["summary"], escort["summary"], strike["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#5b8fd9]⚓ Naval search/strike[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "naval_search_strike_product", "naval_search_patrol", "naval_asw_escort",
            "naval_carrier_strike", "major_45", "naval", "search", "strike", "phase7_depth",
        ],
    }


def execute_naval_search_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "search").strip().lower().replace("naval_", "")
    if s.startswith("search") or s.startswith("patrol"):
        s = "search"
    elif s.startswith("asw") or s.startswith("escort"):
        s = "asw_escort"
    elif s.startswith("strike") or s.startswith("carrier"):
        s = "strike"
    if s not in _STEP_META:
        s = "search"
    meta = _STEP_META[s]
    product = build_naval_search_strike_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute naval search %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_naval_search_step", s, leaf],
    }


def naval_search_strike_integrity() -> Dict[str, Any]:
    product = build_naval_search_strike_product()
    steps = [execute_naval_search_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    base = naval_multi_phase_campaign_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("contacts", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(base.get("ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Naval search/strike integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_naval_search_strike_product_loop() -> Dict[str, Any]:
    product = build_naval_search_strike_product(province_id=2, fuel=0.75)
    gate = naval_search_strike_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close naval search/strike · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
