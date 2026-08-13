"""Weather theater ops product (major #22).

Pressure board → combat/logistics weather gate → crisis response.
Composes weather pressure, logistics, combat weather, crisis day, force readiness.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from weather_crisis_day import weather_crisis_day  # type: ignore
from weather_effects import combat_weather_multiplier  # type: ignore
from weather_forecast import forecast_next_day, air_sortie_weather_gate  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore

PRODUCT_STEPS = ("pressure", "gate", "crisis")
_STEP_META = {
    "pressure": {"action_id": "weather_theater_pressure", "leaf": "apply_station", "label": "Step 0 — weather pressure board"},
    "gate": {"action_id": "weather_theater_gate", "leaf": "apply_assault", "label": "Step 1 — combat/logistics weather gate"},
    "crisis": {"action_id": "weather_theater_crisis", "leaf": "apply_supply", "label": "Step 2 — crisis response"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_weather_step(*, pressure_score: float = 0.5, gate_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if pressure_score < 0.45:
        step, reason = "pressure", "weather pressure high/unknown — re-board"
    elif gate_score < 0.45:
        step, reason = "gate", "combat/logistics weather gate failing"
    elif ready:
        step, reason = "crisis", "gates set — run crisis response"
    else:
        step, reason = "gate", "refresh weather gate"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_weather_theater_ops_product(*, province_id: int = 1) -> Dict[str, Any]:
    crisis = weather_crisis_day(province_id=province_id)
    weather = {
        "visibility": 0.7,
        "precip_intensity": 0.4,
        "temp": 10.0,
        "ground_state": "mud",
        "wind": 0.3,
    }
    forecast = forecast_next_day(weather)
    cwm = float(combat_weather_multiplier(weather))
    sortie = air_sortie_weather_gate(weather)
    logistics = build_logistics_supply_theater_product(province_id=province_id)
    ready = force_readiness_day()
    # Higher crisis pressure → lower board score (need action)
    pressure_raw = _norm(float(crisis.get("score", 0.5)))
    pressure_score = _floor(
        0.55 * (1.0 - min(0.7, abs(pressure_raw - 0.5)))
        + 0.45 * _norm(float(forecast.get("combat_mult", forecast.get("score", 0.55))))
    )
    gate_score = _floor(
        0.4 * cwm
        + 0.3 * _norm(float(sortie.get("effectiveness", sortie.get("score", 0.5))))
        + 0.3 * _norm(float(logistics.get("score", 0.5)))
    )
    crisis_score = _floor(0.5 * pressure_score + 0.5 * _norm(float(ready.get("score", 0.5))))
    score = _floor(0.35 * pressure_score + 0.35 * gate_score + 0.3 * crisis_score)
    rec = recommend_weather_step(pressure_score=pressure_score, gate_score=gate_score, ready=pressure_score >= 0.45 and gate_score >= 0.45)
    step_scores = {"pressure": pressure_score, "gate": gate_score, "crisis": crisis_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({"index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
                         "label": lab, "score": sc, "enabled": True, "recommended": recommended, "province_id": max(1, int(province_id))})
        apply_queue.append({"action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc, "enabled": True,
                            "label": lab, "step": step, "product_action": meta["action_id"]})
    actions = [{"action_id": "weather_theater_ops_product", "label": "Run weather theater ops product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Weather theater ops · pressure %.2f · gate %.2f · crisis %.2f · score %.2f" % (pressure_score, gate_score, crisis_score, score)
    return {"crisis": crisis, "forecast": forecast, "sortie": sortie, "logistics": logistics, "ready": ready, "combat_weather_mult": cwm,
            "pressure_score": pressure_score, "gate_score": gate_score, "crisis_score": crisis_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "weather_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#7ec8ff]🌤 Weather theater[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["weather_theater_ops_product", "weather_theater_pressure", "weather_theater_gate", "weather_theater_crisis", "major_22", "weather", "theater"]}

def execute_weather_theater_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "pressure").strip().lower().replace("weather_theater_", "")
    if s not in _STEP_META: s = "pressure"
    meta = _STEP_META[s]
    product = build_weather_theater_ops_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute weather theater %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#7ec8ff]🌤 Weather %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_weather_theater_step", s, leaf]}

def weather_theater_ops_integrity() -> Dict[str, Any]:
    product = build_weather_theater_ops_product()
    steps = [execute_weather_theater_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Weather theater ops integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_weather_theater_ops_product_loop() -> Dict[str, Any]:
    product = build_weather_theater_ops_product(province_id=2)
    gate = weather_theater_ops_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close weather theater ops · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#7ec8ff]✓ Weather theater[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
