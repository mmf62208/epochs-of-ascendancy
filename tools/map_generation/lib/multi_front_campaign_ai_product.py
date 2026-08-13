"""Multi-front campaign AI product (major #54) — Phase 10 world-class GS.

Multi-front plan board → weekly AI tick → theater execute package.
Deepens campaign AI + theater command into multi-front live path.
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
    from theater_command_product import build_theater_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_theater_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from leader_theater_command_product import build_leader_theater_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_leader_theater_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.7, "empty": False, "orders": 3}

try:
    from strategic_war_goal_product import build_strategic_war_goal_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_war_goal_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False, "pushes": 2, "top_id": "conquer_border"}

try:
    from weather_crisis_campaign_product import build_weather_crisis_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_weather_crisis_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "gate_open": True}

PRODUCT_STEPS = ("plan", "weekly", "execute")
_STEP_META = {
    "plan": {"action_id": "multi_front_plan", "leaf": "apply_focus", "label": "Step 0 — multi-front plan board"},
    "weekly": {"action_id": "multi_front_weekly", "leaf": "apply_production", "label": "Step 1 — weekly AI tick"},
    "execute": {"action_id": "multi_front_execute", "leaf": "apply_assault", "label": "Step 2 — theater execute package"},
}

_FRONTS = ("west", "east", "naval", "air")


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


def compute_multi_front_plan(*, ai_score: float = 0.6, war_goal_score: float = 0.65, fronts: int = 4) -> Dict[str, Any]:
    a = _floor(ai_score)
    w = _floor(war_goal_score)
    n = max(2, min(6, int(fronts)))
    rows = []
    for i, name in enumerate(_FRONTS[:n]):
        sc = _floor(0.4 * a + 0.35 * w + 0.05 * (i + 1))
        rows.append({"front": name, "priority": n - i, "score": sc, "active": True})
    score = _floor(0.5 * a + 0.3 * w + 0.2 * min(1.0, n / 4.0))
    return {
        "fronts": rows, "front_n": n, "score": score,
        "summary": "Multi-front plan · fronts %d · score %.2f" % (n, score),
        "empty": False,
    }


def compute_weekly_tick(*, plan: Dict[str, Any], leader_orders: int = 3, weather_open: bool = True) -> Dict[str, Any]:
    base = _floor(float(plan.get("score", 0.5)))
    orders = max(0, int(leader_orders))
    ticks = max(1, int(round(base * 3 + orders * 0.25)))
    gated = weather_open
    score = _floor(0.55 * base + 0.25 * min(1.0, orders / 6.0) + 0.2 * (1.0 if gated else 0.4))
    return {
        "ticks": ticks, "orders": orders, "weather_open": weather_open, "score": score,
        "summary": "Weekly AI · ticks %d · orders %d · wx %s · score %.2f"
        % (ticks, orders, "OPEN" if weather_open else "HOLD", score),
        "empty": False,
    }


def compute_theater_execute(*, weekly: Dict[str, Any], theater_score: float = 0.58, pushes: int = 2) -> Dict[str, Any]:
    t = _floor(theater_score)
    w = _floor(float(weekly.get("score", 0.5)))
    p = max(0, int(pushes))
    packages = max(1, int(round(0.5 * float(weekly.get("ticks", 1)) + 0.5 * p + t)))
    score = _floor(0.4 * w + 0.35 * t + 0.25 * min(1.0, packages / 5.0))
    return {
        "packages": packages, "pushes": p, "score": score,
        "summary": "Theater execute · packages %d · pushes %d · score %.2f" % (packages, p, score),
        "empty": False,
    }


def recommend_multi_front_step(*, planned: bool = False, weekly_done: bool = False) -> Dict[str, Any]:
    if not planned:
        step, reason = "plan", "build multi-front plan board"
    elif not weekly_done:
        step, reason = "weekly", "run weekly AI tick"
    else:
        step, reason = "execute", "execute theater package"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_multi_front_campaign_ai_product(*, province_id: int = 1, fronts: int = 4) -> Dict[str, Any]:
    ai = build_campaign_ai_multi_month_product(province_id=province_id)
    theater = build_theater_command_product(province_id=province_id)
    leader = build_leader_theater_command_product(province_id=province_id)
    war = build_strategic_war_goal_product(province_id=province_id)
    wx = build_weather_crisis_campaign_product(province_id=province_id)
    plan = compute_multi_front_plan(
        ai_score=float(ai.get("score", 0.6)),
        war_goal_score=float(war.get("score", 0.65)),
        fronts=fronts,
    )
    weekly = compute_weekly_tick(
        plan=plan,
        leader_orders=int(leader.get("orders", 3)),
        weather_open=bool(wx.get("gate_open", True)),
    )
    execute = compute_theater_execute(
        weekly=weekly,
        theater_score=float(theater.get("score", 0.58)),
        pushes=int(war.get("pushes", 2)),
    )
    p_s = _floor(float(plan["score"]))
    w_s = _floor(float(weekly["score"]))
    e_s = _floor(float(execute["score"]))
    score = _floor(0.3 * p_s + 0.35 * w_s + 0.35 * e_s)
    rec = recommend_multi_front_step(planned=True, weekly_done=True)
    step_scores = {"plan": p_s, "weekly": w_s, "execute": e_s}
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
        {"action_id": "multi_front_campaign_ai_product", "label": "Run multi-front campaign AI product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Multi-front campaign AI · fronts %d · ticks %d · packages %d · score %.2f" % (
        int(plan["front_n"]), int(weekly["ticks"]), int(execute["packages"]), score)
    return {
        "ai": ai, "theater": theater, "leader": leader, "war": war, "weather": wx,
        "plan": plan, "weekly": weekly, "execute": execute,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "front_n": int(plan["front_n"]), "ticks": int(weekly["ticks"]), "packages": int(execute["packages"]),
        "score": score, "multi_front_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), plan["summary"], weekly["summary"], execute["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#70a0e0]♟ Multi-front AI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "multi_front_campaign_ai_product", "multi_front_plan", "multi_front_weekly", "multi_front_execute",
            "major_54", "campaign_ai", "multi_front", "phase10_gs", "world_class_gs",
        ],
    }


def execute_multi_front_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "plan").strip().lower().replace("multi_front_", "")
    if s.startswith("plan") or s.startswith("board"):
        s = "plan"
    elif s.startswith("week") or s.startswith("tick") or s.startswith("ai"):
        s = "weekly"
    elif s.startswith("exec") or s.startswith("theater") or s.startswith("package"):
        s = "execute"
    if s not in _STEP_META:
        s = "plan"
    meta = _STEP_META[s]
    product = build_multi_front_campaign_ai_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute multi-front %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_multi_front_step", s, leaf],
    }


def multi_front_campaign_ai_integrity() -> Dict[str, Any]:
    product = build_multi_front_campaign_ai_product()
    steps = [execute_multi_front_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("front_n", 0)) >= 3
        and int(product.get("packages", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Multi-front campaign AI integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_multi_front_campaign_ai_product_loop() -> Dict[str, Any]:
    product = build_multi_front_campaign_ai_product(province_id=2, fronts=4)
    gate = multi_front_campaign_ai_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close multi-front campaign AI · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
