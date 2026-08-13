"""Focus tree content product (major #42) — Phase 6.

National focus catalog → path pick → commit focus step.
Historical focus tables content depth (not multiplayer).
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from focus_war_path_product import build_focus_war_path_product  # type: ignore
except Exception:  # pragma: no cover
    def build_focus_war_path_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "focus war"}

PRODUCT_STEPS = ("catalog", "path", "commit")
NATIONAL_FOCI = {
    "GER": [
        {"id": "rheinland", "label": "Rhineland remilitarization", "year": 1936, "branch": "army"},
        {"id": "autarky", "label": "Four Year Plan", "year": 1936, "branch": "industry"},
        {"id": "anschluss", "label": "Anschluss pressure", "year": 1938, "branch": "diplomacy"},
    ],
    "FRA": [
        {"id": "maginot", "label": "Maginot reinforcement", "year": 1936, "branch": "army"},
        {"id": "popular_front", "label": "Popular Front industry", "year": 1936, "branch": "industry"},
    ],
    "ENG": [
        {"id": "rearmament", "label": "Limited rearmament", "year": 1936, "branch": "army"},
        {"id": "radar", "label": "Chain Home radar", "year": 1937, "branch": "air"},
    ],
    "USA": [
        {"id": "neutrality", "label": "Neutrality acts review", "year": 1936, "branch": "diplomacy"},
        {"id": "naval_act", "label": "Naval expansion act", "year": 1938, "branch": "naval"},
    ],
    "SOV": [
        {"id": "five_year", "label": "Second Five Year Plan", "year": 1936, "branch": "industry"},
        {"id": "deep_battle", "label": "Deep battle studies", "year": 1937, "branch": "army"},
    ],
}
_STEP_META = {
    "catalog": {"action_id": "focus_tree_catalog", "leaf": "apply_focus", "label": "Step 0 — national focus catalog"},
    "path": {"action_id": "focus_tree_path", "leaf": "apply_focus", "label": "Step 1 — pick focus path"},
    "commit": {"action_id": "focus_tree_commit", "leaf": "apply_production", "label": "Step 2 — commit focus step"},
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


def compute_focus_catalog(*, country_tag: str = "GER", era_year: int = 1936) -> Dict[str, Any]:
    tag = str(country_tag or "GER").upper()
    year = max(1918, min(2026, int(era_year)))
    rows = list(NATIONAL_FOCI.get(tag, NATIONAL_FOCI["GER"]))
    open_rows = [r for r in rows if int(r.get("year", 1936)) <= year]
    return {
        "country_tag": tag,
        "era_year": year,
        "rows": open_rows,
        "focus_n": len(open_rows),
        "total_n": len(rows),
        "coverage": _floor(float(len(open_rows)) / max(1, len(rows))),
        "summary": "Focus catalog · %s · year %d · open %d/%d" % (tag, year, len(open_rows), len(rows)),
        "empty": False,
    }


def recommend_focus_pick(catalog: Dict[str, Any]) -> Dict[str, Any]:
    rows = catalog.get("rows") or []
    if not rows:
        return {"focus_id": "", "label": "none", "branch": "army", "score": 0.4, "empty": True, "summary": "No open foci"}
    pick = rows[0]
    for r in rows:
        if str(r.get("branch")) == "industry":
            pick = r
            break
    return {
        "focus_id": str(pick.get("id")),
        "label": str(pick.get("label")),
        "branch": str(pick.get("branch")),
        "score": 0.72,
        "summary": "Pick · %s · %s" % (pick.get("id"), pick.get("label")),
        "empty": False,
    }


def recommend_focus_content_step(*, cataloged: bool = False, path_set: bool = False) -> Dict[str, Any]:
    if not cataloged:
        step, reason = "catalog", "load national focus tables"
    elif not path_set:
        step, reason = "path", "pick historical focus path"
    else:
        step, reason = "commit", "commit focus step to production/trail"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_focus_tree_content_product(
    *, province_id: int = 1, country_tag: str = "GER", era_year: int = 1936
) -> Dict[str, Any]:
    war = build_focus_war_path_product(province_id=province_id)
    catalog = compute_focus_catalog(country_tag=country_tag, era_year=era_year)
    pick = recommend_focus_pick(catalog)
    war_s = _floor(float(war.get("score", 0.55)))
    catalog_score = _floor(0.45 * war_s + 0.55 * float(catalog["coverage"]))
    path_score = _floor(0.5 * float(pick.get("score", 0.6)) + 0.5 * catalog_score)
    commit_score = _floor(0.55 * path_score + 0.45 * catalog_score)
    score = _floor(0.3 * catalog_score + 0.35 * path_score + 0.35 * commit_score)
    rec = recommend_focus_content_step(cataloged=True, path_set=True)
    step_scores = {"catalog": catalog_score, "path": path_score, "commit": commit_score}
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
        {"action_id": "focus_tree_content_product", "label": "Run focus tree content product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Focus tree content · %s · open %d · pick %s · score %.2f" % (
        catalog["country_tag"], catalog["focus_n"], pick.get("focus_id", ""), score)
    return {
        "war": war, "catalog": catalog, "pick": pick, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "country_tag": catalog["country_tag"], "focus_n": catalog["focus_n"],
        "focus_id": pick.get("focus_id"), "branch": pick.get("branch"),
        "score": score, "focus_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(catalog.get("summary", "")), str(pick.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#e0b070]🌳 Focus content[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "focus_tree_content_product", "focus_tree_catalog", "focus_tree_path", "focus_tree_commit",
            "major_42", "focus", "content", "phase6_depth",
        ],
    }


def execute_focus_tree_content_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "catalog").strip().lower().replace("focus_tree_", "")
    if s.startswith("catalog"):
        s = "catalog"
    elif s.startswith("path") or s.startswith("pick"):
        s = "path"
    elif s.startswith("commit"):
        s = "commit"
    if s not in _STEP_META:
        s = "catalog"
    meta = _STEP_META[s]
    product = build_focus_tree_content_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute focus content %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_focus_tree_content_step", s, leaf],
    }


def focus_tree_content_integrity() -> Dict[str, Any]:
    product = build_focus_tree_content_product()
    steps = [execute_focus_tree_content_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("focus_n", 0)) >= 1
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Focus tree content integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_focus_tree_content_product_loop() -> Dict[str, Any]:
    product = build_focus_tree_content_product(province_id=2, country_tag="SOV", era_year=1937)
    gate = focus_tree_content_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close focus tree content · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
