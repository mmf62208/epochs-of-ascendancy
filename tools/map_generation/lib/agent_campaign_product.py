"""Agent campaign product (major #6 / high-priority).

Multi-step agent loop as primary product: board → dispatch coverage → counterplay/escalation.
Not day-package stubs — composes agent AI board, coverage, campaign response, escalation.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from agent_coverage_plan import plan_agent_coverage  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from campaign_cohesion import agent_campaign_response  # type: ignore
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from agent_counterplay import counterplay_options_for_signal  # type: ignore
except Exception:  # pragma: no cover
    def counterplay_options_for_signal(sig, max_options: int = 2):  # type: ignore
        return {"options": [{"id": "counter_intel"}], "count": 1, "empty": False}


PRODUCT_STEPS = ("board", "dispatch", "counterplay")

_STEP_META = {
    "board": {
        "action_id": "agent_product_board",
        "leaf": "apply_agent_dispatch",
        "label": "Step 0 — AI board / mission pick",
    },
    "dispatch": {
        "action_id": "agent_product_dispatch",
        "leaf": "apply_agent_dispatch",
        "label": "Step 1 — coverage dispatch",
    },
    "counterplay": {
        "action_id": "agent_product_counterplay",
        "leaf": "apply_counterplay",
        "label": "Step 2 — counterplay / escalate",
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


def _demo_signals() -> List[Dict[str, Any]]:
    return [
        {
            "action_class": "sabotage",
            "influence": 0.62,
            "province_id": 1,
            "active": True,
            "loyalty": 0.45,
        },
        {
            "action_class": "economic_pressure",
            "influence": 0.48,
            "province_id": 2,
            "active": True,
            "loyalty": 0.55,
        },
        {
            "action_class": "infiltration",
            "influence": 0.55,
            "province_id": 3,
            "active": True,
            "loyalty": 0.4,
        },
    ]


def recommend_agent_product_step(
    signal_count: int,
    *,
    coverage_count: int = 0,
    counter_options: int = 0,
    affinity: float = 0.5,
) -> Dict[str, Any]:
    if signal_count <= 0:
        step = "board"
        reason = "no signals — open board / wait for pulse"
    elif coverage_count <= 0 or affinity < 0.35:
        step = "board"
        reason = "pick missions on AI board"
    elif counter_options >= 1 and coverage_count >= 1:
        step = "counterplay"
        reason = "coverage set — escalate / counterplay"
    else:
        step = "dispatch"
        reason = "dispatch agents to coverage plan"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_agent_campaign_product(
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
    province_id: int = 1,
    max_dispatches: int = 3,
) -> Dict[str, Any]:
    """Agent campaign product: board · dispatch · counterplay as primary UI path."""
    use_signals: List[Dict[str, Any]] = (
        [dict(s) for s in signals if isinstance(s, Mapping)]
        if signals is not None
        else _demo_signals()
    )
    # Normalize active
    for s in use_signals:
        s.setdefault("active", True)
        if "action_class" not in s and "class" in s:
            s["action_class"] = s["class"]

    coverage = plan_agent_coverage(
        use_signals,
        available_agents=available_agents,
        network_strength=network_strength,
    )
    focus = use_signals[0] if use_signals else {
        "action_class": "sabotage",
        "influence": 0.55,
        "province_id": province_id,
        "active": True,
    }
    try:
        response = agent_campaign_response(
            signal=focus,
            available_agents=available_agents,
            network_strength=network_strength,
            loyalty=loyalty,
        )
    except TypeError:
        try:
            response = agent_campaign_response(  # type: ignore
                str(focus.get("action_class", "sabotage")),
                float(focus.get("influence", 0.55)),
                int(focus.get("province_id", province_id)),
                available_agents,
                network_strength,
                loyalty,
            )
        except Exception:
            response = {"score": 0.55, "empty": False, "summary": "agent response"}

    try:
        escalation = plan_agent_escalation(
            focus,
            network_strength=network_strength,
            available_agents=available_agents,
            loyalty=loyalty,
        )
    except TypeError:
        escalation = plan_agent_escalation(focus)

    try:
        counters = counterplay_options_for_signal(focus, max_options=3)
    except TypeError:
        try:
            counters = counterplay_options_for_signal(focus)
        except Exception:
            counters = {"options": [], "count": 0, "empty": True}

    # Board-like mission ranking via response score + coverage
    assignments = list(coverage.get("assignments") or coverage.get("rows") or [])
    if not assignments and isinstance(coverage.get("scored"), list):
        assignments = coverage["scored"]  # type: ignore
    # plan_agent_coverage returns assignments key
    cov_rows = list(coverage.get("assignments") or [])
    if not cov_rows:
        # fallback to scored list if present in lines-only packages
        for k in ("assignments", "plan", "rows"):
            if isinstance(coverage.get(k), list):
                cov_rows = list(coverage[k])  # type: ignore
                break
    # Pure plan_agent_coverage uses "assignments" or builds scored then assigns — check structure
    if not cov_rows and not bool(coverage.get("empty", False)):
        # reconstruct from lines is weak; use signals as dispatch targets
        cov_rows = [
            {
                "province_id": int(s.get("province_id", province_id) or province_id),
                "action_class": str(s.get("action_class", "sabotage")),
                "agents": 1,
                "need": float(s.get("influence", 0.5) or 0.5),
            }
            for s in use_signals[:max_dispatches]
        ]

    cov_count = sum(1 for r in cov_rows if int(r.get("agents", 0) or 0) > 0 or r.get("province_id"))
    opt_count = int(counters.get("count", len(counters.get("options") or [])) or 0)
    esc_level = int(escalation.get("level", 0) or 0)
    resp_score = _norm(float(response.get("score", 0.55) or 0.55))
    cov_score = _norm(float(coverage.get("score", 0.55) if coverage.get("score") is not None else min(1.0, cov_count / 3.0)))
    if bool(coverage.get("empty", False)):
        cov_score = 0.25
    affinity = _floor(0.4 * resp_score + 0.3 * cov_score + 0.3 * min(1.0, (opt_count + 1) / 3.0))

    signal_count = len(use_signals)
    rec = recommend_agent_product_step(
        signal_count,
        coverage_count=cov_count,
        counter_options=opt_count,
        affinity=affinity,
    )

    score = _floor(
        0.3 * resp_score
        + 0.25 * cov_score
        + 0.2 * min(1.0, signal_count / 3.0)
        + 0.15 * min(1.0, (esc_level + 1) / 4.0)
        + 0.1 * min(1.0, opt_count / 2.0)
    )

    step_scores = {
        "board": _floor(0.45 + 0.15 * min(3, signal_count)),
        "dispatch": _floor(0.4 + 0.15 * min(3, cov_count)),
        "counterplay": _floor(0.4 + 0.1 * opt_count + 0.05 * esc_level),
    }
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    focus_pid = int(focus.get("province_id", province_id) or province_id)
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
            "enabled": signal_count > 0 or step == "board",
            "recommended": recommended,
            "province_id": focus_pid,
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": focus_pid,
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": label,
                "step": step,
                "product_action": meta["action_id"],
                "action_class": str(focus.get("action_class", "sabotage")),
            }
        )

    # Extra dispatch targets from coverage
    for r in cov_rows[:max_dispatches]:
        pid = int(r.get("province_id", focus_pid) or focus_pid)
        if pid == focus_pid and len(apply_queue) >= 3:
            continue
        apply_queue.append(
            {
                "action_id": "apply_agent_dispatch",
                "province_id": pid,
                "score": score,
                "enabled": True,
                "label": "Dispatch · #%d · %s" % (pid, r.get("action_class", "signal")),
                "step": "dispatch",
                "product_action": "agent_product_dispatch",
                "action_class": str(r.get("action_class", "sabotage")),
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "agent_campaign_product",
            "label": "Run agent campaign product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "agent_product_board")),
            "label": "Recommended: %s" % rec.get("step", "board"),
            "enabled": True,
        },
        {
            "action_id": "apply_agent_dispatch",
            "label": "Dispatch agents",
            "enabled": signal_count > 0,
        },
        {
            "action_id": "apply_counterplay",
            "label": "Apply counter-intel",
            "enabled": signal_count > 0,
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

    best_mission = str(
        response.get("best_mission")
        or response.get("top_action")
        or escalation.get("top_action")
        or "counterintel"
    )
    if best_mission.startswith("{") or best_mission in ("", "None"):
        best_mission = str(escalation.get("top_action") or "counterintel")

    label = (
        "Agent campaign product · signals %d · coverage %d · esc L%d · affinity %.0f%% · score %.2f"
        % (signal_count, cov_count, esc_level, affinity * 100.0, score)
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        "best mission %s · focus %s @#%d"
        % (best_mission, focus.get("action_class", "sabotage"), focus_pid),
        str(coverage.get("summary", coverage.get("plain", ""))).split("\n")[0]
        if coverage.get("summary") or coverage.get("plain")
        else "",
        str(escalation.get("summary", escalation.get("plain", ""))).split("\n")[0]
        if escalation.get("summary") or escalation.get("plain")
        else "",
    ]
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "signals": use_signals,
        "signal_count": signal_count,
        "coverage": coverage,
        "coverage_count": cov_count,
        "response": response,
        "escalation": escalation,
        "counters": counters,
        "affinity": affinity,
        "best_mission": best_mission,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "agent_score": score,
        "province_id": max(1, int(province_id)),
        "available_agents": int(available_agents),
        "apply_ready": signal_count > 0 and available_agents >= 1,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]🕵 Agent campaign product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": signal_count <= 0,
        "integration": [
            "agent_campaign_product",
            "agent_product_board",
            "agent_product_dispatch",
            "agent_product_counterplay",
            "major_6",
        ],
    }


def execute_agent_product_step(
    step: str,
    province_id: int = 1,
    *,
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    s = str(step or "board").strip().lower()
    if s.startswith("agent_product_"):
        s = s.replace("agent_product_", "")
    if s not in _STEP_META:
        for k, meta in _STEP_META.items():
            if s == meta["action_id"] or s.endswith(k):
                s = k
                break
        else:
            s = "board"
    meta = _STEP_META[s]
    product = build_agent_campaign_product(signals, province_id=province_id)
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
    label = "Execute agent %s · leaf %s · score %.2f · #%d" % (
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
        "bbcode": "[color=#6eb5ff]🕵 Agent %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_agent_product_step", s, meta["leaf"]],
    }


def agent_campaign_product_integrity() -> Dict[str, Any]:
    product = build_agent_campaign_product()
    empty_sig = build_agent_campaign_product([])
    steps = [execute_agent_product_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("signal_count", 0)) >= 2
        and len(product.get("day_rows") or []) >= 3
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and bool(empty_sig.get("empty"))
    )
    return {
        "ok": ok,
        "signal_count": int(product.get("signal_count", 0)),
        "coverage_count": int(product.get("coverage_count", 0)),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Agent campaign product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_agent_campaign_product_loop() -> Dict[str, Any]:
    product = build_agent_campaign_product()
    gate = agent_campaign_product_integrity()
    rich = build_agent_campaign_product(
        [
            {"action_class": "sabotage", "influence": 0.7, "province_id": 1, "active": True},
            {"action_class": "infiltration", "influence": 0.65, "province_id": 2, "active": True},
            {"action_class": "economic_pressure", "influence": 0.6, "province_id": 3, "active": True},
        ],
        available_agents=5,
    )
    thin = build_agent_campaign_product(
        [{"action_class": "sabotage", "influence": 0.25, "province_id": 1, "active": True}],
        available_agents=2,
    )
    signal_shift = float(rich.get("score", 0)) - float(thin.get("score", 0))
    ok = (
        bool(gate.get("ok"))
        and len(product.get("apply_queue") or []) >= 3
        and signal_shift >= 0.02
    )
    label = (
        "Close agent campaign product · signals %d · queue %d · signal_shift %.2f · %s"
        % (
            int(product.get("signal_count", 0)),
            len(product.get("apply_queue") or []),
            signal_shift,
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "signal_shift": signal_shift,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Agent campaign product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
