"""Strategic AI daily campaign product (major #11).

Runtime campaign loop: multi-faction strategic AI board → budgeted daily apply
queue for AI majors (optional skip player tag). Composes multi_faction product
+ execution integrity — deepens deferred campaign AI beyond panel-only product.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from multi_faction_strategic_ai_product import (  # type: ignore
    MAJOR_TAGS,
    build_multi_faction_strategic_ai_product,
    execute_strategic_ai_step,
    multi_faction_strategic_ai_integrity,
)

PRODUCT_STEPS = ("board", "budget", "apply_ai")

_STEP_META = {
    "board": {
        "action_id": "strategic_ai_daily_board",
        "leaf": "apply_focus",
        "label": "Step 0 — multi-faction AI board",
    },
    "budget": {
        "action_id": "strategic_ai_daily_budget",
        "leaf": "apply_station",
        "label": "Step 1 — budget AI day actions",
    },
    "apply_ai": {
        "action_id": "strategic_ai_daily_apply",
        "leaf": "apply_assault",
        "label": "Step 2 — apply budgeted AI actions",
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


def budget_ai_day_actions(
    factions: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = "",
    max_actions: int = 4,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Select top-urgency AI majors (skip player) into a day apply queue."""
    player = str(player_tag or "").strip().upper()
    ranked: List[Dict[str, Any]] = []
    for f in factions or []:
        if not isinstance(f, Mapping):
            continue
        tag = str(f.get("tag", "")).upper()
        if not tag or (player and tag == player):
            continue
        ranked.append(dict(f))
    ranked.sort(key=lambda r: (-float(r.get("urgency", 0)), str(r.get("tag", ""))))
    cap = max(1, int(max_actions))
    selected = ranked[:cap]
    queue: List[Dict[str, Any]] = []
    for f in selected:
        queue.append(
            {
                "action_id": str(f.get("top_leaf", "apply_station")),
                "province_id": max(1, int(province_id)),
                "score": float(f.get("urgency", 0.5)),
                "enabled": True,
                "label": "AI day · %s · %s" % (f.get("tag"), f.get("top_domain")),
                "faction": str(f.get("tag", "")),
                "domain": str(f.get("top_domain", "")),
                "product_action": "strategic_ai_daily_apply",
                "step": "apply_ai",
            }
        )
    label = "AI day budget · selected %d · skipped_player %s · pool %d" % (
        len(selected),
        player or "—",
        len(ranked),
    )
    return {
        "queue": queue,
        "selected": selected,
        "selected_count": len(selected),
        "pool_count": len(ranked),
        "player_tag": player,
        "max_actions": cap,
        "summary": label,
        "plain": label,
        "empty": len(selected) <= 0,
        "score": _floor(0.4 + 0.1 * len(selected)),
    }


def recommend_daily_ai_step(
    faction_count: int,
    *,
    budget_count: int = 0,
    apply_ready: bool = False,
) -> Dict[str, Any]:
    if faction_count <= 0:
        step = "board"
        reason = "empty board — scan majors"
    elif budget_count <= 0:
        step = "budget"
        reason = "build AI day budget"
    elif apply_ready:
        step = "apply_ai"
        reason = "apply budgeted AI actions"
    else:
        step = "budget"
        reason = "refresh AI budget"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_strategic_ai_daily_campaign_product(
    tags: Optional[Sequence[str]] = None,
    *,
    province_id: int = 1,
    player_tag: str = "GER",
    max_ai_actions: int = 4,
) -> Dict[str, Any]:
    """Daily campaign product wrapping multi-faction strategic AI + day budget."""
    board = build_multi_faction_strategic_ai_product(
        tags or list(MAJOR_TAGS), province_id=province_id
    )
    factions = list(board.get("factions") or [])
    budget = budget_ai_day_actions(
        factions,
        player_tag=player_tag,
        max_actions=max_ai_actions,
        province_id=province_id,
    )
    faction_count = int(board.get("faction_count", len(factions)) or 0)
    budget_count = int(budget.get("selected_count", 0) or 0)
    apply_ready = budget_count > 0
    rec = recommend_daily_ai_step(
        faction_count, budget_count=budget_count, apply_ready=apply_ready
    )

    score = _floor(
        0.4 * _norm(float(board.get("score", 0.55)))
        + 0.35 * min(1.0, budget_count / float(max(1, max_ai_actions)))
        + 0.25 * min(1.0, faction_count / 7.0)
    )

    step_scores = {
        "board": _floor(0.45 + 0.05 * min(7, faction_count)),
        "budget": _floor(0.4 + 0.12 * min(4, budget_count)),
        "apply_ai": _floor(0.5 + 0.1 * min(4, budget_count)),
    }
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    top_leaf = str(board.get("top_leaf", "apply_assault"))
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = str(meta["leaf"])
        if step == "apply_ai" and budget.get("queue"):
            leaf = str((budget["queue"][0] or {}).get("action_id", top_leaf))
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · factions %d · budget %d · score %.2f" % (
            lab,
            faction_count,
            budget_count,
            sc,
        )
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": faction_count > 0 or step == "board",
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
            }
        )
    # Merge budget queue actions
    for q in budget.get("queue") or []:
        if isinstance(q, Mapping):
            apply_queue.append(dict(q))

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "strategic_ai_daily_campaign_product",
            "label": "Run strategic AI daily campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "strategic_ai_daily_board")),
            "label": "Recommended: %s" % rec.get("step", "board"),
            "enabled": True,
        },
        {
            "action_id": "multi_faction_strategic_ai_product",
            "label": "Open multi-faction AI board",
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": bool(r["enabled"]),
                "step": r["step"],
            }
        )

    label = (
        "Strategic AI daily campaign · majors %d · AI budget %d · player %s · top %s · score %.2f"
        % (
            faction_count,
            budget_count,
            player_tag or "—",
            board.get("top_faction", "—"),
            score,
        )
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        str(board.get("summary", "")),
        str(budget.get("summary", "")),
    ]
    for ln in board.get("board_lines") or []:
        plain_lines.append(str(ln))
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "board": board,
        "budget": budget,
        "factions": factions,
        "faction_count": faction_count,
        "budget_count": budget_count,
        "player_tag": str(player_tag or "").upper(),
        "top_faction": str(board.get("top_faction", "")),
        "top_domain": str(board.get("top_domain", "")),
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "ai_day_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": apply_ready,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]♟ Strategic AI daily[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": faction_count <= 0,
        "integration": [
            "strategic_ai_daily_campaign_product",
            "strategic_ai_daily_board",
            "strategic_ai_daily_budget",
            "strategic_ai_daily_apply",
            "major_11",
            "strategic_ai",
            "daily_campaign",
        ],
    }


def execute_strategic_ai_daily_step(
    step: str,
    province_id: int = 1,
    *,
    player_tag: str = "GER",
    max_ai_actions: int = 4,
) -> Dict[str, Any]:
    s = str(step or "board").strip().lower()
    if s.startswith("strategic_ai_daily_"):
        s = s.replace("strategic_ai_daily_", "")
    if s == "apply":
        s = "apply_ai"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_strategic_ai_daily_campaign_product(
        province_id=province_id, player_tag=player_tag, max_ai_actions=max_ai_actions
    )
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
        }
    ]
    if s == "apply_ai":
        q = list((product.get("budget") or {}).get("queue") or q)
    label = "Execute AI daily %s · leaf %s · budget %d · score %.2f" % (
        s,
        leaf,
        int(product.get("budget_count", 0)),
        score,
    )
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]♟ AI daily %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_strategic_ai_daily_step", s, leaf],
    }


def strategic_ai_daily_campaign_integrity() -> Dict[str, Any]:
    product = build_strategic_ai_daily_campaign_product(player_tag="GER", max_ai_actions=4)
    # Player GER skipped → budget from other majors
    steps = [execute_strategic_ai_daily_step(s, 1, player_tag="GER") for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    base = multi_faction_strategic_ai_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("faction_count", 0)) >= 5
        and int(product.get("budget_count", 0)) >= 2
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(base.get("ok", False))
    )
    return {
        "ok": ok,
        "faction_count": int(product.get("faction_count", 0)),
        "budget_count": int(product.get("budget_count", 0)),
        "player_tag": product.get("player_tag", ""),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Strategic AI daily campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_strategic_ai_daily_campaign_product_loop() -> Dict[str, Any]:
    product = build_strategic_ai_daily_campaign_product(player_tag="ENG", max_ai_actions=3)
    full = build_strategic_ai_daily_campaign_product(player_tag="", max_ai_actions=7)
    gate = strategic_ai_daily_campaign_integrity()
    skip_shift = int(full.get("budget_count", 0)) - int(product.get("budget_count", 0))
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3 and skip_shift >= 0
    label = (
        "Close strategic AI daily campaign · budget %d · skip_shift %d · %s"
        % (
            int(product.get("budget_count", 0)),
            skip_shift,
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "skip_shift": skip_shift,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Strategic AI daily campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
