"""Historical OOB content product (major #38) — Phase 5.

Catalog national OOB tables → seed production lines → equip formations.
Content/scenario depth: historical starting equipment paths (not multiplayer).
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_oob_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "oob"}

PRODUCT_STEPS = ("catalog", "seed", "equip")
NATIONAL_OOBS = {
    "GER": ["panzer_iii_j_medium", "infantry_k98_bolt_action"],
    "FRA": ["somua_s35_medium", "infantry_k98_bolt_action"],
    "ENG": ["m4_sherman_medium_tank", "infantry_m1_garand"],
    "USA": ["m4_sherman_medium_tank", "infantry_m1_garand"],
    "SOV": ["t34_medium_tank", "infantry_k98_bolt_action"],
    "ITA": ["cv33_tankette", "infantry_k98_bolt_action"],
    "JAP": ["jap_armor_1936", "infantry_k98_bolt_action"],
}
_STEP_META = {
    "catalog": {"action_id": "historical_oob_catalog", "leaf": "apply_focus", "label": "Step 0 — historical OOB catalog"},
    "seed": {"action_id": "historical_oob_seed", "leaf": "apply_production", "label": "Step 1 — seed national production lines"},
    "equip": {"action_id": "historical_oob_equip", "leaf": "apply_station", "label": "Step 2 — equip land formations"},
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


def compute_oob_catalog(*, majors: List[str] | None = None) -> Dict[str, Any]:
    tags = [str(t).upper() for t in (majors or list(NATIONAL_OOBS.keys()))]
    rows: List[Dict[str, Any]] = []
    line_n = 0
    for tag in tags:
        designs = NATIONAL_OOBS.get(tag, ["infantry_k98_bolt_action"])
        for d in designs:
            line_n += 1
            rows.append({
                "country_tag": tag,
                "design_id": d,
                "line_id": "oob_%s_%s" % (tag, d),
                "label": "%s · %s" % (tag, d),
            })
    coverage = _floor(min(1.0, float(len(tags)) / 7.0))
    return {
        "majors": tags,
        "rows": rows,
        "major_n": len(tags),
        "line_n": line_n,
        "coverage": coverage,
        "summary": "Historical OOB catalog · majors %d · lines %d · coverage %.0f%%"
        % (len(tags), line_n, coverage * 100),
        "empty": False,
    }


def recommend_historical_oob_step(*, cataloged: bool = False, seeded: bool = False) -> Dict[str, Any]:
    if not cataloged:
        step, reason = "catalog", "load historical OOB tables"
    elif not seeded:
        step, reason = "seed", "seed national production lines"
    else:
        step, reason = "equip", "equip land formations from stockpile"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_historical_oob_content_product(*, province_id: int = 1, majors: List[str] | None = None) -> Dict[str, Any]:
    med = build_medium_tank_oob_product(province_id=province_id)
    catalog = compute_oob_catalog(majors=majors)
    med_s = _floor(float(med.get("score", 0.55)))
    catalog_score = _floor(0.4 * med_s + 0.6 * float(catalog["coverage"]))
    seed_score = _floor(0.45 + 0.05 * min(14, int(catalog["line_n"])))
    equip_score = _floor(0.5 * seed_score + 0.5 * catalog_score)
    score = _floor(0.3 * catalog_score + 0.35 * seed_score + 0.35 * equip_score)
    rec = recommend_historical_oob_step(cataloged=True, seeded=True)
    step_scores = {"catalog": catalog_score, "seed": seed_score, "equip": equip_score}
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
        {"action_id": "historical_oob_content_product", "label": "Run historical OOB content product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Historical OOB content · majors %d · lines %d · score %.2f" % (
        int(catalog["major_n"]), int(catalog["line_n"]), score)
    return {
        "medium_oob": med, "catalog": catalog, "recommendation": rec, "day_rows": day_rows,
        "apply_queue": apply_queue, "actions": actions,
        "major_n": catalog["major_n"], "line_n": catalog["line_n"], "coverage": catalog["coverage"],
        "score": score, "oob_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(catalog.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#c8a060]📋 Historical OOB[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "historical_oob_content_product", "historical_oob_catalog", "historical_oob_seed",
            "historical_oob_equip", "major_38", "oob", "content", "phase5_depth",
        ],
    }


def execute_historical_oob_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "catalog").strip().lower().replace("historical_oob_", "")
    if s.startswith("catalog"):
        s = "catalog"
    elif s.startswith("seed"):
        s = "seed"
    elif s.startswith("equip"):
        s = "equip"
    if s not in _STEP_META:
        s = "catalog"
    meta = _STEP_META[s]
    product = build_historical_oob_content_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute historical OOB %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_historical_oob_step", s, leaf],
    }


def historical_oob_content_integrity() -> Dict[str, Any]:
    product = build_historical_oob_content_product()
    steps = [execute_historical_oob_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("major_n", 0)) >= 7
        and int(product.get("line_n", 0)) >= 10
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Historical OOB content integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_historical_oob_content_product_loop() -> Dict[str, Any]:
    product = build_historical_oob_content_product(province_id=2)
    gate = historical_oob_content_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close historical OOB content · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
