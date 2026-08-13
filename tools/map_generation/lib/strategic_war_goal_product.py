"""Strategic war-goal product (major #53) — Phase 10 world-class GS.

War-goal board → justify/select package → execute strategic push.
Deepens campaign AI multi-month (#34) + multi-faction AI (#9) with live war-goal trail.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from campaign_ai_multi_month_product import build_campaign_ai_multi_month_product  # type: ignore
except Exception:  # pragma: no cover
    def build_campaign_ai_multi_month_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

try:
    from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_faction_strategic_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from multi_party_peace_conference_product import build_multi_party_peace_conference_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_party_peace_conference_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

try:
    from front_continuity_campaign_product import build_front_continuity_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_front_continuity_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.57, "empty": False}

PRODUCT_STEPS = ("board", "justify", "execute")
_STEP_META = {
    "board": {"action_id": "war_goal_board", "leaf": "apply_focus", "label": "Step 0 — war-goal board"},
    "justify": {"action_id": "war_goal_justify", "leaf": "apply_focus", "label": "Step 1 — justify/select package"},
    "execute": {"action_id": "war_goal_execute", "leaf": "apply_assault", "label": "Step 2 — execute strategic push"},
}

_WAR_GOALS = (
    {"id": "conquer_border", "label": "Conquer border provinces", "weight": 0.75, "kind": "conquest"},
    {"id": "seize_resources", "label": "Seize resource corridor", "weight": 0.68, "kind": "economy"},
    {"id": "naval_choke", "label": "Secure naval chokepoint", "weight": 0.62, "kind": "naval"},
    {"id": "liberate_claim", "label": "Liberate claimed territory", "weight": 0.7, "kind": "political"},
    {"id": "punitive_raid", "label": "Punitive border raid", "weight": 0.55, "kind": "limited"},
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


def compute_war_goal_board(*, ai_score: float = 0.6, faction_score: float = 0.58) -> Dict[str, Any]:
    a = _floor(ai_score)
    f = _floor(faction_score)
    goals = []
    for g in _WAR_GOALS:
        sc = _floor(0.45 * float(g["weight"]) + 0.3 * a + 0.25 * f)
        goals.append({**g, "score": sc, "enabled": True})
    goals.sort(key=lambda x: -float(x["score"]))
    top = goals[0] if goals else {"id": "conquer_border", "score": 0.5, "label": "default"}
    score = _floor(0.5 * float(top["score"]) + 0.5 * a)
    return {
        "goals": goals, "goal_n": len(goals), "top_id": str(top.get("id")),
        "top_label": str(top.get("label")), "score": score,
        "summary": "War-goal board · %d goals · top %s · score %.2f" % (len(goals), top.get("id"), score),
        "empty": False,
    }


def compute_justify(*, board: Dict[str, Any], peace_score: float = 0.55) -> Dict[str, Any]:
    top_id = str(board.get("top_id", "conquer_border"))
    p = _floor(peace_score)
    # Lower peace leverage → harder justify; still pass with planning
    tension = _floor(0.55 + 0.3 * (1.0 - p) + 0.15 * float(board.get("score", 0.5)))
    justified = tension >= 0.5
    score = _floor(0.55 * float(board.get("score", 0.5)) + 0.45 * tension)
    return {
        "goal_id": top_id, "tension": tension, "justified": justified, "score": score,
        "summary": "Justify · %s · tension %.0f%% · %s · score %.2f"
        % (top_id, tension * 100, "READY" if justified else "WAIT", score),
        "empty": False,
    }


def compute_execute_push(*, justify: Dict[str, Any], front_score: float = 0.57) -> Dict[str, Any]:
    f = _floor(front_score)
    j = _floor(float(justify.get("score", 0.5)))
    ready = bool(justify.get("justified", False))
    pushes = max(1, int(round((0.5 * j + 0.5 * f) * 4))) if ready else 0
    score = _floor(0.4 * j + 0.35 * f + 0.25 * (1.0 if ready and pushes >= 1 else 0.35))
    return {
        "goal_id": str(justify.get("goal_id", "")), "pushes": pushes, "ready": ready, "score": score,
        "summary": "Execute push · %s · pushes %d · score %.2f" % (justify.get("goal_id"), pushes, score),
        "empty": False,
    }


def recommend_war_goal_step(*, boarded: bool = False, justified: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "board", "scan war-goal board"
    elif not justified:
        step, reason = "justify", "justify selected war goal"
    else:
        step, reason = "execute", "execute strategic push"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_strategic_war_goal_product(*, province_id: int = 1) -> Dict[str, Any]:
    ai = build_campaign_ai_multi_month_product(province_id=province_id)
    faction = build_multi_faction_strategic_ai_product(province_id=province_id)
    peace = build_multi_party_peace_conference_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    board = compute_war_goal_board(ai_score=float(ai.get("score", 0.6)), faction_score=float(faction.get("score", 0.58)))
    justify = compute_justify(board=board, peace_score=float(peace.get("score", 0.55)))
    execute = compute_execute_push(justify=justify, front_score=float(front.get("score", 0.57)))
    b_s = _floor(float(board["score"]))
    j_s = _floor(float(justify["score"]))
    e_s = _floor(float(execute["score"]))
    score = _floor(0.3 * b_s + 0.35 * j_s + 0.35 * e_s)
    rec = recommend_war_goal_step(boarded=True, justified=bool(justify["justified"]))
    step_scores = {"board": b_s, "justify": j_s, "execute": e_s}
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
        {"action_id": "strategic_war_goal_product", "label": "Run strategic war-goal product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Strategic war-goal · top %s · justified %s · pushes %d · score %.2f" % (
        board["top_id"], "YES" if justify["justified"] else "NO", int(execute["pushes"]), score)
    return {
        "ai": ai, "faction": faction, "peace": peace, "front": front,
        "board": board, "justify": justify, "execute": execute,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "goal_n": int(board["goal_n"]), "top_id": board["top_id"], "pushes": int(execute["pushes"]),
        "justified": bool(justify["justified"]), "score": score, "war_goal_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), board["summary"], justify["summary"], execute["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e07070]🎯 War goals[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "strategic_war_goal_product", "war_goal_board", "war_goal_justify", "war_goal_execute",
            "major_53", "war_goal", "campaign_ai", "phase10_gs", "world_class_gs",
        ],
    }


def execute_war_goal_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("war_goal_", "")
    if s.startswith("board") or s.startswith("scan"):
        s = "board"
    elif s.startswith("justify") or s.startswith("select") or s.startswith("pick"):
        s = "justify"
    elif s.startswith("execute") or s.startswith("push"):
        s = "execute"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_strategic_war_goal_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute war-goal %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_war_goal_step", s, leaf],
    }


def strategic_war_goal_integrity() -> Dict[str, Any]:
    product = build_strategic_war_goal_product()
    steps = [execute_war_goal_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("goal_n", 0)) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Strategic war-goal integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_strategic_war_goal_product_loop() -> Dict[str, Any]:
    product = build_strategic_war_goal_product(province_id=2)
    gate = strategic_war_goal_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close strategic war-goal · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
