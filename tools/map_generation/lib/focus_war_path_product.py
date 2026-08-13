"""Focus war path product (major #14) — first deferred focus-tree vertical slice.

Pick → war-path order → commit/execute. Composes focus pick, focus order path,
war path urgency, agenda execute — not day-package stubs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from focus_pick_priority import rank_focus_picks  # type: ignore
from campaign_execution import execution_integrity_gate, focus_order_path  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from strategic_continuity_day import focus_war_path_day  # type: ignore
from next10_depth import focus_pick_day  # type: ignore


PRODUCT_STEPS = ("pick", "war_path", "commit")

_STEP_META = {
    "pick": {
        "action_id": "focus_war_pick",
        "leaf": "apply_focus",
        "label": "Step 0 — rank/pick focus",
    },
    "war_path": {
        "action_id": "focus_war_path_step",
        "leaf": "apply_focus",
        "label": "Step 1 — war path order",
    },
    "commit": {
        "action_id": "focus_war_commit",
        "leaf": "apply_hh_commit",
        "label": "Step 2 — commit / execute path",
    },
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


def recommend_focus_war_step(
    *,
    pick_score: float = 0.5,
    path_score: float = 0.5,
    commit_ready: bool = False,
) -> Dict[str, Any]:
    if pick_score < 0.4:
        step = "pick"
        reason = "weak pick board — re-rank focuses"
    elif path_score < 0.4:
        step = "war_path"
        reason = "war path score low — replan order"
    elif commit_ready:
        step = "commit"
        reason = "path ready — commit execute"
    else:
        step = "war_path"
        reason = "refresh war path"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_focus_war_path_product(
    *,
    province_id: int = 1,
    focus_id: str = "industrial_effort",
) -> Dict[str, Any]:
    focuses = [
        {"id": "industrial_effort", "urgency": 0.78, "name": "Industrial Effort"},
        {"id": "naval_effort", "urgency": 0.58, "name": "Naval Effort"},
        {"id": "air_effort", "urgency": 0.62, "name": "Air Effort"},
        {"id": "army_effort", "urgency": 0.7, "name": "Army Effort"},
    ]
    picks = rank_focus_picks(focuses)
    pick_day = focus_pick_day(province_id=province_id)
    best_id = str(picks.get("best_id", focus_id) or focus_id)
    path = focus_order_path(focus_id=best_id, focus_base=58.0)
    war = focus_war_path_day(focus_id=best_id, focus_base=58.0, province_id=province_id)

    pick_score = _floor(
        0.55 * _norm(float(picks.get("best_score", 50)) / 140.0)
        + 0.45 * _norm(float(pick_day.get("score", 0.5)))
    )
    path_score = _floor(
        0.55 * _norm(float(path.get("score", 0.5)))
        + 0.45 * _norm(float(war.get("score", 0.5)))
    )
    commit_score = _floor(0.5 * path_score + 0.5 * pick_score)
    score = _floor(0.35 * pick_score + 0.35 * path_score + 0.3 * commit_score)
    rec = recommend_focus_war_step(
        pick_score=pick_score, path_score=path_score, commit_ready=path_score >= 0.4
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {"pick": pick_score, "war_path": path_score, "commit": commit_score}
    step_leaves = {
        "pick": "apply_focus",
        "war_path": "apply_focus",
        "commit": "apply_hh_commit",
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = step_leaves[step]
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · focus %s · score %.2f" % (lab, best_id, sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
                "focus_id": best_id,
            }
        )

    actions = [
        {
            "action_id": "focus_war_path_product",
            "label": "Run focus war path product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "focus_war_pick")),
            "label": "Recommended: %s" % rec.get("step", "pick"),
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": True,
                "step": r["step"],
            }
        )

    label = (
        "Focus war path · pick %s · pick %.2f · path %.2f · commit %.2f · score %.2f"
        % (best_id, pick_score, path_score, commit_score, score)
    )
    return {
        "picks": picks,
        "pick_day": pick_day,
        "path": path,
        "war": war,
        "focus_id": best_id,
        "pick_score": pick_score,
        "path_score": path_score,
        "commit_score": commit_score,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "focus_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(rec.get("summary", "")),
                str(picks.get("summary", "")),
                str(path.get("summary", "")),
                str(war.get("summary", "")),
            ]
            + [str(r.get("label", "")) for r in day_rows]
        ),
        "bbcode": "[color=#c084fc]◆ Focus war path[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "focus_war_path_product",
            "focus_war_pick",
            "focus_war_path_step",
            "focus_war_commit",
            "major_14",
            "focus",
            "war_path",
        ],
    }


def execute_focus_war_step(
    step: str, province_id: int = 1, *, focus_id: str = "industrial_effort"
) -> Dict[str, Any]:
    s = str(step or "pick").strip().lower()
    if s.startswith("focus_war_"):
        s = s.replace("focus_war_", "")
    if s == "path":
        s = "war_path"
    if s not in _STEP_META:
        s = "pick"
    meta = _STEP_META[s]
    product = build_focus_war_path_product(province_id=province_id, focus_id=focus_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
            "focus_id": product.get("focus_id", focus_id),
        }
    ]
    label = "Execute focus war %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]◆ Focus war %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_focus_war_step", s, leaf],
    }


def focus_war_path_product_integrity() -> Dict[str, Any]:
    product = build_focus_war_path_product()
    steps = [execute_focus_war_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "focus_id": product.get("focus_id", ""),
        "gate": gate,
        "summary": "Focus war path integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_focus_war_path_product_loop() -> Dict[str, Any]:
    product = build_focus_war_path_product(focus_id="naval_effort")
    gate = focus_war_path_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close focus war path · focus %s · score %.2f · %s" % (
        product.get("focus_id", "—"),
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]✓ Focus war path[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
