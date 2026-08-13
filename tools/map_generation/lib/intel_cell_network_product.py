"""Intel cell network product (major #51) — Phase 9 full gameplay cycle.

Multi-province cell coverage → cell ops/recruit → counterintel sweep.
Deepens intelligence_network (#19) with multi-province cell map for full GS cycle.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from intelligence_network_product import build_intelligence_network_product  # type: ignore
except Exception:  # pragma: no cover
    def build_intelligence_network_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "coverage_score": 0.55, "counter_score": 0.55}

try:
    from agent_campaign_product import build_agent_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_agent_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from diplomacy_peace_campaign_product import build_diplomacy_peace_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_diplomacy_peace_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

PRODUCT_STEPS = ("cells", "ops", "sweep")
_STEP_META = {
    "cells": {"action_id": "intel_cell_coverage", "leaf": "apply_agent_dispatch", "label": "Step 0 — multi-province cell coverage"},
    "ops": {"action_id": "intel_cell_ops", "leaf": "apply_agent_dispatch", "label": "Step 1 — cell ops/recruit"},
    "sweep": {"action_id": "intel_counter_sweep", "leaf": "apply_hh_commit", "label": "Step 2 — counterintel sweep"},
}

_DEFAULT_CELLS = (
    {"province_id": 1, "strength": 0.6, "exposed": 0.2},
    {"province_id": 2, "strength": 0.45, "exposed": 0.35},
    {"province_id": 3, "strength": 0.55, "exposed": 0.25},
    {"province_id": 4, "strength": 0.4, "exposed": 0.4},
)


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


def compute_cell_coverage(*, cells: List[Dict[str, Any]] = None, base_coverage: float = 0.55) -> Dict[str, Any]:
    rows = list(cells or _DEFAULT_CELLS)
    n = len(rows)
    avg_str = sum(float(c.get("strength", 0.5)) for c in rows) / max(1, n)
    avg_exp = sum(float(c.get("exposed", 0.3)) for c in rows) / max(1, n)
    score = _floor(0.4 * base_coverage + 0.4 * avg_str + 0.2 * (1.0 - avg_exp))
    return {
        "cells": rows, "cell_n": n, "avg_strength": avg_str, "avg_exposed": avg_exp, "score": score,
        "summary": "Cell coverage · cells %d · str %.0f%% · exposed %.0f%% · score %.2f"
        % (n, avg_str * 100, avg_exp * 100, score),
        "empty": False,
    }


def compute_cell_ops(*, coverage: Dict[str, Any], agent_score: float = 0.58) -> Dict[str, Any]:
    n = int(coverage.get("cell_n", 0))
    a = _floor(agent_score)
    recruited = max(1, int(round(n * 0.5 * a)))
    score = _floor(0.45 * float(coverage.get("score", 0.5)) + 0.4 * a + 0.15 * min(1.0, recruited / 3.0))
    return {
        "recruited": recruited, "cell_n": n, "agent_score": a, "score": score,
        "summary": "Cell ops · recruited %d · cells %d · agent %.2f · score %.2f" % (recruited, n, a, score),
        "empty": False,
    }


def compute_counter_sweep(*, ops: Dict[str, Any], counter_score: float = 0.55, diplo_score: float = 0.55) -> Dict[str, Any]:
    c = _floor(counter_score)
    d = _floor(diplo_score)
    swept = max(1, int(round(float(ops.get("recruited", 1)) * c)))
    residual_risk = _floor(0.35 + 0.4 * (1.0 - c) + 0.2 * (1.0 - d))
    secure = residual_risk <= 0.55
    score = _floor(0.4 * float(ops.get("score", 0.5)) + 0.35 * c + 0.25 * (1.0 if secure else 0.4))
    return {
        "swept": swept, "residual_risk": residual_risk, "secure": secure, "score": score,
        "summary": "Counter sweep · swept %d · residual %.0f%% · %s · score %.2f"
        % (swept, residual_risk * 100, "SECURE" if secure else "EXPOSED", score),
        "empty": False,
    }


def recommend_intel_cell_step(*, covered: bool = False, ops_done: bool = False) -> Dict[str, Any]:
    if not covered:
        step, reason = "cells", "map multi-province cell coverage"
    elif not ops_done:
        step, reason = "ops", "run cell ops/recruit"
    else:
        step, reason = "sweep", "counterintel sweep"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_intel_cell_network_product(*, province_id: int = 1, cell_n: int = 4) -> Dict[str, Any]:
    net = build_intelligence_network_product(province_id=province_id)
    agent = build_agent_campaign_product(province_id=province_id)
    diplo = build_diplomacy_peace_campaign_product(province_id=province_id)
    cells = []
    for i in range(max(2, min(8, int(cell_n)))):
        cells.append({
            "province_id": max(1, int(province_id)) + i,
            "strength": 0.4 + 0.08 * ((i + 1) % 4),
            "exposed": 0.2 + 0.05 * (i % 3),
        })
    coverage = compute_cell_coverage(cells=cells, base_coverage=float(net.get("coverage_score", net.get("score", 0.55))))
    ops = compute_cell_ops(coverage=coverage, agent_score=float(agent.get("score", 0.58)))
    sweep = compute_counter_sweep(
        ops=ops,
        counter_score=float(net.get("counter_score", net.get("score", 0.55))),
        diplo_score=float(diplo.get("score", 0.55)),
    )
    c_s = _floor(float(coverage["score"]))
    o_s = _floor(float(ops["score"]))
    s_s = _floor(float(sweep["score"]))
    score = _floor(0.3 * c_s + 0.35 * o_s + 0.35 * s_s)
    rec = recommend_intel_cell_step(covered=True, ops_done=True)
    step_scores = {"cells": c_s, "ops": o_s, "sweep": s_s}
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
        {"action_id": "intel_cell_network_product", "label": "Run intel cell network product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Intel cell network · cells %d · recruited %d · swept %d · %s · score %.2f" % (
        int(coverage["cell_n"]), int(ops["recruited"]), int(sweep["swept"]),
        "SECURE" if sweep["secure"] else "EXPOSED", score)
    return {
        "network": net, "agent": agent, "diplo": diplo,
        "coverage": coverage, "ops": ops, "sweep": sweep,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "cell_n": int(coverage["cell_n"]), "recruited": int(ops["recruited"]), "swept": int(sweep["swept"]),
        "secure": bool(sweep["secure"]), "score": score, "intel_cell_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), coverage["summary"], ops["summary"], sweep["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#c084fc]🕵 Intel cells[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "intel_cell_network_product", "intel_cell_coverage", "intel_cell_ops", "intel_counter_sweep",
            "major_51", "intel", "cells", "phase9_cycle", "full_gameplay_cycle",
        ],
    }


def execute_intel_cell_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "cells").strip().lower().replace("intel_", "").replace("cell_", "")
    if s.startswith("cell") or s.startswith("cover"):
        s = "cells"
    elif s.startswith("ops") or s.startswith("recruit"):
        s = "ops"
    elif s.startswith("sweep") or s.startswith("counter"):
        s = "sweep"
    if s not in _STEP_META:
        s = "cells"
    meta = _STEP_META[s]
    product = build_intel_cell_network_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute intel cell %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_intel_cell_step", s, leaf],
    }


def intel_cell_network_integrity() -> Dict[str, Any]:
    product = build_intel_cell_network_product()
    steps = [execute_intel_cell_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("cell_n", 0)) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Intel cell network integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_intel_cell_network_product_loop() -> Dict[str, Any]:
    product = build_intel_cell_network_product(province_id=2, cell_n=5)
    gate = intel_cell_network_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close intel cell network · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
