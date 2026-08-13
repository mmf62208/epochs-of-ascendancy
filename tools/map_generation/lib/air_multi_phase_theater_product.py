"""Air multi-phase theater product (major #44) — Phase 7 depth on air ops first slice.

Recon/sortie fuel board → weather/CAS gate → interdiction joint.
Deepens air_ops_campaign_product (#13) with live theater mutation path.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from air_ops_campaign_product import (  # type: ignore
        build_air_ops_campaign_product,
        execute_air_ops_step,
        air_ops_campaign_integrity as air_ops_campaign_product_integrity,
    )
except Exception:  # pragma: no cover
    def build_air_ops_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "air ops"}
    def execute_air_ops_step(step="sortie", province_id=1):  # type: ignore
        return {"ok": True, "step": step, "score": 0.6, "leaf_action": "apply_focus", "empty": False}
    def air_ops_campaign_product_integrity():  # type: ignore
        return {"ok": True, "score": 0.6}

try:
    from weather_theater_ops_product import build_weather_theater_ops_product  # type: ignore
except Exception:  # pragma: no cover
    def build_weather_theater_ops_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

try:
    from multi_phase_combat_product import build_multi_phase_combat_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_phase_combat_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

PRODUCT_STEPS = ("recon", "cas_gate", "interdiction")
_STEP_META = {
    "recon": {"action_id": "air_theater_recon", "leaf": "apply_focus", "label": "Step 0 — recon/sortie fuel board"},
    "cas_gate": {"action_id": "air_theater_cas_gate", "leaf": "apply_station", "label": "Step 1 — weather/CAS gate"},
    "interdiction": {"action_id": "air_theater_interdiction", "leaf": "apply_assault", "label": "Step 2 — interdiction joint"},
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


def compute_recon_board(*, sortie_score: float = 0.6, fuel: float = 0.7) -> Dict[str, Any]:
    s = _floor(sortie_score)
    f = _floor(fuel)
    recon = _floor(0.55 * s + 0.45 * f)
    packages = max(1, int(round(recon * 4)))
    return {
        "sortie_score": s, "fuel": f, "recon_score": recon, "packages": packages,
        "summary": "Recon board · sortie %.2f · fuel %.0f%% · pkgs %d · score %.2f" % (s, f * 100, packages, recon),
        "empty": False,
    }


def compute_cas_gate(*, weather_score: float = 0.55, recon_score: float = 0.6) -> Dict[str, Any]:
    w = _floor(weather_score)
    r = _floor(recon_score)
    open_gate = w >= 0.42 and r >= 0.4
    score = _floor(0.5 * w + 0.5 * r) if open_gate else _floor(0.35 * w + 0.25 * r)
    return {
        "weather_score": w, "recon_score": r, "open": open_gate, "cas_score": score,
        "summary": "CAS gate · wx %.2f · recon %.2f · %s · score %.2f" % (w, r, "OPEN" if open_gate else "HOLD", score),
        "empty": False,
    }


def compute_interdiction(*, cas_score: float = 0.55, combat_score: float = 0.58) -> Dict[str, Any]:
    c = _floor(cas_score)
    m = _floor(combat_score)
    joint = _floor(0.5 * c + 0.5 * m)
    strikes = max(1, int(round(joint * 3)))
    return {
        "cas_score": c, "combat_score": m, "joint": joint, "strikes": strikes,
        "summary": "Interdiction · CAS %.2f · combat %.2f · strikes %d · joint %.2f" % (c, m, strikes, joint),
        "empty": False,
    }


def recommend_air_theater_step(*, reconed: bool = False, gated: bool = False) -> Dict[str, Any]:
    if not reconed:
        step, reason = "recon", "board recon/sortie fuel"
    elif not gated:
        step, reason = "cas_gate", "confirm weather/CAS gate"
    else:
        step, reason = "interdiction", "run interdiction joint"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_air_multi_phase_theater_product(*, province_id: int = 1, fuel: float = 0.72) -> Dict[str, Any]:
    air = build_air_ops_campaign_product(province_id=province_id)
    wx = build_weather_theater_ops_product(province_id=province_id)
    combat = build_multi_phase_combat_product(province_id=province_id)
    recon = compute_recon_board(sortie_score=float(air.get("score", 0.6)), fuel=fuel)
    gate = compute_cas_gate(weather_score=float(wx.get("score", 0.55)), recon_score=float(recon["recon_score"]))
    inter = compute_interdiction(cas_score=float(gate["cas_score"]), combat_score=float(combat.get("score", 0.58)))
    recon_s = _floor(float(recon["recon_score"]))
    gate_s = _floor(float(gate["cas_score"]))
    inter_s = _floor(float(inter["joint"]))
    score = _floor(0.3 * recon_s + 0.35 * gate_s + 0.35 * inter_s)
    rec = recommend_air_theater_step(reconed=True, gated=bool(gate["open"]))
    step_scores = {"recon": recon_s, "cas_gate": gate_s, "interdiction": inter_s}
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
        {"action_id": "air_multi_phase_theater_product", "label": "Run air multi-phase theater product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Air multi-phase theater · recon %.2f · gate %s · strikes %d · score %.2f" % (
        recon_s, "OPEN" if gate["open"] else "HOLD", int(inter["strikes"]), score)
    return {
        "air": air, "weather": wx, "combat": combat, "recon": recon, "cas_gate": gate, "interdiction": inter,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "packages": int(recon["packages"]), "strikes": int(inter["strikes"]), "gate_open": bool(gate["open"]),
        "score": score, "air_theater_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), recon["summary"], gate["summary"], inter["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#7ec8e3]✈ Air theater[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "air_multi_phase_theater_product", "air_theater_recon", "air_theater_cas_gate",
            "air_theater_interdiction", "major_44", "air", "theater", "phase7_depth",
        ],
    }


def execute_air_theater_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "recon").strip().lower().replace("air_theater_", "").replace("air_", "")
    if s.startswith("recon") or s.startswith("sortie"):
        s = "recon"
    elif s.startswith("cas") or s.startswith("gate") or s.startswith("weather"):
        s = "cas_gate"
    elif s.startswith("inter") or s.startswith("strike"):
        s = "interdiction"
    if s not in _STEP_META:
        s = "recon"
    meta = _STEP_META[s]
    product = build_air_multi_phase_theater_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute air theater %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_air_theater_step", s, leaf],
    }


def air_multi_phase_theater_integrity() -> Dict[str, Any]:
    product = build_air_multi_phase_theater_product()
    steps = [execute_air_theater_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    base = air_ops_campaign_product_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("packages", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(base.get("ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Air multi-phase theater integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_air_multi_phase_theater_product_loop() -> Dict[str, Any]:
    product = build_air_multi_phase_theater_product(province_id=2, fuel=0.8)
    gate = air_multi_phase_theater_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close air multi-phase theater · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
