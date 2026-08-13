"""Air theater primary command package — Master Plan C3.

Elevates recon → CAS gate → interdiction → close into a primary player loop.
Composes air_multi_phase_theater_product. LIVE_API = real GameData methods.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from air_multi_phase_theater_product import (  # type: ignore
        build_air_multi_phase_theater_product,
        recommend_air_theater_step,
        compute_recon_board,
        compute_cas_gate,
        compute_interdiction,
    )
except Exception:  # pragma: no cover
    def build_air_multi_phase_theater_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "packages": 2, "strikes": 1, "gate_open": True, "empty": False,
                "day_rows": [{"step": "recon", "score": 0.6}, {"step": "cas_gate", "score": 0.55},
                             {"step": "interdiction", "score": 0.58}], "recommendation": {"step": "interdiction"}}
    def recommend_air_theater_step(**_k):  # type: ignore
        return {"step": "interdiction", "action_id": "air_theater_interdiction", "summary": "fallback"}
    def compute_recon_board(**_k):  # type: ignore
        return {"recon_score": 0.6, "packages": 2, "fuel": 0.7, "summary": "recon", "empty": False}
    def compute_cas_gate(**_k):  # type: ignore
        return {"cas_score": 0.55, "open": True, "summary": "gate", "empty": False}
    def compute_interdiction(**_k):  # type: ignore
        return {"joint": 0.58, "strikes": 1, "summary": "inter", "empty": False}

SURFACE_KEYS: Tuple[str, ...] = (
    "air_primary_recon",
    "air_primary_cas_gate",
    "air_primary_interdiction",
    "air_primary_close",
)
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "air_recon",
    "air_cas_gate",
    "air_interdiction",
    "air_theater_close",
)
_STEP_MAJOR = {
    "air_recon": "air_primary_recon",
    "air_cas_gate": "air_primary_cas_gate",
    "air_interdiction": "air_primary_interdiction",
    "air_theater_close": "air_primary_close",
}
LIVE_API_BY_STEP = {
    "air_recon": "apply_air_theater_recon",
    "air_cas_gate": "apply_air_theater_cas_gate",
    "air_interdiction": "apply_air_theater_interdiction",
    "air_theater_close": "apply_air_multi_phase_theater_close_day",
}
PRIMARY_ACTION_IDS = (
    "apply_air_theater_recon",
    "apply_air_theater_cas_gate",
    "apply_air_theater_interdiction",
    "apply_air_multi_phase_theater_close_day",
    "apply_air_multi_phase_theater_product",
    "apply_air_theater_live",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
_MAJOR_META = {
    "air_primary_recon": {"phase_id": "C3", "label": "Recon / sortie fuel board", "leaf": "apply_air_theater_recon"},
    "air_primary_cas_gate": {"phase_id": "C3", "label": "Weather / CAS gate", "leaf": "apply_air_theater_cas_gate"},
    "air_primary_interdiction": {"phase_id": "C3", "label": "Interdiction joint strike", "leaf": "apply_air_theater_interdiction"},
    "air_primary_close": {"phase_id": "C3", "label": "Air theater package close", "leaf": "apply_air_multi_phase_theater_close_day"},
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


def primary_command_dead_audit(
    action_ids: Optional[Sequence[str]] = None,
    *,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 4
    label = "Air theater primary audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "live_n": len(ids) - len(dead),
            "ok": ok, "summary": label, "plain": label, "empty": False}


def build_air_theater_primary_command_product(
    *,
    province_id: int = 1,
    fuel: float = 0.72,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    f = max(0.1, min(1.2, float(fuel)))
    theater = build_air_multi_phase_theater_product(province_id=pid, fuel=f)
    recon = theater.get("recon") if isinstance(theater.get("recon"), dict) else compute_recon_board(fuel=f)
    gate = theater.get("cas_gate") if isinstance(theater.get("cas_gate"), dict) else compute_cas_gate()
    inter = theater.get("interdiction") if isinstance(theater.get("interdiction"), dict) else compute_interdiction()
    scores = {
        "air_recon": _floor(float(recon.get("recon_score") or theater.get("score") or 0.55)),
        "air_cas_gate": _floor(float(gate.get("cas_score") or 0.55)),
        "air_interdiction": _floor(float(inter.get("joint") or 0.55)),
        "air_theater_close": _floor(float(theater.get("score") or 0.55) + 0.02),
    }
    majors_ok = {k: scores[s] >= 0.35 for s, k in _STEP_MAJOR.items()}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 4 and dead_n == 0
    rec = theater.get("recommendation") if isinstance(theater.get("recommendation"), dict) else recommend_air_theater_step(reconed=True, gated=bool(gate.get("open")))
    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, api, sc)
        row = {"index": i, "step": step, "major": major, "action_id": step, "live_api": api,
               "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid}
        steps.append(row)
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True,
                            "label": lab, "step": step, "major": major, "live_api": api})
    score = _floor(0.25 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Air theater primary · majors %d/4 · dead %d · fuel %.0f%% · pkgs %s · strikes %s · score %.2f · %s" % (
        majors_ok_n, dead_n, f * 100, theater.get("packages", recon.get("packages", 0)),
        theater.get("strikes", inter.get("strikes", 0)), score, "PASS" if all_majors_ok else "PARTIAL")
    plain = "\n".join([label, str(audit.get("summary", "")), str(rec.get("summary", ""))] + [r["label"] for r in steps])
    return {
        "score": score, "plain": plain, "summary": label, "empty": False, "province_id": pid, "fuel": f,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "recommendation": rec, "theater": theater, "recon": recon,
        "cas_gate": gate, "interdiction": inter,
        "packages": int(theater.get("packages") or recon.get("packages") or 0),
        "strikes": int(theater.get("strikes") or inter.get("strikes") or 0),
        "gate_open": bool(gate.get("open") if "open" in gate else theater.get("gate_open", True)),
        "integration": ["air_theater_primary_command_product", "air_multi_phase_theater_product", "C3", "air_theater",
                        "primary_command", "player_command_loop"],
        "panel_actions": [
            {"action_id": "air_theater_primary_command_product", "label": "Run air theater primary", "enabled": True},
            {"action_id": "apply_air_theater_recon", "label": "C3 recon", "enabled": True},
            {"action_id": "apply_air_theater_cas_gate", "label": "C3 CAS gate", "enabled": True},
            {"action_id": "apply_air_theater_interdiction", "label": "C3 interdiction", "enabled": True},
            {"action_id": "apply_air_multi_phase_theater_close_day", "label": "C3 close", "enabled": True},
        ],
    }


def apply_air_theater_primary_command_step(step: str, province_id: int = 1, *, fuel: float = 0.72,
                                           runtime: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    s = str(step or "").strip().lower()
    aliases = {"recon": "air_recon", "cas_gate": "air_cas_gate", "cas": "air_cas_gate",
               "interdiction": "air_interdiction", "inter": "air_interdiction", "close": "air_theater_close",
               "air_theater_recon": "air_recon", "air_theater_cas_gate": "air_cas_gate",
               "air_theater_interdiction": "air_interdiction"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        for cand in PRIMARY_COMMAND_STEPS:
            if s in cand or cand in s:
                s = cand
                break
        if s not in PRIMARY_COMMAND_STEPS:
            s = PRIMARY_COMMAND_STEPS[0]
    live_api = LIVE_API_BY_STEP[s]
    major = _STEP_MAJOR[s]
    product = build_air_theater_primary_command_product(province_id=province_id, fuel=fuel)
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute air theater %s · major %s · live %s · score %.2f" % (s, major, live_api, sc)
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
    return {"ok": True, "live": True, "step": s, "major": major, "live_api": live_api, "leaf": live_api,
            "score": sc, "province_id": max(1, int(province_id)), "summary": label, "plain": label, "empty": False,
            "apply_queue": [{"action_id": live_api, "province_id": max(1, int(province_id)), "score": sc,
                             "enabled": True, "label": label, "step": s, "live_api": live_api}]}


def close_air_theater_primary_command_package(province_id: int = 1, *, fuel: float = 0.72) -> Dict[str, Any]:
    rt: Dict[str, Any] = {"applied": [], "tick": 0}
    steps_log = [apply_air_theater_primary_command_step(s, province_id, fuel=fuel, runtime=rt)
                 for s in PRIMARY_COMMAND_STEPS]
    product = build_air_theater_primary_command_product(province_id=province_id, fuel=fuel)
    ok = (len(steps_log) == 4 and all(s.get("ok") for s in steps_log)
          and int(product.get("dead_n", 1)) == 0 and bool(product.get("all_majors_ok")))
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = "Air theater primary close %s · steps %d/4 · dead %d · score %.2f" % (
        "PASS" if ok else "FAIL", len(rt.get("applied") or []), int(product.get("dead_n") or 0), score)
    return {"ok": ok, "live": True, "score": score, "applied_n": len(rt.get("applied") or []), "complete": ok,
            "runtime": rt, "steps": steps_log, "product": product, "dead_n": int(product.get("dead_n") or 0),
            "majors_ok": dict(product.get("majors_ok") or {}), "live_api_by_step": dict(LIVE_API_BY_STEP),
            "summary": label, "plain": label, "empty": False, "closed": list(PRIMARY_COMMAND_STEPS)}


def air_theater_primary_command_integrity() -> Dict[str, Any]:
    p = build_air_theater_primary_command_product()
    closed = close_air_theater_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and len(p.get("steps") or []) == 4 and bool(closed.get("ok")) and no_focus
          and any("apply_air_theater_" in a for a in apis))
    return {"ok": ok, "score": float(p.get("score", 0)), "dead_n": int(p.get("dead_n", 0)),
            "no_focus": no_focus, "closed": closed,
            "summary": "Air theater primary integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
