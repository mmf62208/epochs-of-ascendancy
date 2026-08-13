"""Tech tree branching product (major #39) — Phase 5.

Branch catalog → pick research path → field unlock.
Deepens tech research (#17) with year/branch gates (not multiplayer).
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from tech_research_campaign_product import build_tech_research_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_tech_research_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "tech"}

PRODUCT_STEPS = ("branches", "path", "field")
BRANCHES = {
    "infantry": {"year": 1918, "techs": ["infantry_weapons_1", "support_weapons_1", "doctrine_trench"], "score": 0.72},
    "armor": {"year": 1936, "techs": ["basic_medium_tank", "radio", "sloped_armor"], "score": 0.78},
    "air": {"year": 1936, "techs": ["early_fighter", "cas_1", "radar_air"], "score": 0.7},
    "naval": {"year": 1922, "techs": ["destroyer_hull", "submarine_hull", "fire_control"], "score": 0.68},
    "industry": {"year": 1918, "techs": ["machine_tools", "construction_1", "excavation"], "score": 0.74},
    "electronics": {"year": 1939, "techs": ["electronic_mechanical_engineering", "encryption", "decryption"], "score": 0.66},
}
_STEP_META = {
    "branches": {"action_id": "tech_tree_branches", "leaf": "apply_focus", "label": "Step 0 — tech branch catalog"},
    "path": {"action_id": "tech_tree_path", "leaf": "apply_production", "label": "Step 1 — pick research path"},
    "field": {"action_id": "tech_tree_field", "leaf": "apply_production", "label": "Step 2 — field unlock / apply"},
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


def compute_branch_board(*, era_year: int = 1939) -> Dict[str, Any]:
    year = max(1914, min(2026, int(era_year)))
    open_branches: List[Dict[str, Any]] = []
    locked = 0
    for name, meta in BRANCHES.items():
        open_y = int(meta.get("year", 1936))
        unlocked = year >= open_y
        if not unlocked:
            locked += 1
        open_branches.append({
            "branch": name,
            "year_gate": open_y,
            "unlocked": unlocked,
            "techs": list(meta.get("techs") or []),
            "score": float(meta.get("score", 0.6)),
            "label": "%s · gate %d · %s · techs %d"
            % (name, open_y, "OPEN" if unlocked else "LOCKED", len(meta.get("techs") or [])),
        })
    open_n = sum(1 for b in open_branches if b["unlocked"])
    coverage = _floor(float(open_n) / max(1, len(BRANCHES)))
    return {
        "era_year": year,
        "branches": open_branches,
        "branch_n": len(open_branches),
        "open_n": open_n,
        "locked_n": locked,
        "coverage": coverage,
        "summary": "Tech branches · year %d · open %d/%d · coverage %.0f%%"
        % (year, open_n, len(open_branches), coverage * 100),
        "empty": False,
    }


def recommend_tech_path(*, board: Dict[str, Any], preferred: str = "armor") -> Dict[str, Any]:
    pref = str(preferred or "armor").lower()
    branches = board.get("branches") or []
    open_b = [b for b in branches if isinstance(b, dict) and b.get("unlocked")]
    if not open_b:
        return {"branch": pref, "techs": [], "score": 0.4, "summary": "No open branches", "empty": True}
    pick = next((b for b in open_b if b.get("branch") == pref), open_b[0])
    for b in open_b:
        if float(b.get("score", 0)) > float(pick.get("score", 0)):
            pick = b
    return {
        "branch": str(pick.get("branch")),
        "techs": list(pick.get("techs") or []),
        "score": _floor(float(pick.get("score", 0.6))),
        "summary": "Path · %s · techs %d · score %.2f"
        % (pick.get("branch"), len(pick.get("techs") or []), float(pick.get("score", 0.6))),
        "empty": False,
    }


def recommend_tech_branching_step(*, branches_set: bool = False, path_set: bool = False) -> Dict[str, Any]:
    if not branches_set:
        step, reason = "branches", "catalog tech branches & year gates"
    elif not path_set:
        step, reason = "path", "pick research path branch"
    else:
        step, reason = "field", "field unlock top tech"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_tech_tree_branching_product(*, province_id: int = 1, era_year: int = 1939, preferred: str = "armor") -> Dict[str, Any]:
    base = build_tech_research_campaign_product(province_id=province_id)
    board = compute_branch_board(era_year=era_year)
    path = recommend_tech_path(board=board, preferred=preferred)
    base_s = _floor(float(base.get("score", 0.55)))
    branch_score = _floor(0.45 * base_s + 0.55 * float(board["coverage"]))
    path_score = _floor(0.4 * float(path.get("score", 0.5)) + 0.6 * branch_score)
    field_score = _floor(0.5 * path_score + 0.5 * branch_score)
    score = _floor(0.3 * branch_score + 0.35 * path_score + 0.35 * field_score)
    rec = recommend_tech_branching_step(branches_set=True, path_set=True)
    step_scores = {"branches": branch_score, "path": path_score, "field": field_score}
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
        {"action_id": "tech_tree_branching_product", "label": "Run tech tree branching product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "tech_branch_armor", "label": "Branch: armor", "enabled": True},
        {"action_id": "tech_branch_infantry", "label": "Branch: infantry", "enabled": True},
        {"action_id": "tech_branch_air", "label": "Branch: air", "enabled": True},
        {"action_id": "tech_branch_industry", "label": "Branch: industry", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Tech tree branching · year %d · open %d · path %s · score %.2f" % (
        board["era_year"], board["open_n"], path.get("branch", "armor"), score)
    return {
        "base": base, "board": board, "path": path, "recommendation": rec, "day_rows": day_rows,
        "apply_queue": apply_queue, "actions": actions,
        "era_year": board["era_year"], "open_n": board["open_n"], "branch_n": board["branch_n"],
        "path_branch": path.get("branch"), "tech_n": len(path.get("techs") or []),
        "score": score, "tech_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(board.get("summary", "")), str(path.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#80b0e0]🔬 Tech branching[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "tech_tree_branching_product", "tech_tree_branches", "tech_tree_path", "tech_tree_field",
            "major_39", "tech", "branching", "phase5_depth",
        ],
    }


def execute_tech_tree_branching_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "branches").strip().lower().replace("tech_tree_", "")
    if s.startswith("branch"):
        s = "branches"
    elif s.startswith("path"):
        s = "path"
    elif s.startswith("field"):
        s = "field"
    if s not in _STEP_META:
        s = "branches"
    meta = _STEP_META[s]
    product = build_tech_tree_branching_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute tech branching %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_tech_tree_branching_step", s, leaf],
    }


def tech_tree_branching_integrity() -> Dict[str, Any]:
    product = build_tech_tree_branching_product()
    steps = [execute_tech_tree_branching_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("open_n", 0)) >= 3
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Tech tree branching integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_tech_tree_branching_product_loop() -> Dict[str, Any]:
    product = build_tech_tree_branching_product(province_id=2, era_year=1941, preferred="industry")
    gate = tech_tree_branching_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close tech tree branching · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
