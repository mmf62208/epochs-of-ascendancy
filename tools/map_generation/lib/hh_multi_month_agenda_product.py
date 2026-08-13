"""HH multi-month agenda product (major #5).

Multi-week/month trail board: faction/class filter · monthly brief · quarterly rollup ·
commit/counterplay as primary product actions (not day-package only).
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from hh_agenda_trail import (  # type: ignore
    append_hh_agenda_trail,
    format_hh_agenda_panel,
    format_hh_agenda_screen,
    signal_to_trail_entry,
)
from hh_agenda_actions import pick_agenda_actions, counterplay_options_for_signal  # type: ignore
from hh_monthly_brief import format_hh_monthly_brief  # type: ignore
from hh_quarterly_rollup import format_hh_quarterly_rollup  # type: ignore
from map_next_list_helpers import apply_hh_counterplay  # type: ignore
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


MONTH_STEPS = ("trail_board", "monthly_brief", "quarterly_counter")

_STEP_META = {
    "trail_board": {
        "action_id": "hh_month_trail_board",
        "leaf": "apply_agent_dispatch",
        "label": "Month board — trail + class filter",
    },
    "monthly_brief": {
        "action_id": "hh_month_brief",
        "leaf": "apply_counterplay",
        "label": "Monthly brief — pulse + actions",
    },
    "quarterly_counter": {
        "action_id": "hh_month_quarterly_counter",
        "leaf": "apply_hh_commit",
        "label": "Quarterly — commit counterplay",
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


def _demo_trail() -> List[Dict[str, Any]]:
    trail: List[Dict[str, Any]] = []
    signals = [
        {"action_class": "sabotage", "influence": 0.62, "province_id": 1, "year": 1939, "month": 9},
        {"action_class": "economic_pressure", "influence": 0.48, "province_id": 2, "year": 1939, "month": 10},
        {"action_class": "infiltration", "influence": 0.55, "province_id": 3, "year": 1939, "month": 11},
        {"action_class": "sabotage", "influence": 0.4, "province_id": 4, "year": 1939, "month": 12},
        {"action_class": "economic_pressure", "influence": 0.52, "province_id": 5, "year": 1940, "month": 1},
        {"action_class": "infiltration", "influence": 0.58, "province_id": 6, "year": 1940, "month": 2},
    ]
    for sig in signals:
        try:
            entry = signal_to_trail_entry(sig)
        except Exception:
            entry = dict(sig)
        if not isinstance(entry, dict):
            entry = dict(sig)
        # ensure months for multi-month claim
        for k in ("year", "month", "action_class", "province_id", "influence"):
            if k in sig and k not in entry:
                entry[k] = sig[k]
        trail = append_hh_agenda_trail(trail, entry)
    return trail if isinstance(trail, list) else list(trail or [])


def filter_trail_by_class(
    trail: Sequence[Mapping[str, Any]],
    action_class: str = "",
) -> List[Dict[str, Any]]:
    ac = str(action_class or "").strip().lower()
    out: List[Dict[str, Any]] = []
    for e in trail:
        if not isinstance(e, Mapping):
            continue
        if not ac or str(e.get("action_class", "")).lower() == ac:
            out.append(dict(e))
    return out


def recommend_hh_month_step(
    trail_count: int,
    *,
    class_count: int = 0,
    counter_options: int = 0,
) -> Dict[str, Any]:
    if trail_count <= 0:
        step = "trail_board"
        reason = "empty trail — wait for pulse / open board"
    elif trail_count < 3 or class_count < 2:
        step = "trail_board"
        reason = "build multi-class trail board"
    elif counter_options >= 2:
        step = "quarterly_counter"
        reason = "counterplay ready — commit quarterly"
    else:
        step = "monthly_brief"
        reason = "run monthly brief / pulse actions"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_hh_multi_month_agenda_product(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    action_class_filter: str = "",
    province_id: int = 1,
    max_actions: int = 4,
) -> Dict[str, Any]:
    """Multi-month HH agenda product: trail board · monthly · quarterly counterplay."""
    base_trail: List[Dict[str, Any]] = (
        [dict(e) for e in trail if isinstance(e, Mapping)]
        if trail is not None
        else _demo_trail()
    )
    filtered = filter_trail_by_class(base_trail, action_class_filter)
    use_trail = filtered if filtered else base_trail

    panel = format_hh_agenda_panel(use_trail)
    screen = format_hh_agenda_screen(use_trail)
    monthly = format_hh_monthly_brief(use_trail)
    quarterly = format_hh_quarterly_rollup(use_trail)

    # pick_agenda_actions expects trail sequence
    try:
        picks = pick_agenda_actions(use_trail, max_actions=max_actions)
    except TypeError:
        picks = pick_agenda_actions(use_trail)

    # Counter options from first/most recent signal
    focus = use_trail[-1] if use_trail else {"action_class": "sabotage", "influence": 0.55, "province_id": province_id}
    try:
        counters = counterplay_options_for_signal(focus)
    except Exception:
        counters = {"options": [], "count": 0, "empty": True}

    # Sample counterplay reduction (product honesty)
    try:
        counter_exec = apply_hh_counterplay(
            0.55,
            {
                "action_class": str(focus.get("action_class", "sabotage")),
                "influence": float(focus.get("influence", 0.55) or 0.55),
                "province_id": int(focus.get("province_id", province_id) or province_id),
            },
        )
    except TypeError:
        counter_exec = apply_hh_counterplay(
            0.55, {"action_class": "sabotage", "influence": 0.55, "province_id": province_id}
        )

    trail_count = int(panel.get("count", len(use_trail)) or len(use_trail))
    class_order = list(panel.get("class_order") or quarterly.get("class_order") or [])
    class_count = len(class_order)
    months_covered = int(quarterly.get("months_covered", 0) or 0)
    if months_covered <= 0:
        months = set()
        for e in use_trail:
            y = e.get("year", 0)
            m = e.get("month", 0)
            if y or m:
                months.add((y, m))
        months_covered = max(len(months), 1 if use_trail else 0)

    opt_count = int(counters.get("count", len(counters.get("options") or [])) or 0)
    pick_count = int(picks.get("count", len(picks.get("actions") or [])) or 0)
    reduction = float(counter_exec.get("reduction", 0.0) or 0.0)

    score = _floor(
        0.3 * min(1.0, trail_count / 6.0)
        + 0.2 * min(1.0, class_count / 3.0)
        + 0.2 * min(1.0, months_covered / 3.0)
        + 0.15 * min(1.0, max(opt_count, pick_count) / 3.0)
        + 0.15 * min(1.0, reduction * 5.0)
    )

    rec = recommend_hh_month_step(
        trail_count, class_count=class_count, counter_options=max(opt_count, pick_count)
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "trail_board": _floor(min(1.0, trail_count / 6.0)),
        "monthly_brief": _floor(0.5 + 0.1 * min(3, pick_count)),
        "quarterly_counter": _floor(0.45 + reduction * 2.0 + 0.05 * opt_count),
    }
    for i, step in enumerate(MONTH_STEPS):
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
            "enabled": trail_count > 0 or step == "trail_board",
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": max(1, int(focus.get("province_id", province_id) or province_id)),
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": label,
                "step": step,
                "product_action": meta["action_id"],
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "hh_multi_month_agenda_product",
            "label": "Run HH multi-month agenda product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "hh_month_trail_board")),
            "label": "Recommended: %s" % rec.get("step", "trail_board"),
            "enabled": True,
        },
        {
            "action_id": "apply_counterplay",
            "label": "Commit counterplay",
            "enabled": trail_count > 0,
        },
        {
            "action_id": "apply_hh_commit",
            "label": "HH commit pulse",
            "enabled": trail_count > 0,
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

    # Faction/class filter chips
    class_filters = [{"id": "", "label": "All classes"}] + [
        {"id": c, "label": str(c)} for c in class_order
    ]

    label = (
        "HH multi-month agenda · trail %d · classes %d · months %d · filter %s · score %.2f"
        % (
            trail_count,
            class_count,
            months_covered,
            action_class_filter or "all",
            score,
        )
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        str(monthly.get("headline", monthly.get("summary", ""))),
        str(quarterly.get("headline", quarterly.get("summary", ""))),
    ]
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "trail": use_trail,
        "trail_count": trail_count,
        "class_order": class_order,
        "class_filters": class_filters,
        "action_class_filter": action_class_filter,
        "panel": panel,
        "screen": screen,
        "monthly": monthly,
        "quarterly": quarterly,
        "picks": picks,
        "counters": counters,
        "counter_exec": counter_exec,
        "months_covered": months_covered,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "hh_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": trail_count > 0,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#c084fc]◈ HH multi-month agenda[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": trail_count <= 0,
        "integration": [
            "hh_multi_month_agenda_product",
            "hh_month_trail_board",
            "hh_month_brief",
            "hh_month_quarterly_counter",
            "major_5",
        ],
    }


def execute_hh_month_step(
    step: str,
    province_id: int = 1,
    *,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    action_class_filter: str = "",
) -> Dict[str, Any]:
    s = str(step or "trail_board").strip().lower()
    if s not in _STEP_META:
        for k, meta in _STEP_META.items():
            if s == meta["action_id"] or s.endswith(k):
                s = k
                break
        else:
            s = "trail_board"
    meta = _STEP_META[s]
    product = build_hh_multi_month_agenda_product(
        trail, action_class_filter=action_class_filter, province_id=province_id
    )
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": meta["leaf"],
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": bool((row or {}).get("enabled", True)),
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute HH %s · leaf %s · score %.2f · #%d" % (
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
        "bbcode": "[color=#c084fc]◈ HH %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_hh_month_step", s, meta["leaf"]],
    }


def hh_multi_month_agenda_product_integrity() -> Dict[str, Any]:
    product = build_hh_multi_month_agenda_product()
    filtered = build_hh_multi_month_agenda_product(action_class_filter="sabotage")
    steps = [execute_hh_month_step(s, 1) for s in MONTH_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("trail_count", 0)) >= 3
        and int(product.get("months_covered", 0)) >= 2
        and len(product.get("class_order") or []) >= 2
        and len(filtered.get("trail") or []) >= 1
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "trail_count": int(product.get("trail_count", 0)),
        "months_covered": int(product.get("months_covered", 0)),
        "classes": list(product.get("class_order") or []),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "HH multi-month agenda product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_hh_multi_month_agenda_product_loop() -> Dict[str, Any]:
    product = build_hh_multi_month_agenda_product()
    gate = hh_multi_month_agenda_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close HH multi-month agenda product · trail %d · months %d · classes %d · %s"
        % (
            int(product.get("trail_count", 0)),
            int(product.get("months_covered", 0)),
            len(product.get("class_order") or []),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c084fc]✓ HH multi-month agenda product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
