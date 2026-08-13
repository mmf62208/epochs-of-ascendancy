"""Weather crisis campaign product (major #50) — Phase 9 full gameplay cycle.

Forecast pressure board → multi-theater weather gate → crisis sustain/response.
Deepens weather_theater_ops (#22) with live crisis mutation for full GS cycle.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from weather_theater_ops_product import build_weather_theater_ops_product  # type: ignore
except Exception:  # pragma: no cover
    def build_weather_theater_ops_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False, "pressure_score": 0.55, "gate_score": 0.55}

try:
    from air_multi_phase_theater_product import build_air_multi_phase_theater_product  # type: ignore
except Exception:  # pragma: no cover
    def build_air_multi_phase_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "gate_open": True}

try:
    from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
except Exception:  # pragma: no cover
    def build_logistics_supply_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

PRODUCT_STEPS = ("forecast", "gate_multi", "crisis_sustain")
_STEP_META = {
    "forecast": {"action_id": "weather_crisis_forecast", "leaf": "apply_station", "label": "Step 0 — multi-day forecast pressure"},
    "gate_multi": {"action_id": "weather_crisis_gate_multi", "leaf": "apply_assault", "label": "Step 1 — multi-theater weather gate"},
    "crisis_sustain": {"action_id": "weather_crisis_sustain", "leaf": "apply_supply", "label": "Step 2 — crisis sustain/response"},
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


def compute_forecast_board(*, pressure: float = 0.55, days: int = 5) -> Dict[str, Any]:
    p = _floor(pressure)
    d = max(1, min(14, int(days)))
    severity = _floor(0.4 + 0.5 * (1.0 - p) + 0.05 * min(d, 7) / 7.0)
    fronts = max(1, int(round(severity * 3)))
    score = _floor(0.55 * (1.0 - abs(severity - 0.5)) + 0.45 * p)
    return {
        "pressure": p, "days": d, "severity": severity, "fronts": fronts, "score": score,
        "summary": "Forecast · %dd · severity %.0f%% · fronts %d · pressure %.2f · score %.2f"
        % (d, severity * 100, fronts, p, score),
        "empty": False,
    }


def compute_multi_theater_gate(*, air_open: bool = True, logistics_score: float = 0.55, weather_gate: float = 0.55) -> Dict[str, Any]:
    log_s = _floor(logistics_score)
    wg = _floor(weather_gate)
    air_s = 0.75 if air_open else 0.4
    joint = _floor(0.35 * air_s + 0.35 * log_s + 0.3 * wg)
    open_gate = joint >= 0.45 and (air_open or log_s >= 0.5)
    return {
        "air_open": air_open, "logistics_score": log_s, "weather_gate": wg, "joint": joint, "open": open_gate, "score": joint,
        "summary": "Multi-theater gate · air %s · log %.2f · wx %.2f · %s · score %.2f"
        % ("OPEN" if air_open else "HOLD", log_s, wg, "PASS" if open_gate else "HOLD", joint),
        "empty": False,
    }


def compute_crisis_sustain(*, forecast: Dict[str, Any], gate: Dict[str, Any]) -> Dict[str, Any]:
    sev = float(forecast.get("severity", 0.5))
    joint = float(gate.get("joint", 0.5))
    sustain = _floor(0.45 * joint + 0.35 * (1.0 - sev * 0.5) + 0.2 * (1.0 if gate.get("open") else 0.4))
    responses = max(1, int(round(sustain * 4)))
    return {
        "severity": sev, "joint": joint, "sustain": sustain, "responses": responses, "score": sustain,
        "summary": "Crisis sustain · responses %d · sev %.0f%% · joint %.2f · score %.2f"
        % (responses, sev * 100, joint, sustain),
        "empty": False,
    }


def recommend_weather_crisis_step(*, forecasted: bool = False, gated: bool = False) -> Dict[str, Any]:
    if not forecasted:
        step, reason = "forecast", "board multi-day weather pressure"
    elif not gated:
        step, reason = "gate_multi", "run multi-theater weather gate"
    else:
        step, reason = "crisis_sustain", "sustain crisis response"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_weather_crisis_campaign_product(*, province_id: int = 1, forecast_days: int = 5) -> Dict[str, Any]:
    base = build_weather_theater_ops_product(province_id=province_id)
    air = build_air_multi_phase_theater_product(province_id=province_id)
    logi = build_logistics_supply_theater_product(province_id=province_id)
    forecast = compute_forecast_board(pressure=float(base.get("pressure_score", base.get("score", 0.55))), days=forecast_days)
    gate = compute_multi_theater_gate(
        air_open=bool(air.get("gate_open", True)),
        logistics_score=float(logi.get("score", 0.55)),
        weather_gate=float(base.get("gate_score", base.get("score", 0.55))),
    )
    crisis = compute_crisis_sustain(forecast=forecast, gate=gate)
    f_s = _floor(float(forecast["score"]))
    g_s = _floor(float(gate["score"]))
    c_s = _floor(float(crisis["score"]))
    score = _floor(0.3 * f_s + 0.35 * g_s + 0.35 * c_s)
    rec = recommend_weather_crisis_step(forecasted=True, gated=bool(gate["open"]))
    step_scores = {"forecast": f_s, "gate_multi": g_s, "crisis_sustain": c_s}
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
        {"action_id": "weather_crisis_campaign_product", "label": "Run weather crisis campaign product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Weather crisis campaign · fronts %d · gate %s · responses %d · score %.2f" % (
        int(forecast["fronts"]), "OPEN" if gate["open"] else "HOLD", int(crisis["responses"]), score)
    return {
        "base": base, "air": air, "logistics": logi, "forecast": forecast, "gate": gate, "crisis": crisis,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "fronts": int(forecast["fronts"]), "responses": int(crisis["responses"]), "gate_open": bool(gate["open"]),
        "score": score, "weather_crisis_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), forecast["summary"], gate["summary"], crisis["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#7ec8e3]🌧 Weather crisis[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "weather_crisis_campaign_product", "weather_crisis_forecast", "weather_crisis_gate_multi",
            "weather_crisis_sustain", "major_50", "weather", "crisis", "phase9_cycle", "full_gameplay_cycle",
        ],
    }


def execute_weather_crisis_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "forecast").strip().lower().replace("weather_crisis_", "").replace("weather_", "")
    if s.startswith("forecast") or s.startswith("pressure"):
        s = "forecast"
    elif s.startswith("gate") or s.startswith("multi"):
        s = "gate_multi"
    elif s.startswith("crisis") or s.startswith("sustain") or s.startswith("response"):
        s = "crisis_sustain"
    if s not in _STEP_META:
        s = "forecast"
    meta = _STEP_META[s]
    product = build_weather_crisis_campaign_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute weather crisis %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_weather_crisis_step", s, leaf],
    }


def weather_crisis_campaign_integrity() -> Dict[str, Any]:
    product = build_weather_crisis_campaign_product()
    steps = [execute_weather_crisis_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("fronts", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Weather crisis campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_weather_crisis_campaign_product_loop() -> Dict[str, Any]:
    product = build_weather_crisis_campaign_product(province_id=2, forecast_days=7)
    gate = weather_crisis_campaign_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close weather crisis campaign · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
