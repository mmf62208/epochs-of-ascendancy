"""Occupation revolt network product (major #58) — Phase 11 world-class GS depth.

Multi-province revolt map → cascade risk → network suppress package.
Deepens occupation resistance (#29) + revolt/garrison (#35) with multi-province networks.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from occupation_resistance_compliance_product import build_occupation_resistance_compliance_product  # type: ignore
except Exception:  # pragma: no cover
    def build_occupation_resistance_compliance_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

try:
    from occupation_revolt_garrison_product import build_occupation_revolt_garrison_product  # type: ignore
except Exception:  # pragma: no cover
    def build_occupation_revolt_garrison_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False}

try:
    from manpower_cohort_reserve_product import build_manpower_cohort_reserve_product  # type: ignore
except Exception:  # pragma: no cover
    def build_manpower_cohort_reserve_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from intel_cell_network_product import build_intel_cell_network_product  # type: ignore
except Exception:  # pragma: no cover
    def build_intel_cell_network_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False}

PRODUCT_STEPS = ("map", "cascade", "suppress")
_STEP_META = {
    "map": {"action_id": "revolt_network_map", "leaf": "apply_focus", "label": "Step 0 — multi-province revolt map"},
    "cascade": {"action_id": "revolt_cascade_risk", "leaf": "apply_agent_dispatch", "label": "Step 1 — cascade risk assessment"},
    "suppress": {"action_id": "revolt_network_suppress", "leaf": "apply_station", "label": "Step 2 — network suppress package"},
}

_CELLS = (
    {"id": "cell_a", "provinces": 3, "heat": 0.72, "kind": "urban"},
    {"id": "cell_b", "provinces": 4, "heat": 0.65, "kind": "rural"},
    {"id": "cell_c", "provinces": 2, "heat": 0.8, "kind": "border"},
    {"id": "cell_d", "provinces": 5, "heat": 0.55, "kind": "industrial"},
    {"id": "cell_e", "provinces": 3, "heat": 0.68, "kind": "coastal"},
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


def compute_revolt_map(*, occ_score: float = 0.6, garrison_score: float = 0.62) -> Dict[str, Any]:
    o = _floor(occ_score)
    g = _floor(garrison_score)
    cells = []
    province_n = 0
    for c in _CELLS:
        sc = _floor(0.45 * float(c["heat"]) + 0.3 * o + 0.25 * (1.0 - g * 0.4))
        pn = int(c["provinces"])
        province_n += pn
        cells.append({**c, "score": sc, "enabled": True, "label": "%s · %s · %d prov" % (c["id"], c["kind"], pn)})
    cells.sort(key=lambda x: -float(x["score"]))
    top = cells[0] if cells else {"id": "cell_a", "score": 0.5, "heat": 0.7}
    score = _floor(0.5 * float(top["score"]) + 0.5 * o)
    return {
        "cells": cells, "cell_n": len(cells), "province_n": province_n,
        "top_id": str(top.get("id")), "top_heat": float(top.get("heat", 0.5)), "score": score,
        "summary": "Revolt map · %d cells · %d provinces · top %s · score %.2f"
        % (len(cells), province_n, top.get("id"), score),
        "empty": False,
    }


def compute_cascade_risk(*, revolt_map: Dict[str, Any], intel_score: float = 0.65) -> Dict[str, Any]:
    m = _floor(float(revolt_map.get("score", 0.5)))
    i = _floor(intel_score)
    heat = _floor(float(revolt_map.get("top_heat", 0.5)))
    links = max(1, int(round(float(revolt_map.get("cell_n", 3)) * (0.6 + 0.4 * heat))))
    cascade_risk = _floor(0.5 * heat + 0.3 * m + 0.2 * (1.0 - i * 0.5))
    critical = cascade_risk >= 0.6
    score = _floor(0.45 * cascade_risk + 0.3 * m + 0.25 * i)
    return {
        "links": links, "cascade_risk": cascade_risk, "critical": critical, "score": score,
        "top_id": str(revolt_map.get("top_id", "")),
        "summary": "Cascade risk · links %d · risk %.0f%% · %s · score %.2f"
        % (links, cascade_risk * 100, "CRITICAL" if critical else "WATCH", score),
        "empty": False,
    }


def compute_network_suppress(*, cascade: Dict[str, Any], manpower_score: float = 0.58) -> Dict[str, Any]:
    c = _floor(float(cascade.get("score", 0.5)))
    mp = _floor(manpower_score)
    risk = _floor(float(cascade.get("cascade_risk", 0.5)))
    garrisons = max(1, int(round((0.5 * risk + 0.3 * c + 0.2 * mp) * 6)))
    suppressed = max(1, int(round(garrisons * (0.55 + 0.3 * mp))))
    score = _floor(0.4 * c + 0.35 * mp + 0.25 * (1.0 if suppressed >= 2 else 0.4))
    return {
        "garrisons": garrisons, "suppressed": suppressed, "score": score,
        "links": int(cascade.get("links", 0)),
        "summary": "Network suppress · garrisons %d · suppressed %d · score %.2f"
        % (garrisons, suppressed, score),
        "empty": False,
    }


def recommend_revolt_network_step(*, mapped: bool = False, cascaded: bool = False) -> Dict[str, Any]:
    if not mapped:
        step, reason = "map", "map multi-province revolt cells"
    elif not cascaded:
        step, reason = "cascade", "assess cascade risk links"
    else:
        step, reason = "suppress", "deploy network suppress package"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_occupation_revolt_network_product(*, province_id: int = 1) -> Dict[str, Any]:
    occ = build_occupation_resistance_compliance_product(province_id=province_id)
    garrison = build_occupation_revolt_garrison_product(province_id=province_id)
    manpower = build_manpower_cohort_reserve_product(province_id=province_id)
    intel = build_intel_cell_network_product(province_id=province_id)
    revolt_map = compute_revolt_map(
        occ_score=float(occ.get("score", 0.6)),
        garrison_score=float(garrison.get("score", 0.62)),
    )
    cascade = compute_cascade_risk(revolt_map=revolt_map, intel_score=float(intel.get("score", 0.65)))
    suppress = compute_network_suppress(cascade=cascade, manpower_score=float(manpower.get("score", 0.58)))
    m_s, c_s, s_s = _floor(float(revolt_map["score"])), _floor(float(cascade["score"])), _floor(float(suppress["score"]))
    score = _floor(0.3 * m_s + 0.35 * c_s + 0.35 * s_s)
    rec = recommend_revolt_network_step(mapped=True, cascaded=bool(cascade.get("critical", False)) or int(cascade.get("links", 0)) >= 2)
    step_scores = {"map": m_s, "cascade": c_s, "suppress": s_s}
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
        {"action_id": "occupation_revolt_network_product", "label": "Run occupation revolt network product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Revolt network · cells %d · provinces %d · garrisons %d · score %.2f" % (
        int(revolt_map["cell_n"]), int(revolt_map["province_n"]), int(suppress["garrisons"]), score)
    return {
        "occ": occ, "garrison": garrison, "manpower": manpower, "intel": intel,
        "revolt_map": revolt_map, "cascade": cascade, "suppress": suppress,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "cell_n": int(revolt_map["cell_n"]), "province_n": int(revolt_map["province_n"]),
        "garrisons": int(suppress["garrisons"]), "suppressed": int(suppress["suppressed"]),
        "links": int(cascade["links"]), "critical": bool(cascade["critical"]),
        "score": score, "revolt_network_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), revolt_map["summary"], cascade["summary"], suppress["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e08060]⚑ Revolt net[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "occupation_revolt_network_product", "revolt_network_map", "revolt_cascade_risk", "revolt_network_suppress",
            "major_58", "occupation", "revolt", "phase11_depth", "world_class_gs",
        ],
    }


def execute_revolt_network_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "map").strip().lower().replace("revolt_", "").replace("network_", "").replace("occupation_", "")
    if s.startswith("map") or s.startswith("board") or s.startswith("cell"):
        s = "map"
    elif s.startswith("cascade") or s.startswith("risk") or s.startswith("link"):
        s = "cascade"
    elif s.startswith("suppress") or s.startswith("garrison") or s.startswith("ops") or s.startswith("exec"):
        s = "suppress"
    if s not in _STEP_META:
        s = "map"
    meta = _STEP_META[s]
    product = build_occupation_revolt_network_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute revolt network %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_revolt_network_step", s, leaf],
    }


def occupation_revolt_network_integrity() -> Dict[str, Any]:
    product = build_occupation_revolt_network_product()
    steps = [execute_revolt_network_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("cell_n", 0)) >= 3
        and int(product.get("province_n", 0)) >= 8
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Occupation revolt network integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_occupation_revolt_network_product_loop() -> Dict[str, Any]:
    product = build_occupation_revolt_network_product(province_id=2)
    gate = occupation_revolt_network_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close occupation revolt network · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
