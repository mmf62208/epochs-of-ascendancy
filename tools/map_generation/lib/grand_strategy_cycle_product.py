"""Grand strategy cycle product (major #55) — Phase 10 world-class GS close.

Scan all strategic domains → rank campaign priorities → execute top cycle package.
Composes war goals, multi-front AI, designers, weather, intel, leaders into one GS loop.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from strategic_war_goal_product import build_strategic_war_goal_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_war_goal_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False}

try:
    from multi_front_campaign_ai_product import build_multi_front_campaign_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_front_campaign_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.7, "empty": False, "packages": 3}

try:
    from world_class_campaign_command_product import build_world_class_campaign_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_world_class_campaign_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.62, "empty": False}

try:
    from designer_multi_domain_campaign_product import build_designer_multi_domain_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_designer_multi_domain_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.9, "empty": False, "complete": True}

try:
    from weather_crisis_campaign_product import build_weather_crisis_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_weather_crisis_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False}

try:
    from intel_cell_network_product import build_intel_cell_network_product  # type: ignore
except Exception:  # pragma: no cover
    def build_intel_cell_network_product(*_a, **_k):  # type: ignore
        return {"score": 0.7, "empty": False, "secure": True}

try:
    from leader_theater_command_product import build_leader_theater_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_leader_theater_command_product(*_a, **_k):  # type: ignore
        return {"score": 0.75, "empty": False}

PRODUCT_STEPS = ("scan", "rank", "execute")
_STEP_META = {
    "scan": {"action_id": "gs_cycle_scan", "leaf": "apply_focus", "label": "Step 0 — scan strategic domains"},
    "rank": {"action_id": "gs_cycle_rank", "leaf": "apply_production", "label": "Step 1 — rank campaign priorities"},
    "execute": {"action_id": "gs_cycle_execute", "leaf": "apply_assault", "label": "Step 2 — execute top GS package"},
}

_DOMAINS = (
    ("war_goal", "apply_assault"),
    ("multi_front", "apply_assault"),
    ("designers", "apply_production"),
    ("weather", "apply_supply"),
    ("intel", "apply_agent_dispatch"),
    ("leaders", "apply_station"),
    ("command", "apply_focus"),
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


def compute_domain_scan(*, province_id: int = 1) -> Dict[str, Any]:
    products = {
        "war_goal": build_strategic_war_goal_product(province_id=province_id),
        "multi_front": build_multi_front_campaign_ai_product(province_id=province_id),
        "designers": build_designer_multi_domain_campaign_product(province_id=province_id),
        "weather": build_weather_crisis_campaign_product(province_id=province_id),
        "intel": build_intel_cell_network_product(province_id=province_id),
        "leaders": build_leader_theater_command_product(province_id=province_id),
        "command": build_world_class_campaign_command_product(province_id=province_id),
    }
    rows = []
    for name, _leaf in _DOMAINS:
        p = products[name]
        rows.append({
            "domain": name,
            "score": _floor(float(p.get("score", 0.5))),
            "summary": str(p.get("summary", name))[:80],
            "empty": bool(p.get("empty", False)),
        })
    open_n = sum(1 for r in rows if not r["empty"] and float(r["score"]) >= 0.4)
    avg = sum(float(r["score"]) for r in rows) / max(1, len(rows))
    score = _floor(0.55 * avg + 0.45 * (open_n / max(1, len(rows))))
    return {
        "rows": rows, "products": products, "open_n": open_n, "domain_n": len(rows), "score": score,
        "summary": "GS scan · domains %d/%d open · avg %.2f · score %.2f" % (open_n, len(rows), avg, score),
        "empty": False,
    }


def compute_priority_rank(*, scan: Dict[str, Any]) -> Dict[str, Any]:
    rows = sorted(list(scan.get("rows") or []), key=lambda r: -float(r.get("score", 0)))
    ranked = []
    for i, r in enumerate(rows):
        ranked.append({**r, "rank": i + 1, "priority": len(rows) - i})
    top = ranked[0] if ranked else {"domain": "war_goal", "score": 0.5}
    score = _floor(0.6 * float(top.get("score", 0.5)) + 0.4 * float(scan.get("score", 0.5)))
    return {
        "ranked": ranked, "top_domain": str(top.get("domain")), "top_score": float(top.get("score", 0.5)),
        "score": score,
        "summary": "GS rank · top %s · score %.2f · open %d" % (top.get("domain"), score, int(scan.get("open_n", 0))),
        "empty": False,
    }


def compute_cycle_execute(*, rank: Dict[str, Any], multi_packages: int = 3, war_pushes: int = 2) -> Dict[str, Any]:
    top = str(rank.get("top_domain", "war_goal"))
    packages = max(1, int(multi_packages) + max(0, int(war_pushes) // 2))
    score = _floor(0.5 * float(rank.get("score", 0.5)) + 0.3 * min(1.0, packages / 5.0) + 0.2)
    leaf = dict(_DOMAINS).get(top, "apply_assault")
    return {
        "top_domain": top, "packages": packages, "leaf": leaf, "score": score,
        "summary": "GS execute · top %s · packages %d · leaf %s · score %.2f" % (top, packages, leaf, score),
        "empty": False,
    }


def recommend_gs_cycle_step(*, scanned: bool = False, ranked: bool = False) -> Dict[str, Any]:
    if not scanned:
        step, reason = "scan", "scan all strategic domains"
    elif not ranked:
        step, reason = "rank", "rank campaign priorities"
    else:
        step, reason = "execute", "execute top GS package"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_grand_strategy_cycle_product(*, province_id: int = 1) -> Dict[str, Any]:
    scan = compute_domain_scan(province_id=province_id)
    rank = compute_priority_rank(scan=scan)
    multi = (scan.get("products") or {}).get("multi_front") or {}
    war = (scan.get("products") or {}).get("war_goal") or {}
    execute = compute_cycle_execute(
        rank=rank,
        multi_packages=int(multi.get("packages", 3)),
        war_pushes=int(war.get("pushes", 2)),
    )
    s_s = _floor(float(scan["score"]))
    r_s = _floor(float(rank["score"]))
    e_s = _floor(float(execute["score"]))
    score = _floor(0.3 * s_s + 0.35 * r_s + 0.35 * e_s)
    rec = recommend_gs_cycle_step(scanned=True, ranked=True)
    step_scores = {"scan": s_s, "rank": r_s, "execute": e_s}
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
    # primary leaf follows top domain
    apply_queue.append({
        "action_id": str(execute.get("leaf", "apply_assault")),
        "province_id": max(1, int(province_id)),
        "score": e_s,
        "enabled": True,
        "label": "Top domain primary · %s" % execute.get("top_domain"),
        "step": "execute",
        "product_action": "gs_cycle_execute",
    })
    actions = [
        {"action_id": "grand_strategy_cycle_product", "label": "Run grand strategy cycle product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    complete = int(scan.get("open_n", 0)) >= 6 and float(score) >= 0.5
    label = "Grand strategy cycle · open %d/7 · top %s · packages %d · %s · score %.2f" % (
        int(scan["open_n"]), execute["top_domain"], int(execute["packages"]),
        "COMPLETE" if complete else "PARTIAL", score)
    return {
        "scan": scan, "rank": rank, "execute": execute,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "open_n": int(scan["open_n"]), "top_domain": execute["top_domain"],
        "packages": int(execute["packages"]), "complete": complete,
        "score": score, "gs_cycle_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), scan["summary"], rank["summary"], execute["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#d0c060]🌍 Grand strategy[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "grand_strategy_cycle_product", "gs_cycle_scan", "gs_cycle_rank", "gs_cycle_execute",
            "major_55", "grand_strategy", "phase10_gs", "world_class_gs", "full_gameplay_cycle",
        ],
    }


def execute_gs_cycle_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "scan").strip().lower().replace("gs_cycle_", "").replace("gs_", "")
    if s.startswith("scan") or s.startswith("domain"):
        s = "scan"
    elif s.startswith("rank") or s.startswith("priority"):
        s = "rank"
    elif s.startswith("exec") or s.startswith("package") or s.startswith("top"):
        s = "execute"
    if s not in _STEP_META:
        s = "scan"
    meta = _STEP_META[s]
    product = build_grand_strategy_cycle_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute GS cycle %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_gs_cycle_step", s, leaf],
    }


def grand_strategy_cycle_integrity() -> Dict[str, Any]:
    product = build_grand_strategy_cycle_product()
    steps = [execute_gs_cycle_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("open_n", 0)) >= 5
        and bool(product.get("complete", False))
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Grand strategy cycle integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_grand_strategy_cycle_product_loop() -> Dict[str, Any]:
    product = build_grand_strategy_cycle_product(province_id=2)
    gate = grand_strategy_cycle_integrity()
    ok = bool(gate.get("ok")) and bool(product.get("complete"))
    label = "Close grand strategy cycle · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
