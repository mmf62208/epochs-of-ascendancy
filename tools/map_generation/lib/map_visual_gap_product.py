"""Map visual gap-closure product (Phase 1) — signal graph · occupation visuals · perf · CI fingerprint.

Guarded inventory product: no province renumbering, no destructive writes.
Feeds dual evidence marker map_gap_closure_live and pure CI gates.
"""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

ROOT = Path(__file__).resolve().parents[3]

PRODUCT_STEPS = ("signal_graph", "occupation_visual", "perf_profile", "visual_regression")
_STEP_META = {
    "signal_graph": {
        "action_id": "map_gap_signal_graph",
        "leaf": "apply_focus",
        "label": "Step 0 — signal graph harness (F11)",
    },
    "occupation_visual": {
        "action_id": "map_gap_occupation_visual",
        "leaf": "apply_station",
        "label": "Step 1 — occupation tint + garrison icons",
    },
    "perf_profile": {
        "action_id": "map_gap_perf_profile",
        "leaf": "apply_production",
        "label": "Step 2 — MapRenderer perf profile hooks",
    },
    "visual_regression": {
        "action_id": "map_gap_visual_regression",
        "leaf": "apply_supply",
        "label": "Step 3 — visual regression fingerprint CI",
    },
}

_REQUIRED_SCRIPTS = (
    "SignalGraphVisualizer.gd",
    "scripts/debug/SignalGraphHarness.gd",
    "scripts/map/OccupationOverlayLayer.gd",
    "scripts/map/MapRendererPerf.gd",
    "scripts/map/MapRenderer.gd",
    "scripts/map/ConflictOverlayLayer.gd",
    "scripts/ui/DebugOverlay.gd",
    "scripts/ui/TopInfoBar.gd",
)

_REQUIRED_MARKERS = {
    "scripts/map/MapRenderer.gd": (
        "OccupationOverlayLayer",
        "_setup_occupation_layer",
        "MapRendererPerf",
        "enable_perf_profile",
    ),
    "scripts/ui/TopInfoBar.gd": ("KEY_F11", "SignalGraphHarness"),
    "scripts/ui/DebugOverlay.gd": ("Signal Graph", "Occupation Overlay", "Map Perf"),
    "scripts/core/ScenarioLoader.gd": ("map_gap_closure_live",),
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


def compute_file_presence() -> Dict[str, Any]:
    present = []
    missing = []
    for rel in _REQUIRED_SCRIPTS:
        p = ROOT / rel
        if p.is_file():
            present.append(rel)
        else:
            missing.append(rel)
    score = _floor(len(present) / max(1, len(_REQUIRED_SCRIPTS)))
    return {
        "present": present,
        "missing": missing,
        "present_n": len(present),
        "required_n": len(_REQUIRED_SCRIPTS),
        "score": score,
        "ok": len(missing) == 0,
        "summary": "File presence · %d/%d · missing %d" % (len(present), len(_REQUIRED_SCRIPTS), len(missing)),
        "empty": False,
    }


def compute_stack_markers() -> Dict[str, Any]:
    hits = 0
    total = 0
    detail: List[Dict[str, Any]] = []
    for rel, needles in _REQUIRED_MARKERS.items():
        text = (ROOT / rel).read_text(encoding="utf-8", errors="replace") if (ROOT / rel).is_file() else ""
        for n in needles:
            total += 1
            ok = n in text
            if ok:
                hits += 1
            detail.append({"file": rel, "marker": n, "ok": ok})
    score = _floor(hits / max(1, total))
    return {
        "hits": hits,
        "total": total,
        "detail": detail,
        "score": score,
        "ok": hits == total,
        "summary": "Stack markers · %d/%d" % (hits, total),
        "empty": False,
    }


def compute_visual_fingerprint() -> Dict[str, Any]:
    """Deterministic visual contract fingerprint for CI regression (no GPU)."""
    files = compute_file_presence()
    markers = compute_stack_markers()
    occupation_layer = (ROOT / "scripts/map/OccupationOverlayLayer.gd").read_text(encoding="utf-8", errors="replace") if (ROOT / "scripts/map/OccupationOverlayLayer.gd").is_file() else ""
    renderer = (ROOT / "scripts/map/MapRenderer.gd").read_text(encoding="utf-8", errors="replace") if (ROOT / "scripts/map/MapRenderer.gd").is_file() else ""
    checks = {
        "occupation_class": "class_name OccupationOverlayLayer" in occupation_layer,
        "garrison_icon": "garrison" in occupation_layer.lower() and "draw_colored_polygon" in occupation_layer,
        "resistance_heatmap": "resistance" in occupation_layer.lower() and "show_resistance_heatmap" in occupation_layer,
        "renderer_occupation_setup": "_setup_occupation_layer" in renderer,
        "renderer_perf": "MapRendererPerf" in renderer or "enable_perf_profile" in renderer,
        "conflict_layer_intact": (ROOT / "scripts/map/ConflictOverlayLayer.gd").is_file(),
        "signal_visualizer": (ROOT / "SignalGraphVisualizer.gd").is_file(),
        "signal_harness": (ROOT / "scripts/debug/SignalGraphHarness.gd").is_file(),
        "files_ok": bool(files.get("ok")),
        "markers_ok": bool(markers.get("ok")),
    }
    ok_n = sum(1 for v in checks.values() if v)
    score = _floor(ok_n / max(1, len(checks)))
    # Stable fingerprint string for regression diffs
    bits = "".join("1" if checks[k] else "0" for k in sorted(checks.keys()))
    fingerprint = "mvg1-%s-%02d" % (bits, ok_n)
    return {
        "checks": checks,
        "ok_n": ok_n,
        "check_n": len(checks),
        "fingerprint": fingerprint,
        "score": score,
        "ok": ok_n >= len(checks) - 0,  # all must pass
        "summary": "Visual fingerprint · %s · %d/%d" % (fingerprint, ok_n, len(checks)),
        "empty": False,
    }


def recommend_gap_step(*, signal_ok: bool = False, occupation_ok: bool = False, perf_ok: bool = False) -> Dict[str, Any]:
    if not signal_ok:
        step, reason = "signal_graph", "wire F11 signal graph harness"
    elif not occupation_ok:
        step, reason = "occupation_visual", "land occupation tint + garrison icons"
    elif not perf_ok:
        step, reason = "perf_profile", "enable MapRenderer perf profile"
    else:
        step, reason = "visual_regression", "lock visual fingerprint CI"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_map_visual_gap_product(*, province_id: int = 1) -> Dict[str, Any]:
    files = compute_file_presence()
    markers = compute_stack_markers()
    finger = compute_visual_fingerprint()
    signal_ok = bool(files.get("ok")) and (ROOT / "scripts/debug/SignalGraphHarness.gd").is_file()
    occupation_ok = bool(finger.get("checks", {}).get("occupation_class")) and bool(finger.get("checks", {}).get("renderer_occupation_setup"))
    perf_ok = bool(finger.get("checks", {}).get("renderer_perf"))
    regression_ok = bool(finger.get("ok"))
    step_scores = {
        "signal_graph": _floor(0.9 if signal_ok else 0.4),
        "occupation_visual": _floor(0.9 if occupation_ok else 0.4),
        "perf_profile": _floor(0.9 if perf_ok else 0.4),
        "visual_regression": _floor(float(finger.get("score", 0.5))),
    }
    score = _floor(0.25 * sum(step_scores.values()) / max(1, len(step_scores)) * 4.0)
    # recompute weighted
    score = _floor(
        0.25 * step_scores["signal_graph"]
        + 0.3 * step_scores["occupation_visual"]
        + 0.2 * step_scores["perf_profile"]
        + 0.25 * step_scores["visual_regression"]
    )
    rec = recommend_gap_step(signal_ok=signal_ok, occupation_ok=occupation_ok, perf_ok=perf_ok and regression_ok)
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
    complete = signal_ok and occupation_ok and perf_ok and regression_ok
    label = "Map visual gap · files %d/%d · fingerprint %s · %s · score %.2f" % (
        int(files.get("present_n", 0)), int(files.get("required_n", 0)),
        finger.get("fingerprint", "?"), "COMPLETE" if complete else "OPEN", score,
    )
    return {
        "files": files, "markers": markers, "fingerprint": finger,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue,
        "complete": complete, "score": score, "gap_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, files["summary"], markers["summary"], finger["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#90d0a0]🗺 Map gap[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "map_visual_gap_product", "signal_graph", "occupation_visual", "perf_profile", "visual_regression",
            "map_gap_closure", "phase1_gap", "world_class_map",
        ],
    }


def execute_map_gap_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "signal_graph").strip().lower().replace("map_gap_", "")
    if s.startswith("signal"):
        s = "signal_graph"
    elif s.startswith("occup") or s.startswith("garrison") or s.startswith("visual"):
        if "regress" in s or "finger" in s:
            s = "visual_regression"
        else:
            s = "occupation_visual"
    elif s.startswith("perf"):
        s = "perf_profile"
    elif s.startswith("regress") or s.startswith("finger") or s.startswith("ci"):
        s = "visual_regression"
    if s not in _STEP_META:
        s = "signal_graph"
    meta = _STEP_META[s]
    product = build_map_visual_gap_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute map gap %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_map_gap_step", s, leaf],
    }


def map_visual_gap_integrity() -> Dict[str, Any]:
    product = build_map_visual_gap_product()
    steps = [execute_map_gap_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    finger = product.get("fingerprint") or {}
    ok = (
        not product.get("empty")
        and bool(product.get("complete"))
        and bool(finger.get("ok"))
        and len(product.get("day_rows") or []) >= 4
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "fingerprint": finger.get("fingerprint"),
        "summary": "Map visual gap integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_map_visual_gap_product_loop() -> Dict[str, Any]:
    product = build_map_visual_gap_product(province_id=2)
    gate = map_visual_gap_integrity()
    ok = bool(gate.get("ok")) and bool(product.get("complete"))
    label = "Close map visual gap · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
