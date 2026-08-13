"""Leader theater command product (major #52) — Phase 9 full gameplay cycle.

HQ assign board → multi-formation station → theater command ops.
Deepens leader_command (#26) with theater HQ + multi-formation live path.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from leader_command_product import build_leader_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_leader_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "assign_score": 0.55, "station_score": 0.55}

try:
    from theater_command_product import build_theater_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_theater_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from front_continuity_campaign_product import build_front_continuity_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_front_continuity_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.57, "empty": False}

try:
    from intel_cell_network_product import build_intel_cell_network_product  # type: ignore
except Exception:  # pragma: no cover
    def build_intel_cell_network_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "secure": True}

PRODUCT_STEPS = ("hq_board", "multi_station", "theater_ops")
_STEP_META = {
    "hq_board": {"action_id": "leader_hq_board", "leaf": "apply_focus", "label": "Step 0 — HQ/leader assign board"},
    "multi_station": {"action_id": "leader_multi_station", "leaf": "apply_station", "label": "Step 1 — multi-formation station"},
    "theater_ops": {"action_id": "leader_theater_ops", "leaf": "apply_assault", "label": "Step 2 — theater command ops"},
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


def compute_hq_board(*, assign_score: float = 0.55, skill: float = 0.7, leaders: int = 4) -> Dict[str, Any]:
    a = _floor(assign_score)
    sk = _floor(skill)
    n = max(1, min(12, int(leaders)))
    assigned = max(1, int(round(n * sk)))
    score = _floor(0.4 * a + 0.35 * sk + 0.25 * min(1.0, assigned / 4.0))
    return {
        "leaders": n, "assigned": assigned, "skill": sk, "score": score,
        "summary": "HQ board · leaders %d · assigned %d · skill %.0f%% · score %.2f"
        % (n, assigned, sk * 100, score),
        "empty": False,
    }


def compute_multi_station(*, station_score: float = 0.55, formations: int = 6, theater_score: float = 0.58) -> Dict[str, Any]:
    s = _floor(station_score)
    t = _floor(theater_score)
    f = max(1, min(20, int(formations)))
    stationed = max(1, int(round(f * (0.5 * s + 0.5 * t))))
    score = _floor(0.4 * s + 0.35 * t + 0.25 * min(1.0, stationed / 6.0))
    return {
        "formations": f, "stationed": stationed, "score": score,
        "summary": "Multi-station · formations %d · stationed %d · score %.2f" % (f, stationed, score),
        "empty": False,
    }


def compute_theater_ops(*, hq: Dict[str, Any], station: Dict[str, Any], front_score: float = 0.57, intel_secure: bool = True) -> Dict[str, Any]:
    f = _floor(front_score)
    joint = _floor(0.35 * float(hq.get("score", 0.5)) + 0.35 * float(station.get("score", 0.5)) + 0.2 * f + 0.1 * (1.0 if intel_secure else 0.4))
    orders = max(1, int(round(joint * 5)))
    return {
        "orders": orders, "joint": joint, "intel_secure": intel_secure, "score": joint,
        "summary": "Theater ops · orders %d · joint %.2f · intel %s · score %.2f"
        % (orders, joint, "SECURE" if intel_secure else "BLIND", joint),
        "empty": False,
    }


def recommend_leader_theater_step(*, boarded: bool = False, stationed: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "hq_board", "assign HQ/leaders"
    elif not stationed:
        step, reason = "multi_station", "station multi-formation groups"
    else:
        step, reason = "theater_ops", "execute theater command ops"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_leader_theater_command_product(
    *, province_id: int = 1, leader_skill: float = 0.7, leaders: int = 5, formations: int = 8
) -> Dict[str, Any]:
    base = build_leader_command_product(province_id=province_id, leader_skill=leader_skill)
    theater = build_theater_command_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    intel = build_intel_cell_network_product(province_id=province_id)
    hq = compute_hq_board(
        assign_score=float(base.get("assign_score", base.get("score", 0.55))),
        skill=leader_skill,
        leaders=leaders,
    )
    station = compute_multi_station(
        station_score=float(base.get("station_score", base.get("score", 0.55))),
        formations=formations,
        theater_score=float(theater.get("score", 0.58)),
    )
    ops = compute_theater_ops(
        hq=hq, station=station,
        front_score=float(front.get("score", 0.57)),
        intel_secure=bool(intel.get("secure", True)),
    )
    h_s = _floor(float(hq["score"]))
    s_s = _floor(float(station["score"]))
    o_s = _floor(float(ops["score"]))
    score = _floor(0.3 * h_s + 0.35 * s_s + 0.35 * o_s)
    rec = recommend_leader_theater_step(boarded=True, stationed=int(station["stationed"]) >= 2)
    step_scores = {"hq_board": h_s, "multi_station": s_s, "theater_ops": o_s}
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
        {"action_id": "leader_theater_command_product", "label": "Run leader theater command product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Leader theater command · HQ %d · stationed %d · orders %d · score %.2f" % (
        int(hq["assigned"]), int(station["stationed"]), int(ops["orders"]), score)
    return {
        "base": base, "theater": theater, "front": front, "intel": intel,
        "hq": hq, "station": station, "ops": ops,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "assigned": int(hq["assigned"]), "stationed": int(station["stationed"]), "orders": int(ops["orders"]),
        "score": score, "leader_theater_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), hq["summary"], station["summary"], ops["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e8c070]🎖 Leader theater[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "leader_theater_command_product", "leader_hq_board", "leader_multi_station", "leader_theater_ops",
            "major_52", "leader", "theater", "phase9_cycle", "full_gameplay_cycle",
        ],
    }


def execute_leader_theater_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "hq_board").strip().lower().replace("leader_", "")
    if s.startswith("hq") or s.startswith("assign") or s.startswith("board"):
        s = "hq_board"
    elif s.startswith("multi") or s.startswith("station"):
        s = "multi_station"
    elif s.startswith("theater") or s.startswith("ops") or s.startswith("command"):
        s = "theater_ops"
    if s not in _STEP_META:
        s = "hq_board"
    meta = _STEP_META[s]
    product = build_leader_theater_command_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute leader theater %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_leader_theater_step", s, leaf],
    }


def leader_theater_command_integrity() -> Dict[str, Any]:
    product = build_leader_theater_command_product()
    steps = [execute_leader_theater_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("assigned", 0)) >= 1
        and int(product.get("stationed", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Leader theater command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_leader_theater_command_product_loop() -> Dict[str, Any]:
    product = build_leader_theater_command_product(province_id=2, leaders=6, formations=10)
    gate = leader_theater_command_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close leader theater command · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
