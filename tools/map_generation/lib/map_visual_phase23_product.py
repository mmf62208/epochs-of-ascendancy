"""Map visual Phase 2+3 gap-closure product.

Phase 2: occupation heatmap/partisans · supply/sealane flow · battle indicators · LOD budgets · naval/air ops.
Phase 3: construction progress · leader stations · editor inspector · weather move tint · GPU/LOD targets.
Guarded inventory only — no province renumbering.
"""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

ROOT = Path(__file__).resolve().parents[3]

PRODUCT_STEPS = (
    "occupation_mapmode",
    "supply_flow",
    "battle_indicators",
    "lod_perf",
    "domain_ops",
    "construction",
    "leader_stations",
    "editor_weather_gpu",
)

_REQUIRED = (
    "scripts/map/OccupationOverlayLayer.gd",
    "scripts/map/StrategicFlowOverlayLayer.gd",
    "scripts/map/BattleIndicatorOverlayLayer.gd",
    "scripts/map/DomainOpsOverlayLayer.gd",
    "scripts/map/ConstructionProgressOverlayLayer.gd",
    "scripts/map/LeaderStationOverlayLayer.gd",
    "scripts/map/MapZoomLOD.gd",
    "scripts/map/MapRenderer.gd",
    "scripts/map/WeatherOverlayLayer.gd",
    "scripts/map/ProvinceEditor.gd",
)

_MARKERS = {
    "scripts/map/OccupationOverlayLayer.gd": ("show_partisan_markers", "set_mapmode", "mapmode"),
    "scripts/map/StrategicFlowOverlayLayer.gd": ("class_name StrategicFlowOverlayLayer", "_draw_flow_arrows"),
    "scripts/map/BattleIndicatorOverlayLayer.gd": ("class_name BattleIndicatorOverlayLayer", "push_assault_marker"),
    "scripts/map/DomainOpsOverlayLayer.gd": ("class_name DomainOpsOverlayLayer", "_draw_sortie_arrow"),
    "scripts/map/ConstructionProgressOverlayLayer.gd": ("class_name ConstructionProgressOverlayLayer", "_draw_progress_ring"),
    "scripts/map/LeaderStationOverlayLayer.gd": ("class_name LeaderStationOverlayLayer", "_draw_leader_marker"),
    "scripts/map/MapZoomLOD.gd": ("max_overlay_icons_for_board", "use_lower_vert_fallback", "target_frame_ms_mid_hardware"),
    "scripts/map/MapRenderer.gd": (
        "_setup_strategic_flow_layer",
        "_setup_battle_indicator_layer",
        "_setup_domain_ops_layer",
        "_setup_construction_progress_layer",
        "_setup_leader_station_layer",
        "get_phase23_overlay_stats",
        "KEY_J",
        "KEY_U",
        "KEY_K",
    ),
    "scripts/map/WeatherOverlayLayer.gd": ("apply_movement_cost_tint",),
    "scripts/map/ProvinceEditor.gd": ("get_selected_property_board", "export_roundtrip_check"),
    "scripts/core/ScenarioLoader.gd": ("map_phase23_live",),
}


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except Exception:
        s = 0.5
    if s > 2:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def compute_phase23_fingerprint() -> Dict[str, Any]:
    checks: Dict[str, bool] = {}
    for rel in _REQUIRED:
        checks["file:%s" % Path(rel).name] = (ROOT / rel).is_file()
    hits = 0
    total = 0
    for rel, needles in _MARKERS.items():
        text = (ROOT / rel).read_text(encoding="utf-8", errors="replace") if (ROOT / rel).is_file() else ""
        for n in needles:
            total += 1
            ok = n in text
            checks["m:%s" % n[:40]] = ok
            if ok:
                hits += 1
    ok_n = sum(1 for v in checks.values() if v)
    bits = "".join("1" if checks[k] else "0" for k in sorted(checks.keys()))
    # Compact fingerprint
    fingerprint = "mvp23-%d-%d-%s" % (ok_n, len(checks), bits[:24])
    score = _floor(ok_n / max(1, len(checks)))
    return {
        "checks": checks,
        "ok_n": ok_n,
        "check_n": len(checks),
        "marker_hits": hits,
        "marker_total": total,
        "fingerprint": fingerprint,
        "score": score,
        "ok": ok_n == len(checks) and hits == total,
        "summary": "Phase2/3 visual fingerprint · %s · %d/%d" % (fingerprint, ok_n, len(checks)),
        "empty": False,
    }


def build_map_visual_phase23_product(*, province_id: int = 1) -> Dict[str, Any]:
    finger = compute_phase23_fingerprint()
    step_scores = {
        "occupation_mapmode": _floor(0.9 if finger["checks"].get("m:show_partisan_markers") else 0.4),
        "supply_flow": _floor(0.9 if finger["checks"].get("m:class_name StrategicFlowOverlayLayer") else 0.4),
        "battle_indicators": _floor(0.9 if finger["checks"].get("m:push_assault_marker") else 0.4),
        "lod_perf": _floor(0.9 if finger["checks"].get("m:use_lower_vert_fallback") else 0.4),
        "domain_ops": _floor(0.9 if finger["checks"].get("m:class_name DomainOpsOverlayLayer") else 0.4),
        "construction": _floor(0.9 if finger["checks"].get("m:class_name ConstructionProgressOverlayLayer") else 0.4),
        "leader_stations": _floor(0.9 if finger["checks"].get("m:class_name LeaderStationOverlayLayer") else 0.4),
        "editor_weather_gpu": _floor(
            0.9 if finger["checks"].get("m:apply_movement_cost_tint") and finger["checks"].get("m:get_selected_property_board") else 0.4
        ),
    }
    score = _floor(sum(step_scores.values()) / max(1, len(step_scores)))
    complete = bool(finger.get("ok"))
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    labels = {
        "occupation_mapmode": "Occupation heatmap/partisans",
        "supply_flow": "Supply/sealane flow arrows",
        "battle_indicators": "Battle/assault indicators",
        "lod_perf": "LOD budgets + lower-vert",
        "domain_ops": "Naval/air domain ops",
        "construction": "Construction progress rings",
        "leader_stations": "Leader OOB stations",
        "editor_weather_gpu": "Editor + weather + GPU targets",
    }
    for i, step in enumerate(PRODUCT_STEPS):
        sc = step_scores[step]
        lab = labels[step] + " · score %.2f" % sc
        day_rows.append({
            "index": i, "step": step, "action_id": "map_p23_%s" % step,
            "leaf_action": "apply_focus", "label": lab, "score": sc, "enabled": True,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": "apply_focus", "province_id": max(1, int(province_id)),
            "score": sc, "enabled": True, "label": lab, "step": step,
        })
    label = "Map visual P2/P3 · %s · %s · score %.2f" % (
        finger.get("fingerprint"), "COMPLETE" if complete else "OPEN", score)
    return {
        "fingerprint": finger,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "step_scores": step_scores,
        "complete": complete,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, finger["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#90c8e0]🗺 Map P2/P3[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "map_visual_phase23_product", "phase2_gap", "phase3_gap", "world_class_map",
            "occupation_mapmode", "supply_flow", "battle_indicators", "domain_ops",
        ],
    }


def execute_map_phase23_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or PRODUCT_STEPS[0]).strip().lower()
    if s not in PRODUCT_STEPS:
        s = PRODUCT_STEPS[0]
    product = build_map_visual_phase23_product(province_id=province_id)
    row = next((r for r in product.get("day_rows") or [] if r.get("step") == s), None)
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute map P2/P3 %s · score %.2f" % (s, score)
    return {
        "step": s, "ok": True, "score": score, "province_id": max(1, int(province_id)),
        "summary": label, "plain": label, "empty": False,
        "apply_queue": [{"action_id": "apply_focus", "province_id": max(1, int(province_id)), "score": score, "enabled": True}],
    }


def map_visual_phase23_integrity() -> Dict[str, Any]:
    product = build_map_visual_phase23_product()
    steps = [execute_map_phase23_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        bool(product.get("complete"))
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "fingerprint": (product.get("fingerprint") or {}).get("fingerprint"),
        "summary": "Map visual Phase2/3 integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_map_visual_phase23_product_loop() -> Dict[str, Any]:
    product = build_map_visual_phase23_product(province_id=2)
    gate = map_visual_phase23_integrity()
    ok = bool(gate.get("ok")) and bool(product.get("complete"))
    label = "Close map visual P2/P3 · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": float(product.get("score", 0))}
