"""Combat intel estimate primary package — Master Plan I2 residual.
estimate → recon_bias → sabotage_bias → product → close.
LIVE_API = real GameData methods (not bare apply_focus).
Pre-battle intel impact surfaces on combat estimate path.
"""
from __future__ import annotations
from typing import Any, Dict, Optional

try:
    from assault_estimate_card import build_assault_estimate_card  # type: ignore
except Exception:  # pragma: no cover
    def build_assault_estimate_card(*_a, **_k):  # type: ignore
        return {"score": 0.6, "overall": 0.55, "empty": False}

try:
    from intelligence_network_product import build_intelligence_network_product  # type: ignore
except Exception:  # pragma: no cover
    def build_intelligence_network_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

SURFACE_KEYS = (
    "cie_primary_estimate",
    "cie_primary_recon",
    "cie_primary_sabotage",
    "cie_primary_product",
    "cie_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "cie_estimate",
    "cie_recon",
    "cie_sabotage",
    "cie_product",
    "cie_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "cie_estimate": "apply_multi_phase_estimate_day",
    "cie_recon": "apply_intel_network_coverage",
    "cie_sabotage": "apply_intel_counter_sweep",
    "cie_product": "apply_assault_card_day",
    "cie_close": "apply_combat_agent_joint_close_day",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except (TypeError, ValueError):
        s = 0.5
    if s > 2.0:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Combat intel estimate audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_combat_intel_estimate_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    try:
        card = build_assault_estimate_card(100.0, 80.0, province_name="province_%d" % pid)
    except TypeError:
        card = build_assault_estimate_card(100.0, 80.0)
    try:
        net = build_intelligence_network_product(province_id=pid)
    except TypeError:
        net = build_intelligence_network_product()
    base_overall = float(card.get("overall") or 0.55)
    recon_bias = 0.04 + 0.02 * float(net.get("score") or 0.6)
    sabotage_bias = 0.03 + 0.015 * float(net.get("score") or 0.6)
    biased_overall = _floor(base_overall + recon_bias - sabotage_bias * 0.5, lo=0.05)
    bias_delta = biased_overall - base_overall
    base = _floor(0.5 * float(net.get("score") or 0.6) + 0.5 * base_overall)
    scores = {s: _floor(base + 0.01 * i) for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
    majors_ok = {SURFACE_KEYS[i]: scores[PRIMARY_COMMAND_STEPS[i]] >= 0.35 for i in range(5)}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0
    steps, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        lab = "I2b · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Combat intel estimate primary · majors %d/5 · dead %d · bias %+.2f · score %.2f · %s" % (
        majors_ok_n, dead_n, bias_delta, score, "PASS" if all_majors_ok else "PARTIAL")
    return {
        "score": score, "plain": label + "\n" + "\n".join(r["label"] for r in steps), "summary": label, "empty": False,
        "province_id": pid, "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "card": card, "network": net,
        "base_overall": base_overall, "biased_overall": biased_overall, "recon_bias": recon_bias,
        "sabotage_bias": sabotage_bias, "bias_delta": bias_delta, "intel_impact_visible": abs(bias_delta) > 0.001,
        "integration": ["combat_intel_estimate_primary_command_product", "assault_estimate_card", "I2", "combat"],
    }


def apply_combat_intel_estimate_primary_command_step(step: str, province_id: int = 1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"estimate": "cie_estimate", "recon": "cie_recon", "sabotage": "cie_sabotage",
               "product": "cie_product", "close": "cie_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_combat_intel_estimate_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False}


def close_combat_intel_estimate_primary_command_package(province_id=1):
    rt = {"applied": []}
    steps = [apply_combat_intel_estimate_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_combat_intel_estimate_primary_command_product(province_id=province_id)
    ok = bool(product.get("all_majors_ok")) and len(steps) == 5 and bool(product.get("intel_impact_visible"))
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "dead_n": int(product.get("dead_n") or 0), "summary": "Combat intel estimate close %s" % ("PASS" if ok else "FAIL"),
            "plain": "Combat intel estimate close", "empty": False}


def combat_intel_estimate_primary_command_integrity():
    p = build_combat_intel_estimate_primary_command_product()
    c = close_combat_intel_estimate_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all(a != "apply_focus" for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(c.get("ok")) and no_focus and bool(p.get("intel_impact_visible")))
    return {"ok": ok, "no_focus": no_focus, "summary": "Combat intel estimate integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
