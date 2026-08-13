"""Inspector decision product (high-value) — collapse cognitive load.

Primary decisions strip · secondary budget collapse · recommend leaf apply.
Composes execution/campaign decision strips + product-depth chip budget.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from inspector_product_depth import budget_product_depth_chips, chip_priority  # type: ignore
except Exception:  # pragma: no cover
    def chip_priority(chip_id: str) -> int:  # type: ignore
        return 30

    def budget_product_depth_chips(chips, *, max_chips=8, compact=True, always_ids=None):  # type: ignore
        rows = [dict(c) for c in (chips or []) if isinstance(c, Mapping)]
        sel = rows[: max(0, int(max_chips))] if compact else rows
        return {
            "chips": sel,
            "shown": len(sel),
            "total": len(rows),
            "hidden": max(0, len(rows) - len(sel)),
            "hidden_ids": [str(c.get("id", "")) for c in rows[len(sel) :]],
            "summary": "budget %d/%d" % (len(sel), len(rows)),
            "empty": not sel,
        }


PRODUCT_STEPS = ("primary_strip", "collapse_budget", "apply_decision")

_STEP_META = {
    "primary_strip": {
        "action_id": "inspector_product_primary",
        "leaf": "apply_station",
        "label": "Step 0 — primary decision strip",
    },
    "collapse_budget": {
        "action_id": "inspector_product_collapse",
        "leaf": "refresh_queue",
        "label": "Step 1 — collapse secondary chips",
    },
    "apply_decision": {
        "action_id": "inspector_product_apply",
        "leaf": "apply_supply",
        "label": "Step 2 — apply recommended decision",
    },
}

# Major product chips preferred in primary band
PRIMARY_CHIP_IDS = (
    "multi_phase_combat_product",
    "fleet_multi_day_autonomy_product",
    "medium_tank_oob_product",
    "agent_campaign_product",
    "hh_multi_month_agenda_product",
    "naval_skim",
    "combat_campaign_day",
    "fleet_campaign_day",
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


def _demo_chips() -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for i, cid in enumerate(PRIMARY_CHIP_IDS):
        out.append(
            {
                "id": cid,
                "bbcode": "[chip]%s[/chip]" % cid,
                "priority": 100 - i,
            }
        )
    # flood of secondary day chips
    for n in range(12):
        out.append(
            {
                "id": "day_noise_%d" % n,
                "bbcode": "day package noise %d" % n,
                "priority": 20,
            }
        )
    return out


def recommend_inspector_step(
    shown: int,
    hidden: int,
    *,
    primary_count: int = 0,
) -> Dict[str, Any]:
    if primary_count <= 0 or shown <= 0:
        step = "primary_strip"
        reason = "build primary decision strip"
    elif hidden >= 3:
        step = "collapse_budget"
        reason = "collapse secondary chips (high hidden)"
    else:
        step = "apply_decision"
        reason = "apply recommended leaf decision"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_inspector_decision_product(
    chips: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    province_id: int = 1,
    max_primary: int = 6,
    max_chips: int = 8,
) -> Dict[str, Any]:
    """Inspector decision product: primary strip + budget collapse + apply path."""
    use_chips: List[Dict[str, Any]] = (
        [dict(c) for c in chips if isinstance(c, Mapping)]
        if chips is not None
        else _demo_chips()
    )
    # Boost major product priorities
    for c in use_chips:
        cid = str(c.get("id", ""))
        if cid in PRIMARY_CHIP_IDS:
            c["priority"] = max(int(c.get("priority", 0) or 0), 110 - list(PRIMARY_CHIP_IDS).index(cid))

    budget = budget_product_depth_chips(
        use_chips, max_chips=max_chips, compact=True, always_ids=list(PRIMARY_CHIP_IDS[:4])
    )
    selected = list(budget.get("chips") or [])
    shown = int(budget.get("shown", len(selected)) or 0)
    hidden = int(budget.get("hidden", 0) or 0)
    total = int(budget.get("total", len(use_chips)) or 0)

    primary: List[Dict[str, Any]] = []
    for c in selected:
        cid = str(c.get("id", ""))
        if cid in PRIMARY_CHIP_IDS or int(c.get("priority", 0)) >= 80:
            primary.append(c)
        if len(primary) >= max_primary:
            break
    if not primary and selected:
        primary = selected[: max(1, min(3, max_primary))]

    primary_count = len(primary)
    collapse_ratio = hidden / float(max(1, total))
    score = _floor(
        0.35 * min(1.0, primary_count / 4.0)
        + 0.3 * min(1.0, shown / float(max(1, max_chips)))
        + 0.2 * min(1.0, collapse_ratio * 2.0)
        + 0.15 * (0.8 if hidden >= 2 else 0.4)
    )

    rec = recommend_inspector_step(shown, hidden, primary_count=primary_count)

    # Decision lines for strip
    decision_lines = [str(c.get("id", "")) for c in primary[:6]]
    if not decision_lines:
        decision_lines = ["station basing", "supply sustain", "inspect collapse"]

    step_scores = {
        "primary_strip": _floor(0.5 + 0.1 * min(4, primary_count)),
        "collapse_budget": _floor(0.45 + 0.15 * min(1.0, collapse_ratio * 3)),
        "apply_decision": _floor(0.5 + 0.05 * shown),
    }
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        label = str(meta["label"])
        if recommended:
            label = "★ " + label
        label = "%s · score %.2f" % (label, sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": meta["leaf"],
            "label": label,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": label,
                "step": step,
                "product_action": meta["action_id"],
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "inspector_decision_product",
            "label": "Run inspector decision product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "inspector_product_primary")),
            "label": "Recommended: %s" % rec.get("step", "primary_strip"),
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
        "Inspector decision product · primary %d · shown %d/%d · hidden %d · score %.2f"
        % (primary_count, shown, total, hidden, score)
    )
    plain_lines = [label, str(rec.get("summary", "")), "primary: " + ", ".join(decision_lines)]
    plain_lines.append(str(budget.get("summary", "")))
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "budget": budget,
        "primary": primary,
        "primary_count": primary_count,
        "decision_lines": decision_lines,
        "shown": shown,
        "hidden": hidden,
        "total": total,
        "collapse_ratio": collapse_ratio,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "inspector_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": primary_count > 0,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]◆ Inspector decision[/color] [color=#8899aa]%s[/color]" % label,
        "empty": total <= 0,
        "integration": [
            "inspector_decision_product",
            "inspector_product_primary",
            "inspector_product_collapse",
            "inspector_product_apply",
            "major_7",
        ],
    }


def execute_inspector_product_step(
    step: str,
    province_id: int = 1,
    *,
    chips: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    s = str(step or "primary_strip").strip().lower()
    if s.startswith("inspector_product_"):
        s = s.replace("inspector_product_", "")
        if s == "primary":
            s = "primary_strip"
        elif s == "collapse":
            s = "collapse_budget"
        elif s == "apply":
            s = "apply_decision"
    if s not in _STEP_META:
        s = "primary_strip"
    meta = _STEP_META[s]
    product = build_inspector_decision_product(chips, province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": meta["leaf"],
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute inspector %s · leaf %s · score %.2f · #%d" % (
        s,
        meta["leaf"],
        score,
        max(1, int(province_id)),
    )
    return {
        "step": s,
        "leaf_action": meta["leaf"],
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]◆ Inspector %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_inspector_product_step", s, meta["leaf"]],
    }


def inspector_decision_product_integrity() -> Dict[str, Any]:
    product = build_inspector_decision_product()
    thin = build_inspector_decision_product(
        [{"id": "day_noise_0", "bbcode": "noise", "priority": 10}]
    )
    steps = [execute_inspector_product_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("primary_count", 0)) >= 2
        and int(product.get("hidden", 0)) >= 2
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and float(product.get("score", 0)) >= float(thin.get("score", 0))
    )
    return {
        "ok": ok,
        "primary_count": int(product.get("primary_count", 0)),
        "hidden": int(product.get("hidden", 0)),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Inspector decision product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_inspector_decision_product_loop() -> Dict[str, Any]:
    product = build_inspector_decision_product()
    gate = inspector_decision_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close inspector decision product · primary %d · hidden %d · %s"
        % (
            int(product.get("primary_count", 0)),
            int(product.get("hidden", 0)),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Inspector decision product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
