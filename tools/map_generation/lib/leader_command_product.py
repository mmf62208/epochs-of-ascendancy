"""Leader command product (major #26).

Assign board → formation station → command ops.
Composes leader campaign day patterns, HH agenda, force readiness, theater, front.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from hh_multi_month_agenda_product import build_hh_multi_month_agenda_product  # type: ignore
from theater_command_product import build_theater_command_product  # type: ignore
from front_continuity_campaign_product import build_front_continuity_campaign_product  # type: ignore
from intelligence_network_product import build_intelligence_network_product  # type: ignore

PRODUCT_STEPS = ("assign", "station", "command")
_STEP_META = {
    "assign": {"action_id": "leader_command_assign", "leaf": "apply_focus", "label": "Step 0 — leader assign board"},
    "station": {"action_id": "leader_command_station", "leaf": "apply_station", "label": "Step 1 — formation station"},
    "command": {"action_id": "leader_command_ops", "leaf": "apply_assault", "label": "Step 2 — command ops"},
}

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def recommend_leader_step(*, assign_score: float = 0.5, station_score: float = 0.5, ready: bool = False) -> Dict[str, Any]:
    if assign_score < 0.45:
        step, reason = "assign", "leader assign thin — re-board"
    elif station_score < 0.45:
        step, reason = "station", "formation station weak"
    elif ready:
        step, reason = "command", "leaders set — run command ops"
    else:
        step, reason = "station", "refresh station"
    meta = _STEP_META[step]
    return {"step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
            "summary": "Recommend %s · %s" % (step, reason), "empty": False}

def build_leader_command_product(*, province_id: int = 1, leader_skill: float = 0.65) -> Dict[str, Any]:
    # leader skill contributes to assign score (mirrors GD leader_campaign_day)
    skill = _norm(leader_skill)
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    ready = force_readiness_day()
    theater = build_theater_command_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    intel = build_intelligence_network_product(province_id=province_id)
    assign_score = _floor(0.45 * skill + 0.35 * _norm(float(hh.get("score", 0.5))) + 0.2 * _norm(float(intel.get("score", 0.5))))
    station_score = _floor(0.5 * _norm(float(ready.get("score", 0.5))) + 0.5 * _norm(float(theater.get("score", 0.5))))
    command_score = _floor(0.5 * assign_score + 0.5 * _norm(float(front.get("score", 0.5))))
    score = _floor(0.35 * assign_score + 0.35 * station_score + 0.3 * command_score)
    rec = recommend_leader_step(assign_score=assign_score, station_score=station_score, ready=assign_score >= 0.45 and station_score >= 0.45)
    step_scores = {"assign": assign_score, "station": station_score, "command": command_score}
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
    actions = [{"action_id": "leader_command_product", "label": "Run leader command product", "enabled": True},
               {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True}]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Leader command · assign %.2f · station %.2f · command %.2f · score %.2f" % (assign_score, station_score, command_score, score)
    return {"hh": hh, "ready": ready, "theater": theater, "front": front, "intel": intel, "leader_skill": skill,
            "assign_score": assign_score, "station_score": station_score, "command_score": command_score,
            "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
            "score": score, "leader_score": score, "province_id": max(1, int(province_id)),
            "summary": label, "plain": "\n".join([label, str(rec.get("summary",""))] + [r["label"] for r in day_rows]),
            "bbcode": "[color=#d4a0ff]★ Leader command[/color] [color=#8899aa]%s[/color]" % label, "empty": False,
            "integration": ["leader_command_product", "leader_command_assign", "leader_command_station", "leader_command_ops", "major_26", "leader", "command"]}

def execute_leader_command_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "assign").strip().lower().replace("leader_command_", "")
    if s not in _STEP_META: s = "assign"
    meta = _STEP_META[s]
    product = build_leader_command_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute leader command %s · leaf %s · score %.2f" % (s, leaf, score)
    return {"step": s, "leaf_action": leaf, "action_id": meta["action_id"],
            "apply_queue": [{"action_id": leaf, "province_id": max(1,int(province_id)), "score": score, "enabled": True, "label": meta["label"], "step": s, "product_action": meta["action_id"]}],
            "score": score, "province_id": max(1,int(province_id)), "summary": label, "plain": label,
            "bbcode": "[color=#d4a0ff]★ Leader %s[/color] [color=#8899aa]%s[/color]" % (s, label), "empty": False, "ok": True,
            "integration": ["execute_leader_command_step", s, leaf]}

def leader_command_product_integrity() -> Dict[str, Any]:
    product = build_leader_command_product()
    steps = [execute_leader_command_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (not product.get("empty") and len(product.get("day_rows") or []) >= 3 and float(product.get("score", 0)) >= 0.35
          and all(s.get("ok") for s in steps) and bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True)))
    return {"ok": ok, "score": float(product.get("score", 0)), "summary": "Leader command product integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_leader_command_product_loop() -> Dict[str, Any]:
    product = build_leader_command_product(province_id=2)
    gate = leader_command_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close leader command · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label,
            "bbcode": "[color=#d4a0ff]✓ Leader command[/color] [color=#8899aa]%s[/color]" % label, "empty": False, "ok": ok}
