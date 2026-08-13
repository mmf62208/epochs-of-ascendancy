"""Theater command product (high-value) — orders strip unification.

Composes major product recommendations into a single theater command strip:
combat · fleet · industry/OOB · HH · agent — not day-package catalogue sprawl.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from combat_multi_phase_product import build_multi_phase_combat_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_phase_combat_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "combat", "recommendation": {"step": "engage"}}

try:
    from fleet_multi_day_autonomy_product import build_fleet_multi_day_autonomy_product  # type: ignore
except Exception:  # pragma: no cover
    def build_fleet_multi_day_autonomy_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "fleet", "recommendation": {"step": "posture"}}

try:
    from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_oob_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "oob", "recommendation": {"step": 100}}

try:
    from hh_multi_month_agenda_product import build_hh_multi_month_agenda_product  # type: ignore
except Exception:  # pragma: no cover
    def build_hh_multi_month_agenda_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "hh", "recommendation": {"step": "trail_board"}}

try:
    from agent_campaign_product import build_agent_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_agent_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "agent", "recommendation": {"step": "board"}}


PRODUCT_STEPS = ("scan", "rank", "execute")

_STEP_META = {
    "scan": {
        "action_id": "theater_command_scan",
        "leaf": "apply_station",
        "label": "Step 0 — scan theater domains",
    },
    "rank": {
        "action_id": "theater_command_rank",
        "leaf": "apply_focus",
        "label": "Step 1 — rank domain recommendations",
    },
    "execute": {
        "action_id": "theater_command_execute",
        "leaf": "apply_supply",
        "label": "Step 2 — execute top domain leaf",
    },
}

DOMAIN_META = {
    "combat": {"leaf": "apply_assault", "weight": 1.0},
    "fleet": {"leaf": "apply_station", "weight": 0.95},
    "industry": {"leaf": "apply_production", "weight": 0.9},
    "hh": {"leaf": "apply_hh_commit", "weight": 0.85},
    "agent": {"leaf": "apply_agent_dispatch", "weight": 0.88},
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


def recommend_theater_command_step(
    domain_count: int,
    *,
    top_score: float = 0.5,
) -> Dict[str, Any]:
    if domain_count <= 0:
        step = "scan"
        reason = "no domain products — scan"
    elif top_score < 0.4:
        step = "rank"
        reason = "low scores — re-rank domains"
    else:
        step = "execute"
        reason = "execute top domain recommendation"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_theater_command_product(
    province_id: int = 1,
    *,
    fuel_level: float = 0.65,
    tank_progress: float = 0.15,
    factories: int = 14,
) -> Dict[str, Any]:
    """Theater command product: rank major domain products into one strip."""
    combat = build_multi_phase_combat_product(province_id=province_id)
    try:
        fleet = build_fleet_multi_day_autonomy_product([province_id], fuel_level=fuel_level)
    except TypeError:
        fleet = build_fleet_multi_day_autonomy_product(fuel_level=fuel_level)  # type: ignore
    industry = build_medium_tank_oob_product(
        province_id, tank_line_progress=tank_progress, factories=factories
    )
    hh = build_hh_multi_month_agenda_product(province_id=province_id)
    agent = build_agent_campaign_product(province_id=province_id)

    domains: List[Dict[str, Any]] = []
    for name, block in (
        ("combat", combat),
        ("fleet", fleet),
        ("industry", industry),
        ("hh", hh),
        ("agent", agent),
    ):
        if not isinstance(block, Mapping):
            continue
        if bool(block.get("empty", False)):
            continue
        sc = _norm(float(block.get("score", 0.5) or 0.5))
        w = float(DOMAIN_META[name]["weight"])
        rec = block.get("recommendation") or {}
        domains.append(
            {
                "domain": name,
                "score": sc * w,
                "raw_score": sc,
                "summary": str(block.get("summary", block.get("plain", name)))[:120],
                "recommendation": rec if isinstance(rec, dict) else {},
                "leaf": str(DOMAIN_META[name]["leaf"]),
                "product": block,
            }
        )
    domains.sort(key=lambda d: (-float(d["score"]), str(d["domain"])))

    top = domains[0] if domains else {
        "domain": "fleet",
        "score": 0.45,
        "leaf": "apply_station",
        "summary": "empty theater",
        "recommendation": {},
    }
    top_score = float(top.get("score", 0.45))
    domain_count = len(domains)
    score = _floor(
        0.4 * top_score
        + 0.3 * min(1.0, domain_count / 5.0)
        + 0.3 * (sum(float(d["raw_score"]) for d in domains) / float(max(1, domain_count)))
    )

    rec = recommend_theater_command_step(domain_count, top_score=top_score)

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "scan": _floor(0.4 + 0.1 * min(5, domain_count)),
        "rank": _floor(0.45 + 0.2 * top_score),
        "execute": _floor(0.5 + 0.25 * top_score),
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        label = str(meta["label"])
        if recommended:
            label = "★ " + label
        # execute uses top domain leaf
        leaf = meta["leaf"]
        if step == "execute":
            leaf = str(top.get("leaf", leaf))
        label = "%s · top %s · score %.2f" % (label, top.get("domain", "?"), sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": label,
            "score": sc,
            "enabled": domain_count > 0 or step == "scan",
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
            "domain": top.get("domain", ""),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": label,
                "step": step,
                "product_action": meta["action_id"],
                "domain": top.get("domain", ""),
            }
        )

    # Domain quick-apply rows
    for d in domains[:3]:
        apply_queue.append(
            {
                "action_id": str(d.get("leaf", "apply_station")),
                "province_id": max(1, int(province_id)),
                "score": float(d.get("score", 0.5)),
                "enabled": True,
                "label": "Domain %s · %.2f" % (d.get("domain"), float(d.get("score", 0))),
                "step": "execute",
                "product_action": "theater_domain_%s" % d.get("domain"),
                "domain": d.get("domain"),
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "theater_command_product",
            "label": "Run theater command product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "theater_command_scan")),
            "label": "Recommended: %s" % rec.get("step", "scan"),
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

    strip_lines = [
        "%s · %.2f · %s"
        % (
            d.get("domain"),
            float(d.get("score", 0)),
            str((d.get("recommendation") or {}).get("step", (d.get("recommendation") or {}).get("summary", "")))[:40],
        )
        for d in domains
    ]
    label = (
        "Theater command product · domains %d · top %s · score %.2f"
        % (domain_count, top.get("domain", "—"), score)
    )
    plain_lines = [label, str(rec.get("summary", ""))] + strip_lines
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "domains": domains,
        "domain_count": domain_count,
        "top_domain": str(top.get("domain", "")),
        "top_score": top_score,
        "strip_lines": strip_lines,
        "combat": combat,
        "fleet": fleet,
        "industry": industry,
        "hh": hh,
        "agent": agent,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "theater_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": domain_count > 0,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]🎖 Theater command[/color] [color=#8899aa]%s[/color]" % label,
        "empty": domain_count <= 0,
        "integration": [
            "theater_command_product",
            "theater_command_scan",
            "theater_command_rank",
            "theater_command_execute",
            "major_8",
        ],
    }


def execute_theater_command_step(
    step: str,
    province_id: int = 1,
) -> Dict[str, Any]:
    s = str(step or "scan").strip().lower()
    if s.startswith("theater_command_"):
        s = s.replace("theater_command_", "")
    if s not in _STEP_META:
        s = "scan"
    meta = _STEP_META[s]
    product = build_theater_command_product(province_id)
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
    label = "Execute theater %s · leaf %s · score %.2f · #%d" % (
        s,
        leaf,
        score,
        max(1, int(province_id)),
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
        "bbcode": "[color=#6eb5ff]🎖 Theater %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_theater_command_step", s, leaf],
    }


def theater_command_product_integrity() -> Dict[str, Any]:
    product = build_theater_command_product(1)
    steps = [execute_theater_command_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("domain_count", 0)) >= 4
        and len(product.get("strip_lines") or []) >= 4
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "domain_count": int(product.get("domain_count", 0)),
        "top_domain": str(product.get("top_domain", "")),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Theater command product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_theater_command_product_loop() -> Dict[str, Any]:
    product = build_theater_command_product(1)
    gate = theater_command_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close theater command product · domains %d · top %s · %s"
        % (
            int(product.get("domain_count", 0)),
            product.get("top_domain", "—"),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Theater command product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
