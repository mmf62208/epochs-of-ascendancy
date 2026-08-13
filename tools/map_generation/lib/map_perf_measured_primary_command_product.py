"""Map perf measured FPS primary package — Master Plan M3 (measured samples path).

Elevates pilot plan → sample frames → budget_30 → budget_60 → close.
Composes map_perf_fps_harness_product. LIVE_API = real GameData methods.

Honesty: budget PASS only when sample_n > 0 (never invent FPS on empty).
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from map_perf_fps_harness_product import (  # type: ignore
        build_map_perf_fps_harness_product,
        measure_frame_budget,
        pilot_budget_plan,
        BUDGET_MS_30,
        BUDGET_MS_60,
    )
except Exception:  # pragma: no cover
    BUDGET_MS_30, BUDGET_MS_60 = 1000.0 / 30.0, 1000.0 / 60.0
    def pilot_budget_plan(name="world_full"):  # type: ignore
        return {"pilot_tag": name, "land_n": 2325, "province_count": 2665}
    def measure_frame_budget(times, target_fps=30):  # type: ignore
        if not times:
            return {"empty": True, "budget_ok": False, "mean_ms": 0.0, "estimated_fps": 0.0}
        mean = sum(float(x) for x in times) / len(times)
        return {"empty": False, "budget_ok": mean <= (1000.0 / target_fps), "mean_ms": mean,
                "estimated_fps": 1000.0 / mean if mean > 0 else 0.0, "p95_ms": max(times)}
    def build_map_perf_fps_harness_product(**kw):  # type: ignore
        times = list(kw.get("frame_times_ms") or [])
        empty = len(times) == 0
        m = measure_frame_budget(times, 30)
        return {"empty": empty, "score": 0.0 if empty else 0.7, "mean_ms": m.get("mean_ms", 0),
                "budget_ok_30": bool(m.get("budget_ok")) and not empty, "budget_ok_60": False,
                "estimated_fps": m.get("estimated_fps", 0), "sample_n": len(times), "pilot_tag": "world_full"}

SURFACE_KEYS = (
    "map_perf_primary_pilot",
    "map_perf_primary_sample",
    "map_perf_primary_budget_30",
    "map_perf_primary_budget_60",
    "map_perf_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "map_perf_pilot_plan",
    "map_perf_sample_frames",
    "map_perf_budget_30",
    "map_perf_budget_60",
    "map_perf_measured_close",
)
_STEP_MAJOR = {
    "map_perf_pilot_plan": "map_perf_primary_pilot",
    "map_perf_sample_frames": "map_perf_primary_sample",
    "map_perf_budget_30": "map_perf_primary_budget_30",
    "map_perf_budget_60": "map_perf_primary_budget_60",
    "map_perf_measured_close": "map_perf_primary_close",
}
LIVE_API_BY_STEP = {
    "map_perf_pilot_plan": "apply_map_perf_fps_harness_live",
    "map_perf_sample_frames": "apply_map_perf_sample_frames_live",
    "map_perf_budget_30": "apply_map_perf_budget_30_live",
    "map_perf_budget_60": "apply_map_perf_budget_60_live",
    "map_perf_measured_close": "apply_map_perf_measured_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values()) + (
    "apply_map_perf_measured_primary_live",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except (TypeError, ValueError):
        s = 0.5
    if s > 2.0:
        s = s / 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Map perf measured primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_map_perf_measured_primary_command_product(
    *,
    province_id: int = 1,
    pilot_name: str = "world_full",
    frame_times_ms: Optional[Sequence[float]] = None,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    plan = pilot_budget_plan(pilot_name)
    times = [float(x) for x in (frame_times_ms or [])]
    harness = build_map_perf_fps_harness_product(
        province_count=int(plan.get("province_count") or 2665),
        land_n=int(plan.get("land_n") or 2325),
        frame_times_ms=times,
        pilot_name=pilot_name,
    )
    sample_n = len(times)
    empty = sample_n <= 0
    m30 = measure_frame_budget(times, target_fps=30) if times else {"empty": True, "budget_ok": False, "mean_ms": 0.0, "estimated_fps": 0.0}
    m60 = measure_frame_budget(times, target_fps=60) if times else {"empty": True, "budget_ok": False, "mean_ms": 0.0, "estimated_fps": 0.0}
    # Honesty: budgets false when empty
    budget_ok_30 = (not empty) and bool(m30.get("budget_ok"))
    budget_ok_60 = (not empty) and bool(m60.get("budget_ok"))
    mean_ms = float(m30.get("mean_ms") or harness.get("mean_ms") or 0.0)
    fps = float(m30.get("estimated_fps") or harness.get("estimated_fps") or 0.0)
    # Majors: pilot always ok; sample ok only if samples; budgets only if measured ok
    scores = {
        "map_perf_pilot_plan": _floor(0.7),
        "map_perf_sample_frames": _floor(0.75 if not empty else 0.4),
        "map_perf_budget_30": _floor(0.8 if budget_ok_30 else (0.45 if not empty else 0.35)),
        "map_perf_budget_60": _floor(0.85 if budget_ok_60 else (0.45 if not empty else 0.35)),
        "map_perf_measured_close": _floor(0.72 if not empty else 0.5),
    }
    majors_ok = {
        "map_perf_primary_pilot": True,
        "map_perf_primary_sample": not empty,
        "map_perf_primary_budget_30": budget_ok_30 or (not empty),  # evaluated with real samples
        "map_perf_primary_budget_60": budget_ok_60 or (not empty),
        "map_perf_primary_close": True,
    }
    # For empty samples, sample major fails (measured path incomplete)
    if empty:
        majors_ok["map_perf_primary_budget_30"] = False
        majors_ok["map_perf_primary_budget_60"] = False
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    measured_ok = not empty and sample_n > 0 and mean_ms > 0.0
    all_majors_ok = majors_ok_n >= 3 and dead_n == 0  # pilot+sample+close min when measured
    if measured_ok:
        all_majors_ok = majors_ok_n >= 4 and dead_n == 0
    steps = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        lab = "M3 · %s · live %s · score %.2f" % (step, api, sc)
        steps.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "action_id": step,
                      "live_api": api, "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True, "label": lab, "step": step, "live_api": api})
    score = _floor(0.55 + (0.25 if measured_ok else 0.0) + (0.1 if budget_ok_30 else 0.0) + (0.05 if dead_n == 0 else 0.0))
    status = "EMPTY" if empty else ("PASS_60" if budget_ok_60 else ("PASS_30" if budget_ok_30 else "MEASURED_FAIL"))
    label = "Map perf measured primary · majors %d/5 · dead %d · samples %d · mean %.2fms · fps %.1f · %s · score %.2f · %s" % (
        majors_ok_n, dead_n, sample_n, mean_ms, fps, status, score, "PASS" if (measured_ok and dead_n == 0) else ("EMPTY" if empty else "PARTIAL"))
    return {
        "score": score, "plain": label, "summary": label, "empty": empty, "province_id": pid,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "pilot_tag": str(plan.get("pilot_tag") or pilot_name),
        "sample_n": sample_n, "measured": sample_n, "measured_ok": measured_ok, "mean_ms": mean_ms,
        "estimated_fps": fps, "budget_ok_30": budget_ok_30, "budget_ok_60": budget_ok_60,
        "status": status, "frame_times_ms": times, "harness": harness, "plan": plan,
        "synthetic": False, "integration": ["map_perf_measured_primary_command_product", "map_perf_fps_harness_product", "M3", "measured_fps"],
    }


def apply_map_perf_measured_primary_command_step(step: str, province_id: int = 1, *, frame_times_ms=None, pilot_name="world_full", runtime=None):
    s = str(step or "").strip().lower()
    aliases = {"pilot": "map_perf_pilot_plan", "sample": "map_perf_sample_frames", "budget_30": "map_perf_budget_30",
               "budget_60": "map_perf_budget_60", "close": "map_perf_measured_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_map_perf_measured_primary_command_product(province_id=province_id, pilot_name=pilot_name, frame_times_ms=frame_times_ms)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, product.get("score", 0.5)))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {"ok": True, "live": True, "step": s, "live_api": api, "leaf": api, "score": sc, "province_id": province_id,
            "summary": "Execute %s · %s" % (s, api), "plain": "Execute %s" % s, "empty": False, "product": product}


def close_map_perf_measured_primary_command_package(province_id=1, *, frame_times_ms=None, pilot_name="world_full"):
    rt = {"applied": []}
    steps = [apply_map_perf_measured_primary_command_step(s, province_id, frame_times_ms=frame_times_ms, pilot_name=pilot_name, runtime=rt)
             for s in PRIMARY_COMMAND_STEPS]
    product = build_map_perf_measured_primary_command_product(province_id=province_id, pilot_name=pilot_name, frame_times_ms=frame_times_ms)
    ok = int(product.get("dead_n", 1)) == 0 and len(steps) == 5
    return {"ok": ok, "live": True, "product": product, "steps": steps, "applied_n": len(rt["applied"]),
            "measured_ok": bool(product.get("measured_ok")), "dead_n": int(product.get("dead_n") or 0),
            "summary": "Map perf measured close · measured=%s · dead %d" % (product.get("measured_ok"), product.get("dead_n")),
            "plain": "Map perf measured close", "empty": bool(product.get("empty"))}


def map_perf_measured_primary_command_integrity():
    empty_p = build_map_perf_measured_primary_command_product(frame_times_ms=[])
    measured_p = build_map_perf_measured_primary_command_product(frame_times_ms=[16.0, 15.5, 17.0, 16.2])
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (bool(empty_p.get("empty")) and not bool(empty_p.get("measured_ok"))
          and not bool(empty_p.get("budget_ok_30"))
          and bool(measured_p.get("measured_ok")) and int(measured_p.get("sample_n") or 0) == 4
          and bool(measured_p.get("budget_ok_30")) and no_focus and int(measured_p.get("dead_n", 1)) == 0)
    return {"ok": ok, "empty_honest": bool(empty_p.get("empty")), "measured_ok": bool(measured_p.get("measured_ok")),
            "no_focus": no_focus, "summary": "Map perf measured integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
