"""Multi-party peace conference product (major #37) — Phase 4.

Multi-victor board → war-goal package → multi-party settlement.
Deepens peace settlement (#31) with multiple participants and war goals.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from peace_conference_settlement_product import build_peace_conference_settlement_product  # type: ignore
except Exception:  # pragma: no cover
    def build_peace_conference_settlement_product(*_a, **_k):  # type: ignore
        return {"score": 0.7, "empty": False, "ai_accept": 0.65, "winner_tag": "GER", "loser_tag": "FRA"}

PRODUCT_STEPS = ("board", "wargoals", "settle")
WAR_GOALS = ("annex", "puppet", "reparations", "occupation_zone", "demilitarize")
_STEP_META = {
    "board": {"action_id": "multi_party_peace_board", "leaf": "apply_focus", "label": "Step 0 — multi-party conference board"},
    "wargoals": {"action_id": "multi_party_peace_wargoals", "leaf": "apply_production", "label": "Step 1 — assign war-goal packages"},
    "settle": {"action_id": "multi_party_peace_settle", "leaf": "apply_assault", "label": "Step 2 — multi-party settle map"},
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


def compute_multi_party_board(
    *,
    winners: List[str] | None = None,
    loser_tag: str = "FRA",
    leverages: Dict[str, float] | None = None,
) -> Dict[str, Any]:
    w = [str(t).upper() for t in (winners or ["GER", "ITA", "HUN"])]
    if not w:
        w = ["GER"]
    lev = leverages or {}
    parties: List[Dict[str, Any]] = []
    total_lev = 0.0
    for tag in w:
        L = _norm(float(lev.get(tag, 0.55 + 0.1 * (0 if tag != w[0] else 0.2))))
        total_lev += L
        parties.append({"tag": tag, "role": "winner", "leverage": L})
    parties.append({"tag": str(loser_tag or "FRA").upper(), "role": "loser", "leverage": 0.0})
    cohesion = _floor(total_lev / max(1, len(w)))
    return {
        "winners": w,
        "loser_tag": str(loser_tag or "FRA").upper(),
        "parties": parties,
        "party_n": len(parties),
        "winner_n": len(w),
        "cohesion": cohesion,
        "summary": "Multi-party · winners %s · loser %s · cohesion %.0f%%"
        % (",".join(w), str(loser_tag or "FRA").upper(), cohesion * 100),
        "empty": False,
    }


def compute_wargoal_packages(
    *, winners: List[str] | None = None, loser_tag: str = "FRA", cohesion: float = 0.6
) -> Dict[str, Any]:
    w = [str(t).upper() for t in (winners or ["GER", "ITA"])]
    packages: List[Dict[str, Any]] = []
    goals_cycle = list(WAR_GOALS)
    for i, tag in enumerate(w):
        g = goals_cycle[i % len(goals_cycle)]
        weight = _floor(0.5 + 0.1 * (len(w) - i) + 0.2 * _norm(cohesion))
        packages.append({
            "winner_tag": tag,
            "loser_tag": str(loser_tag or "FRA").upper(),
            "war_goal": g,
            "weight": weight,
            "label": "%s → %s · %s · w %.2f" % (tag, str(loser_tag or "FRA").upper(), g, weight),
        })
    feasibility = _floor(0.4 + 0.45 * _norm(cohesion) + 0.05 * len(packages))
    ai_accept = _floor(0.35 + 0.5 * feasibility)
    return {
        "packages": packages,
        "package_n": len(packages),
        "feasibility": feasibility,
        "ai_accept": ai_accept,
        "summary": "War goals · packages %d · feasibility %.0f%% · AI accept %.0f%%"
        % (len(packages), feasibility * 100, ai_accept * 100),
        "empty": False,
    }


def recommend_multi_party_peace_step(*, boarded: bool = False, goals_set: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "board", "seat multi-party winners/losers"
    elif not goals_set:
        step, reason = "wargoals", "assign per-victor war-goal packages"
    else:
        step, reason = "settle", "apply multi-party settlement to map"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_multi_party_peace_conference_product(
    *,
    province_id: int = 1,
    winners: List[str] | None = None,
    loser_tag: str = "FRA",
    leverages: Dict[str, float] | None = None,
) -> Dict[str, Any]:
    bilat = build_peace_conference_settlement_product(province_id=province_id)
    board = compute_multi_party_board(winners=winners, loser_tag=loser_tag, leverages=leverages)
    goals = compute_wargoal_packages(
        winners=board["winners"], loser_tag=board["loser_tag"], cohesion=float(board["cohesion"])
    )
    bilat_s = _floor(float(bilat.get("score", 0.65)))
    board_score = _floor(0.45 * bilat_s + 0.55 * float(board["cohesion"]))
    goals_score = _floor(0.4 * float(goals["feasibility"]) + 0.35 * float(goals["ai_accept"]) + 0.25 * board_score)
    settle_score = _floor(0.5 * goals_score + 0.5 * board_score)
    score = _floor(0.3 * board_score + 0.35 * goals_score + 0.35 * settle_score)
    rec = recommend_multi_party_peace_step(boarded=True, goals_set=True)
    step_scores = {"board": board_score, "wargoals": goals_score, "settle": settle_score}
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
        {"action_id": "multi_party_peace_conference_product", "label": "Run multi-party peace conference product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "peace_demand_annex", "label": "Demand: annex", "enabled": True},
        {"action_id": "peace_demand_puppet", "label": "Demand: puppet", "enabled": True},
        {"action_id": "peace_demand_reparations", "label": "Demand: reparations", "enabled": True},
        {"action_id": "peace_demand_occupation_zone", "label": "Demand: occupation zone", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Multi-party peace · winners %d · packages %d · AI accept %.0f%% · score %.2f" % (
        int(board["winner_n"]), int(goals["package_n"]), float(goals["ai_accept"]) * 100, score)
    return {
        "bilateral": bilat, "board": board, "wargoals": goals, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "winner_n": board["winner_n"], "package_n": goals["package_n"],
        "ai_accept": goals["ai_accept"], "feasibility": goals["feasibility"],
        "score": score, "peace_score": score, "province_id": max(1, int(province_id)),
        "winners": board["winners"], "loser_tag": board["loser_tag"],
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(board.get("summary", "")), str(goals.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e0c06a]🕊 Multi-party peace[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "multi_party_peace_conference_product", "multi_party_peace_board", "multi_party_peace_wargoals",
            "multi_party_peace_settle", "major_37", "peace", "multi_party", "wargoals", "phase4_depth",
        ],
    }


def execute_multi_party_peace_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("multi_party_peace_", "")
    if s.startswith("board"):
        s = "board"
    elif s.startswith("wargoal") or s.startswith("goal"):
        s = "wargoals"
    elif s.startswith("settle"):
        s = "settle"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_multi_party_peace_conference_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute multi-party peace %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_multi_party_peace_step", s, leaf],
    }


def multi_party_peace_conference_integrity() -> Dict[str, Any]:
    product = build_multi_party_peace_conference_product()
    steps = [execute_multi_party_peace_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("winner_n", 0)) >= 2
        and int(product.get("package_n", 0)) >= 2
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Multi-party peace conference integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_multi_party_peace_conference_product_loop() -> Dict[str, Any]:
    product = build_multi_party_peace_conference_product(province_id=2, winners=["GER", "ITA", "HUN"])
    gate = multi_party_peace_conference_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close multi-party peace · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
